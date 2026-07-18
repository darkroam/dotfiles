# 依赖清单

这是面向全新 Linux 安装的完整命令清单。安装适用组可启用全部已跟踪功能；发行版包名不同，
命令名是稳定参考。基础环境还假定具备 GNU/Linux `sh`、`bash`、GNU coreutils、findutils、
grep、sed、awk、util-linux（`setsid`、`lsblk`、`flock`）、procps（`pgrep`、`pkill`、`ps`）、
`pidof`、psmisc（`killall`）、`file` 和 `sudo`。

发行版包名、安装状态和设备验证不在本文维护；从[平台档案索引](../platforms/index.md)进入对应
设备与发行版档案。

## Shell、源代码管理与开发

| 软件或命令 | 用途 |
| --- | --- |
| `git` | bare 配置仓库、`c` 命令和 Bash/Zsh 共用 Git 快捷命令 |
| OpenSSH 客户端（`ssh`、`ssh-agent`） | 通过 GitHub SSH 部署配置，并在 `.xinitrc` 中启动 DWM 会话 |
| `lazygit` | 可选 Git TUI 别名 |
| `zsh`, `bash` | 交互式和 POSIX shell 支持 |
| `python3` | 辅助脚本和 Python 源文件执行；`compiler` 优先使用 Python 3，并只为其他平台保留 `python` 回退 |
| `vim` 与 `nvim` | Git 固定编辑器，以及默认终端/桌面编辑器和处理器 |
| `tmux`, Perl | Tmux 及其嵌入式配置、主题和辅助处理；配置位于 `.config/tmux/tmux.conf` |
| `less`, `fzf` | 终端查看与模糊查找工作流 |
| `curl`, `wget` | 安装器、下载和网络辅助工具 |
| `node`, `npm` | Neovim 和开发工具 |
| NVM、Bun | 可选 Node.js 版本管理与运行时；本地初始化文件存在时由 Zsh 加载 |
| `highlight`、`bat` 或兼容命令、`fd` 或兼容命令、`ripgrep` | FZF 和 LF 预览/搜索支持 |
| `jq`, Docker (`docker`) | Zsh `json()` 剪贴板格式化和已配置 Docker 插件/`attach()` 辅助命令 |
| `unzip`, `unrar` | 使用相应归档类型时的归档预览辅助工具 |
| `w3m` | `fzf_preview` 的可选 HTML 预览；缺失时仍可进行纯文本预览 |
| ShellCheck (`shellcheck`) | 可选的 POSIX Shell 维护审计；不属于运行时依赖 |
| Oh My Zsh、zplug、`thefuck`；`zsh-autosuggestions`、`zsh-syntax-highlighting`、`zsh-history-substring-search`、`zsh-completions`、`fzf-tab` | 已配置的 Zsh 框架、插件管理器、命令修正工具和插件；zplug 缺失时首次 Zsh 会话会尝试联网安装，`fzf-tab` 仅在存在 `fzf` 时加载 |
| Bash 补全包和 Git 补全脚本 | `c` 与 Git 的 Bash 完整补全；Zsh 使用其内建 Git 补全 |

## X11 桌面与输入

| 软件或命令 | 用途 |
| --- | --- |
| Xorg/Xinit, `dbus-launch`, `dbus-update-activation-environment` | X11 会话启动 |
| `dwm`, `dwmblocks`, `st`, `dmenu` | 窗口管理器、状态栏、终端和启动器；从 `~/src/` 单独构建 |
| C99 编译器、`make`、`pkg-config` | 构建四个独立桌面源码仓库 |
| X11、Xft、Xrender、Xinerama、Fontconfig、FreeType、HarfBuzz 开发头文件和库 | DWM、DWMBlocks、dmenu 与 st 的编译、字体和渲染能力 |
| X11-XCB、XCB、XCB Res 开发头文件和库 | 当前 DWM 补丁使用的进程/窗口资源能力 |
| `tic` | 安装 st 的 terminfo 条目 |
| kbd（`loadkeys`） | Zsh 本地控制台登录时可选加载 TTY 键盘映射；失败不阻塞登录 |
| `fbterm` | 使用已跟踪 `.fbtermrc` 时的可选 framebuffer 终端 |
| `slock` | 系统安装的 X11 锁屏程序；不属于仓库约定的四个 `~/src/` 源码目录 |
| `dunst`, `picom`, `unclutter`, `xwallpaper` | 通知、合成器、鼠标隐藏和壁纸 |
| `xrdb`, `xrandr`, `xset`, `xdotool`, `xdpyinfo`, `xclip`, `xprop`, `setxkbmap` | Xresources、显示、输入、剪贴板和辅助脚本 |
| `xkblayout-state` | 可选键盘布局状态命令；上游来源：<https://github.com/nonpop/xkblayout-state>。缺失时 `sb-kbselect` 回退到 `setxkbmap`。 |
| `notify-send` (libnotify) | 桌面通知 |
| `fcitx5` | 首选已配置输入法；`fcitx` 或 `ibus` 为回退 |
| `xcape` | 启用时将 Caps 作为 Escape/修饰键重映射 |
| `microsoft-edge` | 当前 `BROWSER` 的值 |

