# 待办历史

本文面向 Agent 和维护者。

## 已完成待办

- [x] 2026-08-06：配置文件版本化与节点生命周期已实现。支持 `categories-*.conf` 元数据、
  `full`/`empty` 内置类别、节点 `config_version/status`、`list/history` 展示以及
  `remove/unremove/autoclean` 和向后兼容旧 `index.json`；相关实现和测试见下方记录。

## 最近记录的变更

- [x] 2026-08-11：完成 dotcfg 内部重构阶段 0 至 6。重构保留用户命令、参数、输出和返回码，
  完成按需加载、进程内节点/category 缓存、策略配置外部化、动态 category 状态检测、命令模块拆分、
  公共函数契约注释和文档对齐。全量 Bats `251/251` 通过，ShellCheck 严重级别 `warning/error` 为 0，
  性能和隐私/文档一致性复查结果见[重构计划](dotcfg-refactor.md)。

- [x] 2026-08-11：完成 dotcfg 内部重构阶段 4/5。将 `status/list/history/categories` 从入口
  拆为 `.local/lib/dotfiles/commands/` 的 source 模块，保留 bootstrap、参数分发和用户可见
  接口；为公共函数补充参数/返回值契约，修复确定性的静态问题。全量 Bats `251/251` 通过，
  Bash 语法和 `git diff --check` 通过，ShellCheck 严重级别 `warning/error` 为 0。阶段提交：
  `8352c95`、`a34dea8`、`cc86f93`、`91ac775`、`c7e0a50`。

- [x] 2026-08-11：完成重构阶段 6 的文档对齐。`architecture.md`、`installation-system.md`、
  `installation-testing.md` 已记录命令模块、按需加载边界和测试纳管要求；修正历史待办的完成
  状态，并将设备专属 k10temp 工作移回 Debian 平台档案。Markdown 链接、路径、术语、平台边界
  和隐私扫描通过；已知 Git 身份邮箱按用户决定保留并继续列入活动 TODO。

- [x] 2026-08-06：文件分类体系重构。将 `files.sh` 中 4 个硬编码数组（CFG_SERVER_FILES_DEFAULT、
  CFG_DESKTOP_INDICATORS、CFG_DESKTOP_ONLY_SYMLINKS、CFG_DESKTOP_ONLY_DIRS）和
  `cfg-validate.sh` 中 9 个硬编码桌面指标替换为声明式类别系统。新增 `utils/categories.sh`：
  解析 `categories.conf`（支持 `category`/`include`/`+`/`-` 语法）、类别继承（循环检测）、
  目录前缀匹配、`exclude.conf` 排除规则。内置 server（21 文件）和 desktop（继承 server + 9 桌面
  路径）两个默认类别。`cfg_detect_state()` 改用 `desktop - server` 差集动态计算桌面指标。
  `files.sh` 简化为 `cfg_analyze_files()` + `cfg_get_files_for_state()`。`switch.sh` 和
  `deploy.sh` 统一使用类别 API。新增 15 个类别测试（TC-C01~C15）。160/160 测试通过。
  **文档同步**：更新 installation-system.md（文件分类系统章节）。

