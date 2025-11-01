# Mihomo RPM 与图形控制面板

本仓库提供 mihomo 的 RPM 打包与一个简洁的图形控制面板（可一键启动/停止/重启、启用/禁用开机自启，并打开 Web Dashboard）。

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
   - 点击“打开 Dashboard”或运行 `mihomo-gui`，默认地址 `http://127.0.0.1:9090/ui`。

## 说明与注意

- 首次安装后，若未设置 `MIHOMO_CONFIG` 或对应文件不存在，服务会拒绝启动（systemd 的 ExecStartPre 校验）。
- GUI 进行启动/停止等操作时会请求提权；请确保系统安装了 polkit 图形认证代理（GNOME/KDE 默认自带）。
- Wayland 会话通常通过 XWayland 运行 Tk GUI；若你的系统未启用 XWayland，请先安装/启用。

## 卸载

- 卸载会清理运行数据与日志：`/var/lib/mihomo`、`/var/log/mihomo`；不会删除你的配置与 `/etc/sysconfig/mihomo`。