## 外观、字体与壁纸

| 软件或命令 | 用途 |
| --- | --- |
| Arc GTK 主题、Adwaita 图标主题 | 已跟踪 GTK 外观 |
| Qt GTK platform theme | `QT_QPA_PLATFORMTHEME=gtk3` 对 Qt5/Qt6 程序的 GTK 外观集成 |
| Linux Libertine 和 Biolinum | 主要比例 UI/文档字体 |
| Noto Sans CJK SC、Noto Serif CJK SC、Noto Sans Mono CJK SC | 中文和等宽回退字体 |
| Noto Color Emoji、FontAwesome | Emoji 与 LF/状态栏图标 |
| `wal` (pywal) | `setbg` 生成的可选颜色；缺失时静态颜色仍可用 |
| `lxappearance` | 可选交互式 GTK 设置编辑器 |

## 音频、音乐、录制与视频

| 软件或命令 | 用途 |
| --- | --- |
| PipeWire、`pipewire-pulse`、WirePlumber、`wpctl` | 默认音频栈、输出音量和麦克风静音控制；`pipewire-pulse` 为需要它的应用提供 PulseAudio 兼容服务端 |
| ALSA 库、`pipewire-alsa` 和可选 ALSA 工具 | 平台系统配置可将默认设备接入 PipeWire；显式 `hw:` 访问仍可用，但不承诺服务失效时自动回退；已跟踪 `asoundrc` 不固定硬件 |
| `mpd`, `mpc`, `ncmpcpp` | 音乐守护进程、控制客户端和终端界面 |
| `pulsemixer` | 已配置交互式音频混音器 |
| `mpv`, `socat`, `ffmpeg` | 视频播放、MPV IPC 辅助、录制/转码 |
| `slop` | 选区录制 |
| V4L2 摄像头设备 | 摄像头录制路径 |
| `sox` | `noisereduce` 辅助工具 |
| ImageMagick（`convert`） | `slider` 和图像转换 |
| `vorbiscomment`, `opustags`, `eyeD3`, `metaflac` | `tag` 元数据辅助工具 |

## 文件、文档、密码与桌面处理

| 软件或命令 | 用途 |
| --- | --- |
| `lf`, `ueberzug`, `atool`, `mimeopen`, `vidir` | 文件管理、预览、归档/MIME 工作流 |
| `nsxiv`, `zathura`, `mpv`, `gimp` | 图像、PDF、视频和图形处理器 |
| `localc`（LibreOffice Calc） | LF 中配置的电子表格处理器 |
| ImageMagick（`display`、`convert`）、`mediainfo`、`ffmpegthumbnailer` | LF 图像/视频预览 |
| `pdftoppm`, `pdftotext`, `pdfinfo`, `pdffonts`, `odt2txt` | 文档预览、PDF 渲染/字体检查和 `getbib` |
| `gpg`, `man`, `col`, `xdg-open` | 加密、手册、格式化文本和桌面打开 |
| `neomutt`, `abook`, `newsboat` | 已配置邮件、通讯录和 RSS 客户端；DWM `Mod+Shift+e` 直接启动 Abook，与 Mutt Wizard 共用 Abook 默认数据目录 |
| `pass`、GnuPG、图形 Pinentry、`pass-otp`、`zbarimg`、`maim`、`xclip`、`dmenu` | 加密密码库及图形解锁、OTP、二维码、截图和菜单辅助工具 |
| 已跟踪的 `passmenu`、Bash、`dmenu`、`xclip`；可选 `xdotool` | 独立 DWM 的 `Mod+Shift+d` 密码菜单；默认通过 `pass` 复制密码，只有显式 `--type` 才向当前焦点窗口自动输入 |
| `timedatectl`、`chronyc` 或 `ntpdate` | OTP 时钟同步检查 |
| WPS Office 和 `wps-office-prometheus.desktop` | 已配置办公 MIME 默认项 |
| `clash-verge` 和已跟踪的 `clash-verge-handler.desktop` | `clash`、`clash-verge` URI 方案处理器；本地 handler 避免依赖发行版 desktop 文件名，仅在使用相应链接时需要 |

