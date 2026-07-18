# 桌面使用指南

本指南面向本配置的使用者，说明安装后如何启动、使用和个性化桌面。它按
[依赖清单](../project/dependencies.md) 的十个布局（layout）组织。关于目录关系、启动链和
维护边界，请查阅[项目架构](../project/architecture.md)；发行版安装映射和设备已知问题见
[平台档案索引](../platforms/index.md)。日常使用不需要先理解实现细节。

## 安装与首次启动

1. 按根目录 [README 安装说明](../../../../README.md#installation)部署配置库，并安装依赖清单中计划使用的功能组。依赖清单以稳定
   命令/能力为准，具体包名从平台索引选择对应设备与发行版档案。
2. 按同一安装说明获取 DWM、DWMBlocks、dmenu 和 st，在 `~/src/` 分别编译安装；本配置不会
   自动克隆或编译它们。
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

Tmux 从 `${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf` 加载配置，并继续加载已跟踪的仓库共享
覆盖层 `tmux.conf.local`。运行 `ref` 重新生成快捷方式后，`cft` 打开主 `tmux.conf`；相邻的
`tmux.conf.local` 也是共享配置，不要向其中写入机器私有值。

常用软件安装、更新、删除和查询使用 `p` 前缀别名，例如 `pu`、`pi`、`pr`。不同发行版
会选择对应包管理器。个人机器差异放进未跟踪的 `profile.local` 或 `aliasrc.local`，不要
修改公共配置来保存账户、令牌或设备专属路径。

若 FZF 搜索不可用，确认已安装提供 `fd` 能力的命令；兼容命令映射见平台档案。Zsh 插件由
zplug 管理，首次缺失时会尝试通过 Git 联网安装；`thefuck`、NVM 和 Bun 是可选增强，缺失时
基础 shell 仍应可用。

## X11 桌面与输入

进入 X11 后，DWM 管理窗口，dmenu 用于启动程序，st 提供终端，Dunst 显示通知。常用操作
包括 `Mod+Enter` 打开终端、`Mod+d` 打开 dmenu、`Mod+数字` 切换工作区、
`Mod+Shift+数字` 移动窗口。

`Mod+F1` 会用 Groff 动态生成英文快捷键指南并在 Zathura 中打开。若指南无法生成或命令标签
显示异常，确认已安装 `groff`、可嵌入的 Nimbus Sans Type 1 字体、`zathura` 和 PDF 后端，
再从 `~/src/dwm` 重新安装帮助文件；发行版包名见平台档案。

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

音量和麦克风静音使用 `wpctl`；`Mod+F4` 打开 Pulsemixer。MPD 音乐服务运行后，`Mod+m` 打开 Ncmpcpp，
媒体键和状态栏通过 `mpc` 控制播放。没有音乐输出时，先检查默认音频设备和 MPD 是否运行。

`Print` 保存截图，`Shift+Print` 选择区域截图，`Mod+Print` 选择录制类型，
`Mod+Shift+Print` 或 `Mod+Delete` 停止录制。录制、摄像头和降噪依赖可用的硬件设备；取消
菜单不应中断已有录制。MPV 用于视频和音频播放，`noisereduce` 用于按需处理媒体文件。

## 文件、文档、密码与桌面处理

`Mod+r` 在终端打开 LF。LF 可预览文本、图片、PDF、媒体和归档；缺少某种格式的预览工具时，
只会影响该格式。图片用 nsxiv，PDF 用 Zathura，电子表格和办公文档按 MIME 规则打开。

密码和一次性验证码使用 `pass` 与 `otp`；`Mod+Shift+d` 打开已跟踪的 `passmenu`，
默认通过 `pass` 复制所选条目的第一行。`pass` 会在超时后恢复当前剪贴板，但不能清理
外部剪贴板历史。GPG 未缓存密钥密码时，图形 Pinentry 会请求解锁；
只有在终端显式执行 `passmenu --type` 才会向当前焦点窗口自动输入，使用前应确认焦点。OTP
二维码导入会要求截图和识别工具；密码库、GPG 私钥和账户数据由你自行初始化和保存，配置库不会跟踪它们。
常用剪贴板操作依赖 X11 剪贴板，图形程序通常使用 `Ctrl+C`/`Ctrl+V`。

安装 `clash-verge` 后，`clash:` 和 `clash-verge:` 链接由已跟踪的本地 desktop handler 打开；
该入口通过 PATH 查找命令，不依赖发行版提供的 desktop 文件名。

## 显示、网络、挂载与系统控制

`Mod+F3` 打开显示选择器；多屏、镜像和手动布局按当前显示器连接状态选择。亮度滚轮和
`xlight` 依赖硬件支持，无法调节时先检查显卡/背光接口。

登录 X11 时，`xdisplay.sh --watch` 会同时监测笔记本盖子和已连接显示器：合盖且有外接显示器时关闭内屏并
将外屏设为主屏；切换时会先准备外屏再关闭内屏。开盖时恢复内屏为主屏并把外屏置于右侧。启动时若暂时只发现一个输出，会直接将其启用为主屏；
之后检测到新输出会再次收敛布局。无法识别内屏的多屏情况会尝试镜像，失败后 watcher 会继续重试，
但 XRandR 不保证自动回滚已经部分应用的布局。`xdisplay.sh` 失败时会输出错误，并在
`notify-send` 可用时通知；`displayselect` 的所有失败路径不保证通知。需要立即修正布局时执行
`xdisplay.sh` 或 `xdisplay.sh --apply`。只排查、不修改布局时执行 `xdisplay.sh --status`，它会
显示 lid、各输出的连接与 geometry、current/preferred/target 模式及刷新率、模式数量和能力签名、
stale/pending、当前策略、锁路径、watcher generation 和 manual marker 状态。标准内屏名称无需
设置。当前非标准硬件仍使用平台档案登记的 legacy 环境变量注入；尚未实施的目标迁移按
[设备适配器指引](../project/display-device-adapter.md)处理，不把新设备参数继续写进通用配置。
事件后 watcher 会短时提高探测频率以等待迟到模式；手动显示选择期间
自动布局等待共享锁。缺少基础命令时脚本会明确提示，缺少 Arandr 只影响可选手动界面。

切换不正常时，先保存 `xdisplay.sh --status` 和 `xrandr --current`，检查 stale/pending、primary、
geometry、target 模式和 framebuffer，再执行一次 `xdisplay.sh --apply`。不要手工套用另一台设备
或另一 connector 的分辨率。布局已经正确但物理出图仍慢时，按
[显示管理设计](../project/display-management.md#framebuffer-延迟诊断)区分软件收敛与驱动/链路延迟；
设备已知现象和已验证恢复路径只从[平台档案索引](../platforms/index.md)查看。

保留 `nmtui` 作为交互式网络管理界面。`Mod+F9/F10` 用于挂载/卸载 `lsblk` 可见的普通块设备；
局域网 CIFS 挂载使用独立菜单命令 `dmenumountcifs`。锁屏、睡眠、关机等系统操作从系统菜单进入。

## 状态栏、通信与网络服务

状态栏右侧模块显示电池、时间、网络、音量、任务、RSS、邮件、种子和天气等信息。点击或
滚动模块会打开相应程序或执行动作；某个模块为空通常表示该功能未配置、服务未运行或其
可选依赖缺失，不应影响其他模块。

按住 Shift 右键点击状态栏会用 Nvim 打开 `~/src/dwmblocks/config.h`。修改后需要在该源码目录
手动执行 `make` 和 `sudo make install`，再重新启动 DWMBlocks；保存文件本身不会自动编译安装。

邮件、RSS 和天气需要各自的账户、订阅或网络。添加 RSS 后可用 Newsboat 阅读；邮件账户和
同步设置属于账户私有数据。需要查看状态栏功能说明时，使用鼠标中键提示或快捷键摘要。

## 下载、种子与文本浏览

Newsboat、dmenu 和链接处理器可以把下载交给 `qndl` 队列。使用 `tsp -l` 查看队列；
`yt-dlp` 处理媒体下载。Transmission 守护进程、远程客户端和状态栏用于种子任务。

`torrent` 在安装 Tremc 时打开终端界面；没有 Tremc 时仍会启动守护进程并提示使用 Web 界面
或 `transmission-remote`。Lynx 用于需要纯文本浏览的场景。

## 编译、排版与数据辅助

`compiler <文件>` 按文件类型运行相应工具，`getbib` 可从 DOI 或 PDF 获取 BibTeX。使用多文件
TeX 项目时，在各子文件前 20 行内指向根文件：

```tex
% !TeX root = ../main.tex
```

在根文件中按需选择引擎：

```tex
% !TeX program = xelatex
```

根文件未声明程序时默认使用 PDFLaTeX；也可以明确选择 `pdflatex`、`xelatex` 或 `lualatex`。
运行 `texroot <当前文件>` 可查看最终根文件，`compiler <当前文件>` 会用 `latexmk` 编译该根文件，
最终 PDF 固定生成在根文件同目录。`opout <当前文件>` 打开这个 PDF，`texclear <当前文件>` 清理
可再生辅助文件但保留根源文件、参考文献源和最终 PDF。

若命令报告根文件缺失、声明冲突、循环、引擎不支持或 PDF 尚未生成，先用 `texroot` 检查声明，
再按依赖清单确认 `latexmk`、所选引擎和参考文献工具已经安装。其他编程语言和排版格式仍按需
安装各自工具链。

## 模板与计划工作

`.local/share/sys-etc/` 中的网络和包管理文件是示例，不能直接视为当前系统设置。复制前先
根据目标平台、网卡和安全要求调整，并把实际部署记录写入对应平台档案。cron 示例依赖图形
会话、用户 D-Bus 和明确 sudo 策略；未确认前不要启用自动更新任务。

## 个性化与故障处理

共享设置只修改已跟踪文件；单机运行覆盖只使用文档明确指定且被 Git 忽略的扩展点，例如
`profile.local` 和 `aliasrc.local`。目标显示设备适配器只有在接口实施并加入精确 ignore 规则后
才属于扩展点。文件名以 `.local` 结尾并不自动表示私有，已跟踪的 `tmux.conf.local` 仍是共享配置。
设备/发行版事实写入一个平台档案，其他文档只经平台索引引用。修改后以 `c diff` 审查，确认功能
正常再提交。常见问题的排查顺序
是：确认所需程序已安装，确认相关服务或会话已启动，重新登录 X11，然后检查对应布局（layout）
的配置入口和平台档案。

上游 LARBS 手册假定不同的浏览器、邮件工具、PulseAudio、源码路径和快捷键。遇到差异时，
以本指南、快捷键摘要和依赖清单为准，而不是直接套用上游个人设置。
