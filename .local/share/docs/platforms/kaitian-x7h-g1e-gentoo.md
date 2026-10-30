# KaiTian X7h G1e + Gentoo 平台档案

本文面向 Agent 和维护者。

状态：安装落地（2026-10-12）。档案于 2026-10-11 新建。同一台 KaiTian X7h G1e 从 Debian 13 换成 Gentoo 后单独建档。
2026-10-11 的依赖表是安装前快照；当前结果见「2026-10-12 安装落地」。
2026-10-14：R18 已结项，与错题本 P6 对齐。X 层启动黑屏用合盖外屏配置 `Option "Disable" "true"` 解决；周期重探已有变化门禁；登录前黑屏是内核交接，记为外部边界。显卡驱动和恢复步骤仍未复核。桌面启动链和状态栏见阶段五。
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
| init 与服务管理 | profile 选择 systemd。2026-10-12 用户回传 `ps -p 1` 的命令名是 systemd。不记录主机其他信息 |
| 图形会话与桌面启动链 | 2026-10-12：`.zprofile` 只在本地第一控制台、没有 SSH、没有 `DISPLAY`、有显卡设备、且没有已在跑的 Xorg 时设置 `XINITRC` 并 `exec startx`。`~/.xinitrc` 指向 `.config/x11/xinitrc`，先 source `xprofile`，再 `ssh-agent dwm`。`xprofile` 拉起壁纸、xrdb、输入法、`xss-lock`、picom，以及 `mpd`、`dunst`、`unclutter`、`/opt/Synergy/synergy-service`。dwm 的 `runAutostart()` 执行 `killall -q dwmblocks; dwmblocks &` |
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
| U05 | `zathura`、`poppler`、`isync`、`neomutt`、`mutt-wizard`、`newsboat`、`maim`、`ueberzug` 已装。办公用手动安装的 WPS 12.1.2（deb，`/opt/kingsoft/wps-office`，2026-10-12，捆绑库）。已卸 Portage 旧版 `app-office/wps-office` 及其 19 个孤儿依赖。命令仍是 `et`、`wps`、`wpp`。没有 LibreOffice。`lf` 在 `~/.local/bin/lf`，`nsxiv` 在 `/usr/local/bin/nsxiv`，都不是 Portage 包。`opustags` 仍无官方 ebuild |
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

2026-10-12 阶段五补记，不改上面两张快照表：核对时 PipeWire 用户服务已在运行；U10「`crontab` 仍没有」已过时，见会话核对。

## Gentoo 关键映射

只记通用依赖在本平台的映射。未验证的命令不算已安装。

| 通用能力 | Gentoo 映射或本平台结论 |
| --- | --- |
| 包管理 | Portage / `emerge`。2026-10-12：`checkup` 已支持 apt、pacman、xbps、emerge 探测链。Gentoo 用 `sudo -n emerge-webrsync` 刷新，再用 `emerge --color n --pretend --verbose --update @world` 的 `Total` 判断有没有更新；刷新或解析失败会通知并退出，不执行升级。`aliasrc` 的 `pmu` 仍是 `emerge-webrsync` 后 `emerge --ask -uDN @world` |
| 状态栏可更新包计数 | 2026-10-12：`sb-pacpackages` 已实现 emerge 计数，解析上面同一条预览的 `Total`。有更新显示数量，0 不显示；没有 `Total` 时标明不可用，不再把空列表当成没有更新。计数是 `-u`，不含 `pmu` 的 `-uDN` |
| 触控板开关 | 2026-10-12：依赖 `xinput`（`x11-apps/xinput`），不依赖 `synclient`。输入驱动包是 `x11-drivers/xf86-input-libinput`。本机没有 `/usr/bin/synclient`，也没有 `xf86-input-synaptics` |


## 编译参数与 USE

现状（2026-10-11，已写入；`--newuse --deep @world` 已跑完）：