- [x] 2026-08-06：history 输出格式优化。将 `dotcfg history` 从简单递归 DFS 渲染重写为
  Git log --graph 风格：最新节点在顶部、根在底部，使用泳道（lane）算法绘制分支图。主线
  （newest leaf → root）占 lane 0，侧分支按时间倒序插入 lane 1+。符号：`*` HEAD 节点、
  `o` 普通节点、`|` 垂直延续、`|\` 分叉、`|/` 合并。支持 ANSI 颜色（终端检测）。
  更新 history-graph.bats TC-H01 适配新格式。145/145 测试通过。
  **文档同步**：更新 installation-system.md 的 history 输出示例。

- [x] 2026-08-06：节点系统重构（v3.0）。将三态模型（fresh/desktop/server）+ 会话备份目录
  重构为 Git 风格的节点管理系统。新增 `utils/nodes.sh`（节点 CRUD、HEAD、deploy status、
  树操作），`commands/deploy.sh`（部署当前节点），`commands/undeploy.sh`（卸载当前节点），
  `commands/migrate.sh`（旧会话迁移），`commands/switch.sh`（统一切换逻辑）。节点存储：
  `~/.config-backup/nodes/{code}/` 含 manifest.txt、backup/、files/。index.json 用 awk
  解析（无 jq 依赖）。CODE 为 8 位 `[a-z0-9]` 随机码。dotcfg CLI 新增 list（四列表）、
  history（ASCII 分支图）、deploy、undeploy、migrate 命令，删除 graph 命令。switch 支持
  CODE 参数切换到历史节点（产生分支）。自动迁移在首次运行时将旧 `{from}-to-{to}-{ts}` 会话
  转为节点树。uninstall 兼容新旧备份源。145/145 测试通过（新增 18 个迁移测试）。
  **文档同步**：重写 installation-system.md（v3.0）和 installation-testing.md（v3.0）。

- [x] 2026-08-05：代码审查修复与安全性增强。
  **Q4 修复 - 时间排序**：uninstall.sh 改用目录名称时间戳排序（格式：`{from}-to-{to}-{YYYYMMDDTHHMMSS}`），
  mtime 作为回退。解决目录重命名、cp -rp、同一秒创建等场景的排序不确定性。
  **Q6 修复 - 克隆后验证**：install-2.sh 和 install-server.sh 在克隆仓库后重新执行 `cfg_validate`，
  确保克隆的仓库身份正确，防止 URL 错误或仓库损坏导致的安全问题。
  **状态检查**：restore-desktop.sh 和 restore-server.sh 添加状态检查，确保只在正确的前置状态下执行
  （restore-desktop 要求 server 状态，restore-server 要求 desktop 状态），避免误操作。
  **测试**：新增 6 个测试用例（TC-26/26b、TC-30/30b、TC-44/44b），覆盖状态检查和 timestamp 排序。
  全部 77 个测试通过。
  **文档同步**：更新 installation-system.md 反映新的排序逻辑、克隆后验证和状态检查。

- [x] 2026-08-05：安全性改进与库重构。
  **库重构**：将共享验证库从 `.local/share/dotfiles-lib/` 移到 `.local/lib/dotfiles/`，
  符合 XDG 规范（share/ 用于数据，lib/ 用于库）。更新所有引用路径。
  **测试隔离**：为 4 个关键函数添加安全检查（create_mock_cfg_repo、create_mock_cfg_repo_with_remote、
  create_valid_existing_cfg、setup_installed_state），拒绝在 REAL_HOME 下执行，防止测试污染真实环境。
  **uninstall 安全性**：重新设计为"恢复到 fresh 状态"而非"完全卸载"。只删除用户配置文件，
  保护安装基础设施（脚本、运行时库）永远不被删除。移除 `--clean-backups` 选项，改为打印手动清理说明。
  确保系统自洽：任何状态都可恢复，所有操作幂等，没有破坏性命令。
  **文档同步**：更新 installation-system.md 反映新的 uninstall 行为和保护文件列表。

- [x] 2026-08-05：备份系统重设计与统一 CLI。
  **备份系统**：将备份目录从扁平 `$HOME/.config-backup-{from}-to-{to}-{ts}/` 改为嵌套
  `$HOME/.config-backup/{from}-to-{to}-{ts}/`。MANIFEST 格式从绝对路径改为 tab 分隔的
  `relative_path\tmd5\tstatus`。完全重写 uninstall.sh：备份链扫描（bash 关联数组）、双模式恢复
  （默认=最早，--latest=最新）、--clean-backups。使用 `cp` 而非 `mv` 恢复文件实现幂等性。
  修复时间排序问题：使用文件系统 mtime（`find -printf '%T@\t%p\n' | sort -n`）替代目录名称排序。
  **统一 CLI**：新增 `dotcfg` 命令（~300 行），git 风格子命令：status（默认）、graph（ASCII 状态图）、
  history（从 MANIFEST 重建转换时间线）、switch（exec 调度到底层脚本）、validate、help。
  **测试**：从 Gen 1 shell 脚本迁移到 Bats v1.11.1。72 个测试全部通过（TC-01 到 TC-58），
  新增 15 个 dotcfg 测试。测试目录从 `scripts/test/` 迁移到 `.local/share/test/installation/`，
  消除额外的顶层目录，符合只用 `.config` 和 `.local` 的目录原则。
  **文档**：重写 installation-system.md（v2.0）和 installation-testing.md（v2.0）。

- [x] 2026-08-04：全量配置审计与文档重构。逐文件审查 140 个跟踪文件，发现并修复 112 项问题
  （22 项高严重度：eval 注入、printf 格式串、未初始化变量等；42 项中严重度：XDG 变量顺序、
  未加引号变量、临时文件泄漏等；52 项低严重度：GNU 扩展、拼写错误、风格问题）。审计记录归档于
  `audits/` 目录。文档重构：将工作流规则从"已接受的决定"提升为 maintenance-policy.md
  独立章节；审计文件从 planning/ 迁移到 audits/ 按日期归档；清理会话指令。

- [x] 2026-08-03 ~ 08-04：实施安装系统 v2.0。新增 5 个 Gen 2 脚本（install-2.sh、install-server.sh、
  restore-desktop.sh、restore-server.sh、uninstall.sh），实现三状态幂等安装系统（FRESH/DESKTOP/SERVER）。
  核心特性：状态感知备份（`.config-backup-{from}-to-{to}-{timestamp}`）、MD5 内容对比过滤、
  MANIFEST.txt 精确追踪、`.cfg-checkout-state` 指纹记录、智能状态决策交互提示、`--dry-run`/`--reinstall`
  参数。新增共享验证库 `cfg-validate.sh`（cfg_validate/cfg_should_backup_file/cfg_detect_state）及内联回退。
  新增状态机测试框架（9 种转换全部通过）和单元测试（11 项）。卸载改为不自动删除仓库。文档整合为
  installation-system.md 和 installation-testing.md。代码审查发现 7 个待修复问题（B1-B7），
  详见 planning/installation-fixes.md。

- [x] 2026-08-03：优化 getkeys 快捷键参考系统。增强脚本支持无参数时按类别显示程序列表
  （窗口管理、终端/文件、文档/媒体、通信、生产力）；新增 dwm、dmenu、lf、st 的快捷键文档；
  删除 ranger（改用 lf）；重构全部10个文件按功能分区（导航、剪贴板、文件操作等），提升可读性。
  共修改12个文件，新增374行，删除70行。

- [x] 2026-08-03：清理 i3 相关内容。删除 `profile` 和 `xinitrc` 中的 i3 注释行；简化
  `showclip` 注释（脚本保持 WM 无关）；移除 `sb-help-icon` 的 i3 回退分支，改为 dwm 单一分支；
  删除 `tutorialvids` 的 i3 视频教程条目。`dependencies.md` 保留 LARBS 迁移历史记录。共修改
  5 个文件，删除 11 行，新增 2 行。

- [x] 2026-07-20：加固 `maimpick`。DWM 的普通 `Print` 与 `Shift+Print` 统一进入 helper，CLI 和六项
  菜单共用选区、窗口、全屏的保存/复制路径。截图默认保存到已忽略的 `~/Pictures`，支持绝对
  `MAIMPICK_DIR`，使用 mode 600 的唯一临时文件、显式 PNG 格式和不覆盖原子落位；复制只有在捕获
  成功且非空后才更新 `CLIPBOARD`。依赖改为按分支检查，明确区分选区取消与真实错误，当前窗口
  统一包含透明区域下方画面。Dash、系统 sh、BusyBox sh 语法和隔离 mock `33/33` 通过；DWM 从
  干净状态构建成功，源码帮助生成 7 页 PDF，嵌入字体、文本和代表页面渲染正常。部署和实机证据
  见[平台档案索引](../platforms/index.md)。

- [x] 2026-07-19：在 st 源码中加入状态相关的右键复制/粘贴。已完成选区时右键复制到
  `CLIPBOARD` 并清除高亮，无选区时右键粘贴；中键 `PRIMARY` 保持不变。应用启用鼠标上报时
  普通右键继续交给应用，`Shift+左键拖动`和 `Shift+右键`强制执行本地动作。同步删除不可达的
  重复 `Shift+Insert` 绑定并修正不存在的 `Alt-p` 手册说明。st 从干净状态构建成功，Groff 手册
  解析和隔离 Xvfb 核心复制/粘贴流程通过。用户确认目标功能可用并关闭本项；安装副本和实机
  证据见[平台档案索引](../platforms/index.md)。

- [x] 2026-07-19：加固 `otp`。密码库路径支持标准默认值和 `PASSWORD_STORE_DIR`，候选可递归包含
  嵌套条目，取消与自由输入不会触发操作。二维码改为 `maim` 到 `zbarimg` 的管道，脚本不创建明文
  图片文件；URI 只通过 stdin 送入 `pass-otp`。私有加密暂存和 `ln -T` 原子落位保证不覆盖已有条目，
  密码库 Git 只提交本次条目并保留签名提交设置。导入和 HOTP 共用用户锁，所有可能后台化的子进程
  关闭锁 FD；`oathtool` 低于 2.6.5 时拒绝生成，通过门槛后强制 `pass-otp` 使用 stdin 安全分支，
  时间同步按 Chrony、systemd NTP 和一次性客户端的所有权选择。POSIX Shell 语法和隔离 mock
  `82/82` 通过；系统 `pass`/`pass-otp` 的假 GPG/oathtool/xclip 隔离验证确认 seed 不在 argv 且只
  进入 stdin。验证未读取真实密码库、GPG 密钥或 OTP secret；真实 X11、账户、HOTP 和剪贴板行为
  继续由平台待办跟踪。

- [x] 2026-07-19：加固 `dmenurecord`。屏幕和选区录制改用当前 `$DISPLAY`，摄像头从 V4L2
  by-id/可读节点发现并支持环境覆盖，FFmpeg H.264 编码器修正为本机实际提供的 `libx264`。
  PID、启动时刻、图标和日志移入用户运行时/缓存目录，使用 `flock` 串行控制并阻止后台进程
  继承锁；PID 与 procfs 启动时刻以单个状态文件原子登记，缺失或无效 token 一律拒绝。停止先
  TERM 有界等待，再按需 KILL。POSIX Shell 语法和隔离 mock `21/21` 通过；真实 X11/硬件采集仍由
  平台待办跟踪。

- [x] 2026-07-19：统一 Bash/Zsh 的代理控制。将环境代理和 Git 代理函数集中到共享 `aliasrc`，
  保持 `7897` 端口和大小写环境变量行为；移除 X11 非交互 shell 中不会生效的 proxy alias，以及
  Zsh 中的重复定义。代理不会因启动图形会话而强制注入所有程序。

- [x] 2026-07-19：加固匿名 CIFS 菜单。脚本改用 Avahi resolved hostname/port 和 `smbclient -g`，
  严格限制候选服务器与共享名，使用用户级锁、`findmnt` 核对和 `/mnt/cifs-<UID>/` 下的隔离目标；
  提权统一走 `sudo -A`，挂载使用 guest、本地 uid/gid、`nosuid`/`nodev`，不再关闭客户端权限检查，
  也不要求宽泛 sudoers。`dash -n`、`sh -n` 和隔离 mock `22/22` 通过；本机没有 SMB 测试服务，
  真实 guest 验证按用户决定挂起，认证共享与专用卸载入口同样列入挂起项。

- [x] 2026-07-19：固定网络接口的唯一所有者规则。选择 NetworkManager 时，由它负责连接配置、
  自动连接、地址、路由和 DNS；平台选用全局 D-Bus `wpa_supplicant` 时，它仅作为 Wi-Fi 认证后端。ifupdown、
  systemd-networkd、dhcpcd 和接口级 `wpa_supplicant@` 不得并行管理同一接口。备用
  systemd-networkd/接口级 `wpa_supplicant` 模板已加入就地互斥警告；发行版部署、迁移验证和
  恢复事实只记录在[平台档案](../platforms/index.md)。

- [x] 2026-07-18：移除 DWM 中的 Void 风格 `sudo -A zzz` 睡眠键绑定，硬件键改由
  systemd-logind 或 elogind 唯一处理。X11 会话单实例启动
  `xss-lock --ignore-xss -- slock`，在不改变 XScreenSaver 空闲策略的前提下桥接 login1 锁屏/睡眠事件；
  单实例由按登录会话和 X server 划分的 `flock` 运行锁保证。
  `sysact` 的菜单和显式动作共用同一分派，使用 `systemctl` 或 elogind `loginctl`，
  并移除会跳过 inhibitors 的 `-i`。标准 `slock` 不支持延迟锁 FD 握手，因此本项不使用
  `--transfer-sleep-lock`；严格 locker-ready 握手留待单独设计和验证。

- [x] 2026-07-18：跟踪 X11 专用 `passmenu`，使 DWM `Mod+Shift+d` 不再依赖
  发行版的文档示例路径。脚本基于 Password Store 官方 dmenu 示例并保留
  GPL-2.0-or-later 来源与版权；默认复制密码，显式 `--type` 才自动输入。
  `dmenupass` 继续只负责 sudo Askpass；隔离 mock 回归 `9/9` 通过，两个密码库目录均由
  Git 忽略且验证过程不读取或跟踪真实数据。

- [x] 2026-07-18：将 DWM 麦克风静音键从 `pactl` 切换为不经 shell 直接调用
  `wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle`，复用已有 PipeWire/WirePlumber 控制链，
  不再为单一按键引入 PulseAudio 协议客户端依赖；`pipewire-pulse` 兼容服务保持不变。

- [x] 2026-07-18：将 DWM `Mod+Shift+e` 改为不经 shell 直接启动
  `abook`，与 Mutt Wizard 共用 `~/.abook` 默认数据目录。不新增或跟踪通讯录配置和
  账户数据；DWM 帮助中的 `Mod+E` 仍表示同一 Shift 组合键。

- [x] 2026-07-18：加入可移植的 `clash-verge-handler.desktop`，统一处理 `clash:` 与
  `clash-verge:` URI。handler 通过 PATH 和 `TryExec` 定位程序，`Exec` 不经过 shell；配置不再
  依赖发行版含空格的 desktop 文件名。`gio` 与 `xdg-mime` 的隔离测试和当前配置查询均正确解析
  两个 scheme，未在验证中启动 GUI。

- [x] 2026-07-18：统一独立桌面源码入口为 `~/src`。规范书签 `rr`/`src`、`cfb`、DWM 状态栏
  `Shift+Button3` 和 DWMBlocks 注释不再引用旧 `~/.local/src`；已重新生成被 Git 忽略的 Shell、
  Zsh 与 LF 快捷方式。DWM 帮助同步修正源码目录，并明确保存 `config.h` 不会自动编译安装。
  DWM/DWMBlocks 隔离构建通过；用户安装并 renew DWM 后，运行映像确认只含新路径。实际安装的
  `larbs.mom` 与源码校验和一致，生成 PDF 保持 7 页，Nimbus Sans 已嵌入，文本和受影响页面
  渲染正常。

- [x] 2026-07-18：完成文档库内容准确性终审并同步实现。安装器改为临时克隆、预检目标及祖先
  冲突、拒绝不安全备份链接，并以私有目录按原层级备份；嵌套/空格路径、祖先文件/符号链接、
  冲突拒绝和失败清理回归通过。README 补齐 Git、OpenSSH、SSH 凭据及四个独立桌面源码的获取/
  构建入口，并移除跳过 TLS 校验的执行方式。通用依赖补入登录、控制台、进程探测、Qt 外观、
  Zsh/Tmux、DWM 外部调用和桌面源码开发能力；四仓库隔离构建通过，Python 执行改为优先
  `python3`。ALSA 默认路由交还平台系统配置并明确不自动硬件回退，图形登录接受动态 DRM/fbdev
  节点。另已校正 DWM 快捷键、Tmux 主配置/共享覆盖层、显示 legacy 注入/目标适配器边界；尚缺
  的 DWM 命令、旧源码绑定、Clash 并发改动和未跟踪硬件钩子均归入正确的通用或
  [平台待办](../platforms/index.md)。

- [x] 2026-07-17：完成通用文档与平台个性化事实分离。新增平台档案索引，以“设备类别 +
  发行版主版本”维护单一事实文件；迁移既有发行版依赖审计、设备显示事实、恢复信息和平台待办，
  将架构、依赖、用户指南、显示设计和 planning 恢复为通用内容。退役重复的设备报告/审计记录，
  并把平台泄漏、索引可达和隐私字段加入维护与跨发行版审计规则；平台工作固定拆分为活动待办和
  带恢复条件的挂起项目，可从索引分别聚合。一致性检查同时把根 ALSA
  兼容链接改为相对目标，并让 Bun completion 通过 `$BUN_INSTALL` 定位，清除共享配置中的固定
  home 路径。入口见
  [平台档案索引](../platforms/index.md)。

- [x] 2026-07-17：修正 DWM `Mod+F1` 帮助 PDF 的命令和快捷键标签显示。最终使用嵌入式常规
  字重 Nimbus Sans，避免查看器替代字体造成字宽错配，并保持七页内容和快捷键不变。维护策略
  和跨发行版审计流程已固化生成类文档检查：
  必须验证实际入口、安装副本、产物、字体嵌入、文本和代表页面渲染，不能只检查命令成功。
  发行版提供者和实测证据见[平台档案](../platforms/index.md)。

- [x] 2026-07-17：移除移动设备专用 SDK 环境变量、终端安装器分支、文件传输挂载逻辑和字符
  入口；`dmenumount`、`dmenuumount` 及 DWM `Mod+F9/F10` 保留普通块设备能力，CIFS 继续由
  独立命令负责。同步清理依赖、架构、用户指南和挂起状态。

- [x] 2026-07-17：完成 TeX 工作流审查。新增共享 `texroot`，统一 `compiler`、`opout`、
  `texclear` 的根文件语义；使用 `latexmk` 支持 PDFLaTeX、XeLaTeX、LuaLaTeX、Biber 和多轮引用，
  最终 PDF 固定在根文件同目录。本次 `77/77` CLI 回归通过，覆盖中日文字体、特殊路径、项目
  `.latexmkrc`、无图形及非 TeX 打开、冲突/循环声明和不越界清理；平台安装映射单独记录。

- [x] 2026-07-16：共享显示引擎加入 `disconnected + geometry` stale 清理、完整模式能力签名、
  显式 target mode/rate、短时 settling 和有界退避；fixture 通过 `11/11` 状态/锁、`4/4`
  watcher 生命周期与 `11/11` 显示回归。设备实测链路与模式见[平台档案](../platforms/index.md)。

- [x] `0b40ac7`：完成显示状态解析、按 X server 加锁和 watcher 生命周期重构；共享策略继续把
  framebuffer 收敛到有效输出包围盒，保留旧尺寸只允许用于受控 A/B 诊断。平台重启、外屏和
  延迟证据见[平台档案](../platforms/index.md)。

- [x] `ef104b6`：完成跨设备 X11 显示管理方案和单设备适配器开发指引，确立共享布局所有权、
  平台本地适配器、临时隔离与可验证恢复边界；具体隔离清单只保存在对应平台档案。

- [x] 完成 X11 显示管理关系分析，将状态模型、自动/手动布局、服务边界、验证矩阵和恢复原则
  固化为通用设计；设备硬件、服务和实测结果由平台档案承担。

- [x] 将 `architecture.md` 重写为 Codex/开发者设计文档，将 `desktop-guide-zh.md` 重写为
  自洽的用户操作指南。两者均使用十个依赖布局（layout）；维护策略固定了不同读者和内容边界。
  全库文档检查通过术语、链接、路径、布局（layout）覆盖和文档关系验证。

- [x] 静态凭据扫描未在当前树或可达历史中发现私钥或高置信度 token 模式；已跟踪 Git 身份和
  既有历史作者元数据有意保留。

- [x] `11b758e`：通过 `BROWSER` 选择 Microsoft Edge，并移除剩余 Firefox 专用 DWM 规则。
- [x] `66846b6`：将 LF 图标移动至 `.config/lf/icons`。
- [x] `ac3e17b`：加入感知缓存的 `weath` 辅助命令。
- [x] `ddd0693`：使 `samedir` 能处理活动终端/LF 进程树。
- [x] `f228040`、`f7c5cfd`、`a84bd30`：将亮度、图形和 TeX 提案记录为延期，而不是改变
  未测试行为。
- [x] `f99558e`：为更多图像/文档格式加入 LF 预览。
- [x] `342b643`：通过 `rssget` 加入 RSS feed 发现并加固 `rssadd`。
- [x] `c1181c1`：将 PipeWire 感知静音整合进锁屏处理。
- [x] `508d029`：使 PATH 初始化在 shell 与 X11 启动中幂等。
- [x] `89d9aa8`：加固 shell 命令配置，包括 bare Git 命令补全路径。
- [x] `7deada6`：完成并记录第一轮配置审查。

## 第一轮配置审查

- [x] 验证 bare 仓库操作、根符号链接、shell 启动和 `c` 补全。
- [x] 检查 X11 启动、输入法选择、壁纸/pywal 回退、PipeWire 所有权、字体、GTK 和 Xresources。
- [x] 检查状态模块语法和缺失传感器行为；没有 CPU 热传感器时温度保持为空，不以 NVMe 温度
  冒充 CPU 温度。
- [x] 检查 cron 文档、MIME 图像关联和包管理器可移植性。
- [x] 审查显示、挂载和亮度辅助命令；`xlight` 可容忍没有已保存状态。
- [x] 完成通用辅助命令的静态和语义审查：文件/MIME、下载/种子、媒体、文档、系统辅助和模板。
- [x] 修正录制控制、幻灯片/有声书时间码解析、PeerTube/RSS、文档编译和辅助命令错误报告边界情况。
- [x] 加固可选辅助命令对缺失依赖和失败队列的处理。

## 已采用的 Voidrice 启发工作

- [x] 加入 `sysact` 锁屏集成：锁定时静音 PipeWire 默认输出并暂停 MPD/MPV，只恢复原先未静音的
  输出；不自动恢复播放，音量刷新 DWMBlocks。
- [x] 加入 `rssget`：接收 URL 或剪贴板 URL，发现 feed，提供选择，并使用有限请求和唯一临时文件调用 `rssadd`。
- [x] 为 AVIF、DjVu、SVG、XCF 和 NDJSON 回退加入 LF 预览。
- [x] 将 LF 图标移动至 `.config/lf/icons`，使所有 LF 启动路径一致。
- [x] 通过活动窗口进程树查询加固 `samedir`，同时保留 shell/LF 回退。
- [x] 使用共享 XDG 缓存以 `weath` 替代过时天气别名。

## 其他已完成决定

- [x] 在 APT、pacman、XBPS 和 Portage 中统一 `p`、`pu`、`pi`、`pr`、`pse`、`pp`、`pl`、`pc` 包别名。
- [x] 将状态栏音量动作切换至 `wpctl`，同时保留 ALSA 兼容入口和 `pulsemixer` 界面。
- [x] 使壁纸/pywal 行为可选，同时保留静态默认值。
- [x] 保持 PipeWire 用户服务所有权，并移除重复 X 会话启动。
- [x] 通过 `setbg` 统一 URL 壁纸选择；成功下载刷新可选 wal 颜色，失败下载保留桌面状态。
