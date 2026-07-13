# 维护策略

## 项目约束

- 只跟踪可复用的 home 目录配置。不得加入缓存、凭据、已安装浏览器状态、构建输出或其他机器状态。
- 发现未跟踪代码时必须先报告并评估，不得自动纳入仓库。仅当代码具备明确运行必要性、跨设备复用价值、
  足够效率、结构清晰且维护成本合理时才跟踪；硬件专用补丁优先保留为本机钩子。
- 当应用程序或显示管理器依赖根兼容链接时保留它们；规范配置放在 `.config` 或 `.local` 下。
- 共享辅助命令优先使用既有本地模式和 POSIX Shell。
- 除非功能无法运行，否则将命令可用性视为可选；缺少可选程序不得破坏登录或 X11 启动。
- 在配置支持的范围内，使 APT、pacman、XBPS 和 Portage 的包管理行为保持可移植。
- 除非条目被证明无效、无效能或危险，否则保留可信个人值和模板。
- 仅在新文件形成明确配置或维护边界时才跟踪它；否则扩展现有归属文件。
- 未经明确决定，不得改变编辑器选择或既有 `vim` 调用约定。
- 公开推送前，检查已跟踪内容和 Git 历史中的凭据及个人信息。
- 每次修改 `.local/share/docs/` 后，提交前必须执行全库文档一致性检查：术语统一、内部链接有效、
  文档描述的目录与已跟踪路径一致，且文档之间的关系和职责仍然成立。
- `project/architecture.md` 是自洽的 Codex/开发者设计文档，只描述结构、所有权、运行关系、
  决策和维护边界。`user/desktop-guide-zh.md` 是自洽的用户操作文档，只描述安装、日常使用、
  个性化和故障处理。两者都遵循 `dependencies.md` 的布局（layout），但不得要求读者理解另一份文档，
  也不得重复对方职责。
- 除根 `README.md` 外，`.local/share/docs/` 下文档应尽量使用中文。命令名、路径、代码标识、
  字面输出、许可证和必要上游引用保持原样。
- 应先检查并讨论行为改动，再执行；仅在批准后验证和提交。
- 显示管理共享代码不得保存设备输出名、固定分辨率或 modeline。普通设备保持零配置，确有必要的
  硬件差异集中到一个未跟踪设备适配器；适配器不得另起 watcher、绕过共享布局锁或常驻轮询。

## 已接受的决定

- `c` 保持为核心 bare 仓库命令。
- `profile.local` 和 `aliasrc.local` 是支持的每机器扩展点。
- PipeWire 和 WirePlumber 由 systemd 用户服务负责。
- 静态颜色和桌面默认值必须在没有 `wal` 或壁纸时可用。
- 输入法选择集中于 `xprofile`：优先 `fcitx5`，再 `fcitx`，最后 `ibus`。
- Microsoft Edge 通过 `BROWSER` 作为配置浏览器。
- 安装 NetworkManager 时，`nmtui` 保持交互式网络管理入口。
- 现有 ALSA 回退文件保留，直到持续 PipeWire-only 测试证明可移除。
- DWM、DWMBlocks、dmenu、st 源码在 `~/src/` 下单独维护；由用户编译安装。
- `innogpu-restore-dp1-mode-x11` 是未跟踪的本机硬件恢复代码，通过
  `XDISPLAY_RESTORE_COMMAND` 可选接入；其固定 modeline 和设备假设不适合作为通用配置跟踪。
  在显示重构完成前它仍是当前接口，之后只在等价设备适配器验证通过后进入临时隔离目录。

## 明确不采用

- Voidrice 手动 PipeWire/WirePlumber X 会话自启动。
- Voidrice Bash/LUKS 专用的 `mounter` 与 `unmounter` 脚本。
- 常驻的 `remapd` udev 监视器；现有重映射入口足够。
- Tor 包装及上游个人浏览器、Neovim、Python 配置。
- 原样采用 Voidrice `xdg-terminal-exec`；它缺少有用回退和桌面注册。
- 盲目导入任何上游 DWM 键位或用户指南；本仓库只记录自身配置的行为。

审查历史见[历史](../planning/history.md)，延期提案见[挂起项](../planning/suspended.md)。
