# KaiTian X7h G1e + Debian 13 平台档案

## 设备基本信息

| 项目 | 平台事实 |
| --- | --- |
| 档案身份 | KaiTian X7h G1e 笔记本 + Debian 13 |
| 厂商与型号 | KaiTian X7h G1e；主板 `LXKT-HG4M-X7` |
| 架构与处理器 | `x86_64`；Hygon C86-4G 3450M，8 核 16 线程 |
| 内存 | 约 31 GiB 可用内存 |
| 显卡与驱动 | Fantasy II-M `[1ec8:9810]`；内核驱动 `inno-drv`，模块 `innogpu` |
| 发行版 | Debian GNU/Linux 13 `trixie`；审计快照为 13.6 |
| 内核快照 | `6.12.95+deb13-amd64`，仅表示 2026-07-17 的验证环境 |
| 图形会话 | X11、`startx`、DWM 6.5；登录链由 Xinit/Xprofile 启动 |
| 服务与包管理 | systemd 257；APT 3、dpkg `amd64` |
| 本轮起始基线 | 配置仓库 `257ae78`；DWM 仓库 `a00b789`；首轮记录 2026-07-17，内容复核 2026-07-19 |

## 适用范围与隐私边界

本档案是“该设备型号 + Debian 13”组合的唯一个性化事实来源，不代表所有笔记本、所有
innogpu 设备或其他 Debian 版本。同一设备升级到新的发行版主版本时新建档案，不覆盖本记录。

档案不得记录主机名、用户名、序列号、UUID、MAC/IP 地址、账户、凭据或原始 EDID。硬件和
系统快照只保留定位配置边界所需的非敏感信息；易变化的点版本、内核和软件版本必须附审计日期。

## 通用规则入口

- 稳定命令与能力：[依赖清单](../project/dependencies.md)
- 跨发行版验证步骤：[依赖与文档审计流程](../planning/dependency-audit.md)
- 共享结构与职责：[架构与设计](../project/architecture.md)
- 显示状态模型与验证：[X11 显示管理设计](../project/display-management.md)
- 非标准显示硬件扩展：[显示设备适配器指引](../project/display-device-adapter.md)
- 文档与平台边界：[维护策略](../project/maintenance-policy.md)

## Debian 13 依赖审计

状态：Debian 首轮审计已完成。其他发行版分支当时只做语法检查。发现缺失依赖时仅暂停对应
项目，不以未验证替代项自动改写配置。`progs.csv` 的一次性历史迁移已经结束，后续平台审计
不再处理该文件。

下表的 `progs.csv` 列是首轮迁移快照；其中“待核对”只表示当时尚未完成来源行迁移，不代表当前
任务或依赖状态。当前状态以本文“平台活动待办”和“平台挂起项目”为准。

