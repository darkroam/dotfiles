# 本配置的桌面与 LARBS 指南

本文按 `/usr/local/share/dwm/larbs.mom` 的章节翻译、整理，并按本仓库和当前
`~/src/dwm/config.h` 修订。上游 LARBS 的个人路径、浏览器、邮件向导、自动编译
和快捷键并不自动适用于本机，因此本文优先保证本机行为准确。

## 基本理念

这个桌面由可替换的小程序组成：DWM 管理窗口，DWMBlocks 显示状态，`st` 提供
终端，`dmenu` 用于启动命令。许多工具使用 Vim 风格的 `h`、`j`、`k`、`l`
按键。`Mod` 指键盘上的 Super/Windows 键。

配置文件主要位于 `~/.config`，可执行辅助脚本位于 `~/.local/bin`。本仓库使用
`c` 管理：`c status` 查看跟踪改动，`c diff` 查看差异。DWM、st、dmenu、
DWMBlocks 的源码位于 `~/src/`，由用户自行编译安装。

## 通用键盘设置

LARBS 的原始设计强调以键盘和 Vim 风格操作为中心。当前会话启动时运行
`remaps`，它负责键盘重映射；Caps 的具体行为、外接键盘和 `xcape` 的效果以
该脚本及当前硬件为准。出现输入或修饰键问题时，先检查 `remaps`，再重新执行
`Mod+F12`，不要假定上游 Caps/菜单键规则必然完全相同。

Shell 也使用适合 Vim 的输入设置。若希望修改 shell 编辑模式，检查
`.config/shell/inputrc` 与 Zsh 配置；这与 DWM 键位相互独立。

## 登录与桌面启动

`~/.profile`、`~/.zprofile` 和 `~/.xinitrc` 都是指向规范位置的链接。无论通过
`startx` 还是显示管理器登录，都会读取 `.config/x11/xprofile`。它负责：

- 为图形会话补充 `~/.local/bin`；
- 选择输入法，优先级为 `fcitx5`、`fcitx`、`ibus`，并统一 GTK、Qt 与
  `XMODIFIERS` 变量；
- 合并静态 Xresources，若安装 pywal 则再加载其生成颜色；
- 使用 `setbg` 恢复壁纸；没有壁纸或 pywal 时仍使用默认颜色；
- 启动键盘重映射、picom、MPD、Dunst 和 unclutter（存在时）。

PipeWire、pipewire-pulse 和 WirePlumber 不在此处启动，而由 systemd 用户服务
管理。音量操作使用 `wpctl`；交互式混音器是 `pulsemixer`。

## 状态栏与高 DPI

屏幕左侧显示当前标签，右侧由 DWMBlocks 模块显示系统状态。每个模块是
`~/.local/bin/statusbar/` 下的独立脚本；鼠标点击会给 DWMBlocks 发送实时信号，
由对应模块刷新或执行其交互动作。修改状态栏模块或 DWMBlocks 源码后，需要在
`~/src/dwmblocks` 中由用户自行重新编译安装。

高 DPI 屏幕可调整 `.config/x11/xprofile` 中的 `xrandr --dpi 96`。数值越大，
X11 应用与状态栏通常越大；修改后重新登录 X11，或按实际 DWM 重载流程刷新。

## 窗口与工作区

DWM 把窗口按最近操作顺序组织为栈。`Mod+Enter` 打开 `st`，`Mod+j/k` 在栈中
切换窗口，`Mod+Space` 将当前窗口提升为主窗口，`Mod+Shift+Space` 切换浮动。
`Mod+h/l` 调整主区域宽度，`Mod+z/x` 增减间隙，`Mod+a` 切换间隙，
`Mod+Shift+a` 恢复默认间隙。布局包括平铺、底部栈、螺旋、递减、Deck、Monocle、
居中主窗口、居中浮动主窗口和纯浮动。完整实际绑定见
[快捷键摘要](keybindings-zh.md)。

标签就是工作区。`Mod+数字` 切换标签，`Mod+Shift+数字` 将窗口发送到标签；
`Mod+g`/`Mod+;` 前后切换标签，配合 Shift 移动当前窗口。多显示器焦点使用
`Mod+Left/Right`，配合 Shift 移动窗口。

## 常用程序

