# 依赖与文档审计记录

审计范围：当前 Debian 系统。其他发行版分支仅做语法检查。

状态：第一阶段进行中。发现缺失依赖时，仅暂停对应项目；不得以未验证的替代项
自动改写配置。

## 第一批：根目录兼容入口与 FbTerm 配置

| 来源文件 | 依赖 | 要求级别 | 安装状态 | 依赖布局（layout） | `progs.csv` 状态 | 处理结果 |
| --- | --- | --- | --- | --- | --- | --- |
| `.profile`、`.zprofile`、`.xinitrc`、`.xprofile`、`.asoundrc`、`.gtkrc-2.0` | 无；均为指向规范配置的兼容链接 | 不适用 | 不适用 | 不适用 | 不适用 | 通过；目标文件将在所属批次审计 |
| `.gitignore` | 无 | 不适用 | 不适用 | 不适用 | 不适用 | 通过 |
| `.bashrc` | `bash`、`stty`、`tput`、`git`、Bash/Git completion、`fzf`、`groff` | 必需或条件可选 | 已安装；补全文件可读；`~/.fzf.bash` 缺失但已有条件加载 | Shell、源代码管理与开发 | 待核对 | 已验证，`bash -n` 通过 |
| `.gitconfig` | `git`、`vim`、`less` | 必需 | 已安装；`git`、`less` 由 Debian 软件包提供，`vim` 可执行 | Shell、源代码管理与开发 | 待核对 | 已验证，待 `progs.csv` 全量迁移时核对说明 |
| `.npmrc` | `npm` | 必需（使用 npm 时） | 已安装；当前由 NVM 提供，非 APT 软件包 | Shell、源代码管理与开发 | 待核对 | 已验证，待 `progs.csv` 全量迁移时核对说明 |
| `.config/shell/profile` | `find`、`nvim`、`st`、`microsoft-edge`、`zathura`、`lfub`、`dwm`、`dwmblocks`、`highlight`、`shortcuts`、`dmenupass`、Qt GTK 平台主题 | 必需或已启用默认功能 | 已安装；Qt5/Qt6 GTK 平台主题由 `qt5-gtk-platformtheme`、`qt6-gtk-platformtheme` 提供 | Shell、源代码管理与开发；X11 桌面与输入；文件、文档与桌面处理 | 待核对 | 已验证，`sh -n` 通过 |
| `.config/shell/zprofile` | `zsh`、`sudo`、`loadkeys`、`startx`、Xorg、`tty`、`pgrep`、`ttymaps.kmap` | 必需（登录与本地 X11 启动时） | 已安装；`loadkeys` 由 `kbd`、`startx` 由 `xinit`、Xorg 由 `xserver-xorg-core` 提供；键盘映射可读 | Shell、源代码管理与开发；X11 桌面与输入 | 待核对 | 已验证，`zsh -n` 通过 |
| `.config/x11/xinitrc` | `sh`、`ssh-agent`、`dwm`、`.config/x11/xprofile` | 必需（`startx` 会话） | 已安装；规范 xprofile 文件存在 | X11 桌面与输入 | 待核对 | 已验证，`sh -n` 通过 |
| `.config/x11/xprofile` | `dbus-update-activation-environment`、`dbus-launch` | 必需（完整 X11 D-Bus 会话） | 已安装；`dbus-launch` 由 Debian 软件包 `dbus-x11` 提供 | X11 桌面与输入 | 待核对 | 已验证；现有条件判断保留为兼容保护 |
| `.config/x11/xprofile` | `fcitx5`、`xrandr`、`xrdb`、`xset`、`picom`、`mpd`、`dunst`、`unclutter`、本地 `setbg`/`remaps`/`xdisplay.sh` | 已启用 X11 会话功能 | 已安装；`fcitx`、`ibus`、`xcompmgr` 缺失但均为有条件回退路径 | X11 桌面与输入；外观、字体与壁纸；音频、音乐、录制与视频 | 待核对 | 已验证，`sh -n` 通过；PipeWire 用户服务运行状态需在正常用户会话复查，沙箱不可访问用户 D-Bus |
| `.config/x11/xresources` | `xrdb`、等宽字体 | Xresources 加载 | 已安装；`xrdb` 已由 xprofile 审计，`monospace` 字体解析由 Fontconfig 提供 | X11 桌面与输入；外观、字体与壁纸 | 待核对 | 通过；实际加载在 X11 会话复查 |
| `.config/x11/picom.conf` | `picom` | X11 合成器 | 已安装于 `/usr/local/bin/picom` | X11 桌面与输入；外观、字体与壁纸 | 待核对 | 通过；实际合成效果在 X11 会话复查 |
| `.config/alsa/asoundrc` | ALSA 库与 PipeWire ALSA 兼容层 | 保留的音频回退配置 | 已由现有 PipeWire/ALSA 栈提供 | 音频、音乐、录制与视频 | 待核对 | 通过；不设置会破坏 PipeWire 的 `ALSA_CONFIG_PATH` |
| `.config/dunst/dunstrc`、`.config/wal/postrun`、`.config/wal/templates/dunstrc` | `dunst`、`pkill`、`setsid`、`wal` | 通知与可选 pywal 后处理 | `dunst`、`pkill`、`setsid` 已安装；`wal` 仅在调用 `setbg` 生成配色时需要 | 外观、字体与壁纸 | 待核对 | 已验证，`wal/postrun` 语法通过；默认静态配色不依赖 wal |
| `.config/fontconfig/fonts.conf` | Fontconfig、Linux Libertine/Biolinum、Noto CJK 字体 | 字体回退配置 | 已安装并可解析 | 外观、字体与壁纸 | 待核对 | 已验证 |
| `.config/gtk-2.0/gtkrc-2.0`、`.config/gtk-3.0/settings.ini` | Arc GTK 主题、Adwaita 图标主题 | GTK 外观 | 已安装，主题目录存在 | 外观、字体与壁纸 | 待核对 | 已验证 |
| `.config/wget/wgetrc` | `wget` | 下载工具配置 | 已安装 | Shell、源代码管理与开发 | 待核对 | 已验证 |
| `.config/shell/aliasrc` | `bc` | 已启用计算器及显示选择功能 | 已安装，Debian 软件包 `bc` | 显示、网络、挂载与系统控制 | 待核对 | 已验证 |
| `.config/shell/aliasrc` | `transmission-remote` | 可选种子控制别名 | 已安装，Debian 软件包 `transmission-cli` | 下载、种子与文本浏览 | 待核对 | 已验证；守护进程已在种子脚本批次复查，`tremc` 已降为最低优先级可选项 |
| `.config/shell/aliasrc`、`.config/newsboat/config` | `youtube-viewer` | 最低优先级可选视频别名及 Newsboat 宏 | 不检查安装状态 | 状态栏、RSS、邮件、天气与任务队列 | 待核对 | 代码完备性已验证：仅由可选 Newsboat 视频宏和别名调用；常规流程已有浏览器、`mpv`、`yt-dlp` 与 `linkhandler`，本轮不安装或运行验证 |
| `.config/shell/aliasrc` | `calcurse` | 可选日历别名和状态栏操作 | 已安装，Debian 软件包 `calcurse` | 状态栏、RSS、邮件、天气与任务队列 | 待核对 | 已验证 |
| 图像查看链路（`.config/shell/aliasrc`、LF、桌面条目与处理脚本） | `nsxiv` | 已批准整体替换当前 `sxiv` 图像查看链路 | 已安装，Debian 软件包 `nsxiv` | 文件、文档与桌面处理 | `sxiv` 行已迁移为历史替代 | 已迁移配置目录、调用点、桌面条目、帮助文本和项目文档；待 X11 图形流程复查 |
| `.config/shell/aliasrc` | `lazygit` | 可选 Git TUI 别名 | 已安装，Debian 软件包 `lazygit` | Shell、源代码管理与开发 | 不存在 | 已验证；后续需补入 `dependencies.md` |
| `.config/shell/aliasrc` | 本地 `cc-switch` 包装 | 可选自定义别名 | 已安装于 `~/.local/bin/cc-switch` | Shell、源代码管理与开发 | 不存在 | 已验证；非外部软件包 |
| `.config/shell/aliasrc` | APT 分支 | 当前 Debian 包管理 | 已安装 | Shell、源代码管理与开发 | 待核对 | 已验证，`sh -n` 通过；pacman、XBPS、Portage 分支留作语法检查 |
| `.fbtermrc` | `fbterm` | 必需（使用 FbTerm 时） | 已安装，Debian 软件包 `fbterm` | 外观、字体与壁纸 | 不存在 | 已验证 |
| `.fbtermrc` | Hack、Fira Code、JetBrains Mono、Noto Sans Mono CJK SC、Sarasa Mono SC、Noto Sans CJK SC | 回退字体链 | 已安装并可被 Fontconfig 解析；Noto Sans Mono CJK SC 由 Debian `fonts-noto-cjk` 提供 | 外观、字体与壁纸 | 待核对 | 已验证；以仓库既有等宽中文字体替换缺失的 Maple Mono CN |
| `.tmux.conf`、`.tmux.conf.local` | `tmux` | 必需（使用 Tmux 时） | 已安装，Debian 软件包 `tmux` | Shell、源代码管理与开发 | 待核对 | 命令已验证；当前沙箱禁止 Tmux Unix 套接字操作，运行加载需在正常用户会话复查 |
| `.tmux.conf` | `urlview` | 可选 URL 选择绑定 | 已安装，Debian 软件包 `urlview` | 下载、种子与文本浏览 | 待核对 | 已验证 |
| `.tmux.conf` | Facebook PathPicker `fpp` | 最低优先级可选路径选择绑定 | 不检查安装状态 | 下载、种子与文本浏览 | 待核对 | 代码完备性已验证：绑定调用 `_fpp`，helper 对 `fpp` 使用 `|| true`；本轮不安装或运行验证 |
| `.tmux.conf` | `xclip`、`xsel` | X11 剪贴板绑定 | `xclip` 已安装；`xsel` 缺失，但配置会在无 `xsel` 时回退到 `xclip` | Shell、源代码管理与开发 | 待核对 | 已验证；不要求安装 `xsel` |
| `.config/mpd/mpd.conf`、`.config/ncmpcpp/config`、`.config/ncmpcpp/bindings`、`.local/bin/statusbar/sb-music`、`.local/bin/statusbar/sb-mpdup`、`.local/bin/sysact` | `mpd`、`mpc`、`ncmpcpp` | 已启用的本地音乐服务、控制客户端与终端界面 | 均已安装；`mpc` 不支持 `--version`，但可执行 | 音频、音乐、录制与视频 | 待核对 | 静态配置与关联脚本的 `sh -n` 检查通过；当前沙箱无权连接用户 D-Bus，`mpc status` 与 MPD 用户服务实际运行状态需在正常登录会话复查 |
| `.config/mpv/input.conf`、`.config/lf/lfrc`、`.local/bin/pauseallmpv`、`.local/bin/linkhandler`、`.local/bin/dmenuhandler` | `mpv`、`socat`、`ffmpeg`、`zathura`、`yt-dlp` | 已启用的媒体播放、MPV IPC、转码与文档查看 | 均已安装 | 音频、音乐、录制与视频；文件、文档与桌面处理 | 待核对 | 关联 Shell 脚本语法通过；图形交互与 MPV IPC 需在 X11 会话复查 |
| `.local/bin/qndl`、Newsboat 与 dmenu 下载队列入口、`.local/bin/statusbar/sb-tasks` | `tsp` | 已启用的后台下载队列与任务状态栏模块 | 已安装；Debian 包为 `task-spooler` | 下载、种子与文本浏览 | 待核对 | 可执行；`qndl` 与状态栏模块的 Shell 语法检查通过。实际队列任务需在正常用户会话按需复查 |
| `.local/bin/torrent`、`.local/bin/transadd`、`.local/bin/td-toggle`、`.local/bin/statusbar/sb-torrent` | `transmission-daemon`、`transmission-remote`、`transmission-show` | 已启用的本地种子守护进程、添加器、控制命令与状态栏 | 均已安装；`transmission-daemon` 单独由 Debian 软件包提供，其余由 `transmission-cli` 提供 | 下载、种子与文本浏览 | 待核对 | Shell 语法检查通过；守护进程实际监听、远程控制与状态栏刷新需在正常用户会话复查 |
| `.local/bin/torrent` | `tremc` | 最低优先级可选的 Transmission 终端界面 | 不检查安装状态；当前 Debian 仓库无同名软件包 | 下载、种子与文本浏览 | 待核对 | 已调整为可选：存在时启动 Tremc，缺失时仍启动守护进程并提示改用 Web 界面或 `transmission-remote`；本轮不安装或运行验证 |
| `.local/bin/dmenuhandler`、`.config/lf/scope`、`.config/newsboat/config` | `lynx` | dmenu、LF 预览和 Newsboat 中已提供的文本浏览器打开方式 | 已安装；Debian 包为 `lynx` | 下载、种子与文本浏览；文件、文档与桌面处理 | 待核对 | 版本可执行；`dmenuhandler` 与 LF scope 的 Shell 语法检查通过 |
| `.local/bin/podentr` | `entr` | 监控 Newsboat 队列文件并触发后台下载 | 已安装；Debian 包为 `entr` | 下载、种子与文本浏览 | 待核对 | 可执行，关联脚本的 Shell 语法检查通过；实际队列监控需在正常用户会话按需复查 |
| `.config/newsboat/config` | `urlscan` | Newsboat 外部 URL 选择器 | 已安装；Debian 包为 `urlscan` | 状态栏、RSS、邮件、天气与任务队列 | 待核对 | 版本可执行；Newsboat 实际交互需在终端会话按需复查 |
| `.local/bin/statusbar/sb-nettraf` | `bmon` | 状态栏网络流量模块的终端详情界面 | 已安装；Debian 包为 `bmon` | 状态栏、RSS、邮件、天气与任务队列 | 待核对 | 可执行，脚本语法检查通过；终端交互需在正常用户会话按需复查 |
| `.local/bin/statusbar/sb-clock` | `cal` | 状态栏日历弹窗 | 已安装；Debian 软件包 `ncal` 提供 | 状态栏、RSS、邮件、天气与任务队列 | 待核对 | 可执行，脚本语法检查通过 |
| `.local/bin/statusbar/sb-internet` | `nmtui` | 状态栏网络模块的交互式网络管理界面 | 已安装；Debian 软件包 `network-manager` 提供 | 状态栏、RSS、邮件、天气与任务队列 | 待核对 | 已明确保留该功能；脚本语法检查通过，实际网络管理需在正常用户会话复查 |
| `.local/bin/statusbar/sb-battery` | `xbacklight` | 状态栏电池模块的背光滚轮控制 | 已安装；Debian 包为 `xbacklight` | 显示、网络、挂载与系统控制 | 待核对 | 可执行，脚本语法检查通过；实际硬件背光支持需在 X11 会话复查 |
| `.local/bin/statusbar/sb-iplocate` | `geoiplookup` | 可选 IP 地理位置状态栏模块 | 未安装；Debian 包为 `geoip-bin` | 状态栏、RSS、邮件、天气与任务队列 | 待核对 | 脚本会先检查命令，缺失时静默隐藏模块；按可降级路径处理，不要求安装 |
| `.local/bin/statusbar/sb-mailbox` | Mutt Wizard (`mw`) | 状态栏邮件同步操作 | 已安装于 `/usr/local/bin/mw`，非 Debian 软件包 | 状态栏、RSS、邮件、天气与任务队列 | 不存在 | 已补入 `dependencies.md`；账户配置文件未被仓库跟踪，按审计范围排除，不读取或记录其内容 |
| `.local/share/applications/mail.desktop` | `st`、`neomutt` | 邮件桌面入口 | 均已安装 | 文件、文档与桌面处理 | 待核对 | 桌面入口的可执行路径与命令均可解析；实际桌面启动需在 X11 会话复查 |
| `.config/lf/scope` | `mediainfo` | 无图形预览时的媒体信息显示 | 已安装；Debian 包为 `mediainfo` | 文件、文档与桌面处理 | 已迁移 | 可执行；LF scope 语法检查通过 |
| `.config/lf/lfrc`、`.config/lf/scope` | `atool`、`aunpack` | LF 的归档列出与解包功能 | 已安装；Debian 包 `atool` 提供两者 | 文件、文档与桌面处理 | 已迁移 | 可执行；LF 配置与 scope 语法检查通过 |
| `.config/lf/scope` | `ffmpegthumbnailer` | 视频预览缩略图生成 | 已安装；Debian 包为 `ffmpegthumbnailer` | 文件、文档与桌面处理 | 待核对 | 可执行；实际视频预览需在 LF/X11 会话复查 |
| `.config/lf/scope` | `odt2txt` | ODT 文档文本预览 | 已安装；Debian 包为 `odt2txt` | 文件、文档与桌面处理 | 待核对 | 可执行；LF scope 语法检查通过 |
| `.config/lf/lfrc` | `vidir` | LF 批量重命名操作 | 已安装；Debian 包 `moreutils` 提供 | 文件、文档与桌面处理 | 待核对 | 可执行；LF 配置语法检查通过 |
| `.config/lf/lfrc` | `localc` | XLSX 电子表格打开方式 | 已安装；Debian 包 `libreoffice-calc` 提供 | 文件、文档与桌面处理 | 不存在 | 已补入 `dependencies.md`；可执行 |
| `.config/lf/lfrc` | `gimp` | XCF 图像打开方式 | 已安装；Debian 包为 `gimp` | 文件、文档与桌面处理 | 待核对 | 可执行；实际图形打开需在 X11 会话复查 |
| `.local/bin/noisereduce` | `sox` | 音视频降噪的噪声样本与滤波处理 | 已安装；Debian 包为 `sox` | 音频、音乐、录制与视频 | 待核对 | 可执行；脚本语法检查通过，实际媒体处理需按需复查 |
| `.local/bin/dmenurecord` | `slop` | 选区录屏 | 已安装；Debian 包为 `slop` | 音频、音乐、录制与视频 | 待核对 | 可执行；脚本语法检查通过，实际 X11 录制和硬件输入需在图形会话复查 |
| `.local/bin/opout` | `sent` | 打开 `.sent` 演示文稿输出 | 已安装；Debian 包为 `sent` | 编译、排版与数据辅助 | 待核对 | 可执行；脚本语法检查通过 |
| `.local/bin/maimpick`、`.local/bin/otp` | `maim` | 截图、截图式 OTP 二维码导入 | 已安装；Debian 包为 `maim` | 文件、文档与桌面处理 | 待核对 | 可执行；关联脚本语法检查通过，实际 X11 截图需在图形会话复查 |
| `.local/bin/otp` | `zbarimg` | OTP 二维码内容识别 | 已安装；Debian 包 `zbar-tools` 提供 | 文件、文档与桌面处理 | 待核对 | 可执行；关联脚本语法检查通过 |
| `.local/bin/otp` | `pass-otp` | 基于 `pass` 的一次性密码管理 | 已安装；Debian 包为 `pass-extension-otp` | 文件、文档与桌面处理 | 待核对 | `pass otp --help` 通过；实际密码库操作不在本轮执行 |
| `.local/bin/otp` | `timedatectl` 或 `chronyc` 或 `ntpdate` | OTP 时钟同步 | `timedatectl` 已安装；其运行状态受沙箱 systemd 总线限制，未验证 | 文件、文档与桌面处理 | 待核对 | 脚本已有按顺序回退逻辑；本轮不要求安装额外时间同步客户端 |
| `.local/bin/dmenumount`、`.local/bin/dmenuumount` | `simple-mtpfs` | Android MTP 挂载与卸载 | 未安装；当前 Debian 仓库无 `simple-mtpfs` 包 | 显示、网络、挂载与系统控制 | 已迁移为 Debian 挂起项 | 脚本使用其特定命令行接口；`jmtpfs`、`go-mtpfs` 虽有 Debian 包但未验证兼容性，Android 路径挂起；普通 USB 挂载不依赖此命令 |
| `.local/bin/dmenumountcifs` | `avahi-browse`、`smbclient`、CIFS 挂载支持 | 局域网 SMB 发现和挂载 | 已安装；Debian 包分别为 `avahi-utils`、`smbclient`、`cifs-utils` | 显示、网络、挂载与系统控制 | 待核对 | 可执行；`mount.cifs` 已由 `cifs-utils` 安装在 `/usr/sbin`，脚本语法检查通过；实际 LAN 发现与挂载需按需复查 |
| `.local/bin/displayselect` | `arandr` | 显示布局的手动选择入口 | 已安装；Debian 包为 `arandr` | 显示、网络、挂载与系统控制 | 待核对 | 可执行；`displayselect` Shell 语法检查通过，实际图形布局需在 X11 会话复查 |
| `.local/bin/displayselect`、`.local/bin/remaps`、`.local/bin/sysact`、`.local/bin/setbg`、`.local/bin/xdisplay.sh` | `xrandr`、`xset`、`xdotool`、`dunst`、`bc`、`xcape`、`slock`、`xwallpaper`、`wal` | 显示管理、键盘重映射、锁屏、壁纸与可选配色 | 均已安装；`wal` 为本地可执行文件 | 显示、网络、挂载与系统控制；外观、字体与壁纸 | 待核对 | Shell 语法检查通过；实际显示布局、壁纸和锁屏需在 X11 会话复查 |
| `.local/bin/dmenuunicode`、`.local/bin/getkeys`、`.local/bin/shortcuts`、`.local/bin/showclip`、`.local/bin/samedir`、`.local/bin/unix`、`.local/bin/weath` | `dmenu`、`xclip`、`xdotool`、`xprop`、`dunst`、`curl`、`less`、`pstree` | Unicode 输入、快捷键、剪贴板、同目录终端和天气辅助功能 | 均已安装 | Shell、源代码管理与开发；状态栏、RSS、邮件、天气与任务队列 | 待核对 | 全部 Shell 语法检查通过；需要 X11 或网络的实际交互按会话和网络条件复查 |
| `.local/bin/peertubetorrent`、`.local/bin/rssadd`、`.local/bin/rssget` | `curl`、`python3`、`dmenu`、本地 `transadd`、本地 `rssadd` | PeerTube 种子转交与 RSS 订阅发现/添加 | 均已安装或为已跟踪本地脚本 | 下载、种子与文本浏览；状态栏、RSS、邮件、天气与任务队列 | 待核对 | Shell 语法检查通过；RSS/PeerTube 网络请求不在本轮执行 |
| `.local/bin/xlight`、`.local/bin/cron/checkup`、`.local/bin/cron/crontog`、`.local/bin/ifinstalled` | `xbacklight`、APT、`sudo`、`crontab`、`notify-send` | 背光、包更新检查、cron 切换和依赖检查 | 均已安装；`cron` 包提供服务与 `crontab`，不提供同名命令 | 显示、网络、挂载与系统控制；Shell、源代码管理与开发 | 待核对 | Shell 语法检查通过；计划任务与 sudo 的实际交互需在正常用户会话复查 |
| `.local/bin/tag` | `vorbiscomment`、`eyeD3`、`metaflac` | OGG、MP3、FLAC 元数据写入 | 已安装；Debian 包分别为 `vorbis-tools`、`eyed3`、`flac` | 音频、音乐、录制与视频 | 待核对 | 可执行；脚本语法检查通过 |
| `.local/bin/tag` | `opustags` | Opus 元数据写入 | 已安装；Debian 包为 `opustags`。`opus-tools` 仅提供编码、解码和信息查询工具 | 音频、音乐、录制与视频 | 待核对 | 可执行；`tag` 脚本语法检查通过 |
| `.config/mimeapps.list`、`.local/share/applications/{file,img,mail,pdf,rss,text,torrent,video}.desktop` | `st`、`lfub`、`nsxiv`、`neomutt`、`zathura`、`rssadd`、`transadd`、`nvim`、`mpv`、WPS Office、`clash-verge` 桌面文件 | MIME 默认程序、自定义桌面入口和 Clash URI 方案处理器 | 均已安装或为已跟踪本地脚本；`wps-office-prometheus.desktop` 与 `Clash Verge.desktop` 存在于 `/usr/share/applications` | 文件、文档与桌面处理 | 待核对 | 所有 `Exec` 路径可解析；实际桌面启动和 URI 方案调用需在 X11 会话复查 |
| `.config/nsxiv/exec/key-handler` | `setbg`、`dmenu`、ImageMagick、`xclip`、`mediainfo`、`gimp`、本地 `ifinstalled` | nsxiv 的壁纸、文件操作、图像处理与信息按键 | 均已安装或为已跟踪本地脚本 | 文件、文档与桌面处理 | 待核对 | `sh -n` 通过；实际图形按键交互需在 X11 会话复查 |
| `.config/zsh/.zshrc` | `zsh`、Oh My Zsh、zplug、`thefuck`、`fzf`、NVM、Bun | Zsh 框架、插件与条件加载的开发环境 | 均已安装；NVM/Bun 由其本地初始化文件提供 | Shell、源代码管理与开发 | 待核对 | `zsh -n` 通过；本轮不触发 zplug 的联网安装或更新 |
| `.config/zsh/.zshrc` | `fd` 或 `fdfind`、`jq`、Docker (`docker`) | FZF 文件搜索、`json()` 剪贴板格式化、Docker 插件与 `attach()` | 已安装；Debian 包为 `fd-find`、`jq`、`docker.io` | Shell、源代码管理与开发 | 不存在 | Zsh 已修正为支持 Debian 的 `fdfind`，并实际选中该命令；Docker 守护进程运行状态需在正常用户会话复查 |
| `.config/shell/inputrc`、`.config/user-dirs.dirs` | `/etc/inputrc`、`xdg-user-dirs-update` | Readline vi 模式及 XDG 用户目录定义 | 均已安装且可读 | Shell、源代码管理与开发；文件、文档与桌面处理 | 待核对 | 配置为声明式内容；`/etc/inputrc` include 和 XDG 更新工具均可解析 |
| `.local/bin/install.sh` | `git`、OpenSSH 客户端、Bash、基础 POSIX 工具 | 通过 SSH 远程仓库部署 bare dotfiles | 均已安装 | Shell、源代码管理与开发 | 待核对 | `bash -n` 通过；新机器还需自行配置 GitHub SSH 凭据，审计不读取或记录账户密钥 |
| `.local/bin/install-ohmyz.sh` | `zsh`、`git`、`chsh`、网络 | Oh My Zsh 安装器 | 均已安装 | Shell、源代码管理与开发 | 待核对 | `sh -n` 通过；脚本会联网克隆上游仓库，安装行为本轮不执行 |
| `.local/bin/getbib` | `pdfinfo`、`pdftotext`、`curl` | 从 PDF/DOI 获取 Crossref BibTeX 条目 | 均已安装 | 文件、文档与桌面处理 | 待核对 | `sh -n` 通过；实际 Crossref 网络请求不在本轮执行 |
| `.local/bin/compiler`、`.local/bin/texclear` | 核心 POSIX 工具及按源文件类型选择的编译/排版工具链 | 文档、代码与演示文稿编译及 TeX 构建清理 | 核心工具已安装；完整工具链安装状态暂不逐项验证 | 编译、排版与数据辅助 | 待核对 | `sh -n` 通过；TeX 与多语言工具链的运行验证保留到确定实际启用范围后进行，不在本批次自动安装 |
| `.config/lf/icons`、`.config/newsboat/urls`、`.config/shell/bm-dirs`、`.config/shell/bm-files`、`.config/wal/templates/*`、`.local/patch/*`、`.local/share/larbs/{LICENSE,chars/,getkeys/,ttymaps.kmap}` | 无新增运行依赖 | 图标、书签、模板、补丁、帮助与数据资源 | 不适用 | 对应功能所属布局（layout） | 待核对或历史来源 | 通过；运行入口和外部命令已在所属配置或脚本批次审计 |
| `.local/bin/prompt`、`.local/bin/tutorialvids`、`.local/bin/queueandnotify`、`.local/bin/td-toggle`、`.local/bin/transadd` | `dmenu`、`mpv`、`curl`、`tsp`、Transmission、`notify-send`、本地 `ifinstalled` | 通用确认、教程视频、下载队列与种子管理入口 | 均已在所属批次验证 | 下载、种子与文本浏览；音频、音乐、录制与视频；X11 桌面与输入 | 待核对 | 已纳入全量 Shell 语法检查；不新增依赖 |
| `.local/share/sys-etc/{portage/make.conf.template,systemd/network/wireless.network.template,wpa_supplicant/wpa_supplicant.conf.template}` | Portage、systemd-networkd、`wpa_supplicant` | 非 Debian 系统服务模板 | 仅模板，不部署或安装 | 模板与计划工作 | 历史或仅模板 | 通过；按本轮 Debian 范围仅做格式与路径审阅，不验证其他发行版运行时 |
| `README.md`、`.local/share/docs/**`、`.local/share/larbs/progs.csv`、`.local/bin/cron/README.md` | 无直接运行时依赖；内容包含项目依赖说明 | 项目说明、计划与历史数据 | 不适用 | 文档与规划 | 第二至四阶段处理 | 第一阶段不把文档文字当作运行配置；`progs.csv` 迁移、依赖清单完整性和用户/架构文档对齐按后续阶段执行 |
| `dependencies.md` 第三阶段反向检索 | `pactl`、`pamixer`、`abook`、`profanity` | 旧依赖清单条目 | 无已跟踪运行时引用 | 对应布局（layout） | 不适用 | 已从活跃必需项移除；PipeWire 条目更正为不宣称提供 `pactl`，当前 `pulsemixer` 为已配置混音器 |
| `dependencies.md` 第三阶段反向检索 | `w3m`、`xkblayout-state`、`geoiplookup`、`synclient`、`screenkey` | 条件回退、可隐藏模块或外部 DWM 参考 | 不要求安装 | 对应布局（layout） | 不适用 | 已明确标注条件行为或仅外部源码用途；不阻塞 Debian 部署审计 |
| `desktop-guide-zh.md`、`architecture.md` 第四阶段对齐 | `dependencies.md` 的十个布局（layout） | 用户与维护文档结构 | 不适用 | 文档与规划 | 不适用 | 已为每个布局（layout）增加独立章节；保留原有启动流程、上游差异、工作流与维护边界 |