| 来源文件 | 依赖 | 要求级别 | 安装状态 | 依赖布局（layout） | `progs.csv` 首轮快照 | 处理结果 |
| --- | --- | --- | --- | --- | --- | --- |
| `.profile`、`.zprofile`、`.xinitrc`、`.xprofile`、`.asoundrc`、`.gtkrc-2.0` | 无；均为指向规范配置的兼容链接 | 不适用 | 不适用 | 不适用 | 不适用 | 通过；目标文件将在所属批次审计 |
| `.gitignore` | 无 | 不适用 | 不适用 | 不适用 | 不适用 | 通过 |
| `.bashrc`、`.config/zsh/.zshrc` | `bash`、`zsh`、`stty`、`tput`、`git`、Bash/Git completion、`fzf`、`groff` | 必需或条件可选 | 已安装；Bash 补全文件可读；`~/.fzf.bash` 缺失但已有条件加载 | Shell、源代码管理与开发 | 待核对 | 已验证，`bash -n`、`zsh -n` 通过；`c` 在两种 shell 中均映射到完整 Git 补全，`diff` 无专属候选限制 |
| `.gitconfig` | `git`、`vim`、`less` | 必需 | 已安装；`git`、`less` 由 Debian 软件包提供，`vim` 可执行 | Shell、源代码管理与开发 | 已迁移 | 已验证；默认 `log.date` 使用 `%Y/%m/%d %H:%M:%S` |
| `.npmrc` | `npm` | 必需（使用 npm 时） | 已安装；当前由 NVM 提供，非 APT 软件包 | Shell、源代码管理与开发 | 已迁移 | 已验证 |
| `.config/shell/profile` | `find`、`nvim`、`st`、`microsoft-edge`、`zathura`、`lfub`、`dwm`、`dwmblocks`、`highlight`、`shortcuts`、`dmenupass`、Qt GTK 平台主题 | 必需或已启用默认功能 | 已安装；Qt5/Qt6 GTK 平台主题由 `qt5-gtk-platformtheme`、`qt6-gtk-platformtheme` 提供 | Shell、源代码管理与开发；X11 桌面与输入；文件、文档、密码与桌面处理 | 待核对 | 已验证，`sh -n` 通过 |
| `.config/shell/zprofile` | `zsh`、`sudo`、`loadkeys`、`startx`、Xorg、`tty`、`pgrep`、`ttymaps.kmap` | 必需（登录与本地 X11 启动时） | 已安装；`loadkeys` 由 `kbd`、`startx` 由 `xinit`、Xorg 由 `xserver-xorg-core` 提供；键盘映射可读 | Shell、源代码管理与开发；X11 桌面与输入 | 待核对 | `zsh -n` 通过；图形门槛动态接受任意 `/dev/dri/cardN` 或 `/dev/fbN`，不再固定 `card0` |
| `.config/x11/xinitrc` | `sh`、`ssh-agent`、`dwm`、`.config/x11/xprofile` | 必需（`startx` 会话） | 已安装；`openssh-client` 提供 `ssh-agent`，规范 xprofile 文件存在 | X11 桌面与输入 | 待核对 | 已验证，`sh -n` 通过 |
| `.config/x11/xprofile` | `dbus-update-activation-environment`、`dbus-launch` | 必需（完整 X11 D-Bus 会话） | 已安装；`dbus-launch` 由 Debian 软件包 `dbus-x11` 提供 | X11 桌面与输入 | 待核对 | 已验证；现有条件判断保留为兼容保护 |
| `.config/x11/xprofile` | `flock`、`xss-lock`、`slock`、systemd-logind 或 elogind | login1 锁屏/睡眠事件到 X11 locker 的单实例桥接 | 已安装；Debian 包 `util-linux` 提供 `flock`，`xss-lock` 为 `0.3.0+git20230128.0c562b-1+b2`，`suckless-tools` 提供 `slock 1.5`，当前 login manager 为 systemd-logind | X11 桌面与输入；显示、网络、挂载与系统控制 | 不存在 | 参数解析及 `flock` 互斥回归通过；重启 X11 后确认一个运行锁和一个 xss-lock 实例，真实挂起/恢复后实例继续存活且临时 slock 已退出；不使用 `--transfer-sleep-lock` |
| `.config/x11/xprofile` | `fcitx5`、`xrandr`、`flock`、`xrdb`、`xset`、`picom`、`mpd`、`dunst`、`unclutter`、本地 `setbg`/`remaps`/`xdisplay.sh` | 已启用 X11 会话功能 | 已安装；`fcitx`、`ibus`、`xcompmgr` 缺失但均为有条件回退路径 | X11 桌面与输入；外观、字体与壁纸；音频、音乐、录制与视频 | 待核对 | 已验证，`sh -n` 通过；`xprofile` 是仓库跟踪的显示 watcher 入口，单实例锁防止重复 watcher；未跟踪的 innogpu 恢复命令仅由可选本机钩子调用，不属于通用依赖；PipeWire 用户服务运行状态需在正常用户会话复查 |
| `~/src/{dwm,dwmblocks,dmenu,st}` | C 编译器、`make`、`pkg-config`、`tic` 及 X11/Xft/Xrender/Xinerama/Fontconfig/FreeType/HarfBuzz/X11-XCB/XCB/XCB Res 开发库 | 构建 X11 桌面四个独立源码仓库 | 均已安装；Debian 映射见下方关键映射 | X11 桌面与输入 | 不适用（独立源码仓库） | 四个 origin 均为 `https://github.com/darkroam/<repo>`；审计 HEAD 依次为 DWM `a00b789`、DWMBlocks `4874d4d`、dmenu `9d6f1c4`、st `d93faf0`。2026-07-18 在隔离副本中逐一 `make clean && make`，四个可执行文件均构建成功；DWM 删除旧睡眠键绑定后再次构建通过 |
| `~/src/dwm/{config.h,larbs.mom}` | `groff`、`fonts-urw-base35`、`zathura`、Zathura PDF 后端 | `Mod+F1` 动态帮助 | 已安装；当前 PDF 后端由 Debian `zathura-pdf-poppler` 提供 | X11 桌面与输入；编译、排版与数据辅助 | 不适用（独立源码仓库） | 源码与 `/usr/local/share/dwm/larbs.mom` 安装副本一致；实际快捷键命令生成 7 页非空 PDF，文本可提取，`NimbusSans-Regular` 为 `emb=yes`，代表页面已渲染且用户在 Zathura 实测无字符重叠 |
| `~/src/dwm/config.h` | `abook`、`profanity`、`wpctl`、本地 `passmenu` | 通讯录、XMPP、麦克风静音和密码菜单的 DWM 绑定 | `abook`、`profanity` 已安装；`wpctl` 已由 Debian `wireplumber` 包提供；`passmenu` 已跟踪于 `~/.local/bin` | 文件、文档、密码与桌面处理；状态栏、通信与网络服务；音频、音乐、录制与视频 | 不适用（独立源码仓库） | DWM 保留已验证的应用键，已删除 `XF86XK_Sleep`；安装副本只保留 `sysact` 字符串而无 `zzz`，硬件睡眠键交由 logind 唯一处理 |
| `.config/x11/xresources` | `xrdb`、等宽字体 | Xresources 加载 | 已安装；`xrdb` 已由 xprofile 审计，`monospace` 字体解析由 Fontconfig 提供 | X11 桌面与输入；外观、字体与壁纸 | 待核对 | 通过；实际加载在 X11 会话复查 |
| `.config/x11/picom.conf` | `picom` | X11 合成器 | 已安装于 `/usr/local/bin/picom` | X11 桌面与输入；外观、字体与壁纸 | 待核对 | 通过；实际合成效果在 X11 会话复查 |
| `.config/alsa/asoundrc` | ALSA 库与 `pipewire-alsa` | 保留通用 ALSA 入口，但不覆盖系统默认 PCM/CTL | `pipewire-alsa` 已安装；系统配置无条件把默认 PCM/CTL 交给 PipeWire，显式 `hw:` 设备仍可访问但不会在服务失效时自动接管默认值 | 音频、音乐、录制与视频 | 待核对 | 2026-07-18 `aplay -L` 确认 `default` 为 PipeWire；旧 `hw:Intel,0` 强制路由已从共享配置移除，且不设置会替换系统配置的 `ALSA_CONFIG_PATH` |
| `.config/dunst/dunstrc`、`.config/wal/postrun`、`.config/wal/templates/dunstrc` | `dunst`、`pkill`、`setsid`、`wal` | 通知与可选 pywal 后处理 | `dunst`、`pkill`、`setsid` 已安装；`wal` 仅在调用 `setbg` 生成配色时需要 | 外观、字体与壁纸 | 待核对 | 已验证，`wal/postrun` 语法通过；默认静态配色不依赖 wal |
| `.config/fontconfig/fonts.conf` | Fontconfig、Linux Libertine/Biolinum、Noto CJK 字体 | 字体回退配置 | 已安装并可解析 | 外观、字体与壁纸 | 待核对 | 已验证 |
| `.config/gtk-2.0/gtkrc-2.0`、`.config/gtk-3.0/settings.ini` | Arc GTK 主题、Adwaita 图标主题 | GTK 外观 | 已安装，主题目录存在 | 外观、字体与壁纸 | 待核对 | 已验证 |
| `.config/wget/wgetrc` | `wget` | 下载工具配置 | 已安装 | Shell、源代码管理与开发 | 待核对 | 已验证 |
| `.config/shell/aliasrc` | `bc` | 已启用计算器及显示选择功能 | 已安装，Debian 软件包 `bc` | 显示、网络、挂载与系统控制 | 待核对 | 已验证 |
| `.config/shell/aliasrc` | `transmission-remote` | 可选种子控制别名 | 已安装，Debian 软件包 `transmission-cli` | 下载、种子与文本浏览 | 待核对 | 已验证；守护进程已在种子脚本批次复查，`tremc` 已降为最低优先级可选项 |
| `.config/shell/aliasrc`、`.config/newsboat/config` | `youtube-viewer` | 最低优先级可选视频别名及 Newsboat 宏 | 不检查安装状态 | 状态栏、通信与网络服务 | 待核对 | 代码完备性已验证：仅由可选 Newsboat 视频宏和别名调用；常规流程已有浏览器、`mpv`、`yt-dlp` 与 `linkhandler`，本轮不安装或运行验证 |
| `.config/shell/aliasrc` | `calcurse` | 可选日历别名和状态栏操作 | 已安装，Debian 软件包 `calcurse` | 状态栏、通信与网络服务 | 待核对 | 已验证 |
| `.config/shell/aliasrc`、`.config/shell/profile` | `git` | Bash/Zsh 共用 Git 与 bare 配置仓库快捷命令、日志格式和交互认证设置 | 已安装 | Shell、源代码管理与开发 | 不存在 | 已验证；`gst` 保留 `gs` 的 Ghostscript 命令名，`cg*` 通过 `cfg_git` 固定使用 bare 配置仓库，Zsh 在 Oh My Zsh 后加载共享别名 |
| 图像查看链路（`.config/shell/aliasrc`、LF、桌面条目与处理脚本） | `nsxiv` | 已批准整体替换当前 `sxiv` 图像查看链路 | 已安装，Debian 软件包 `nsxiv` | 文件、文档、密码与桌面处理 | `sxiv` 行已迁移为历史替代 | 已迁移配置目录、调用点、桌面条目、帮助文本和项目文档；待 X11 图形流程复查 |
| `.config/shell/aliasrc` | `lazygit` | 可选 Git TUI 别名 | 已安装，Debian 软件包 `lazygit` | Shell、源代码管理与开发 | 不存在 | 已验证；已补入 `dependencies.md` |
| `.config/shell/aliasrc` | 本地 `cc-switch` 包装 | 可选自定义别名 | 已安装于 `~/.local/bin/cc-switch` | Shell、源代码管理与开发 | 不存在 | 已验证；非外部软件包 |
| `.config/shell/aliasrc` | APT 分支 | 当前 Debian 包管理 | 已安装 | Shell、源代码管理与开发 | 待核对 | 已验证，`sh -n` 通过；pacman、XBPS、Portage 分支留作语法检查 |
| `.fbtermrc` | `fbterm` | 必需（使用 FbTerm 时） | 已安装，Debian 软件包 `fbterm` | 外观、字体与壁纸 | 不存在 | 已验证 |
| `.fbtermrc` | Hack、Fira Code、JetBrains Mono、Noto Sans Mono CJK SC、Sarasa Mono SC、Noto Sans CJK SC | 回退字体链 | 已安装并可被 Fontconfig 解析；Noto Sans Mono CJK SC 由 Debian `fonts-noto-cjk` 提供 | 外观、字体与壁纸 | 待核对 | 已验证；以仓库既有等宽中文字体替换缺失的 Maple Mono CN |
| `.config/tmux/tmux.conf`、`.config/tmux/tmux.conf.local` | `tmux`、Perl | 必需（使用完整 Tmux 配置时） | 已安装，Debian 软件包为 `tmux`、`perl`；配置使用的核心 Perl 模块可加载 | Shell、源代码管理与开发 | 待核对 | 命令已验证；配置已迁移至 Tmux 支持的 XDG 路径，当前沙箱禁止 Tmux Unix 套接字操作，运行加载需在正常用户会话复查 |
| `.config/tmux/tmux.conf` | `urlview` | 可选 URL 选择绑定 | 已安装，Debian 软件包 `urlview` | 下载、种子与文本浏览 | 待核对 | 已验证 |
| `.config/tmux/tmux.conf` | Facebook PathPicker `fpp` | 最低优先级可选路径选择绑定 | 不检查安装状态 | 下载、种子与文本浏览 | 待核对 | 代码完备性已验证：绑定调用 `_fpp`，helper 会容忍 `fpp` 非零退出；本轮不安装或运行验证 |
| `.config/tmux/tmux.conf` | `xclip`、`xsel` | X11 剪贴板绑定 | `xclip` 已安装；`xsel` 缺失，但配置会在无 `xsel` 时回退到 `xclip` | Shell、源代码管理与开发 | 待核对 | 已验证；不要求安装 `xsel` |
| `.config/mpd/mpd.conf`、`.config/ncmpcpp/config`、`.config/ncmpcpp/bindings`、`.local/bin/statusbar/sb-music`、`.local/bin/statusbar/sb-mpdup`、`.local/bin/sysact` | `mpd`、`mpc`、`ncmpcpp` | 已启用的本地音乐服务、控制客户端与终端界面 | 均已安装；`mpc` 不支持 `--version`，但可执行 | 音频、音乐、录制与视频 | 待核对 | 静态配置与关联脚本的 `sh -n` 检查通过；当前沙箱无权连接用户 D-Bus，`mpc status` 与 MPD 用户服务实际运行状态需在正常登录会话复查 |
| `.config/mpv/input.conf`、`.config/lf/lfrc`、`.local/bin/pauseallmpv`、`.local/bin/linkhandler`、`.local/bin/dmenuhandler` | `mpv`、`socat`、`ffmpeg`、`zathura`、`yt-dlp` | 已启用的媒体播放、MPV IPC、转码与文档查看 | 均已安装 | 音频、音乐、录制与视频；文件、文档、密码与桌面处理 | 待核对 | 关联 Shell 脚本语法通过；图形交互与 MPV IPC 需在 X11 会话复查 |
| `.local/bin/qndl`、Newsboat 与 dmenu 下载队列入口、`.local/bin/statusbar/sb-tasks` | `tsp` | 已启用的后台下载队列与任务状态栏模块 | 已安装；Debian 包为 `task-spooler` | 下载、种子与文本浏览 | 待核对 | 可执行；`qndl` 与状态栏模块的 Shell 语法检查通过。实际队列任务需在正常用户会话按需复查 |
| `.local/bin/torrent`、`.local/bin/transadd`、`.local/bin/td-toggle`、`.local/bin/statusbar/sb-torrent` | `transmission-daemon`、`transmission-remote`、`transmission-show` | 已启用的本地种子守护进程、添加器、控制命令与状态栏 | 均已安装；`transmission-daemon` 单独由 Debian 软件包提供，其余由 `transmission-cli` 提供 | 下载、种子与文本浏览 | 待核对 | Shell 语法检查通过；守护进程实际监听、远程控制与状态栏刷新需在正常用户会话复查 |
| `.local/bin/torrent` | `tremc` | 最低优先级可选的 Transmission 终端界面 | 不检查安装状态；当前 Debian 仓库无同名软件包 | 下载、种子与文本浏览 | 待核对 | 已调整为可选：存在时启动 Tremc，缺失时仍启动守护进程并提示改用 Web 界面或 `transmission-remote`；本轮不安装或运行验证 |
| `.local/bin/dmenuhandler`、`.config/lf/scope`、`.config/newsboat/config` | `lynx` | dmenu、LF 预览和 Newsboat 中已提供的文本浏览器打开方式 | 已安装；Debian 包为 `lynx` | 下载、种子与文本浏览；文件、文档、密码与桌面处理 | 待核对 | 版本可执行；`dmenuhandler` 与 LF scope 的 Shell 语法检查通过 |
| `.local/bin/podentr` | `entr` | 监控 Newsboat 队列文件并触发后台下载 | 已安装；Debian 包为 `entr` | 下载、种子与文本浏览 | 待核对 | 可执行，关联脚本的 Shell 语法检查通过；实际队列监控需在正常用户会话按需复查 |
| `.config/newsboat/config` | `urlscan` | Newsboat 外部 URL 选择器 | 已安装；Debian 包为 `urlscan` | 状态栏、通信与网络服务 | 待核对 | 版本可执行；Newsboat 实际交互需在终端会话按需复查 |
| `.local/bin/statusbar/sb-nettraf` | `bmon` | 状态栏网络流量模块的终端详情界面 | 已安装；Debian 包为 `bmon` | 状态栏、通信与网络服务 | 待核对 | 可执行，脚本语法检查通过；终端交互需在正常用户会话按需复查 |
| `.local/bin/statusbar/sb-clock` | `cal` | 状态栏日历弹窗 | 已安装；Debian 软件包 `ncal` 提供 | 状态栏、通信与网络服务 | 待核对 | 可执行，脚本语法检查通过 |
| `.local/bin/statusbar/sb-internet`、`~/src/dwm/config.h` | `nmtui` | 状态栏和 `Mod+Shift+w` 的交互式网络管理界面 | 已安装；Debian 软件包 `network-manager` 提供 | 显示、网络、挂载与系统控制；状态栏、通信与网络服务 | 待核对 | 已在正常 X11 会话验证两个入口均可打开 `nmtui`，当前连接显示为已激活 |
| `.local/bin/statusbar/sb-battery` | `xbacklight` | 状态栏电池模块的背光滚轮控制 | 已安装；Debian 包为 `xbacklight` | 显示、网络、挂载与系统控制 | 待核对 | 可执行，脚本语法检查通过；实际硬件背光支持需在 X11 会话复查 |
| `.local/bin/statusbar/sb-iplocate` | `geoiplookup` | 可选 IP 地理位置状态栏模块 | 未安装；Debian 包为 `geoip-bin` | 状态栏、通信与网络服务 | 待核对 | 脚本会先检查命令，缺失时静默隐藏模块；按可降级路径处理，不要求安装 |
| `.local/bin/statusbar/sb-mailbox` | Mutt Wizard (`mw`) | 状态栏邮件同步操作 | 已安装于 `/usr/local/bin/mw`，非 Debian 软件包 | 状态栏、通信与网络服务 | 不存在 | 已补入 `dependencies.md`；账户配置文件未被仓库跟踪，按审计范围排除，不读取或记录其内容 |
| `.local/share/applications/mail.desktop` | `st`、`neomutt` | 邮件桌面入口 | 均已安装 | 文件、文档、密码与桌面处理 | 待核对 | 桌面入口的可执行路径与命令均可解析；实际桌面启动需在 X11 会话复查 |
| `.config/lf/scope` | `mediainfo` | 无图形预览时的媒体信息显示 | 已安装；Debian 包为 `mediainfo` | 文件、文档、密码与桌面处理 | 已迁移 | 可执行；LF scope 语法检查通过 |
| `.config/lf/lfrc`、`.config/lf/scope` | `atool`、`aunpack` | LF 的归档列出与解包功能 | 已安装；Debian 包 `atool` 提供两者 | 文件、文档、密码与桌面处理 | 已迁移 | 可执行；LF 配置与 scope 语法检查通过 |
| `.config/lf/scope` | `ffmpegthumbnailer` | 视频预览缩略图生成 | 已安装；Debian 包为 `ffmpegthumbnailer` | 文件、文档、密码与桌面处理 | 待核对 | 可执行；实际视频预览需在 LF/X11 会话复查 |
| `.config/lf/scope` | `odt2txt` | ODT 文档文本预览 | 已安装；Debian 包为 `odt2txt` | 文件、文档、密码与桌面处理 | 待核对 | 可执行；LF scope 语法检查通过 |
| `.config/lf/lfrc` | `vidir` | LF 批量重命名操作 | 已安装；Debian 包 `moreutils` 提供 | 文件、文档、密码与桌面处理 | 待核对 | 可执行；LF 配置语法检查通过 |
| `.config/lf/lfrc` | `localc` | XLSX 电子表格打开方式 | 已安装；Debian 包 `libreoffice-calc` 提供 | 文件、文档、密码与桌面处理 | 不存在 | 已补入 `dependencies.md`；可执行 |
| `.config/lf/lfrc` | `gimp` | XCF 图像打开方式 | 已安装；Debian 包为 `gimp` | 文件、文档、密码与桌面处理 | 待核对 | 可执行；实际图形打开需在 X11 会话复查 |
| `.local/bin/noisereduce` | `sox` | 音视频降噪的噪声样本与滤波处理 | 已安装；Debian 包为 `sox` | 音频、音乐、录制与视频 | 待核对 | 可执行；脚本语法检查通过，实际媒体处理需按需复查 |
| `.local/bin/dmenurecord` | `ffmpeg`、`dmenu`、`xdpyinfo`、`slop`、`flock`、`ps`、`pkill`、Linux procfs；可选 V4L2 设备 | 全屏、选区、音频和摄像头录制，用户级状态与停止控制 | 命令均已安装或由当前 Linux 内核提供；Debian 包为 `ffmpeg`、`x11-utils`、`slop`、`util-linux`、`procps`，`dmenu` 由本机源码构建；FFmpeg 已确认提供 `libx264`、AAC、FLAC、ALSA、V4L2 和 X11 捕获能力；当前无 `/dev/video*` | 音频、音乐、录制与视频 | 待核对 | `dash -n`、`sh -n` 和隔离 mock `21/21` 通过，覆盖动态 DISPLAY、摄像头覆盖、输入选项顺序、菜单取消、并发锁、原子状态、缺失/无效/重用 PID token、启动失败和 TERM 停止；沙箱不能建立隔离 X server，真实 X11 录制及有摄像头时的采集仍在图形会话复查 |
| `.local/bin/opout` | `sent` | 打开 `.sent` 演示文稿输出 | 已安装；Debian 包为 `sent` | 编译、排版与数据辅助 | 待核对 | 可执行；脚本语法检查通过 |
| `.local/bin/passmenu` | Bash、`pass`/GnuPG、`dmenu`、`xclip`、图形 Pinentry；显式 `--type` 另需 `xdotool` | X11 密码库选择、剪贴板复制和可选自动输入 | 均已安装；Debian 包为 `bash`、`pass`、`gnupg`、`xclip`、`xdotool`、`pinentry-gtk2`，`dmenu` 为本机源码构建；`/usr/bin/pinentry` 解析到 `pinentry-gtk-2` | 文件、文档、密码与桌面处理 | 不存在 | 基于 Password Store 官方 dmenu 示例的 X11 版本，保留 GPL-2.0-or-later 来源与版权；`bash -n` 通过，隔离 mock 回归 `9/9` 覆盖复制、自动输入、取消、缺失条件及特殊路径，不读取真实密码库；实际解密与剪贴板清理待 X11 会话复查 |
| `.local/bin/maimpick`、`.local/bin/otp` | `maim` | 截图及 OTP 二维码区域选择 | 已安装；Debian 包为 `maim` | 文件、文档、密码与桌面处理 | 待核对 | OTP 不创建图片文件，`maim` 的 PNG stdout 直接送入识别器；实际 X11 区域选择仍需会话复查 |
| `.local/bin/otp` | `zbarimg` | OTP 二维码内容识别 | 已安装；Debian 包 `zbar-tools` 提供 | 文件、文档、密码与桌面处理 | 待核对 | 用生成的非账户测试二维码验证 `--raw --nodbus -` stdin 识别成功；真实账户二维码未读取 |
| `.local/bin/otp` | `pass-otp`、`oathtool` 2.6.5 或更高版本、`xclip`、`flock`、GNU coreutils | 加密 OTP 管理、验证码生成/复制、HOTP/导入互斥及原子落位 | 均已安装；扩展文件由 Debian 包 `pass-otp` 提供，`pass-extension-otp` 是依赖它的过渡包；`oathtool` 为 `2.6.12`，其余分别由 `xclip`、`util-linux` 和 `coreutils` 提供 | 文件、文档、密码与桌面处理 | 待核对 | 当前扩展内部以 `sort -n` 误判 `2.6.12`，包装脚本在可靠版本检查后显式强制 stdin 安全分支；`pass otp --help`、POSIX Shell 语法和隔离 mock `82/82` 通过。另以系统 `pass`/`pass-otp` 配合假 GPG、oathtool 和 xclip 完成扩展级隔离验证，确认 seed 不在 argv 且只进入 stdin；全过程不读取真实密码库或 GPG 密钥 |
| `.local/bin/otp` | `timedatectl` 或 `chronyc` 或 `ntpdate`，手动同步另需 `sudo` | OTP 时钟检查与同步 | `timedatectl` 由已安装的 `systemd` 提供；`chrony`/`chronyc` 和 `ntpsec-ntpdate`/`ntpdate` 未安装，属于替代后端 | 文件、文档、密码与桌面处理 | 待核对 | 三个后端的隔离分支已验证；沙箱不能访问 systemd 系统总线，因此本机真实同步状态未宣称通过，也不要求安装替代客户端 |
| `.local/bin/dmenumount`、`.local/bin/dmenuumount` | `lsblk`、`mount`、`umount`、`find`、`dmenu`、`sudo`、`notify-send` | 普通块设备发现、挂载和卸载 | 已安装；Debian 软件包为 `util-linux`、`mount`、`findutils`、`sudo`、`libnotify-bin`，`dmenu` 由本机单独构建 | 显示、网络、挂载与系统控制 | 不适用（后续审计） | 两脚本收敛为普通块设备路径；Shell 语法和无设备/单设备 mock 回归通过，CIFS 继续由独立脚本负责 |
| `.local/bin/dmenumountcifs` | `avahi-browse`、Avahi 守护进程、`smbclient`、`mount.cifs`、`findmnt`、`flock`、`dmenu`、`sudo`、可选 `notify-send` | 局域网匿名 SMB 发现和 CIFS 挂载 | 均已安装；Debian 包为 `avahi-utils`、`avahi-daemon`、`smbclient`、`cifs-utils`、`util-linux`、`sudo`、`libnotify-bin`，`dmenu` 由本机源码构建 | 显示、网络、挂载与系统控制 | 挂起（无测试服务） | `dash -n`、`sh -n` 和隔离 mock `22/22` 通过；只支持 Avahi guest 共享，不跟踪凭据；本轮因无 SMB 测试服务跳过真实 LAN 验证 |
| `.local/bin/displayselect` | `xrandr`、`arandr`、`flock`、`bc`、`dmenu` | 显示布局选择、手动布局入口、共享布局锁和镜像缩放 | 均已安装；前四项由 Debian 包 `x11-xserver-utils`、`arandr`、`util-linux`、`bc` 依次提供，`dmenu` 为本机单独构建 | 显示、网络、挂载与系统控制 | 已完成 | 已在真实多显示器 X11 会话验证精确输出筛选、主屏设置和与 watcher 的串行布局；Arandr 分支只释放锁，内置布局路径才执行后处理 |
| `.local/bin/sysact` | `dmenu`、systemd `systemctl` 或 elogind `loginctl`、`slock`、`wpctl`、`mpc`、本地 `pauseallmpv`、`pstree`、`xset`、`notify-send` | 交互式及显式的锁屏、会话、电源和显示操作 | 均已安装或为已跟踪本地命令；Debian 包 `systemd` 提供 `systemctl`，`psmisc` 提供 `pstree`，`suckless-tools` 提供 `slock`，其余提供者已在所属批次审计 | 显示、网络、挂载与系统控制；音频、音乐、录制与视频 | 不存在 | `dash -n` 及无破坏 stub 回归通过；无参数菜单与单参数动作共用分派且不使用 `-i`；`sysact suspend` 的真实挂起、恢复和 slock 解锁已验证，休眠未执行 |
| `.local/bin/remaps`、`.local/bin/setbg`、`.local/bin/xdisplay.sh` | `xrandr`、`flock`、`xset`、`xdotool`、`dunst`、`bc`、`xcape`、`xwallpaper`、`wal` | 显示管理、键盘重映射、壁纸与可选配色 | 均已安装；`wal` 为本地可执行文件 | 显示、网络、挂载与系统控制；外观、字体与壁纸 | 主要流程已完成 | Shell 语法检查通过；本机已验证 `xdisplay.sh` 的开合盖、热插入、拔出、动态轮询、合盖快速路径和单实例/布局锁。原审计发现的 innogpu 拔屏后 disconnected geometry/framebuffer 残留，后续已通过显式关闭、重读验证和完整实机链路修复；依赖集合未变化。壁纸仍按图形会话路径维护 |
| `.local/bin/dmenuunicode`、`.local/bin/getkeys`、`.local/bin/shortcuts`、`.local/bin/showclip`、`.local/bin/samedir`、`.local/bin/unix`、`.local/bin/weath` | `dmenu`、`xclip`、`xdotool`、`xprop`、`dunst`、`curl`、`less`、`pstree` | Unicode 输入、快捷键、剪贴板、同目录终端和天气辅助功能 | 均已安装 | Shell、源代码管理与开发；状态栏、通信与网络服务 | 待核对 | 全部 Shell 语法检查通过；需要 X11 或网络的实际交互按会话和网络条件复查 |
| `.local/bin/peertubetorrent`、`.local/bin/rssadd`、`.local/bin/rssget` | `curl`、`python3`、`dmenu`、本地 `transadd`、本地 `rssadd` | PeerTube 种子转交与 RSS 订阅发现/添加 | 均已安装或为已跟踪本地脚本 | 下载、种子与文本浏览；状态栏、通信与网络服务 | 待核对 | Shell 语法检查通过；RSS/PeerTube 网络请求不在本轮执行 |
| `.local/bin/xlight`、`.local/bin/cron/checkup`、`.local/bin/cron/crontog`、`.local/bin/ifinstalled` | `xbacklight`、APT、`sudo`、`crontab`、`notify-send` | 背光、包更新检查、cron 切换和依赖检查 | 均已安装；`cron` 包提供服务与 `crontab`，不提供同名命令 | 显示、网络、挂载与系统控制；Shell、源代码管理与开发 | 待核对 | Shell 语法检查通过；计划任务与 sudo 的实际交互需在正常用户会话复查 |
| `.local/bin/tag` | `vorbiscomment`、`eyeD3`、`metaflac` | OGG、MP3、FLAC 元数据写入 | 已安装；Debian 包分别为 `vorbis-tools`、`eyed3`、`flac` | 音频、音乐、录制与视频 | 待核对 | 可执行；脚本语法检查通过 |
| `.local/bin/tag` | `opustags` | Opus 元数据写入 | 已安装；Debian 包为 `opustags`。`opus-tools` 仅提供编码、解码和信息查询工具 | 音频、音乐、录制与视频 | 待核对 | 可执行；`tag` 脚本语法检查通过 |
| `.config/mimeapps.list`、`.local/share/applications/{file,img,mail,pdf,rss,text,torrent,video}.desktop`、`.local/share/applications/clash-verge-handler.desktop` | `st`、`lfub`、`nsxiv`、`neomutt`、`zathura`、`rssadd`、`transadd`、`nvim`、`mpv`、WPS Office、`clash-verge` | MIME 默认程序、自定义桌面入口和 Clash URI 方案处理器 | 自定义入口、WPS 和 `/usr/bin/clash-verge` 均可解析；系统包仍提供含空格文件名的 `Clash Verge.desktop`，但 URI 关联不再依赖它 | 文件、文档、密码与桌面处理 | 待核对 | 本地 handler 使用 `TryExec=clash-verge` 和不经 shell 的 `Exec=clash-verge %u`，同时声明 `clash`、`clash-verge`；2026-07-18 `gio mime` 与 `xdg-mime query default` 均解析到该 handler，实际 GUI 启动留待按需复查 |
| `.config/nsxiv/exec/key-handler` | `setbg`、`dmenu`、ImageMagick、`xclip`、`mediainfo`、`gimp`、本地 `ifinstalled` | nsxiv 的壁纸、文件操作、图像处理与信息按键 | 均已安装或为已跟踪本地脚本 | 文件、文档、密码与桌面处理 | 待核对 | `sh -n` 通过；实际图形按键交互需在 X11 会话复查 |
| `.config/zsh/.zshrc` | `zsh`、Oh My Zsh、zplug、`thefuck`、`fzf`、`fzf-tab`、NVM、Bun | Zsh 框架、插件与条件加载的开发环境 | `fzf` 已安装；`fzf-tab` 由 zplug 在存在 `fzf` 时按需安装和加载；NVM/Bun 由其本地初始化文件提供 | Shell、源代码管理与开发 | 待核对 | `zsh -n` 通过；本轮不触发 zplug 的联网安装或更新；缺少 `fzf` 时保持原生 Tab 补全 |
| `.config/zsh/.zshrc` | `fd` 或 `fdfind`、`jq`、Docker (`docker`) | FZF 文件搜索、`json()` 剪贴板格式化、Docker 插件与 `attach()` | 已安装；Debian 包为 `fd-find`、`jq`、`docker.io` | Shell、源代码管理与开发 | 不存在 | Zsh 已修正为支持 Debian 的 `fdfind`，并实际选中该命令；Docker 守护进程运行状态需在正常用户会话复查 |
| `.config/shell/inputrc`、`.config/user-dirs.dirs` | `/etc/inputrc`、`xdg-user-dirs-update` | Readline vi 模式及 XDG 用户目录定义 | 均已安装且可读 | Shell、源代码管理与开发；文件、文档、密码与桌面处理 | 待核对 | 配置为声明式内容；`/etc/inputrc` include 和 XDG 更新工具均可解析 |
| `.local/bin/install.sh` | `git`、OpenSSH 客户端、Bash、GNU 文件工具 | 通过 SSH 远程仓库部署 bare dotfiles | 均已安装 | Shell、源代码管理与开发 | 待核对 | `bash -n` 通过；临时 bare 仓库回归覆盖嵌套/空格路径、祖先文件与符号链接、私有备份、冲突拒绝、checkout 和隐藏未跟踪文件。新机器仍需配置 GitHub SSH 凭据，审计不读取或记录账户密钥 |
| `.local/bin/install-ohmyz.sh` | `zsh`、`git`、`chsh`、网络 | Oh My Zsh 安装器 | 均已安装 | Shell、源代码管理与开发 | 待核对 | `sh -n` 通过；脚本会联网克隆上游仓库，安装行为本轮不执行 |
| `.local/bin/getbib` | `pdfinfo`、`pdftotext`、`curl` | 从 PDF/DOI 获取 Crossref BibTeX 条目 | 均已安装 | 文件、文档、密码与桌面处理 | 待核对 | `sh -n` 通过；实际 Crossref 网络请求不在本轮执行 |
| `.local/bin/compiler` 的 Python 分支 | `python3`；兼容回退为 `python` | 执行 Python 源文件 | `python3` 已安装，未提供 `python` 命令 | Shell、源代码管理与开发；编译、排版与数据辅助 | 不存在 | 已改为优先 `python3`、回退 `python`；最小 Python 文件执行回归通过 |
| `.local/bin/compiler`、`.local/bin/texroot`、`.local/bin/opout`、`.local/bin/texclear` | GNU coreutils（`readlink`、`head`、`tr`、`rm`）、`awk`、`grep`、`setsid`、`xdg-open`、`latexmk`、`pdflatex`、`xelatex`、`lualatex`、`biber` 及按文档使用的中日文宏包 | 根文件解析、依赖驱动编译、根 PDF 打开和精确清理；TeX 之外的格式仍按需安装 | Debian 13 已安装 `latexmk`、`texlive-latex-base`、`texlive-xetex`、`texlive-luatex`、`biber`、`texlive-bibtex-extra`、`texlive-lang-chinese`、`texlive-lang-japanese`；日文包是按文档需要的可选能力 | 编译、排版与数据辅助 | 不适用（后续审计） | `dash -n`、`sh -n` 通过；本次 `77/77` CLI 回归覆盖多级/冲突/循环根文件、特殊路径、三引擎、交叉引用、XeLaTeX 中文、LuaLaTeX 日文字体、Biber、项目输出/辅助目录覆盖、无图形精确打开、非 TeX 打开回归和不越界清理；PDF 均位于根文件同目录 |
| `.config/lf/icons`、`.config/newsboat/urls`、`.config/shell/bm-dirs`、`.config/shell/bm-files`、`.config/wal/templates/*`、`.local/patch/*`、`.local/share/larbs/{LICENSE,chars/,getkeys/,ttymaps.kmap}` | 无新增运行依赖 | 图标、书签、模板、补丁、帮助与数据资源 | 不适用 | 对应功能所属布局（layout） | 待核对或历史来源 | 通过；运行入口和外部命令已在所属配置或脚本批次审计 |
| `.local/bin/prompt`、`.local/bin/tutorialvids`、`.local/bin/queueandnotify`、`.local/bin/td-toggle`、`.local/bin/transadd` | `dmenu`、`mpv`、`curl`、`tsp`、Transmission、`notify-send`、本地 `ifinstalled` | 通用确认、教程视频、下载队列与种子管理入口 | 均已在所属批次验证 | 下载、种子与文本浏览；音频、音乐、录制与视频；X11 桌面与输入 | 待核对 | 已纳入全量 Shell 语法检查；不新增依赖 |
| `.local/share/sys-etc/portage/make.conf.template` | Portage | 其他发行版的包管理模板 | 仅模板，不在 Debian 部署 | 模板与计划工作 | 历史或仅模板 | 通过；本轮只做格式与路径审阅 |
| `.local/share/sys-etc/systemd/network/wireless.network.template` | systemd-networkd、`networkctl` | NetworkManager 以外的可选三层网络模板 | systemd 已安装，但该模板未部署；本轮未选择 systemd-networkd 作为 Wi-Fi 接口所有者 | 模板与计划工作 | 历史或仅模板 | 通过；已增加同一接口不得与 NetworkManager 并用的就地警告 |
| `.local/share/sys-etc/wpa_supplicant/wpa_supplicant.conf.template` | `wpa_supplicant` | 与 systemd-networkd 配套的接口级 Wi-Fi 认证模板 | `wpasupplicant` 已安装并作为 NetworkManager 的全局 D-Bus 后端；接口模板未部署 | 模板与计划工作 | 历史或仅模板 | 通过；全局后端与接口级模板用途已区分，后者不得用于 NetworkManager 已管理的接口 |
| `README.md`、`.local/share/docs/**`、`.local/share/larbs/progs.csv`、`.local/bin/cron/README.md` | 无直接运行时依赖；内容包含项目依赖说明 | 项目说明、计划与历史数据 | 不适用 | 不适用（项目文档） | 已完成 | 首轮已完成 `progs.csv` 迁移、依赖清单完整性和用户/架构文档对齐；后续仅按新的审计流程维护 |
| `dependencies.md` 第三阶段反向检索 | `pamixer` | 旧依赖清单条目 | 无当前配置或独立 DWM 源码引用 | 音频、音乐、录制与视频 | 不适用 | 已从活跃依赖移除；当前交互式混音器为 `pulsemixer` |
| `dependencies.md` 第三阶段反向检索 | `w3m`、`xkblayout-state`、`geoiplookup`、`synclient`、`screenkey` | 条件回退、可隐藏模块或外部 DWM 参考 | 不要求安装 | 对应布局（layout） | 不适用 | 已明确标注条件行为或仅外部源码用途；不阻塞 Debian 部署审计 |
| `desktop-guide-zh.md`、`architecture.md` 第四阶段对齐 | `dependencies.md` 的十个布局（layout） | 用户与维护文档结构 | 不适用 | 不适用（项目文档） | 不适用 | 已为每个布局（layout）增加独立章节；保留原有启动流程、上游差异、工作流与维护边界 |

