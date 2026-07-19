# 架构与设计

## 目的与读者

本文面向 Codex 和维护者，说明已跟踪配置的结构、职责、运行关系、设计决策和维护边界。
它不是桌面操作手册；用户使用方法见[桌面使用指南](../user/desktop-guide-zh.md)。

## 仓库约定

仓库是位于 `$HOME/.cfg`、工作树为 `$HOME` 的 bare Git 仓库，`c` 是规范 Git 入口。
只跟踪可复用的 home 配置；凭据、浏览器状态、缓存、构建产物、硬件状态，以及文档明确指定的
每机器覆盖文件有意排除在仓库外。`.local` 后缀本身不表示未跟踪。

根目录 dotfile 是兼容链接。规范内容应位于 `.config` 或 `.local`；不得用重复文件替代根链接。

## 目录与运行关系

| 层级 | 规范路径 | 职责 |
| --- | --- | --- |
| Shell | `.config/shell/`、`.config/zsh/`、`.config/tmux/`、`.bashrc` | XDG 环境、PATH、别名、补全、Tmux 和包管理命令 |
| X11 会话 | `.config/x11/`、根 profile 链接 | 会话环境、输入法、Xresources 和会话自启动 |
| 桌面程序 | `~/src/{dwm,dwmblocks,dmenu,st}` | 单独维护、编译和安装的桌面程序 |
| 用户辅助命令 | `.local/bin/` | 被 shell、DWM、MIME、状态栏和 cron 调用的命令 |
| 运行数据 | `.local/share/larbs/` | 键盘映射、Unicode 数据和兼容帮助文本 |
| 项目文档 | `.local/share/docs/{project,user,planning}/` | 通用设计、使用、计划与历史 |
| 平台档案 | `.local/share/docs/platforms/` | 设备类别与发行版组合的包映射、系统事实、验证和恢复记录 |
| 系统示例 | `.local/share/sys-etc/` | 必须显式复制并调整的未激活模板 |

正常 X11 链路是：登录 shell 加载 profile；`startx` 加载 `.xinitrc`；X 会话加载 `xprofile`；
`xprofile` 加载资源并启动会话负责的程序；`.xinitrc` 启动 `ssh-agent dwm`。音频等系统能力由
目标平台的用户服务管理器负责，X11 链路不得重复启动；具体实现见
[平台档案索引](../platforms/index.md)。

## 通用与平台边界

项目、用户和 planning 文档只描述共享能力、接口、规则和仓库级状态。以下事实只能写入一个
平台档案：发行版包名/安装状态、设备型号、connector/modeline、驱动或系统服务状态、实测模式/
耗时、机器专用恢复路径以及平台待办。通用文档通过平台索引定位这些事实，不得复制摘要形成
第二事实来源。

仓库统一选择的编辑器、浏览器、键位、命令和工作流属于共享产品决策，不因其具有个人偏好就
迁入平台档案。只有随设备或发行版变化的内容属于平台个性化。

## 布局（layout）模型

`dependencies.md` 是权威布局（layout）模型。新增依赖、脚本、文档引用和用户可见能力都必须先
归属一个布局（layout）。布局（layout）是职责边界，不是某个发行版的软件包安装清单。

## Shell、源代码管理与开发

负责 shell 初始化、别名、补全、编辑器、FZF 和 bare 仓库工作流。`profile` 提供共享环境，
`aliasrc` 提供命令和包管理分支，`.zshrc` 承担 Zsh 专属框架和补全。共享辅助脚本优先使用
POSIX Shell；`profile.local` 和 `aliasrc.local` 是预期的每机器扩展点。

`c` 的 Bash 与 Zsh 补全映射至 Git 补全，并在补全期间设置 bare 仓库环境。共享 `g*` 命令由
`aliasrc` 提供，`cg*` 通过 `cfg_git` 固定操作 `$HOME/.cfg`，不能依赖 alias 展开或当前目录仓库。
Git 状态使用 `gst`，不得占用非 Git 的 `gs`。