桌面入口会调用 `st`、`lfub`、`nsxiv`、`neomutt`、`zathura`、`nvim`、`rssadd`、
`transadd` 和 `mpv`；使用相应入口时应安装对应命令。

若干 DWM 绑定调用已跟踪本地辅助命令而非单独软件包：`dmenuunicode`、`dmenumount`、
`dmenuumount`、`dmenurecord`、`maimpick`、`mailsync`、`td-toggle`、`torrent`、
`tutorialvids` 和 `remaps`。其外部要求列于上方相关章节。

## 显示、网络、挂载与系统控制

| 软件或命令 | 用途 |
| --- | --- |
| `xrandr`, `flock` | `xdisplay.sh` 与 `displayselect` 的基础显示布局和互斥；缺少任一命令时拒绝运行 |
| `dmenu`, `bc` | `displayselect` 的选择界面和双屏镜像缩放计算 |
| `arandr` | `displayselect` 的可选手动布局界面；选中该路径但缺少命令时提示安装 |
| `dunst`, `xwallpaper` | 手动布局后的可选通知与壁纸刷新；不属于自动 watcher 的基础依赖 |
| `cvt` | 仅在非标准面板确需自定义 modeline 时使用的可选设备适配开发工具 |
| `systemd-analyze`, `udevadm` | 可选的 logind 合并配置检查和显示迁移规则维护工具；不属于 watcher 运行依赖 |
| NetworkManager 守护进程、`nmtui`、`nmcli` | 网络连接、自动连接、地址/路由/DNS 所有权、交互式设置和诊断；选择该栈时，同一接口不能再由其他网络管理器接管 |
| `wpa_supplicant` | 可供 NetworkManager 选用的全局 D-Bus Wi-Fi 认证后端，也是已跟踪接口模板的实现；平台可选择 NetworkManager 支持的其他认证后端，选用时仍不取代 NetworkManager 的连接和三层网络所有权 |
| `xbacklight` | 亮度键和状态栏滚轮动作 |
| `lm-sensors` | 硬件导出 CPU 传感器时的 CPU 温度模块 |
| `mount`、`umount`、`lsblk` | 普通块设备挂载、卸载和发现 |
| `mount.cifs`、`smbclient`、`avahi-browse`、Avahi 守护进程 | CIFS 发现和挂载辅助工具 |
| systemd-logind（`systemctl`）或 elogind（`loginctl`）、`flock`、`xss-lock`、`slock`、`pstree` | 硬件睡眠键、挂起前锁屏以及 `sysact` 电源/会话控制；`flock` 按登录会话和 X server 保证单实例，`xss-lock` 只桥接 login1 事件，不接管 XScreenSaver 空闲超时 |
| `geoiplookup` | 可选 IP 地理位置状态模块 |
| `synclient` 和 X11 Synaptics 触摸板驱动 | 为单独构建 DWM 触摸板切换代码保留的可选依赖；无已跟踪 dotfiles 运行调用 |
| `screenkey` | 为单独构建 DWM 绑定保留的可选按键覆盖层；无已跟踪 dotfiles 运行调用 |

## 状态栏、通信与网络服务