## Debian 13 关键映射

本节只保存通用依赖清单到本平台的映射，不应复制回 `project/dependencies.md`。

| 通用能力 | Debian 13 映射或本平台结论 |
| --- | --- |
| 包管理 | APT/dpkg；`p` 系列别名在本平台选择 APT 分支，`checkup` 使用 APT 更新检查 |
| `fd` 文件查找能力 | `fd-find` 软件包提供 `fdfind`；Shell 配置会自动选择该兼容命令 |
| 普通块设备工具 | `mount` 软件包提供 `mount`/`umount`，`util-linux` 提供 `lsblk`/`flock` |
| X11 与 D-Bus | `xserver-xorg-core`、`xinit`、`dbus-x11`；实际会话使用 `startx` |
| X11 睡眠锁屏 | `xss-lock`、`suckless-tools`、`systemd`；logind 拥有硬件睡眠键，`xss-lock --ignore-xss -- slock` 只桥接 login1 事件 |
| 桌面源码构建工具 | `build-essential`、`pkgconf`（提供 `pkg-config`）、`ncurses-bin`（提供 `tic`） |
| 桌面源码开发库 | `libx11-dev`、`libxft-dev`、`libxrender-dev`、`libxinerama-dev`、`libfontconfig-dev`、`libfreetype-dev`、`libharfbuzz-dev`、`libx11-xcb-dev`、`libxcb1-dev`、`libxcb-res0-dev` |
| 登录与脚本基础 | `openssh-client` 提供 `ssh`/`ssh-agent`，`kbd` 提供 `loadkeys`，`psmisc` 提供 `killall` |
| 进程探测 | `procps` 提供 `pgrep`/`pkill`/`ps`，`sysvinit-utils` 提供 `pidof` |
| 终端与 Qt 外观 | `fbterm`、`qt5-gtk-platformtheme`、`qt6-gtk-platformtheme` |
| PDF 预览与检查 | `zathura`、`zathura-pdf-poppler`、`poppler-utils`；`fonts-urw-base35` 提供 DWM 帮助使用的 Nimbus Sans |
| TeX 基础与引擎 | `latexmk`、`texlive-latex-base`、`texlive-xetex`、`texlive-luatex` |
| TeX 参考文献与语言 | `biber`、`texlive-bibtex-extra`、`texlive-lang-chinese`、`texlive-lang-japanese` |
| OTP | `pass-otp` 提供扩展，`pass-extension-otp` 为过渡包；`oathtool` 2.6.12、`zbar-tools`、`maim`、`xclip` 和 `util-linux` 已安装，时钟入口由 `systemd` 的 `timedatectl` 提供 |
| CIFS 匿名挂载 | `cifs-utils`、`smbclient`、`avahi-utils`、`avahi-daemon`、`util-linux`、`sudo`、`libnotify-bin`；`mount.cifs` 位于 `/usr/sbin` |
| PipeWire | `pipewire`、`pipewire-pulse`、`wireplumber` 由 systemd 用户服务管理，X11 启动脚本不重复拉起 |
| NetworkManager 与 Wi-Fi 认证 | `network-manager` 提供 NetworkManager、`nmtui` 和 `nmcli`，`wpasupplicant` 提供全局 D-Bus 认证后端；旧 ifupdown 路径保持禁用，不与同一接口并用 |
| 最低优先级可选项 | `fpp`、`youtube-viewer`、`tremc` 不阻塞部署；缺失行为已在通用依赖清单中定义 |