Zsh 在 `compinit` 后按条件加载 `fzf-tab`；缺失 `fzf` 时保留原生 Tab。Tmux 的规范配置位于
`.config/tmux/tmux.conf`，并加载已跟踪的共享覆盖层 `.config/tmux/tmux.conf.local`；它不是
每机器私有文件。仓库不保留根目录重复副本。

## X11 桌面与输入

负责会话启动、输入法选择、键盘重映射、合成器、Xresources 和 X11 辅助工具。`xprofile` 是
唯一输入法决策点，必须从选定引擎导出完整环境。它可以启动会话应用，但不得取得由平台服务
管理器负责的音频服务所有权。

`~/src/` 的 DWM、DWMBlocks、dmenu 和 st 是独立源码仓库；`slock` 是系统程序。DWM `Mod+F1`
使用 Groff 将安装的 `larbs.mom` 动态生成 PDF 并交给 Zathura，命令/快捷键标签必须使用实际
嵌入字体。四仓库的获取与构建入口位于根 README，编译能力由依赖清单定义，发行版开发包映射
只写平台档案。源码、安装副本、字体和代表页面的检查遵循维护策略。

## 外观、字体与壁纸

负责 Fontconfig、GTK、Dunst、Xresources、wal 模板和 `setbg`。静态颜色与字体回退是基础状态；
壁纸和 pywal 是可选覆盖层，缺少图片或 `wal` 时必须恢复默认，不能依赖陈旧生成缓存。

## 音频、音乐、录制与视频

负责 ALSA 兼容与显式硬件入口、MPD/Ncmpcpp/MPV 配置以及录制、处理、缩略图、标签和幻灯片辅助工具。配置消费
PipeWire 兼容音频栈，不启动该栈；已跟踪 `asoundrc` 不覆盖系统默认 PCM/CTL，避免把一个声卡名
写成共享默认。摄像头、捕获设备和 MPD 服务都是运行条件，缺失时只能影响相关功能。

## 文件、文档、密码与桌面处理

负责 LF、预览器、nsxiv、Zathura、MIME、桌面入口、文档工具和密码/OTP 工具。MIME 与 LF
处理器形成依赖链：新增处理器必须同步处理命令、桌面入口、依赖和缺失行为。邮件账户、密码库
内容和个人文档保持未跟踪。

## 显示、网络、挂载与系统控制

负责 RandR 自动/手动布局、重映射、亮度、锁屏/会话操作、NetworkManager 入口和挂载工具。
选择 NetworkManager 的部署中，它是连接配置、自动连接、地址、路由和 DNS 的唯一所有者；平台
选用全局 `wpa_supplicant` 时，它只通过 D-Bus 提供 Wi-Fi 认证后端，不是第二个接口管理器。
同一接口不得再由 ifupdown、systemd-networkd、dhcpcd 或接口级 `wpa_supplicant@` 服务管理。

`.local/share/sys-etc/systemd/network/` 与 `.local/share/sys-etc/wpa_supplicant/` 组成另一套
可选模板栈：systemd-networkd 负责三层网络，接口级 `wpa_supplicant` 负责 Wi-Fi 认证。模板必须
明确部署后才生效，并与同一接口上的 NetworkManager 互斥；平台为 NetworkManager 选择的全局
D-Bus 认证后端不属于冲突。

硬件睡眠键由 systemd-logind 或 elogind 唯一处理，DWM 不重复绑定。`xprofile` 通过按登录会话和
规范化 X server 划分的 `flock` 运行锁，单实例启动 `xss-lock --ignore-xss -- slock`：它在
login1 睡眠准备阶段启动真实 locker，
但不改变 XScreenSaver 空闲策略。`sysact` 无参数时提供菜单，显式参数走同一动作分派；
电源请求交给当前 login manager 且不跳过 inhibitors。标准 `slock` 不实现
`XSS_SLEEP_LOCK_FD` 握手，因此不使用 `--transfer-sleep-lock`；若未来要求严格的 locker-ready
确认，必须另行实现可验证的 FD 关闭协议，不得只加该选项。
显示状态模型、锁、布局、设备适配器边界、验证矩阵和 framebuffer 诊断统一由
[X11 显示管理设计](display-management.md)定义；本节不复制算法或平台实测。

