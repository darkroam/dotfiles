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
unclutter，但不得启动 PipeWire 服务。`~/src/` 的 DWM、DWMBlocks、dmenu、st、slock
源码不属于本仓库的修改范围。

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
路径必须条件化。`displayselect` 只负责交互式 RandR 布局；`xdisplay.sh` 在 X11 会话中读取
盖子状态，普通执行时立即对齐布局，`--watch` 以盖子状态和 RandR 快照签名变化触发处理。
盖子状态和 DRM sysfs 状态每 0.5 秒读取；RandR 稳定时每 1 秒读取一次，变化后在 5 秒快速窗口内每 0.5 秒读取，
因此可覆盖启动时外屏或驱动延迟出现的情况，同时限制稳定期唤醒。`xrandr --query` 仅在
DRM 状态变化、快速窗口每秒一次及 10 秒兜底时主动探测硬件；盖子变化先使用缓存状态立即处理，
其他检查和布局验证使用
`xrandr --current`，避免持续 EDID 探测给驱动施压。每轮只消费一份快照，
布局结果验证成功后才提交新拓扑签名。它不硬编码外接输出名，
以内屏标准前缀识别内屏；非标准或驱动变化的名称必须由 `XDISPLAY_INTERNAL_OUTPUTS` 显式列出，无法识别时
对多屏尝试镜像回退，镜像失败时必须保留布局并重试。合盖切换必须先准备外屏主输出，再关闭内屏，
已激活输出不得无条件重跑 `--auto`。硬件专用内屏恢复通过 `XDISPLAY_RESTORE_COMMAND`
注入未跟踪的本机命令，只允许在共享锁内执行有界短时尝试；后续重试由 watcher 调度，
不能让辅助脚本的内部休眠长期阻塞通用布局流程。当前 innogpu 恢复命令写死 modeline 与设备候选，
不属于可跨设备复用的仓库代码。
watcher 使用单实例锁，并与 `displayselect` 共用布局锁；仓库跟踪的启动入口是 `xprofile`，
布局已满足时不得重复 modeset。Android MTP 在 Debian 的 `simple-mtpfs` 接口尚无经过验证的兼容替代，
不得未经接口测试替换。

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