## 系统与会话差异

本平台通过 X11 和 `startx` 进入 DWM。显示 watcher 由 `.config/x11/xprofile` 在图形会话内启动，
不是 systemd 用户服务，因此自然继承 `DISPLAY`、`XAUTHORITY` 和用户 D-Bus 环境。PipeWire 与
WirePlumber 则由 systemd 用户服务负责，二者所有权不得混合。

2026-07-19 已把 Wi-Fi 从 ifupdown/按接口认证链迁移到 NetworkManager。脱敏实测确认
NetworkManager 已启用并运行，Wi-Fi 为 `managed=yes` 且总体网络状态为 `connected:full`；
全局 `wpa_supplicant` 作为唯一 D-Bus 认证后端运行。`networking.service` 已禁用且未运行，活动
ifup unit、dhcpcd 进程和接口级 `wpa_supplicant` 进程均为 0。当前所有权关系为：

```text
NetworkManager
├─ 连接配置、自动连接、DHCP、地址、路由和 DNS
└─ 全局 D-Bus wpa_supplicant：Wi-Fi 认证后端
```

同日首次整机冷启动后，NetworkManager 仍为 `enabled`、`active`，总体状态为
`connected:full`，`nmcli device show` 列出的设备均为 `GENERAL.NM-MANAGED:yes`；断开或不可用的
非活动设备不影响当前连接。`networking.service` 和 `systemd-networkd.service` 均为
`disabled`、`inactive`，没有活动 ifup unit、dhcpcd 进程或接口级 `wpa_supplicant@` unit，且只
存在一个使用 D-Bus 参数的全局 `wpa_supplicant` 进程。第一次冷启动的自动连接和唯一所有权验证通过。

