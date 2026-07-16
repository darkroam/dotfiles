# 架构与设计

## 目的与读者

本文面向 Codex 和维护者，说明已跟踪配置的结构、职责、运行关系、设计决策和维护边界。
它不是桌面操作手册；用户使用方法见 `../user/desktop-guide-zh.md`。

## 仓库约定

仓库是位于 `$HOME/.cfg`、工作树为 `$HOME` 的 bare Git 仓库，`c` 是规范 Git 入口。
只跟踪可复用的 home 配置；凭据、浏览器状态、缓存、构建产物、硬件状态和 `*.local`
每机器覆盖文件有意排除在仓库外。

根目录 dotfile 是兼容链接。规范内容应位于 `.config` 或 `.local`；不得为了本机编辑方便
而用重复文件替代根链接。

## 目录与运行关系

| 层级 | 规范路径 | 职责 |
| --- | --- | --- |
| Shell | `.config/shell/`、`.config/zsh/`、`.config/tmux/`、`.bashrc` | XDG 环境、PATH、别名、补全、Tmux 和包管理命令 |
| X11 会话 | `.config/x11/`、根 profile 链接 | 会话环境、输入法、Xresources 和会话自启动 |
| 桌面程序 | `~/src/{dwm,dwmblocks,dmenu,st}` | 单独维护、编译和安装的桌面程序 |
| 用户辅助命令 | `.local/bin/` | 被 shell、DWM、MIME、状态栏和 cron 调用的命令 |
| 运行数据 | `.local/share/larbs/` | 键盘映射、Unicode 数据和兼容帮助文本 |
| 项目文档 | `.local/share/docs/` | 依赖、约束、计划、历史和用户资料 |
| 系统示例 | `.local/share/sys-etc/` | 必须显式复制并调整的未激活模板 |

正常 X11 链路是：登录 shell 加载 shell profile；`startx` 加载 `.xinitrc`；X 会话加载
`xprofile`；`xprofile` 加载资源并启动会话负责的程序；`.xinitrc` 启动 `ssh-agent dwm`。
PipeWire、pipewire-pulse 和 WirePlumber 不在此链中，因为它们由 systemd 用户服务负责。

## 布局（layout）模型

`dependencies.md` 是权威布局（layout）模型。新增依赖、脚本、文档引用和用户可见能力都必须先
归属一个布局（layout）。布局（layout）是职责边界，不是软件包安装清单。

## Shell、源代码管理与开发

负责 shell 初始化、别名、补全、编辑器、FZF 和 bare 仓库工作流。`profile` 提供共享环境，
`aliasrc` 提供命令和包管理分支，`.zshrc` 承担 Zsh 专属框架和补全。共享辅助脚本优先
POSIX Shell；`profile.local` 和 `aliasrc.local` 是唯一预期的每机器扩展点。

`c` 的 Bash 与 Zsh 补全都映射至 Git 补全，并在补全期间设置 bare 仓库环境；不得为某个
子命令保留比 Git 原生行为更窄的候选项。

共享 Git 快捷命令由 `aliasrc` 提供，并在 Oh My Zsh 初始化后加载，以覆盖其同名 Git 别名；
不得占用非 Git 的 `gs`，Git 状态使用 `gst`。`.gitconfig` 保存 Git 默认日志日期格式，
`profile` 设置允许交互认证的 `GIT_TERMINAL_PROMPT`。

`cfg_git` 是仅供 `cg*` 函数使用的 bare 仓库包装器。`cg*` 必须通过它调用 `/usr/bin/git`，
从而不依赖 alias 展开，并始终使用 `$HOME/.cfg` 作为 Git 目录、`$HOME` 作为工作树。

当 `fzf` 可用时，Zsh 通过 zplug 在 `compinit` 后加载 `fzf-tab`，以交互式选择补全候选；
缺失 `fzf` 时不加载该插件，保留原生 Tab 行为。

Tmux 的规范配置是 `.config/tmux/tmux.conf` 及其 `.local` 覆盖文件；不保留根目录
`.tmux.conf` 兼容副本，以便 Tmux 按 XDG 路径加载配置。

## X11 桌面与输入

负责会话启动、输入法选择、键盘重映射、合成器、Xresources 和 X11 辅助工具。`xprofile`
是唯一输入法决策点，必须从所选引擎导出全部环境变量。它可启动 Dunst、Picom、MPD 和
unclutter，但不得启动 PipeWire 服务。`~/src/` 的 DWM、DWMBlocks、dmenu、st 源码不属于
本仓库的修改范围；`slock` 使用系统安装的可执行文件，不在这四个源码目录中。

