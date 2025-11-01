# Mihomo RPM 与图形控制面板

本仓库提供 mihomo 的 RPM 打包与一个简洁的图形控制面板（可一键启动/停止/重启、启用/禁用开机自启，并打开 Web Dashboard）。

## 重要变更（工作目录与 Dashboard 打开逻辑）

- 系统级工作目录固定为 `/var/lib/mihomo`（原“配置同级目录”已不再作为默认工作目录）。
  - 影响：运行产生的外部 UI 资源、下载缓存等将位于 `/var/lib/mihomo`，不会再把用户配置目录弄乱。
  - 如需放在其它位置，请在 ` /etc/sysconfig/mihomo` 覆盖 `MIHOMO_DIR`。
- 控制面板与 `mihomo-gui` 会自动解析你的配置 YAML：
  - 若配置了 `external-controller-tls`，浏览器将打开 `https://<addr>/ui`；
  - 否则若配置了 `external-controller`，将打开 `http://<addr>/ui`；
  - 若监听地址为 `0.0.0.0`/`::`，会自动归一化为本机 `127.0.0.1`/`[::1]` 以便在本机浏览器访问；
  - 控制面板：未配置外部控制器时，“打开 Dashboard”按钮会禁用并提示；
  - `mihomo-gui`：未配置时会回退到默认地址并在终端给出提示。
- 应用菜单中的 “Mihomo Dashboard” 已改为调用 `mihomo-gui`，以便后续动态 URL 推断与环境覆盖（`MIHOMO_DASHBOARD_URL`）。

## 首次使用流程

1. 安装 RPM
   - 例如：`sudo dnf install ./mihomo-*.rpm`

2. 打开“控制面板”
   - 应用菜单搜索“Mihomo 控制面板”，或运行 `mihomo-control`（桌面入口会自动提权）。

3. 指定配置文件（服务未设置前不会启动）
   - 常规：在“当前配置”一行点击“选择...”，从“用户主目录”中选择你的配置（如 `~/.config/mihomo/config.yaml`）。
   - 高级：点击“打开 sysconfig”，直接编辑 `/etc/sysconfig/mihomo`，设置变量：
     - `MIHOMO_DIR="/etc/mihomo"`（或你的目录）
     - `MIHOMO_CONFIG="/绝对/路径/config.yaml"`
     - 可“保存并重启服务”。

4. 启动与自启
   - 在控制面板内点击“启动”与“启用自启”。
   - 也可命令行：`sudo systemctl enable --now mihomo`。

5. 打开面板
   - 点击“打开 Dashboard”或运行 `mihomo-gui`。
   - 工具会按你的 YAML 中的 `external-controller(-tls)` 自动推断 URL；未配置时回退到 `http://127.0.0.1:9090/ui`。

## 说明与注意

- 首次安装后，若未设置 `MIHOMO_CONFIG` 或对应文件不存在，服务会拒绝启动（systemd 的 ExecStartPre 校验）。
- GUI 进行启动/停止等操作时会请求提权；请确保系统安装了 polkit 图形认证代理（GNOME/KDE 默认自带）。
- Wayland 会话通常通过 XWayland 运行 Tk GUI；若你的系统未启用 XWayland，请先安装/启用。

### SAFE_PATHS 指南（外部 UI 与资源路径）

- 当你的 `external-ui`（或 rule-providers、geo 文件等资源）不在工作目录 `MIHOMO_DIR` 内时，内核会出于安全考虑拒绝访问。此时需要在环境变量 `SAFE_PATHS` 中显式允许这些绝对路径。
- `SAFE_PATHS` 解析规则与系统 PATH 类似：在 Linux 下使用冒号 `:` 分隔多个目录。
- 配置方法：编辑 ` /etc/sysconfig/mihomo` 并重启服务。

常见场景示例：
- external-ui 放在系统目录（只读）：
  - `external-ui: /usr/share/metacubexd`
  - sysconfig: `SAFE_PATHS="/usr/share/metacubexd:/var/lib/mihomo"`
- external-ui 放在工作目录内（推荐）：
  - `MIHOMO_DIR=/var/lib/mihomo`
  - `external-ui: /var/lib/mihomo/ui`（或相对路径 `./ui`）
  - 无需设置 `SAFE_PATHS`
- external-ui 放在你的家目录：
  - `external-ui: /home/you/mihomo-ui`
  - sysconfig: `SAFE_PATHS="/home/you/mihomo-ui:/var/lib/mihomo"`

编辑完 ` /etc/sysconfig/mihomo` 后执行：
`sudo systemctl daemon-reload && sudo systemctl restart mihomo`

### 最小配置示例（推荐）

- sysconfig（编辑 ` /etc/sysconfig/mihomo`）：
  - `MIHOMO_DIR="/var/lib/mihomo"`
  - `MIHOMO_CONFIG="/home/you/.config/mihomo/config.yaml"`
  - 如果 `external-ui` 或其它资源不在 `MIHOMO_DIR`，为通过安全校验可设置：
    - `SAFE_PATHS="/home/you/.config/mihomo:/var/lib/mihomo"`

- YAML（你的 `config.yaml`）：
  - `external-controller: 127.0.0.1:9090`（或 `external-controller-tls: 127.0.0.1:9443`）
  - `external-ui: /var/lib/mihomo/ui`（或相对路径 `./ui`，相对于 `MIHOMO_DIR`）

提示：你也可以通过环境变量覆盖打开地址，例如：
`MIHOMO_DASHBOARD_URL="https://127.0.0.1:9443/ui" mihomo-gui`

## 卸载

- 卸载会清理运行数据与日志：`/var/lib/mihomo`、`/var/log/mihomo`；不会删除你的配置与 `/etc/sysconfig/mihomo`。