2026-07-18 重启 X11 后，按登录会话和 X server 划分的 `flock` 运行锁只启动一个 xss-lock
实例。`sysact suspend` 对应的 `systemd-suspend.service` 从 22:28:46 运行到 22:29:22，结果为
success；恢复后 slock 完成认证并退出，原 xss-lock 实例继续存活。认证时用户日志出现
`pam_unix(slock:account): setuid failed: Operation not permitted`；Debian 的 slock 说明明确指出
该包使用 PAM 且刻意不授予 setuid-root，本次解锁未受影响。不得仅为消除该日志提高 slock 权限；
若后续发生实际认证失败，再单独审计 PAM 栈。

系统 Xorg 层存在以下未跟踪配置，它们只属于本平台：

| 系统路径 | 当前作用 |
| --- | --- |
| `/etc/X11/xorg.conf` | 选择 PCI `02:00.0` 的 innogpu，声明 `DRI=3`、TearFree 并关闭 Xorg 空白计时；Xorg 日志将 DRI 选项标为未采用，实际 GL provider 为 DRI2 |
| `/etc/X11/xorg.conf.d/10-innogpu.conf` | 为 innogpu OutputClass 设置 GLX vendor 与 `FBCompression=2` |
| `/etc/X11/xorg.conf.d/20-innogpu-display.conf` | 声明 `eDP-1`、`DP-1` Monitor/DPMS 选项；驱动输出名会在两者间变化，Xorg 使用当次名称匹配的 section。2026-07-18 最新日志匹配 `DP-1`，并仍报告全局 DPMS enabled |
| `/etc/systemd/logind.conf` | `HandleLidSwitchExternalPower=ignore`，接电合盖时允许 X11 先切换到外屏 |
| `/etc/systemd/system/innogpu-repair-dri-nodes.service` | `enabled`、`active (exited)` 且结果 success；启动时修复 innogpu 的 DRI/fbdev 设备节点，不参与 RandR 布局 |