- Profile：`default/linux/amd64/23.0/systemd`，不是 desktop。全局没有 `X`、`alsa`、`wayland`、`cairo`。不要改回 desktop profile。
- `/etc/portage/make.conf`：`COMMON_FLAGS="-march=native -O2 -pipe"`，四个语言标志引用它；`MAKEOPTS="-j16"`（`nproc` 为 16）；`LC_MESSAGES=C.UTF-8`；镜像是清华和中科大；`USE="-qt5 -qt6 -gtk4"`。没有 `-gtk2`。
- `CPU_FLAGS_X86` 来自 `cpuid2cpuflags`：`aes avx avx2 bmi1 bmi2 f16c fma3 mmx mmxext pclmul popcnt rdrand sha sse sse2 sse3 sse4_1 sse4_2 sse4a ssse3`。`-march=native` 不代替这一行。
- `package.use` 现有 `fcitx`、`fh2m-xorg`、`x11`、`local`、`mail`、`pinentry`、`synergy`、`picom`、`nsxiv`。autounmask 文件已删。`X`、PipeWire、`poppler cairo`、`mpv -vulkan` 都在包级，不进 `make.conf`。`picom` 与 `nsxiv` 只有备注。
- 2026-10-29 音频 USE：`media-video/pipewire` 加 `dbus bluetooth`（DBus 支持与蓝牙音频，后者仅蓝牙耳机/音箱需要）；`media-sound/ncmpcpp` 加 `visualizer`（拉入 `sci-libs/fftw`，`visualizer_type = "spectrum"` 才可用，否则用 `wave`）。`rtkit` 仍是可选，未加入必需依赖；缺失只回退实时调度。
- 仓库模板 `make.conf.template` 是 `-j5`、`USE="-kde alsa X"`。不要用它覆盖本机。
- 没有用 CFLAGS 或环境变量代替 USE。

留着、不改：

- `-march=native -O2 -pipe` 和 `-j16`。这是一台机器，不做可移植 binpkg。
- `USE="-qt5 -qt6 -gtk4"`。不要把 `qtbase` 的 `-X -gui` 升到全局，否则会拆掉正在用的 X。
- 显卡负 USE 留在 `fh2m-xorg`。不要在 `make.conf` 里再设 `VIDEO_CARDS`。arch profile 仍全局带有 amdgpu、intel、nouveau 等，只有 mesa 和 xorg-drivers 被包级关掉。
- 不做 LTO、ccache、`-O3`，也不给 `-j16` 加 `-l`。

`media-libs/libsdl2` 在 2026-10-12 已不在系统里。以后需要 SDL 窗口时再安装，并加 `media-libs/libsdl2 X`，然后 `emerge --ask --newuse media-libs/libsdl2`。

2026-10-14 locale：`/etc/locale.conf` 与 `/etc/env.d/02locale` 的 `LANG` 都是 `zh_CN.UTF-8`。`env-update` 从 `env.d` 生成 `/etc/profile.env`，其中有 `export LANG='zh_CN.UTF-8'`。这不是「系统已是中文」。同日会话观察是 `LC_ALL=C.UTF-8`，各类别跟着 `C.UTF-8`。`make.conf` 的 `LC_MESSAGES=C.UTF-8` 只作用于 Portage 消息。

## 系统与会话差异

2026-10-14：下面这些已经在后文按日期写过，不能再当成「都还没在 Gentoo 上复核」，也不能从 Debian 档案搬过来。

- 内核、init（systemd）、桌面启动链、Portage profile：见基本信息。
- 输入法与 Edge：见本节后面。
- 电池快照、外屏快照、状态栏实跑、cronie：见 2026-10-12 各节。
- 包管理是 Portage。Debian 时期的 APT `checkup` 不是本平台配置；Gentoo 定时见会话核对。

仍未复核，保持待填：显卡与驱动、本机显示钩子、恢复步骤。主板、处理器和内存也还没在本系统复核，见基本信息。

Debian 档案里的包映射、服务所有权和实测结果仍只属于 Debian。