| 软件或命令 | 用途 |
| --- | --- |
| `htop`, `bmon`, `cal`, `calcurse`, `sensors` | 系统、网络、日历和温度模块 |
| `curl`, `nmtui`, `newsboat`, `neomutt`, `mbsync`, Mutt Wizard (`mw`) | 网络、RSS 和邮件模块；Mutt Wizard 提供邮箱模块使用的本地 `mw` 账户/同步包装器 |
| `profanity` | 独立 DWM 源码中 `Mod+c` 调用的可选终端 XMPP 客户端 |
| `tsp`, `transmission-remote`, `wpctl`, `pulsemixer` | 任务队列、种子和音频模块 |
| `dwmblocks` | 渲染状态模块并接收其实时信号 |
| 到 `wttr.in` 的出站 HTTPS 访问 | 天气预报和月相模块 |
| 出站 HTTPS 数据源 | 启用时的 Doppler 和价格模块 |
| `urlscan` | 已配置 Newsboat URL 选择宏 |
| `youtube-viewer` | 最低优先级可选 Newsboat 视频宏；常规 RSS 和视频处理已有浏览器、`mpv`、`yt-dlp` 与 `linkhandler`，正常部署不要求安装 |

包状态模块需要 APT、pacman、XBPS 或 Portage 之一。APT 检查脚本还使用 `sudo`。

## 下载、种子与文本浏览

| 软件或命令 | 用途 |
| --- | --- |
| `yt-dlp`, `curl`, `tsp`, `entr` | 队列下载和 RSS 队列监控 |
| `transmission-daemon`, `transmission-remote`, `transmission-show` | 种子守护进程、辅助工具和状态模块 |
| `lynx` | `dmenuhandler` 中的文本浏览器选项 |
| `urlview` | 已配置 tmux URL 选择绑定 |
| Facebook PathPicker (`fpp`) | 最低优先级可选 tmux 路径选择绑定；正常部署不需要 |
| `tremc` | 最低优先级可选 Transmission 终端界面。没有它时 `torrent` 启动守护进程并引导用户使用 Web 界面或 `transmission-remote` |

## 编译、排版与数据辅助

| 源格式或辅助工具 | 命令 |
| --- | --- |
| TeX 根文件与构建编排 | 已跟踪的 `texroot` 统一解析根文件；`latexmk` 负责多轮编译、交叉引用和清理 |
| TeX 引擎 | `pdflatex`、`xelatex`、`lualatex`；LuaLaTeX 还需要完整字体和宏包能力 |
| TeX 参考文献 | `biber` 和 BibLaTeX 宏包 |
| TeX 中日文排版 | 中文文档需要 `ctex`/`xeCJK` 与相应字体，日文文档按需提供 LuaTeX-ja 等语言能力 |
| Groff、mom 和 ms | `preconv`、`refer`、`groff`；DWM `Mod+F1` 帮助还需要可供 Groff 嵌入 PDF 的 Nimbus Sans Type 1 字体 |
| Markdown | `lowdown` 或 `groffdown`，否则 `pandoc` |
| Org mode | 带 Org 和 LaTeX 导出支持的 `emacs` |
| R Markdown | 带 `rmarkdown` 包的 `Rscript` |
| C、C++、C#、Go、Java、Rust | `cc`, `g++`, `mcs`, `mono`, `go`, `javac`, `java`, `cargo` |
| Octave、Sass、OpenSCAD、Sent | `octave`, `sassc`, `openscad`, `sent` |
| 其他构建和 TeX 精确清理 | `make`、GNU `rm`；TeX 通用清理由 `latexmk` 完成，不再依赖目录正则搜索 |
| 有声书分割 | `ffmpeg`、`iconv` |

## 模板与计划工作

系统示例不会自动安装。仅在安装相应栈后复制并调整：

- `.local/share/sys-etc/portage/make.conf.template`：Portage 和 `emerge`
- `.local/share/sys-etc/systemd/network/wireless.network.template`:
  systemd-networkd 和 `networkctl`；只用于由 systemd-networkd 管理的接口
- `.local/share/sys-etc/wpa_supplicant/wpa_supplicant.conf.template`:
  接口级 `wpa_supplicant`；与上一模板组成可选栈，不得用于 NetworkManager 已管理的同一接口

这套 systemd-networkd/接口级 `wpa_supplicant` 模板栈与 NetworkManager 对同一接口互斥。
平台为 NetworkManager 选择全局 D-Bus `wpa_supplicant` 作为 Wi-Fi 认证后端时不构成重复管理。

