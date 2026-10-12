# KaiTian X7h G1e + Gentoo 平台档案

本文面向 Agent 和维护者。

状态：安装落地（2026-10-12）。档案于 2026-10-11 新建。同一台 KaiTian X7h G1e 从 Debian 13 换成 Gentoo 后单独建档。
2026-10-11 的依赖表是安装前快照；当前结果见「2026-10-12 安装落地」。
显示、电池、外屏、桌面启动链和状态栏模块仍待填。
Debian 的实测、包映射和待办仍只在 [Debian 13 档案](kaitian-x7h-g1e-debian-13.md)，不是本平台事实。

## 设备基本信息

| 项目 | 平台事实 |
| --- | --- |
| 档案身份 | KaiTian X7h G1e 笔记本 + Gentoo |
| 厂商与型号 | KaiTian X7h G1e。主板、处理器、内存、显卡与驱动未在本系统复核，待填 |
| 发行版 | Gentoo。2026-10-12：profile 为 `default/linux/amd64/23.0/systemd`。`@world` 有 106 条，本文不逐条抄录 |
| 包管理 | Portage（`emerge`）。不是 APT，不沿用 Debian 的 APT 结论 |
| 配置仓库 | bare 仓库 `$HOME/.cfg`，work-tree `$HOME` |
| 内核 | 2026-10-12 正在运行 `6.12.111-gentoo-x86_64`。`@world` 含 `sys-kernel/gentoo-sources` 与 `sys-kernel/gentoo-sources:6.12.111`。`6.18.54` 的源码和模块也在，未核对其能否启动 |
| init 与服务管理 | profile 选择 systemd。宿主机 pid 1 与桌面启动链未复核 |
| 图形会话与桌面启动链 | 待填 |
| 使用人 | 本机日常账户。公开档案不记录用户名 |

## 适用范围与隐私边界

本档案只记录“KaiTian X7h G1e + Gentoo”。它不代表其他 Gentoo 机器，也不取代
Debian 13 档案。没有在本系统重新核对的项目保持待填，不用 Debian 档案里的安装状态、
服务所有权或实测结果填空。

不得记录主机名、用户名、序列号、UUID、MAC/IP、账户、凭据或原始 EDID。以后写入的内核、
软件版本和测试结果必须带日期，且不能当作长期身份。

## 通用规则入口

- 稳定命令与能力：[依赖清单](../project/dependencies.md)
- 跨发行版验证步骤：[依赖与文档审计流程](../planning/dependency-audit.md)
- 共享结构与职责：[架构与设计](../project/architecture.md)
- 显示状态模型与验证：[X11 显示管理设计](../project/display-management.md)
- 非标准显示硬件扩展：[显示设备适配器指引](../project/display-device-adapter.md)
- 文档与平台边界：[维护策略](../project/maintenance-policy.md)

## Gentoo 依赖审计

状态：2026-10-11 安装前快照，保留。当时只读，没有 emerge，也没有改 `/etc/portage`。不要用下表判断现在缺什么。
证据是当时 PATH 上的 `command -v`（不含代理工具自己的目录）和 `qlist -I`。
可执行的安装命令在本轮私有汇报，不写进本档案。

| 域 | 2026-10-11 结论 |
| --- | --- |
| U01 | 已有 git、OpenSSH、zsh、bash、python、perl、curl、wget、less、unzip、w3m。node/npm 来自本机版本管理器，不是 Portage。缺 `app-editors/vim`、`app-editors/neovim`、`app-misc/tmux`、`app-shells/fzf`、`sys-apps/ripgrep`。`lazygit` 官方仓库无 ebuild |
| U02 | Xorg、xinit、dbus、fcitx5、pkg-config 所需的 X11/Xft/Xinerama/XCB 头文件已在。dwm、dwmblocks、st、dmenu、picom 是本地编译，不是 Portage。缺 `xrandr`、`setxkbmap`、`xdpyinfo`、`xdotool`、`xclip`、`libnotify`、`dunst`、`slock`、`xss-lock`、`xwallpaper`。`microsoft-edge-stable` 已装 |
| U03 | Noto CJK 与 Noto Color Emoji、Adwaita 图标已装。缺 `media-fonts/libertine`、`media-fonts/fontawesome`。Arc 主题未装。`wal` 是本地命令 |
| U04 | 没有 PipeWire、WirePlumber、mpv、ffmpeg、mpd。ALSA 库已装 |
| U05 | GnuPG、pinentry、xdg-utils 已装。`lf`、`nsxiv`、`opustags` 官方仓库无 ebuild。PDF 工具、zathura、邮件和 RSS 客户端都未装 |
| U06 | NetworkManager、wpa_supplicant、systemd-logind、`bc` 已装。缺 `xbacklight`。Avahi/CIFS、sensors、arandr 未装 |
| U07–U08 | `cal` 已有。htop、calcurse、新闻和种子相关命令都未装。`urlscan`、`urlview`、`tsp` 官方仓库无 ebuild |
| U09 | gcc、make、groff、cargo 已有。TeX、pandoc、emacs、R、Go、Java、mono 未装 |
| U10 | `networkctl` 已有。`cron`/`crontab` 没有。`checkup` 仍只调用 apt |
| S01 | 基础壳、coreutils、sudo、git 已有，没有待装项 |
| S04 | `validate-collab` 在仓库内。`bats` 未装，属可选测试器 |