2026-10-11 核对了 Edge，不是从 Debian 档案搬来的。同日回写：打开和输入法模块都已解决。

- Mod+w：已解决。`/usr/local/bin/dwm` 含 `/usr/bin/microsoft-edge-stable` 和类名 `Microsoft-edge`，不再是 `librewolf`。`~/.local/bin/microsoft-edge` 仍指向 stable。
- 9 号标签：规则已写入，类名字符串在上述二进制里。本轮没有用 `xprop` 再对窗口。
- 输入法：`app-i18n/fcitx-gtk` 已安装并写入 `@world`。GTK3 模块 `im-fcitx5.so` 在，`gtk-query-immodules-3.0` 能看到 `fcitx`。没有改 `GTK_IM_MODULE`。



## 2026-10-12 会话核对

这次核对的是正在跑的 Gentoo 会话。X 日志时间是 16:27（内核命令行含分区标识，按公开档案规则不记录）。

- 字体：2026-10-12 用户确认状态栏 14 像素可以。`/usr/local/bin/dwm` 与 `~/src/dwm/dwm` 的 SHA256 都是 `ba195c5c1054684a45dcccd0866b9deb0fdca0a1e6597bd5ec7c531773b72be9`。二进制里是 `monospace:pixelsize=14:antialias=true:autohint=true` 和 `NotoColorEmoji:pixelsize=14`。`monospace:size=16` 只在计算器弹出窗口。`st` 与 `dmenu` 仍是 12。`~/.local/bin/dwm` 不存在。`~/.config/x11/xinitrc` 第 17 行是 `ssh-agent dwm`。
- dwmblocks：源码用 `setroot()` 把文字交给 dwm 画，自己没有字体。2026-10-12 阶段五：`/usr/local/bin/dwmblocks` 与 `~/src/dwmblocks/dwmblocks` 的 SHA256 都是 `abd356cbefc3a2edcdb03c6b7c1af72445ad2f7bfedaf70eb166aad38eaed81f`。命令列表与当时的 `config.h` 一致，含 `sb-pacpackages` 和 `sb-forecast2`，不含已注释的录音图标、`sb-tasks`、`sb-torrent`、`sb-doppler`。
- 触控板：依赖是 `xinput`，不是 `synclient`。设备名 `HTIX5288:00 36B6:C002 Touchpad`。`/usr/bin/xinput` 在；`/usr/bin/synclient` 和 `synaptics_drv.so` 不在。`qlist` 有 `x11-apps/xinput` 和 `x11-drivers/xf86-input-libinput`，没有 `xf86-input-synaptics`。dwm 用 `xinput` 改 `libinput Send Events Mode Enabled`（`0, 0` 开，`1, 0` 关）。2026-10-12 17:20 的 X 日志里，触控板已是 `Using input driver 'libinput'`。日志还有一条内核提示：clickpad 宣称了右键。
- 定时：2026-10-12 用户回传。`systemctl is-enabled cronie` 为 `enabled`。用户 crontab 两条：每天 9:00 跑 checkup、每 6 小时跑 sb-forecast2 --refresh（cron 行带会话 DBUS/DISPLAY 前缀与家目录路径，按公开档案规则不记录细节）。



## 2026-10-12 阶段五

只读。没有改服务，没有装包。