2026-07-18 复核时 `systemd-logind` 为 `active (running)`，`innogpu-repair-dri-nodes.service` 为
`enabled`、`active (exited)` 且结果 success；既有合盖验证场景为接电且盖子关闭。本平台当前没有显示管理 systemd
用户服务或活动 udev 热插拔规则；PipeWire 等用户服务与显示布局无直接所有权关系。未接电且
未被 logind 判断为 docked 时，合盖仍可能按系统策略挂起，接电实测结果不能外推到该场景。

### 音频硬件与本机钩子

系统 `pipewire-alsa` 负责通用 ALSA 默认路由。当前还存在未跟踪的设备本地 unit
`~/.config/systemd/user/hygon-hda-audio-user.service` 及辅助命令
`~/.local/bin/hygon-hda-audio-user-apply`，用于该设备的 HDA 输出选择；它们不属于通用配置。
2026-07-18 只读状态为 `enabled`、`inactive (dead)`、结果 success，符合执行后退出的 oneshot
形态。常规已跟踪文件审计不读取其源码；是否继续保留为本地实现需单独评估。

## 显示硬件与本机钩子

GPU 的 DRM connector `card0-DP-1`、`card0-HDMI-A-1`、`card0-HDMI-A-2` 在 Xorg 中通常映射为
`eDP-1`、`HDMI-1`、`HDMI-2`。内屏曾出现 `DP-1` 别名，因此当前 Xprofile 使用
`XDISPLAY_INTERNAL_OUTPUTS="eDP-1 DP-1"` 补充候选；外屏名称仍由运行时发现，不能写死。