cron 辅助命令需要 `cron`、`crontab`、`notify-send`、`xdotool`、`newsboat` 和运行中的
用户 DBus 会话。`.local/bin/cron/README.md` 的示例设置 `DISPLAY` 和
`DBUS_SESSION_BUS_ADDRESS`，随后加载 `.profile`。`checkup` 是平台专用的包更新辅助命令，只能在
对应平台档案验证其包管理器和参数后启用；需要提权的无人值守分支必须配置范围严格的免密 sudo
规则，否则保持手动检查。

## 平台映射

发行版包提供者、安装状态、服务所有权和实机结果维护在[平台档案索引](../platforms/index.md)；
不得将任一平台的软件包快照视为通用需求清单。

## LARBS 迁移参考

以下来源软件包记录从 `larbs/progs.csv` 迁移而来。它们保留原始用途，同时区分当前活跃
配置与旧 LARBS/Arch/Void 假设。

为保留可追溯性，表中的“原始用途”保留上游英文原文；历史包名、URL 和原始描述均不是
当前部署要求。“当前处置”说明本库对这些来源记录的中文结论。

### X11、字体与早期桌面选择

| 来源记录 | 原始用途 | 当前处置 |
| --- | --- | --- |
| `xorg-server`, `xorg-xinit`, `xorg-minimal` | Graphical server and startup | 当前活跃要求，在 X11 布局（layout）中以 Xorg/Xinit 表示；来源名称是发行版专属的。 |
| `xorg-xwininfo` | Query window information | 历史来源条目；已跟踪辅助命令改用活跃的 `xprop`。 |
| `libxft-bgra` | Color emoji rendering in suckless software | 历史源码构建依赖；仅当单独构建的 DWM/ST 源码需要该补丁时保留。 |
| `xorg-fonts`, `ttf-inconsolata`, `nerd-fonts-inconsolata`, `ttf-linux-libertine` | LARBS fonts and symbols | 已被跟踪的 Fontconfig/GTK 字体选择替代：Linux Libertine、Noto CJK、Noto Color Emoji 和 FontAwesome。 |
| `libX11-devel`, `libXft-devel`, `gcr-devel`, `fontconfig-devel` | Build dependencies | 历史 Arch/Void 包名不是当前通用名称；X11/Xft/Fontconfig 开发能力仍是四个独立桌面源码的活跃构建要求，`gcr-devel` 当前无源码引用。 |
| `i3-gaps` | Earlier window manager | 历史项；当前会话启动 DWM。 |
| `ranger-git` | Earlier terminal file manager | 历史项；LF 是已配置文件管理器。Ranger 帮助数据仅作参考。 |
| `arandr` | Screen-layout UI | 活跃 `displayselect` 手动布局依赖。 |
| `bc` | Calculator and arithmetic | 活跃计算器别名和显示布局算术辅助。 |
| `calcurse` | Terminal calendar | 活跃别名和状态栏日历辅助。 |
| `xcompmgr` | Transparency/compositing | `xprofile` 中的可选回退路径；Picom 是活跃合成器。 |
| `xorg-xprop`, `xprop` | Window property query | 活跃 `samedir` 辅助依赖。 |
| `dosfstools`, `exfat-utils` | DOS/FAT filesystem management | 历史包条目；当前挂载辅助使用系统 `mount`/`lsblk`，不格式化文件系统。 |
| `libnotify` | Desktop notifications | 活跃 `notify-send` 提供者，在 X11 布局（layout）中表示。 |
| `dbus` | Inter-process communication | 活跃 X11 会话要求，以 `dbus-launch` 和 D-Bus 激活工具表示。 |
| `dunst` | Notification daemon | 活跃通知服务。 |
| `sxiv` | Image viewing | 已在全部跟踪配置中被 `nsxiv` 替代。 |
| `xwallpaper` | Wallpaper setting | 活跃 `setbg` 后端。 |
| `ffmpeg` | Command-line video/audio processing | 活跃播放、录制、缩略图、幻灯片和媒体处理依赖。 |
| `gnome-keyring` | System keyring | 历史项；无已跟踪配置调用它。 |

### 媒体、文件、Shell 与状态来源