- PipeWire：用户会话的运行目录里有 `pipewire.service`、`pipewire-pulse.service`、`wireplumber.service` 的 invocation，并且有 `pipewire-0` 套接字。`default.target.wants` 启用了前两个，`pipewire.service.wants` 拉着 wireplumber。本会话的 `systemctl --user` 连不上用户总线，所以上面不是 `is-active` 的输出。
- mpd：没有用户服务 invocation，也没有运行目录里的套接字。本会话执行 `mpc status` 得到 Operation not permitted，不能判断进程是否在跑。`xprofile` 进桌面时仍会 `pidof mpd || mpd &`。
- 状态栏实跑（2026-10-12 18:04 前后，未设置 `BLOCK_BUTTON`）：
  - `sb-clock`：退出 0，打出日期和时间。
  - `sb-battery`：退出 0，`✅99%`。
  - `sb-nettraf`：退出 0，打出收发字节。
  - `sb-internet`：退出 0。无线未连接，两块有线网卡一个 down、一个 up。脚本把两块网卡打成两行，`🌐` 在第二行。dwmblocks 只读第一行，所以状态栏上看不到 `🌐`。
  - `sb-forecast2`：退出 0，打出当天雾霾、温度和明/后提示。
  - `sb-pacpackages`：退出 0，无输出。脚本只在数量大于 0 时显示；解析失败才会显示 `📦?`。这次按 0 条更新处理。
  - `sb-news`：无输出，退出 1。`newsboat` 报告 0 篇未读，所以不显示；退出码来自缺少的 `.update` 文件，不是没装 `newsboat`。
  - `sb-mailbox`：退出 0，无输出。没有邮件目录和账户配置。
  - `sb-help-icon`：退出 0，`❓`。
  - `sb-volume`：阶段五在会话外实跑退出 2，是权限限制，不是模块故障。2026-10-12 用户在图形会话复验，输出 `🔉56%`。
- 显示回传见「显示硬件」。这是 2026-10-12 快照；画面问题已随 R18 于 2026-10-14 结项，现行结论见文首和 P6。
- 2026-10-12 阶段六：`sb-internet` 把多块网卡拼成一行，避免 `🌐` 落在 dwmblocks 读不到的第二行。本机当时无线 down、一块有线 down、一块有线 up，实跑是一行，同时有 `❎` 和 `🌐`。

## 显示硬件与本机钩子

2026-10-12 用户回传，合盖、外屏已接。没有记 EDID，也没有改配置。

- `HDMI-2` 已连接，是 primary，当前 `1920x1080`。
- `HDMI-1` 未连接。
- `eDP-1` 已连接，这次没有标成正在使用的模式。盖子状态是 closed。
- 屏幕当前大小 `1920x1080`。驱动和本机钩子仍未核对。

2026-10-14：合盖且至少一块外屏为 connected 时，登录前写入 `/etc/X11/xorg.conf.d/90-lid-external.conf`。OutputClass 匹配驱动 `fh2m`，Monitor 段是 `Option "Disable" "true"`。这是 xorg-server 21.1 上关闭已连接输出的语义；`Enable false` 对已连接输出不生效。写入前先删残留。该目录需 root 建一次并交给当前用户，之后写入和删除不调用 sudo；目录不可写则跳过。逻辑在 shell 的 `zprofile`，不写入通用显示设计。


## 显示验证与已知行为

2026-10-12 快照：用户确认当时就是外屏，画面有问题但可以用。2026-10-14：该问题已在 R18 结项，见错题本 P6。本段不改写当天快照。

电池同一次回传：`BAT0` 状态 Full，电量 99。这只是这一次快照，不是充放电策略。



## 音频输出顺序

2026-10-30 用户验证通过。只记本机，不写进通用依赖。

自动顺序：

1. 蓝牙输出节点在，就用蓝牙。
2. 否则用板载模拟输出。这是同一个节点：3.5 毫米孔插上走耳机口，拔掉走喇叭。板载 codec 有插孔检测。
3. 扩展坞 USB 耳机不自动选。要听它时单独用 `wpctl` 或 Pulsemixer 选。

扩展坞是 HP Thunderbolt Dock 声卡 `03f0:0269`。UCM 写了 `Headsets Playback Jack`，混音器里没有这个控件，只有播放音量和开关。耳机拔掉，USB 节点还在。若把它的优先级放到板载之上，空耳机口会一直占着默认输出，板载喇叭不响。所以该节点优先级低于板载。

实现文件：`.config/wireplumber/wireplumber.conf.d/51-sink-order.conf`。