盖子状态来自 `/proc/acpi/button/lid/LID0/state`，外接电源状态来自
`/sys/class/power_supply/ADP1/online`。显示链路为：

```text
innogpu -> Xorg/RandR -> xprofile -> xdisplay.sh --watch -> DWM/Xinerama
systemd-logind ----------------------^ 合盖与会话授权
Mod+F3 -> displayselect -> 共享 RandR apply lock
```

未跟踪的 `.local/bin/innogpu-restore-dp1-mode-x11` 是当前可选恢复钩子，固定处理 `DP-1`/`eDP-1`
和 `1920x1200R` modeline。它通过 `XDISPLAY_RESTORE_COMMAND` 接入，只在内屏缺少模式时运行；
由于包含硬件假设，不得纳入通用配置。目标设备适配器完成实测前保留现有接口。

## 显示验证与已知行为

- 2026-07-16 完成扩展坞外屏热插、热拔、合盖、开盖和再次拔出的完整链路；手动
  `displayselect` 与 watcher 使用同一布局锁。
- innogpu 曾让已断开的 HDMI 保留 geometry 并扩大 framebuffer；共享脚本现会显式关闭
  `disconnected + geometry` 输出、重读验证，并把 framebuffer 收敛到有效输出包围盒。
- 同一 Dell 外屏直连时 EDID 产品码为 `0x4277`，可暴露 `3840x2160@60`；经当时扩展坞时产品码
  为 `0x4279`，最高只暴露 `2560x1440` 且没有 preferred。当前实现使用各连接路径实际模式表，
  不复用另一连接方式的 EDID 能力。