- `Mod+d` 打开 dmenu；`Mod+Shift+d` 打开密码菜单。
- `Mod+r` 在终端启动 LF，`Mod+Shift+r` 启动 Htop。`Mod+n` 打开 Vimwiki，
  `Mod+Shift+n` 打开 Newsboat。
- `Mod+m` 打开 Ncmpcpp。MPD 需要运行，`mpc update` 可更新其音乐数据库。
- 浏览器命令由 `BROWSER=microsoft-edge` 决定。
- `Mod+F4` 打开 Pulsemixer，`Mod+F9/F10` 挂载/卸载设备，`Mod+F3` 打开显示
  选择器。显示选择器的多屏改进仍处于挂起状态。

## 状态栏、壁纸与颜色

状态栏由独立的 DWMBlocks 脚本生成。状态模块的鼠标操作以实时信号刷新模块；
具体模块在 `~/.local/bin/statusbar/`。高 DPI 调整可编辑
`.config/x11/xprofile` 中的 `xrandr --dpi 96`。

`setbg <image>` 设置壁纸；安装 `wal` 后，它会同时生成颜色。没有 `wal` 或没有
壁纸时，静态 Xresources、Dunst 与 Zathura 配色仍可正常使用。

## 截图、录制与媒体键

`Print` 保存全屏截图，`Shift+Print` 进行区域截图。`Mod+Print` 打开录制类型
选择，`Mod+Shift+Print`、`Mod+Delete` 停止正在运行的录制。录制功能依赖
`maim`、`slop`、`ffmpeg` 和可用的音频/视频设备；取消菜单不应终止已有录制。

普通音量键用 `wpctl` 操作 PipeWire 默认输出，媒体键通过 `mpc` 控制 MPD。若未
安装 `mpc` 或 MPD 未运行，相应操作不会生效。`screenkey` 是可选工具；安装后可
用 `Mod+ScrollLock` 显示按键。

## 文件、剪贴板与文档

LF 是文件管理器，`lfub` 是统一启动包装。其预览依赖见
[依赖清单](../project/dependencies.md)。图形程序通常使用 `Ctrl+C`/`Ctrl+V`；终端复制粘贴
由 `st` 自身规则决定。Neovim 配置默认接入系统剪贴板。

`compiler` 和 `opout` 处理文档编译和打开；支持的格式与程序在依赖文档中列出。
TeX 的 `latexmk` 工作流和复杂 PDF 输出目录尚未决定，因此不应假定其已启用。

## 依赖布局参考

以下章节以 [依赖清单](../project/dependencies.md) 的 layout 为准；它说明某项功能
属于哪里、正常使用时的入口，以及哪些能力只是可选或挂起。

### Shell、源代码管理与开发

登录 shell 从 `.config/shell/`、`.config/zsh/` 与 `.bashrc` 读取环境、别名、补全和
书签。`c` 是本仓库的 Git 命令；Zsh 的 FZF 搜索会使用 `fd` 或 Debian 的 `fdfind`。
Oh My Zsh、zplug、NVM 和 Bun 均是条件加载，缺失的本地扩展不应阻止 shell 启动。

### X11 桌面与输入

`.config/x11/xinitrc` 与 `xprofile` 建立 X11 会话、输入法、Xresources、重映射、通知和
合成器。`fcitx5` 是首选输入法；`xkblayout-state` 缺失时键盘状态栏回退到 `setxkbmap`。
DWM、dmenu、st、slock 和 DWMBlocks 是另行编译安装的本地程序。

### 外观、字体与壁纸

Fontconfig、GTK、Dunst、Xresources 和 `setbg` 组成静态外观。Arc、Linux Libertine、Noto
CJK、Noto Color Emoji 与 FontAwesome 是当前字体/主题选择。`wal` 仅在设壁纸后生成覆盖色；
没有壁纸或 `wal` 时仍保持静态默认配色。

### 音频、音乐、录制与视频

PipeWire、pipewire-pulse 和 WirePlumber 由 systemd 用户服务管理；音量使用 `wpctl` 和
`pulsemixer`。MPD、MPC、Ncmpcpp 提供音乐服务与终端控制，MPV/FFmpeg/Sox/Slop 用于播放、
录制和媒体处理。硬件摄像头与 ALSA 捕获是否可用取决于当前设备。

### 文件、文档、密码与桌面处理