| 来源记录 | 原始用途 | 当前处置 |
| --- | --- | --- |
| `gtk-theme-arc-gruvbox-git` | Dark GTK theme | 历史 Arch 包名；已跟踪外观选择 Arc 主题。 |
| `neovim` | Improved Vim editor | 活跃编辑器，在 Shell 布局（layout）中以 `vim`/`nvim` 表示。 |
| `i3blocks` | Earlier status bar | 历史项；当前状态栏是 DWMBlocks。 |
| `mpd`, `mpc`, `mpv`, `ncmpcpp` | Music daemon, control, playback, and terminal UI | 活跃音频和音乐依赖。 |
| `newsboat` | Terminal RSS client | 活跃 RSS 客户端和状态栏集成。 |
| `brave-bin` | Earlier browser | 历史项；当前 `BROWSER` 是 Microsoft Edge。 |
| `noto-fonts-emoji` | Emoji font | 活跃要求，以 Noto Color Emoji 表示。 |
| `font-symbola` | Unicode and emoji symbols | 历史字体替代；FontAwesome 和 Noto Color Emoji 是当前已配置图标字体。 |
| `ntfs-3g` | NTFS access | 可选文件系统支持；无已跟踪辅助命令直接调用，部分内核也可能提供 NTFS3。 |
| `alsa-utils` | ALSA interface tools | 可选工具包；保留 ALSA 配置和捕获路径需要 ALSA 栈，而非特定 `alsa-utils` 命令。 |
| `sc-im` | Terminal spreadsheet manager | 历史可选应用；`localc`/WPS MIME 处理器是当前电子表格路径。 |
| `maim`, `socat`, `tmux`, `unclutter` | Screenshots, MPV IPC, terminal multiplexing, pointer hiding | 各自布局（layout）中的活跃依赖。 |
| `unclutter-xfixes` | Pointer hiding | 历史替代；当前命令是 `unclutter`。 |
| `unrar`, `unzip` | Archive extraction | 活跃 LF/FZF 归档预览和提取辅助。 |
| `lynx` | Text browser | 活跃 dmenu、LF 和 Newsboat 文本浏览器选项。 |
| `xcape`, `xclip`, `xdotool`, `xorg-xdpyinfo`, `xdpyinfo` | Key remapping, clipboard, window action, screen query | 活跃 X11 辅助依赖；`xorg-xdpyinfo` 是历史来源名称。 |
| `youtube-dl` | Video download | 已被活跃 `yt-dlp` 替代。 |
| `zathura` | Vim-like PDF viewer | 活跃文档查看器。 |
| `zathura-pdf-mupdf` | Zathura PDF backend | 历史后端专属条目；当前配置需要发行版提供的 Zathura PDF 后端，而非特定 MuPDF。 |
| `python-ueberzug` | Terminal image previews | 活跃预览能力由当前 `ueberzug` 命令表示；来源包名是历史的。 |
| `poppler` | PDF manipulation and previews | 活跃 PDF 预览/工具能力由 `pdftoppm`、`pdftotext`、`pdfinfo` 和 `pdffonts` 表示。 |
| `mediainfo`, `atool`, `fzf`, `highlight`, `xorg-xbacklight` | Media info, archive handling, fuzzy finding, highlighting, brightness | 活跃依赖；`xorg-xbacklight` 映射为当前 `xbacklight`。 |
| `zsh-syntax-highlighting` | Fish-like shell highlighting | 活跃已配置 Oh My Zsh/zplug 插件。 |
| `task-spooler`, `ts` | Background command queue | 活跃 `tsp` 队列依赖；`ts` 是历史命令/包拼写。 |
| `setxkbmap`, `xset` | Keyboard layout and X repeat settings | 活跃 X11 输入辅助。 |
| `xmodmap`, `xsetroot` | Earlier keyboard/status-root handling | 历史项；重映射使用 `setxkbmap`，状态输出由 DWMBlocks 管理。 |
| Luke Smith `dwmblocks`, `dmenu`, `st`, `dwm` Git URLs | Status bar, launcher, terminal, window manager | 历史上游源码引用。当前单独构建源码位于 `~/src/`；活跃运行命令在 X11 布局（layout）中记录。 |
| `slock` | Screen lock | 活跃 `sysact` 锁屏依赖。 |