优先级和分批命令见私有汇报。没有官方 ebuild 的命令本轮不编造包名。


## 2026-10-12 安装落地

对照上一节的缺口做了安装，并用 `qlist` 目录与 `command -v` 复核。没有重跑整份依赖审计。
服务有没有启动、状态栏模块能不能用，本轮没有测。

| 域 | 2026-10-12 结论 |
| --- | --- |
| U01 | `vim`、`neovim`、`tmux`、`fzf`、`ripgrep` 已由 Portage 安装。`/usr/bin/rg` 在；当前 shell 的 `rg` 仍可能先命中别的目录。`lazygit` 仍无官方 ebuild。node/npm 仍来自本机版本管理器 |
| U02 | 上一节列出的 `xrandr`、`setxkbmap`、`xdpyinfo`、`xdotool`、`xclip`、`libnotify`、`dunst`、`slock`、`xss-lock`、`xwallpaper` 已装并在 `@world`。dwm、dwmblocks、st、dmenu、picom 仍是本地编译。`xset`、`xprop` 因本机脚本在用而进入 `@world` |
| U03 | `libertine`、`fontawesome`、`arc-theme` 已装 |
| U04 | `pipewire`、`wireplumber`、`mpv`、`ffmpeg`、`mpd` 已装。没有核对 user 服务是否已启用 |
| U05 | `zathura`、`poppler`、`isync`、`neomutt`、`mutt-wizard`、`newsboat`、`maim`、`ueberzug` 已装。办公用 `app-office/wps-office`（`et`、`wps`、`wpp`），没有 LibreOffice。`lf` 在 `~/.local/bin/lf`，`nsxiv` 在 `/usr/local/bin/nsxiv`，都不是 Portage 包。`opustags` 仍无官方 ebuild |
| U06 | `xbacklight`、`avahi`、`cifs-utils`、`lm-sensors`、`arandr` 已装。`bluez` 保留并在 `@world` |
| U07–U09 | `htop`、`calcurse` 已装。`urlscan` 仍无官方 ebuild。`go` 已装；`pandoc`、`emacs` 未装。`rust-bin` 仍在，`go-bootstrap` 已不在 |
| U10 | `crontab` 仍没有。不要启用 APT 版 `checkup` |
| 清理 | 2026-10-12 已看不到 `ruby`、`nano`、`libayatana-appindicator`、`libsdl2`、`wayland`、`go-bootstrap`、`brotli`、`libjxl`。没有重跑 `--depclean --pretend`，不能把这当作完整清理清单 |

不是主动选来用的库，已 `--noreplace` 进 `@world`，备注写在 `package.use`，避免和真正要装的软件混在一起：

| 谁在用 | 包 | 备注文件 |
| --- | --- | --- |
| 本地 picom | `dev-libs/libconfig`、`x11-libs/xcb-util-renderutil` | `package.use/picom`（只有备注） |
| 本地 nsxiv | `media-libs/imlib2`、`media-libs/libexif` | `package.use/nsxiv`（只有备注） |
| `/opt/Synergy` | `dev-qt/qtbase`、`dev-libs/libei` | `package.use/synergy` 末尾备注。Synergy 本身不是 Portage 包 |

`package.use/synergy` 里原有的 `libdbusmenu gtk3` 不是这张表的保留项。`libayatana-appindicator` 已不在系统里。

## Gentoo 关键映射

只记通用依赖在本平台的映射。未验证的命令不算已安装。

| 通用能力 | Gentoo 映射或本平台结论 |
| --- | --- |
| 包管理 | Portage / `emerge`。`checkup` 仍只跑 `apt update` 和 `apt list --upgradable`，不能在本平台启用。2026-10-11：`command -v apt` 为空，`aliasrc` 的探测会落到 emerge 分支（`emerge-webrsync` 后 `emerge --ask -uDN @world`）。该分支没有实际执行 |
| 状态栏可更新包计数 | `sb-pacpackages` 在没有 apt/pacman/xbps 时进入 emerge 分支，把更新列表留空，并把 `updates_supported` 设为 false。2026-10-11 本机会走到这个分支。这是空实现，不是已核对的“没有更新” |


