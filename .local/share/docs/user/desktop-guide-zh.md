# 桌面使用指南

本指南面向本配置的使用者，说明安装后如何启动、使用和个性化桌面。它按
[依赖清单](../project/dependencies.md) 的十个布局（layout）组织。关于目录关系、启动链和
维护边界，请查阅项目架构文档；日常使用不需要先理解那些实现细节。

## 安装与首次启动

1. 按根目录 `README.md` 部署配置库，并安装依赖清单中计划使用的功能组。不同发行版的
   包名不同，以命令名和本发行版映射为准。
2. 确认 DWM、DWMBlocks、dmenu 和 st 已在 `~/src/` 由你自行编译安装；本配置不会自动
   编译它们。
3. 重新登录 shell 后，使用 `c status` 查看配置库状态，使用 `c diff` 审查改动。
4. 使用 `startx` 或显示管理器进入 X11。首次会话先确认输入法、网络、音量、终端和
   状态栏正常，再开启可选的壁纸、录制、挂载或下载功能。

`Mod` 指 Super/Windows 键。完整 DWM 绑定见
[快捷键摘要](keybindings-zh.md)。

## Shell、源代码管理与开发

日常终端使用 `vim`、`nvim`、`lf`、`tmux` 和 FZF。`c` 是配置库专用 Git 命令：用
`c status` 查看已跟踪改动，`c diff` 检查差异，确认后再 `c add` 和提交。

共享 Git 快捷命令包括 `gco`、`gpo`、`gpl`、`gd`、`gst`、`gss`、`gsh`、`gpt`、`glt`、
`gat`、`gam`、`gll` 和 `glll`。`gst` 是 Git 状态，`gs` 保留给系统 Ghostscript 命令；
`gll`、`glll` 分别显示简要和带日期/作者的彩色日志，可通过 `gitHashColor`、
`gitContentColor`、`gitDateColor`、`gitAuthorColor` 调整颜色。

同名的 `cg*` 函数始终作用于配置仓库，例如 `cgst`、`cgd`、`cgll`、`cgam`；它们不受当前
目录 Git 仓库影响。`cgpo`、`cgpl` 与普通仓库对应命令一样，要求当前分支不是 detached HEAD。

在 Bash 或 Zsh 中输入 `c` 后按 Tab，会获得与 `git` 相同的子命令、选项、引用和路径补全。

安装 `fzf` 后，Zsh 的 Tab 会使用 `fzf-tab` 交互式筛选候选；未安装时自动保留原生补全。

Tmux 从 `${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf` 加载配置，个人覆盖写入同目录的
`tmux.conf.local`。运行 `ref` 重新生成快捷方式后，`cft` 可打开该文件。

常用软件安装、更新、删除和查询使用 `p` 前缀别名，例如 `pu`、`pi`、`pr`。不同发行版
会选择对应包管理器。个人机器差异放进未跟踪的 `profile.local` 或 `aliasrc.local`，不要
修改公共配置来保存账户、令牌或设备专属路径。

若 FZF 搜索不可用，确认安装 `fd` 或 Debian 的 `fdfind`。Zsh 插件、NVM 和 Bun 是可选
增强，缺失时基础 shell 仍应可用。

## X11 桌面与输入

进入 X11 后，DWM 管理窗口，dmenu 用于启动程序，st 提供终端，Dunst 显示通知。常用操作
包括 `Mod+Enter` 打开终端、`Mod+d` 打开 dmenu、`Mod+数字` 切换工作区、
`Mod+Shift+数字` 移动窗口。

输入法优先使用 fcitx5。无法输入中文时，先确认输入法程序已安装，再完整退出并重新进入
X11。Caps、菜单键或外接键盘行为不符合预期时，使用 `Mod+F12` 重新应用键盘映射；若仍有
问题，检查当前硬件是否支持该映射。

## 外观、字体与壁纸