- `node.restore-default-targets = false`。手动 `wpctl set-default` 会被记住并加很高的优先级，会挡住上面的顺序。
- `bluez_output.*` 的 `priority.session` 为 3000。
- 板载 `alsa_output.pci-0000_06_00.6.analog-stereo` 为 1500。
- 坞上 `alsa_output.usb-.*-Generic_USB_Audio-.*-00.*` 为 900。

改文件后要 `systemctl --user restart wireplumber`。已经在播的流要重新接一次，例如 `mpc stop; mpc play`。之后跟着默认输出的流会随默认设备切换。


## 状态栏音乐

2026-10-30 用户验证通过。不要再加波形。

- 音乐块只显示播放和暂停：播放是标题，暂停是标题加暂停符号。没有 cava 波形，也没有滚动标题。`sb-musicwave` 和 `.config/cava/statusbar` 已删除。
- `dwmblocks` 里 `sb-music` 的刷新间隔是 0，只在收到信号 11 时更新。间隔改成 1 是为波形每秒重画，已退回。源码在 `~/src/dwmblocks/config.h`，装到 `/usr/local/bin/dwmblocks` 后必须重启进程，否则内存里仍是旧间隔。
- `Mod+p` 只执行 `mpc toggle`，不直接刷新状态栏。`sb-mpdup` 用 `mpc idle` 看到状态变化后发信号 11。看守进程在找不到 `dwmblocks` 时不能退出，否则播放暂停不再马上反映到状态栏。
- 状态栏不跟手时执行：`pkill -x sb-mpdup`，再 `sb-mpdup >/dev/null 2>&1 &`，然后 `killall dwmblocks` 并重新启动 `dwmblocks`。2026-10-30 这样做之后用户确认跟手。
- 内存条仍是 8 格：█ 已用、▓ 缓存、░ 空闲。这和波形无关，不要一起退掉。

## 临时隔离与恢复

待填。没有已验证的本机恢复步骤。

## 平台工作

### 平台活动待办

- 运行中的内核版本已记。2026-10-12 阶段五：桌面启动链已从文件核对，见基本信息。同日用户回传 pid 1 的命令名是 systemd。
- `@world` 不逐条抄录。不是主动安装的库见「2026-10-12 安装落地」。
- 显示：2026-10-12 已回写外屏快照。画面问题已随 R18 结项（2026-10-14，见 P6），不再作为待办。显卡驱动、本机钩子和恢复步骤仍未复核。
- Edge 启动与 `fcitx-gtk` 已在 2026-10-11 解决。类名仍可用 `xprop` 再对一次，不挡其他工作。
- WPS 12 统一类名，三应用共入标签 6（xprop 实测 2026-10-12）。
- 状态栏：2026-10-12 阶段五实跑见该节。同日 `sb-volume` 已复验；`sb-internet` 多网卡改为单行。
- PipeWire：2026-10-12 阶段五，用户服务在跑（invocation 与套接字）。mpd 没有这些痕迹，进程未证实。正文同此，不另写一套结论。
- 默认输出顺序：2026-10-30 已验证，见「音频输出顺序」。扩展坞 USB 耳机保持手动。
- 状态栏音乐：2026-10-30 退回播放/暂停，不要波形。`sb-music` 间隔 0。`sb-mpdup` 找不到状态栏时不退出。见「状态栏音乐」。
- 2026-10-12：`cronie` 为 `enabled`，用户 crontab 里已有每天 9:00 的 `checkup` 和每 6 小时的 `sb-forecast2 --refresh`。命令细节见会话核对。本会话 `crontab -l` 被 pam 拒绝，没有重读。
- fantgpu overlay 在 `/var/db/repos/fantgpu`，`repos.conf` 指向这里。家目录保持 `700`。`profiles/thirdpartymirrors` 仍然没有，Portage 把它当空表。

### 平台挂起项目

- macOS 与 Arch 的真机效果对等验证留到以后有对应机器时再做，不在本轮。