`xdisplay.sh` 无参数或 `--apply` 时立即对齐，`--watch` 监测，`--status` 只读取；
`displayselect` 是交互式入口，两者必须共用布局锁。共享实现不得新增硬编码设备输出、模式或服务；
现有兼容注入是平台档案已登记、按显示管理未完成工作迁移的过渡例外，不得扩展为新设备方案。

`dmenumount` 和 `dmenuumount` 只处理 `lsblk` 可见的普通块设备，CIFS 使用独立命令；不得在普通
块设备入口混入协议专用分支。`dmenumountcifs` 仅解析 Avahi 的 SMB hostname/port，接受候选列表中的
guest 共享，并把目标限制在 `/mnt/cifs-<UID>/<hostname>-<port>/`；它使用用户级 `flock`、现有
`SUDO_ASKPASS` 的 `sudo -A` 和 `findmnt` 状态核对，不要求宽泛 sudoers，也不跟踪凭据。认证共享和
专用卸载入口在需求明确后另行设计。平台的显示/亮度/服务事实和验证结果见
[平台档案索引](../platforms/index.md)。

## 状态栏、通信与网络服务

负责 DWMBlocks 模块、RSS 刷新、邮件/任务/种子状态和有限网络查询。模块必须隔离：缺少命令
只能隐藏或降级该模块，不能阻塞整条状态栏，也不能引入无限重试的网络守护进程。

## 下载、种子与文本浏览

负责 task-spooler 队列、Newsboat 动作、链接处理、Transmission 和终端文本浏览。Tremc、FPP、
youtube-viewer 等低优先级集成必须有保护和回退，并保持守护进程与客户端边界清晰。

## 编译、排版与数据辅助

负责 `compiler`、`texroot`、`opout`、`getbib`、`texclear` 和按格式选择的工具链。工具链是按需
能力，不是无条件基础依赖。

TeX 根文件解析集中在 `texroot`：只读取每级文件前 20 行的标准 root 声明，相对声明文件逐级
解析，拒绝缺失/非 TeX/冲突/循环/过深目标。`compiler`、`opout` 和 `texclear` 共享解析结果。

根文件可声明 PDFLaTeX、XeLaTeX 或 LuaLaTeX；未声明时默认 PDFLaTeX。`compiler` 在根目录调用
`latexmk`，最终 PDF 固定与根文件同目录同名；`opout` 只打开该 PDF，`texclear` 只清理可再生
辅助文件，保留根源、最终 PDF、参考文献源和其他文档文件。

## 模板与计划工作

负责系统模板和 cron 辅助命令。模板绝不是生效配置；cron 需要明确的显示、用户 D-Bus 环境和
经过审查的提权策略，不能因文档存在就自动启用。平台是否部署模板只记录在对应档案。

## 设计与维护规则

- 优先使用现有布局（layout）职责，不随意新增抽象或文件。
- 除非配置确实无效、不安全或无效能，否则保留可信共享设置。
- 可选程序不得破坏 shell、X11 或无关状态栏模块。
- 跨发行版设计使用稳定命令名；发行版提供者只在平台档案映射。
- 通用文档不得保存平台事实；平台档案不得重新定义共享行为。
- 修改 `.local/share/docs/` 后执行维护策略规定的全库一致性、平台泄漏和隐私检查。
- `dependencies.md` 定义能力，本文定义职责，用户指南定义操作，平台档案定义部署事实。

活动、已完成和挂起工作分别见 [TODO](../planning/todo.md)、[历史](../planning/history.md)和
[挂起项](../planning/suspended.md)；平台状态见[平台档案索引](../platforms/index.md)。