## 外观、字体与壁纸

负责 Fontconfig、GTK、Dunst、Xresources、wal 模板和 `setbg`。静态颜色与字体回退是基础
状态；壁纸和 pywal 是覆盖层，缺少图片或 `wal` 时必须恢复默认，不能留下陈旧生成颜色。

## 音频、音乐、录制与视频

负责 ALSA 回退、MPD/Ncmpcpp/MPV 配置以及录制、处理、缩略图、标签和幻灯片辅助工具。
它消费 PipeWire 兼容音频栈，不启动该栈。摄像头、捕获硬件和 MPD 服务均是运行条件，
不能被配置改动静默假设。

## 文件、文档、密码与桌面处理

负责 LF、预览器、nsxiv、Zathura、MIME、桌面入口、文档工具和密码/OTP 工具。MIME 和 LF
处理器形成依赖链：新增处理器必须同时处理命令、必要桌面入口、依赖文档和可选缺失行为。
邮件账户、密码库内容和个人文档保持未跟踪。

## 显示、网络、挂载与系统控制

负责显示选择、重映射、亮度、锁屏/会话操作、NetworkManager 入口和挂载工具。硬件特定
路径必须条件化。`displayselect` 只负责交互式 RandR 布局；`xdisplay.sh` 无参数或使用
`--apply` 时立即对齐布局，`--watch` 在 X11 会话中监测，`--status` 只读取并解释当前状态。
每份原始 RandR 快照只由一个 POSIX awk 过程解析一次，形成固定 TSV 状态：输出连接、primary、
geometry、宽高坐标、首个模式、current/preferred/target 模式及刷新率、模式数量、模式能力签名、
active、stale 和 pending。geometry 支持正负坐标，active 不以 `connected` 为前提，因此可以观察
innogpu 的 disconnected geometry。模式能力签名保留模式、刷新率和 preferred `+`，忽略表示
当前模式的 `*`；这样能力变化会触发重新规划，而一次正常 modeset 不会制造签名循环。

物理拓扑签名包含 lid 是否存在及其状态，以及所有输出的连接状态、首个模式和完整模式能力签名；
它不包含 current `*`、primary、坐标或缩放。基础 `health` 独立报告 stale、pending、无连接输出
或 ready；stale 和能力签名即使在连接状态不变时变化，也会触发有限重试。完整的自动布局
primary/geometry 健康检查必须与 manual marker 一起实现，否则会覆盖合法的 Arandr 手动布局，
这部分仍属于阶段 4 的后续工作。

盖子状态和 DRM sysfs 状态每 0.5 秒读取；RandR 稳定时每 1 秒读取一次，变化后保留约 5 秒的
快速窗口。布局成功不会提前结束该窗口，期间每秒用 `xrandr --query` 捕捉扩展坞稍后出现的
preferred、刷新率或新增模式；稳定期主动探测仍只作约 60 秒兜底，其余检查和布局验证使用
`xrandr --current`，避免持续 EDID 探测给驱动施压。相同拓扑和健康状态下的失败写入最多连续
尝试 3 次、间隔约 5 秒，之后只在低频主动探测时恢复尝试；状态变化会重置退避。

目标模式优先采用 RandR 标记的首个 preferred 模式及刷新率；没有 preferred 时采用模式表首项
及其首个刷新率。单屏、开盖扩展、合盖外屏和无法识别内屏时的镜像回退都显式应用目标模式，
不再委托 `--auto` 猜测。模式能力缺失时保留已经 active 的输出，尚未 active 的输出保持 pending，
不根据 EDID 或设备名称猜分辨率。