Arc、Noto CJK、Linux Libertine、FontAwesome 和 Dunst 构成默认外观。修改 GTK 外观可使用
`lxappearance`（已安装时），字体可在 Fontconfig 和 GTK 设置中调整。

使用 `setbg <图片路径>` 设置壁纸。安装 `wal` 后，同一操作会生成配色；未安装 `wal`、
未设置壁纸或壁纸失效时，桌面仍应使用默认 Xresources、Dunst 和 Zathura 配色。不要手动
依赖 wal 缓存文件来维持基础外观。

## 音频、音乐、录制与视频

音量使用 `wpctl`；`Mod+F4` 打开 Pulsemixer。MPD 音乐服务运行后，`Mod+m` 打开 Ncmpcpp，
媒体键和状态栏通过 `mpc` 控制播放。没有音乐输出时，先检查默认音频设备和 MPD 是否运行。

`Print` 保存截图，`Shift+Print` 选择区域截图，`Mod+Print` 选择录制类型，
`Mod+Shift+Print` 或 `Mod+Delete` 停止录制。录制、摄像头和降噪依赖可用的硬件设备；取消
菜单不应中断已有录制。MPV 用于视频和音频播放，`noisereduce` 用于按需处理媒体文件。

## 文件、文档、密码与桌面处理

`Mod+r` 在终端打开 LF。LF 可预览文本、图片、PDF、媒体和归档；缺少某种格式的预览工具时，
只会影响该格式。图片用 nsxiv，PDF 用 Zathura，电子表格和办公文档按 MIME 规则打开。

密码和一次性验证码使用 `pass` 与 `otp`。OTP 二维码导入会要求截图和识别工具；密码库内容
由你自行初始化和保存，配置库不会提供账户或密钥。常用剪贴板操作依赖 X11 剪贴板，图形
程序通常使用 `Ctrl+C`/`Ctrl+V`。

## 显示、网络、挂载与系统控制

`Mod+F3` 打开显示选择器；多屏、镜像和手动布局按当前显示器连接状态选择。亮度滚轮和
`xlight` 依赖硬件支持，无法调节时先检查显卡/背光接口。

登录 X11 时，`xdisplay.sh --watch` 会同时监测笔记本盖子和已连接显示器：合盖且有外接显示器时关闭内屏并
将外屏设为主屏；切换时会先准备外屏再关闭内屏。开盖时恢复内屏为主屏并把外屏置于右侧。启动时若暂时只发现一个输出，会直接将其启用为主屏；
之后检测到新输出会再次收敛布局。无法识别内屏的多屏情况会尝试镜像，失败后 watcher 会继续重试，
但 XRandR 不保证自动回滚已经部分应用的布局；手动执行失败时会通知。需要立即修正布局时执行
`xdisplay.sh` 或 `xdisplay.sh --apply`。只排查、不修改布局时执行 `xdisplay.sh --status`，它会
显示 lid、各输出的连接与 geometry、current/preferred/target 模式及刷新率、模式数量和能力签名、
stale/pending、当前策略、锁路径、watcher generation 和 manual marker 状态。内屏名称为标准
`eDP-*`、`LVDS-*` 或 `DSI-*` 时无需设置；若硬件使用其他
名称，在 `.config/x11/xprofile` 中设置 `XDISPLAY_INTERNAL_OUTPUTS` 并以空格列出所有可能的
内屏名称。可通过 `XDISPLAY_RESTORE_COMMAND` 指定本机专用的内屏恢复命令；普通设备无需设置。
watcher 稳定时每秒检查一次显示输出，检测到开合盖或输出变化后会临时以 0.5 秒间隔检查；
合盖会先使用当前缓存布局快速切换。事件后约 5 秒内会继续主动读取模式能力，因此扩展坞稍后才
给出的模式或 preferred 也能自动收敛；更晚的能力变化仍由低频探测恢复。没有 preferred 时脚本
明确使用 RandR 模式表首项及其刷新率，不从其他连接方式的 EDID 猜测分辨率。手动显示选择期间
自动布局会等待共享锁；物理拓扑再次变化后恢复自动策略。缺少 `xrandr` 或 `flock` 时脚本会提示
安装；在显示选择器中选择手动布局但缺少 `arandr` 时也会提示安装。