- 扩展坞完整模式能力可能晚约 1.6 秒出现。能力签名、约 5 秒 settling 窗口和有界退避已使外屏
  收敛到 `2560x1440@59.95`，不再由 `--auto` 误选 `2048x1280`。
- fixture 已通过状态/锁 `11/11`、watcher 生命周期 `4/4` 和显示回归 `11/11`；2026-07-16
  重启后 watcher generation 与单实例锁验证通过。阶段 2 的受控 watcher 交接前后 RandR 保持
  `4608x1600`，没有因换代改变布局。
- 完整热插拔链路中 framebuffer 分别收敛为双屏 `5120x1600`、合盖单外屏 `2560x1440` 和开盖
  单内屏 `2560x1600`，断开输出不再保留 geometry。
- 另一块原生 `1920x1080` 外屏完成预接冷启动、出图和开合盖测试；该次启动未读到 EDID 时驱动
  曾只提供 fallback 模式并首选 `1920x1200`，随后现场按已知原生 `1920x1080` 修正。这个历史分支
  不能替代不同外屏、扩展坞和 EDID/preferred 分支的自动冷启动复测。
- 合盖慢恢复 A/B 中，标准 framebuffer 收敛约 `1.07s`，物理出图曾超过 5 秒；临时保留旧
  `4480x1600` framebuffer 时约 `0.65s` 完成且近乎立即出图。该证据只用于定位 innogpu/输出链路
  重新同步，最终仍采用通用 framebuffer 收敛，避免不可见区域、鼠标越界和整屏截图尺寸错误。
- 本平台没有标准 `/sys/class/backlight` 设备；`xlight`、`xbacklight` 和状态栏亮度动作仍待选定
  可用后端后统一。

## 临时隔离与恢复

未跟踪目录 `~/.local/share/xdisplay-transition-20260714/` 保存恢复说明、原路径、UID/GID/mode、
链接目标、SHA256 清单和活动配置快照；隔离边界基线为 `9e0c292`，共享显示代码恢复基线为
`a191c3c`。已经隔离：

- 四字节且无引用的 `.config/x11/xinit`；
- 旧 `.local/bin/xdisplay-hybrid.sh` 与对应 `95-display-hotplug.rules`；
- `/etc/X11/` 下 12 份不参与加载的 `*.before-*` 历史备份。

活动 Xorg 配置、logind 配置、innogpu service、modprobe/modules-load/ld.so 配置和内屏恢复钩子
只备份、不移动。需要回退时严格按隔离目录 `RESTORE.md` 和校验清单逐项恢复；恢复 udev 规则后
reload rules，恢复 logind/Xorg 后通过整机重启验证。黑屏时从 TTY 停止 watcher 并恢复文件，
不要在无可见输出时继续执行 RandR 试验。

NetworkManager 迁移的 root 私有恢复目录是 `/root/networkmanager-transition-20260719/`，不属于
配置仓库，也不得把其中的连接资料复制进文档。网络回退入口为：

```sh
sudo /root/networkmanager-transition-20260719/networkmanager-transition.sh rollback
```

脚本 SHA256 为
`58fa78aaac3cc2fcde4ab058685eaf9f6b536d10f45db557639980357c1218a0`。在完成下方冷启动与
交互验证前保留该目录；回退会使用仍已安装的 ifupdown 恢复迁移前配置和服务关系。ifupdown 只
属于本次迁移的回退能力，不是 NetworkManager 正常运行或全新部署的依赖。

## 平台工作

活动待办可以在当前审计周期直接推进；挂起项目只有达到所列条件或收到明确恢复决定后才重新开始。

### 平台活动待办

- [ ] 复查仍依赖真实 X11、硬件、账户或网络的交互路径：截图；录制的全屏、选区、音频及有
  摄像头时的采集；OTP、Transmission、RSS/邮件和媒体预览。录制与 OTP 的静态和 mock 检查已完成；
  OTP 此处只保留真实 X11 `dmenu`/`maim`、GPG/Pinentry、验证码、HOTP 计数及剪贴板清理验证。
- [ ] 按“运行必要性、跨设备价值、效率、结构和维护成本”评估未跟踪的 HDA audio user unit/helper；
  未经单独审查不纳入配置仓库。

### 平台挂起项目

- [ ] 仅在本机出现可用的匿名 SMB 服务或明确产生 CIFS 使用需求时，恢复
  `.local/bin/dmenumountcifs` 的真实 LAN 验证；当前因无测试服务跳过，代码和 mock 结果已记录在依赖审计中。
- [ ] 2026-08 进入下一轮检查时，先询问是否恢复[跨设备显示工作](../project/display-management.md#未完成的通用工作)；
  当前屏幕切换继续视为已完成。
- [ ] 后续通过键帽或输入事件确认本机存在实际发出 `XF86Sleep` 的实体键时，再验证该键只触发
  一次挂起；当前 X11 映射包含 keycode 150，但尚不能对应到具体键帽。恢复条件是先识别出实际
  输入事件；已完成的 `sysact suspend` 实机验证不受此项阻塞。
- [ ] 隔离目录稳定使用至少 14 天并完成至少 3 次冷启动；覆盖开合盖、热插拔、延迟外屏和手动
  布局后，实际恢复并再次隔离一个无运行影响的文件，核对路径、所有者、mode 和校验和，再讨论删除。
- [ ] 用户明确恢复跨设备显示工作后，分别复测不同外屏直连、不同扩展坞、登录前预接、
  EDID/preferred 正常/延迟/缺失和多个外屏。
- [ ] 通用设备适配器运行接口实现并获准进入平台验证后，在不创建适配器、适配器失败和内屏确需
  模式恢复三条路径上验证降级行为，再迁移当前 `XDISPLAY_INTERNAL_OUTPUTS` 与恢复钩子。
- [ ] 用户明确恢复系统级合盖策略审查后，单独评估是否把当前
  `HandleLidSwitchExternalPower=ignore` 迁入
  `/etc/systemd/logind.conf.d/60-xdisplay.conf`；如实施，先用
  `systemd-analyze cat-config systemd/logind.conf` 核对合并结果，再通过整机重启验证，不在图形
  会话中直接重启 logind。
- [ ] 用户明确恢复亮度控制工作后，选定本硬件可用后端，再统一 `xlight`、状态栏和按键行为。
- [ ] 只有通用 cron 调度和最小 sudo 策略获批后，才在本平台启用并验证无人值守 APT 检查。
- [ ] NetworkManager 稳定使用并完成至少 3 次冷启动，且每次均通过自动连接和唯一所有权检查后，
  再评估删除 `/root/networkmanager-transition-20260719/`；当前已完成 `1/3`，未达到条件时继续保留
  可回退状态。

## 升级与重新审计

升级到 Debian 14 或改变设备类别时，应从平台索引新建档案，重新执行通用依赖审计流程；不得
直接把本文件的包名、服务状态、connector、modeline 或验证结果复制为新平台事实。内核、Xorg、
innogpu、systemd/logind 或扩展坞固件变化后，至少重新检查 X11 冷启动、开合盖、外屏插拔、
RandR 模式能力、网络接口唯一所有权、服务所有权和隔离恢复清单。