## 编译参数与 USE

现状（2026-10-11，已写入；`--newuse --deep @world` 已跑完）：

- Profile：`default/linux/amd64/23.0/systemd`，不是 desktop。全局没有 `X`、`alsa`、`wayland`、`cairo`。不要改回 desktop profile。
- `/etc/portage/make.conf`：`COMMON_FLAGS="-march=native -O2 -pipe"`，四个语言标志引用它；`MAKEOPTS="-j16"`（`nproc` 为 16）；`LC_MESSAGES=C.UTF-8`；镜像是清华和中科大；`USE="-qt5 -qt6 -gtk4"`。没有 `-gtk2`。
- `CPU_FLAGS_X86` 来自 `cpuid2cpuflags`：`aes avx avx2 bmi1 bmi2 f16c fma3 mmx mmxext pclmul popcnt rdrand sha sse sse2 sse3 sse4_1 sse4_2 sse4a ssse3`。`-march=native` 不代替这一行。
- `package.use` 现有 `fcitx`、`fh2m-xorg`、`x11`、`local`、`mail`、`pinentry`、`synergy`、`picom`、`nsxiv`。autounmask 文件已删。`X`、PipeWire、`poppler cairo`、`mpv -vulkan` 都在包级，不进 `make.conf`。`picom` 与 `nsxiv` 只有备注。
- 仓库模板 `make.conf.template` 是 `-j5`、`USE="-kde alsa X"`。不要用它覆盖本机。
- 没有用 CFLAGS 或环境变量代替 USE。

留着、不改：

- `-march=native -O2 -pipe` 和 `-j16`。这是一台机器，不做可移植 binpkg。
- `USE="-qt5 -qt6 -gtk4"`。不要把 `qtbase` 的 `-X -gui` 升到全局，否则会拆掉正在用的 X。
- 显卡负 USE 留在 `fh2m-xorg`。不要在 `make.conf` 里再设 `VIDEO_CARDS`。arch profile 仍全局带有 amdgpu、intel、nouveau 等，只有 mesa 和 xorg-drivers 被包级关掉。
- 不做 LTO、ccache、`-O3`，也不给 `-j16` 加 `-l`。

`media-libs/libsdl2` 在 2026-10-12 已不在系统里。以后需要 SDL 窗口时再安装，并加 `media-libs/libsdl2 X`，然后 `emerge --ask --newuse media-libs/libsdl2`。

## 系统与会话差异

Debian 档案里的 init、包管理、网络、显示钩子和会话所有权都还没有在 Gentoo 上复核。
下列项不能从 Debian 搬过来：

- 显示，包括外接屏幕
- 输入法
- 电池
- 内核、init、桌面启动链
- Portage profile 与 `@world`
- 已验证的状态栏模块

Debian 时期为 APT 加过 `checkup` 定时任务。这里不记录它是否还在 crontab 里，也不把它当作 Gentoo 配置。

2026-10-11 核对了 Edge，不是从 Debian 档案搬来的。同日回写：打开和输入法模块都已解决。

- Mod+w：已解决。`/usr/local/bin/dwm` 含 `/usr/bin/microsoft-edge-stable` 和类名 `Microsoft-edge`，不再是 `librewolf`。`~/.local/bin/microsoft-edge` 仍指向 stable。
- 9 号标签：规则已写入，类名字符串在上述二进制里。本轮没有用 `xprop` 再对窗口。
- 输入法：`app-i18n/fcitx-gtk` 已安装并写入 `@world`。GTK3 模块 `im-fcitx5.so` 在，`gtk-query-immodules-3.0` 能看到 `fcitx`。没有改 `GTK_IM_MODULE`。


## 显示硬件与本机钩子

待填。没有 Gentoo 上的输出名、驱动、钩子或 modeline 记录。

## 显示验证与已知行为

待填。没有 Gentoo 上的显示验证记录。

## 临时隔离与恢复

待填。没有已验证的本机恢复步骤。

## 平台工作

### 平台活动待办

- 运行中的内核版本已记。init 的 pid 1 和桌面启动链仍待填。
- `@world` 不逐条抄录。不是主动安装的库见「2026-10-12 安装落地」。
- 在本系统重新核对显示、电池和外屏。
- Edge 启动与 `fcitx-gtk` 已在 2026-10-11 解决。类名仍可用 `xprop` 再对一次，不挡其他工作。
- 列出已在 Gentoo 上验证通过的状态栏模块；没跑过的保持待填。
- PipeWire 与 mpd 的包已装，服务是否启动未复核。
- `crontab` 仍未装。`checkup` 有经本平台验证的 Portage 路径之前，不要启用 APT 版 `checkup`。

### 平台挂起项目

当前没有挂起项。