本机 innogpu 在拔屏后可能短暂让已断开的 HDMI 带有旧几何；watcher 会显式关闭该输出并收缩
framebuffer。若切换后仍不正常，先用 `xdisplay.sh --status` 检查 `stale_outputs`、`health` 以及
current 与 target 模式，再用 `xrandr --current` 检查 `disconnected` 行是否仍含分辨率和坐标。
状态持续不收敛时保存这两份输出，再执行一次 `xdisplay.sh --apply`；不要手工套用另一条连接路径的
分辨率。

如果合盖后的布局最终正确，但外屏肉眼黑屏连续两次超过 5 秒，先分别保存
`xdisplay.sh --status` 和 `xrandr --current`。若输出、primary、geometry 和 framebuffer 已在约
2 秒内正确，而画面稍后才恢复，问题更接近驱动 modeset 或外屏链路重新同步，不应继续缩短 watcher
轮询。维护者可按显示重构计划做一次临时 framebuffer A/B；日常配置仍应恢复与有效输出匹配的
framebuffer，避免鼠标进入不可见区域和整屏截图尺寸异常。

保留 `nmtui` 作为交互式网络管理界面。`Mod+F9/F10` 用于挂载/卸载设备；普通 USB 和 CIFS
按菜单操作。Android MTP 当前在 Debian 上处于挂起状态，不应把未验证的替代程序当作可用。
锁屏、睡眠、关机等系统操作从系统菜单进入。

## 状态栏、通信与网络服务

状态栏右侧模块显示电池、时间、网络、音量、任务、RSS、邮件、种子和天气等信息。点击或
滚动模块会打开相应程序或执行动作；某个模块为空通常表示该功能未配置、服务未运行或其
可选依赖缺失，不应影响其他模块。

邮件、RSS 和天气需要各自的账户、订阅或网络。添加 RSS 后可用 Newsboat 阅读；邮件账户和
同步设置属于本机私有数据。需要查看状态栏功能说明时，使用鼠标中键提示或快捷键摘要。

## 下载、种子与文本浏览

Newsboat、dmenu 和链接处理器可以把下载交给 `qndl` 队列。使用 `tsp -l` 查看队列；
`yt-dlp` 处理媒体下载。Transmission 守护进程、远程客户端和状态栏用于种子任务。

`torrent` 在安装 Tremc 时打开终端界面；没有 Tremc 时仍会启动守护进程并提示使用 Web 界面
或 `transmission-remote`。Lynx 用于需要纯文本浏览的场景。

## 编译、排版与数据辅助

`compiler <文件>` 按文件类型运行相应工具，`getbib` 可从 DOI 或 PDF 获取 BibTeX，
`texclear` 清理 TeX 副产物。完整 TeX、编程语言和排版工具链并不默认启用；需要某种格式时，
先在依赖清单中确认所需命令，再安装对应发行版的软件包。

## 模板与计划工作

`.local/share/sys-etc/` 中的网络和包管理文件是示例，不能直接视为当前系统设置。复制前先
根据发行版、网卡和安全要求调整。cron 示例依赖图形会话、用户 D-Bus 和明确 sudo 策略；
未确认前不要启用自动更新任务。

## 个性化与故障处理

公共设置只修改已跟踪文件；个人差异使用 `*.local` 覆盖。修改后以 `c diff` 审查，确认功能
正常再提交。常见问题的排查顺序是：确认所需程序已安装，确认相关服务或会话已启动，重新
登录 X11，然后检查对应布局（layout）的配置入口。

上游 LARBS 手册假定不同的浏览器、邮件工具、PulseAudio、源码路径和快捷键。遇到差异时，
以本指南、快捷键摘要和依赖清单为准，而不是直接套用上游个人设置。