应用布局前会显式关闭 `disconnected + geometry` 的 stale 输出并重读验证；若此时没有 connected
活屏，则先按盖子策略激活并验证替代输出，合盖时只允许外屏作为替代，激活失败就保留旧
framebuffer 等待重试。每轮只消费一份快照，布局和 stale-free 结果验证成功后才提交状态。脚本
不硬编码外接输出名，以内屏标准前缀识别内屏；非标准或驱动变化的名称必须由
`XDISPLAY_INTERNAL_OUTPUTS` 显式列出，无法识别时对多屏尝试镜像回退；失败时不得提交成功状态并
应继续重试，但 RandR 不提供事务回滚，不能保证先前布局完全保留。硬件专用内屏恢复通过
`XDISPLAY_RESTORE_COMMAND`
注入未跟踪的本机命令，只允许在共享锁内执行有界短时尝试；后续重试由 watcher 调度，
不能让辅助脚本的内部休眠长期阻塞通用布局流程。当前 innogpu 恢复命令写死 modeline 与设备候选，
不属于可跨设备复用的仓库代码。
锁前缀由 UID 和规范化后的 X server `DISPLAY` 组成，`:0` 与 `:0.0` 共用锁，不同 X server
互不影响。有效 `XDG_RUNTIME_DIR` 必须归当前 UID 所有、权限为 `0700`；fallback 使用绝对
`TMPDIR` 或 `/tmp` 下归当前 UID 所有的非符号链接私有目录。watcher 使用有界单实例锁，并与
`displayselect` 共用 apply lock；连续 6 次 RandR 快照失败后退出，HUP、INT、TERM 和正常退出
只清理本代 generation。新 watcher 启动时清除无法验证的旧 manual marker；阶段 2 尚不写 marker。

`XDISPLAY_TEST_MODE=1` 只允许测试把 `/proc` 和 `/sys` 观测根指向 fixture，默认路径不受影响。
仓库跟踪的启动入口仍是 `xprofile`，布局已满足时不得重复 modeset。Android MTP 在 Debian 的
`simple-mtpfs` 接口尚无经过验证的兼容替代，不得未经接口测试替换。

本机已验证 innogpu 会让已拔出的输出短暂保持 `disconnected` 几何；当前 stale 清理会显式关闭
该输出，并要求 framebuffer 最终与有效输出包围盒一致。热插拔验证仍必须同时检查 connection、
geometry、实际模式和 framebuffer，不能只以物理屏幕已经切换作为成功条件。

自动布局的收敛还包括让根 framebuffer 匹配有效输出包围盒，不能长期留下没有物理输出覆盖的
根窗口区域。`health=ready`、输出 geometry 和 framebuffer 已正确，只能证明 X11 控制面完成，
不能证明显示器已经物理出图。若软件在约 2 秒内收敛而肉眼恢复连续超过 5 秒，应按重构计划的
framebuffer A/B 分支区分 watcher、驱动 modeset 和输出链路重新同步；保留旧 framebuffer 只用于
临时诊断，不是共享策略或设备适配能力。

本机硬件、systemd/udev 边界、遗留链路和实机验证结论见
[`display-management.md`](display-management.md)。该报告记录设备事实，不改变本节的跨设备设计约束。
显示管理的目标状态、设备边界和分阶段实施顺序见
[`display-management-redesign.md`](../planning/display-management-redesign.md)，设备专用实现必须遵循
[`display-device-adapter.md`](display-device-adapter.md) 的单适配器契约。重构完成前，本文前述
`XDISPLAY_*` 变量仍描述当前运行接口，不能提前按目标状态解释。

## 状态栏、通信与网络服务

负责 DWMBlocks 模块、RSS 刷新、邮件/任务/种子状态和有限网络查询。模块必须隔离：缺少
命令只能隐藏或降级该模块，不能阻塞整条状态栏，也不能引入无限重试的网络守护进程。

## 下载、种子与文本浏览

负责 task-spooler 队列、Newsboat 动作、链接处理、Transmission 和终端文本浏览。Tremc、
FPP、youtube-viewer 等可选集成必须有保护和回退说明，并保持 Transmission 守护进程与
客户端边界清晰。

## 编译、排版与数据辅助

负责 `compiler`、`getbib`、`texclear` 和按文件格式选择的工具链。工具链是功能范围，
不是无条件基础依赖；TeX 和多语言工具链的实际支持范围仍待决定。

## 模板与计划工作

负责系统模板和 cron 辅助命令。模板绝不是生效配置；cron 需要明确的显示、用户 D-Bus
环境和经过审查的 sudo 策略，不能因文档存在就自动启用。

## 设计与维护规则

- 优先使用现有布局（layout）职责，不随意新增抽象或文件。
- 除非配置确实无效、不安全或无效能，否则保留可信个人设置。
- 可选程序不得破坏 shell、X11 或无关状态栏模块。
- 跨发行版设计使用稳定命令名；各发行版提供者在审计中单独映射。
- 修改 `.local/share/docs/` 后必须执行 `maintenance-policy.md` 规定的全库文档一致性检查。
- `dependencies.md` 定义能力，本文定义职责与关系，用户指南定义操作；三者不得互相重复。

活动、已完成和挂起工作分别见 [TODO](../planning/todo.md)、[历史](../planning/history.md)
和[挂起项](../planning/suspended.md)。
