Name:           mihomo
Summary:        Mihomo (Clash.Meta) 内核二进制与 systemd 服务
URL:            https://github.com/MetaCubeX/mihomo
License:        AGPL-3.0

# 兼容性宏：在某些发行版（如 Ubuntu 的 rpm）中 _unitdir 未预定义
%{!?_unitdir:%global _unitdir /usr/lib/systemd/system}
# 交叉打包时避免对不同架构二进制执行 strip 导致失败
%global __strip /bin/true
%global __objdump /bin/true
%define debug_package %{nil}

# 版本与发布号由构建脚本通过 -D 传入
# - 稳定版：  -D "ver 1.XX.YY" -D "rel 1"
# - Alpha版： -D "ver 0" -D "rel 0.alpha%%{?buildtag}.%%{?dist}"
Version:        %{?ver}%{!?ver:0}
Release:        %{?rel}%{!?rel:1}%{?dist}

# 仅限常见 Linux 架构
ExclusiveArch:  x86_64 aarch64 armv7hl

# 允许在脚本阶段使用 systemctl
Requires:         xdg-utils
Requires:         python3
Requires:         python3-tkinter
Requires:         polkit
Requires(post):   systemd
Requires(preun):  systemd
Requires(postun): systemd

# 源文件在构建脚本中放入 SOURCES 目录
Source0:        mihomo                   # 解压后的二进制，可执行
Source1:        mihomo.service           # systemd 单元文件
Source3:        mihomo.desktop           # Dashboard 桌面入口
Source4:        mihomo-gui               # 打开 Dashboard 脚本
Source5:        mihomo-control           # 图形控制器（Tkinter）
Source6:        mihomo-control.desktop   # 控制器桌面入口
Source7:        mihomo-control-pkexec    # 提权包装器，传递显示/总线环境
Source8:        sysconfig.mihomo         # /etc/sysconfig/mihomo 环境配置

%description
Mihomo 是 Clash.Meta 内核的延续版本。本包直接打包上游预编译二进制，
并提供 systemd 服务与基础配置目录（/etc/mihomo）。

注意：上游 Alpha 版本没有严格的语义版本号，构建脚本会将其映射为
Version=0 且在 Release 带上 "alpha" 标记与日期/commit 信息。

%prep
# 无源码展开，资源由构建脚本放入 SOURCES

%build
# 纯二进制打包，无需编译

%install
mkdir -p "%{buildroot}%{_bindir}"
mkdir -p "%{buildroot}%{_unitdir}"
mkdir -p "%{buildroot}%{_sysconfdir}/mihomo"
mkdir -p "%{buildroot}%{_sysconfdir}/sysconfig"
mkdir -p "%{buildroot}%{_localstatedir}/lib/mihomo"
mkdir -p "%{buildroot}%{_localstatedir}/log/mihomo"
mkdir -p "%{buildroot}%{_datadir}/applications"

install -m 0755 "%{_sourcedir}/mihomo" "%{buildroot}%{_bindir}/mihomo"
install -m 0644 "%{_sourcedir}/mihomo.service" "%{buildroot}%{_unitdir}/mihomo.service"
install -m 0755 "%{_sourcedir}/mihomo-gui" "%{buildroot}%{_bindir}/mihomo-gui"
install -m 0644 "%{_sourcedir}/mihomo.desktop" "%{buildroot}%{_datadir}/applications/mihomo.desktop"
install -m 0755 "%{_sourcedir}/mihomo-control" "%{buildroot}%{_bindir}/mihomo-control"
install -m 0644 "%{_sourcedir}/mihomo-control.desktop" "%{buildroot}%{_datadir}/applications/mihomo-control.desktop"
install -m 0755 "%{_sourcedir}/mihomo-control-pkexec" "%{buildroot}%{_bindir}/mihomo-control-pkexec"
install -m 0644 "%{_sourcedir}/sysconfig.mihomo" "%{buildroot}%{_sysconfdir}/sysconfig/mihomo"

%post
# 安装或升级后刷新 unit 缓存
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload >/dev/null 2>&1 || :
fi

%preun
# 卸载时尝试停用服务（不强制失败）
if [ $1 -eq 0 ] && command -v systemctl >/dev/null 2>&1; then
  systemctl stop mihomo.service >/dev/null 2>&1 || :
  systemctl disable mihomo.service >/dev/null 2>&1 || :
fi

%postun
# 升级或卸载后刷新 unit 缓存
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload >/dev/null 2>&1 || :
fi

%files
%{_bindir}/mihomo
%{_unitdir}/mihomo.service
%dir %{_sysconfdir}/mihomo
%dir %{_localstatedir}/lib/mihomo
%dir %{_localstatedir}/log/mihomo
%{_bindir}/mihomo-gui
%{_datadir}/applications/mihomo.desktop
%{_bindir}/mihomo-control
%{_bindir}/mihomo-control-pkexec
%{_datadir}/applications/mihomo-control.desktop
%config(noreplace) %{_sysconfdir}/sysconfig/mihomo

%changelog
# 本地构建包，变更历史由使用者维护