LF、`lfub`、Ueberzug、nsxiv、Zathura 和 MIME 桌面入口处理文件浏览。预览工具按格式调用，
例如 Atool、Poppler、MediaInfo、FFmpegthumbnailer、ODT2TXT 与 ImageMagick。密码与 OTP
入口使用 `pass`、`pass-otp`、Maim 和 Zbar；实际密码库内容不属于本仓库。

### 显示、网络、挂载与系统控制

`displayselect` 使用 Xrandr/Arandr，`sysact` 处理锁屏和会话操作，NetworkManager 的 `nmtui`
负责交互联网。USB 挂载使用系统 `mount`/`lsblk`，CIFS 使用 Avahi、Samba 客户端和 CIFS 工具。
Android `simple-mtpfs` 在当前 Debian 没有兼容包，因此该路径保持挂起。

### 状态栏、通信与网络服务

`~/.local/bin/statusbar/` 中的脚本由 DWMBlocks 调度。日历、网络、RSS、邮件、任务队列、
种子和天气模块均可独立失效；`geoiplookup` 缺失时定位模块会隐藏。邮件账户配置不被跟踪，
状态栏只调用已安装的 `mw`、Neomutt 与 Mbsync。

### 下载、种子与文本浏览

`qndl` 使用 `tsp` 排队下载，Newsboat 可调用 `yt-dlp`、Lynx、Urlscan 和本地链接处理器。
Transmission 守护进程、远程客户端和状态栏模块是标准种子路径；`tremc` 是最低优先级可选
终端界面，缺失时 `torrent` 会提示使用 Web 界面或 `transmission-remote`。

### 编译、排版与数据辅助

`compiler` 按源文件后缀选择 TeX、Groff、Markdown、Org、R 或语言工具链；完整 TeX/多语言
工具链尚未按实际需求确认。`getbib` 使用 Poppler 与 Crossref，`texclear` 只清理构建副产物。
不要假定所有编译器都会随基础桌面安装。

### 模板与计划工作

`.local/share/sys-etc/` 下的 Portage、systemd-networkd 与 wpa_supplicant 文件只是模板，绝不
自动部署。cron 示例需要用户 D-Bus、显示环境和明确的 sudo 策略；在确认前不要启用无人值守
更新。

## 配置与更新

将常用配置修改限制在本仓库已跟踪文件中。使用 `c status`、`c diff` 审查，使用
`c add <path>` 明确加入改动，再提交。不要以重新运行安装器替代审查式更新；安装
器会处理部署，但不能替代对个人配置、依赖和本地改动的确认。

系统模板位于 `.local/share/sys-etc/`，默认不会生效。复制到系统位置前必须根据
当前发行版、网卡和安全要求调整。`profile.local` 与 `aliasrc.local` 是不跟踪的
每机器扩展点，适合放不同设备的个人差异。

## 故障排查

- 输入法不可用：确认 `fcitx5`、`fcitx` 或 `ibus` 之一已安装，然后重新登录
  X11 会话。
- 没有声音：检查 PipeWire/WirePlumber 用户服务和默认输出，使用 `pulsemixer`
  或 `wpctl status` 选择设备。
- 没有壁纸或颜色：这是允许的默认状态；安装 `xwallpaper`，设置图片后可使用
  `setbg`，安装 `wal` 后才会生成配色。
- 快捷键失效：确认正在运行的是用户自行编译安装的当前 DWM；本仓库不会替你
  编译 `~/src/dwm`。
- 触摸板键无效：`synclient` 只适用于支持它的 X11 Synaptics 环境；现代 libinput
  设备可能需要另行决定控制方式。
- 需要连接网络：保留 `nmtui` 作为 NetworkManager 的交互界面；先安装
  NetworkManager，再用 `Mod+Shift+w` 或终端启动它。

## 与上游指南的差异

上游文件假定 LibreWolf、mutt-wizard、`~/.local/src`、自动重编译 DWMBlocks、
手动 PulseAudio 和一组不同的 DWM 键位。本配置分别使用 Microsoft Edge、现有
邮件/RSS 配置、`~/src`、systemd 管理的 PipeWire，且不自动编译 Suckless 程序。
因此应以本文和快捷键摘要为准；`Mod+F1` 当前仍显示系统安装的原始英文手册。
