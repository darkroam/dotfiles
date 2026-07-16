# X11 显示管理重构计划

状态：阶段 2 实现、fixture、当前会话和 2026-07-16 真实 X11 换代验证均已完成。现场缺陷促使
阶段 4 中的 stale 清理、模式能力观测、显式目标模式、settling 和有界退避提前完成并通过实机
链路；阶段 3 和阶段 4 的其余项目尚未开始。代码回退基线为 `a191c3c`，规划文档基线为
`ef104b6`，隔离边界基线为 `9e0c292`，阶段 2 实现基线为 `0b40ac7`。

本文把本机已经验证的显示链路重构为可跨设备复用的方案，并规定实施顺序、隔离范围、
验证门槛和恢复方法。当前运行事实仍以
[`../project/display-management.md`](../project/display-management.md) 为准；设备个性化接口见
[`../project/display-device-adapter.md`](../project/display-device-adapter.md)。

## 目标与边界

- 保持外屏热插入后自动扩展、拔出后恢复单屏；接电且会话未挂起时，合盖关闭内屏，开盖恢复
  内屏并重新扩展外屏。
- 普通 `eDP-*`、`LVDS-*`、`DSI-*` 内屏不需要任何设备配置。输出名称、数量、分辨率和连接
  顺序均从运行状态读取，不写入共享脚本。
- 非标准内屏名称和驱动恢复命令只存在于一个未跟踪的设备适配器中；共享 `xprofile` 不再保存
  本机输出名或 modeline。
- 保留 `xprofile -> xdisplay.sh --watch -> xrandr` 的会话所有权。udev 不直接执行 `xrandr`，
  systemd 用户服务不另起 watcher。
- 保留 `displayselect` 作为 `Mod+F3` 的交互入口，并与 watcher 串行修改布局。
- 本轮不调整 DWM、DWMBlocks、dmenu、st、活动 Xorg 驱动配置或
  `innogpu-repair-dri-nodes.service`。
- logind 决定系统是否在合盖时挂起，`xdisplay.sh` 只在仍然存活的 X11 会话中决定输出布局；
  两种职责不得混为一体。

## 目标所有权

```text
内核/DRM + Xorg
  -> RandR 输出、模式和几何
  -> .config/x11/xprofile
       -> xdisplay.sh --watch             通用且唯一的自动布局引擎
            -> 标准内屏识别               默认零配置
            -> xdisplay-device.local      可选、未跟踪、单设备适配器
            -> xrandr                     唯一布局修改接口
                 -> DWM ConfigureNotify/Xinerama

Mod+F3 -> displayselect -> 同一 DISPLAY 的布局锁 -> xrandr

systemd-logind -> 合盖挂起/忽略策略，不负责 RandR 布局
```

`xdisplay.sh` 统一负责快照读取、状态解析、策略规划、加锁、应用、验证、有限重试和诊断。
设备适配器只回答内屏候选并可进行一次短时恢复尝试，不能另起监视器或自行决定布局。

## 状态模型

每轮只解析一份 RandR 快照，并为所有 `connected` 或 `disconnected` 输出记录以下字段：

| 字段/状态 | 定义 | 用途 |
| --- | --- | --- |
| `lid_present` | 是否存在 lid 状态文件，不以本轮读取成功为前提 | 区分桌面设备与状态暂时不可读的笔记本 |
| `lid_state` | 有 lid 时为 `open`、`closed` 或 `unknown`；无 lid 时为 `absent` | 选择笔记本或桌面回退策略 |
| `connection` | RandR 报告的 `connected` 或 `disconnected` | 表示当前物理连接判断 |
| `geometry` | `<宽>x<高><+|->x<+|->y`；必须支持负坐标 | 表示输出仍占用 framebuffer |
| `active` | 存在 geometry，不要求输出仍为 `connected` | 捕获 innogpu 的断开残留 |
| `mode_ready` | `connected` 且存在至少一个可用模式 | 判断是否存在可显式应用的目标模式 |
| `stale` | `disconnected` 但仍存在 geometry | 必须显式加入待关闭输出 |
| `pending` | `connected`、未激活且模式尚未就绪 | 保留安全活屏并有限重试 |
| `current_mode/current_rate` | 带 current `*` 的实际模式及刷新率 | 判断当前输出是否已经处于目标模式 |
| `preferred_mode/preferred_rate` | 首个带 preferred `+` 的模式及刷新率 | 有 preferred 时作为目标 |
| `target_mode/target_rate` | preferred，缺失时回退模式表首项及首个刷新率 | 所有自动布局路径显式应用，不依赖 `--auto` |
| `mode_count/mode_signature` | 模式数量，以及模式、刷新率和 preferred 的完整签名 | 捕捉扩展坞迟到的能力变化；签名忽略 current `*` |

当前物理拓扑签名包含 lid 是否存在及其状态、输出连接状态、首个可用模式和完整模式能力签名，
不包含 current `*`、primary、坐标或缩放。它既能捕捉连接变化，也能捕捉首模式不变但 preferred
或刷新率改变的情况；仍不能单独表示布局已经收敛，也不能单独保护手动布局。

watcher 已把基础收敛健康与拓扑独立比较，检查 stale、pending 和无连接输出。相同拓扑/health
的失败写入最多连续尝试 3 次、间隔约 5 秒，达到上限后只在低频 query 时恢复尝试；拓扑、能力
或 health 变化会重置退避。期望输出 active、自动布局 primary/geometry 等完整健康仍须与 manual
marker 同步实现，否则会覆盖合法的手动布局。

每次自动规划必须同时得到 `desired_outputs` 和 `off_outputs`。后者是所有已知输出减去期望输出，
包括 `disconnected` 但仍有 geometry 的输出；不能只配置期望输出后提前返回。

## 通用布局策略

| 场景 | 目标行为 | 安全条件 |
| --- | --- | --- |
| 单个可用输出 | 设为 primary、定位 `0x0`，其余已知输出全部 `--off` | 合盖且只剩内屏时不强制重新 modeset，但仍清理其他 stale 输出 |
| 开盖/盖子状态未知且识别内屏 | 内屏为 primary，外屏按 RandR 顺序向右扩展 | 内屏无模式时先调用一次设备恢复，再由 watcher 重试 |
| 合盖且外屏可用 | 先激活外屏 primary，再关闭内屏，多个外屏向右扩展 | 外屏未验证为 active 前不得关闭最后一个安全活屏 |
| 合盖且外屏尚未就绪 | 暂时保留当前安全活屏并进入 pending | 不提交成功状态，有限频率主动探测 |
| 有盖子但无法识别内屏，多输出 | 选择最高共同模式后镜像所有可用输出 | 没有共同模式时保留至少一个已验证活屏，不执行可能只完成一半的布局 |
| 没有盖子设备，多输出 | 选择已有 primary 或首个输出并向右扩展 | 桌面设备不因缺少“内屏”概念退化为镜像 |
| 没有可用输出 | 不执行破坏性 RandR 命令 | 等待 connector 或模式就绪 |

扩展布局前必须验证计划包围盒不超过 RandR 最大 framebuffer；超限时优先使用安全镜像或保留
一个已验证活屏，不提交部分扩展。

布局锁和 watcher 单实例锁必须同时包含 UID 与规范化后的 X server `DISPLAY`，避免同一用户的
多个 X server 互相阻塞，同时让 `:0` 与 `:0.0` 共用同一组锁。优先使用有效且可写的
`XDG_RUNTIME_DIR`；回退 `/tmp` 时建立并验证 UID 所有、权限 `0700` 的私有目录。

共享锁只防止并发写入，不能防止 watcher 在手动命令释放锁后继续应用旧计划。DWM 的 `Mod+F3`
保持调用 `displayselect`；`displayselect` 的默认入口立即委托 `xdisplay.sh --manual-run`，引擎取得
布局锁后再调用 `displayselect --unlocked` 的内部 UI 模式，避免递归和双重加锁。选择成功后，
引擎在同一把锁内写入包含当前物理拓扑的 runtime manual marker。dmenu 取消、命令失败，以及
Arandr 退出前后布局没有变化时不得写 marker。

manual marker 还必须绑定 watcher generation；每个新 watcher 启动时生成新值并清理上一代 marker，
避免同一 `DISPLAY` 上重启 X server 后采用旧会话状态。marker 匹配时暂停自动 primary、几何、
stale 清理和 framebuffer 健康修复，只观察物理拓扑并确认至少存在一个活屏；输出、首个模式或
lid 状态变化立即让 marker 失效并恢复自动收敛。因此合法的负坐标和缩放不会触发自动覆盖。

自动路径保持现有无参数调用兼容，并计划提供：

```text
xdisplay.sh [--apply]
xdisplay.sh --watch
xdisplay.sh --status
xdisplay.sh --manual-run
```

`--status` 只报告盖子、输出解析、计划动作、manual marker、收敛健康、退避状态、适配器状态和
锁路径，不执行 `xrandr` 修改。

watcher 必须为 `TERM`、`HUP`、`INT` 和正常退出设置清理；连续 RandR 快照失败达到门槛时判定
当前 X server 已消失并退出，使重新登录的同一 DISPLAY 能取得新锁。短暂探测失败只进入退避，
不能让 watcher 因一次驱动延迟退出。新 watcher 对 watch lock 的等待必须有界，且等待窗口长于
旧 watcher 的 X server 失败退出门槛；不能因旧进程尚在清理就直接非阻塞退出。验证矩阵必须包含
退出 X11 后重新登录。

## 设备个性化

唯一设备文件计划为：

```text
${XDG_CONFIG_HOME:-$HOME/.config}/x11/xdisplay-device.local
```

它保持未跟踪并加入精确忽略规则。固定命令契约只有 `internal-outputs` 和
`restore-internal OUTPUT`；两个子命令都作为独立进程执行并使用带 kill-after 的 timeout，不能
`source` 或 `eval` 设备代码。引擎只接受当前 RandR 快照中存在的合法单输出名并去重。
详细返回值、示例和新设备开发流程见
[设备适配器开发指引](../project/display-device-adapter.md)。当前本机的 `DP-1` 别名和
`1920x1200R` innogpu 恢复逻辑将在适配器启用后迁入该文件；迁移前不得移走现有恢复命令。

内屏选择规则必须确定：先检查当前快照中的标准内屏候选；恰好一个时采用，多个时报告歧义并进入
安全回退。只有没有标准候选时才检查适配器候选，同样要求当前只匹配一个；不得按列表顺序随意
选择多个同时连接的候选并关闭另一个。

## 临时隔离与恢复

实施第一阶段时创建未跟踪目录：

```text
~/.local/share/xdisplay-transition-20260714/
|-- RESTORE.md
|-- manifest.sha256
|-- home/
`-- system/
```

目录权限设为 `0700`，内部为每个对象保留原路径、文件类型、UID/GID、mode、链接目标、校验和、
迁移阶段、恢复命令和代码基线；`cp -a` 保留实际元数据，清单用于复核。系统文件需要提升权限时
逐项请求确认，不能因创建了目录就批量移动。

| 对象 | 处理时机 | 理由与恢复 |
| --- | --- | --- |
| `.config/x11/xinit` | 第一阶段移动至 `home/` | 仅四字节 `::::`，未跟踪且无引用；按原路径和权限移回即可 |
| `.local/bin/xdisplay-hybrid.sh` | 第一阶段移动至 `home/` | 旧 udev 脚本硬编码 `eDP-1`、无共享锁；移回前也不能重新启用旧规则 |
| `/etc/udev/rules.d/95-display-hotplug.rules` | 备份后移至 `system/`，再重载 udev 规则 | 使用不存在的 `connector_status` 属性且硬编码会话；恢复后需再次 reload rules |
| `/etc/X11/xorg.conf.before-*`、`/etc/X11/xorg.conf.d/*.before-*` | 核对差异和校验和后移至 `system/` | 不参与 Xorg 加载，只是散落的历史备份；恢复不需要重启 Xorg |
| `.local/bin/innogpu-restore-dp1-mode-x11` | 设备适配器通过实机验证后再移动 | 当前仍是活动恢复钩子，必须先完成等价迁移 |
| 活动 Xorg、logind 和 innogpu service 配置 | 只复制快照，不移动 | 它们仍参与启动或电源策略，不能作为遗留文件隔离 |

隔离目录不进入配置仓库。只有在挂起项规定的稳定期、验证矩阵和至少一次无害文件的实际恢复
演练全部通过后，才讨论彻底删除；在此之前任何失败都应优先使用该目录逐项恢复。

## 分阶段实施

每一阶段都必须先记录变更前状态，完成静态检查和对应实机门槛，再单独提交。失败时停止后续阶段，
不能把多个不确定因素合并调试。

### 阶段 0：方案与基线

- [x] 盘点现行启动链、系统服务、Xorg 文件、未跟踪恢复脚本和遗留 udev 链路。
- [x] 记录代码回退基线 `a191c3c` 和当前已知的 stale framebuffer 缺陷。
- [x] 完成本计划、设备适配器指引和全库文档一致性检查，经确认后才进入阶段 1。

### 阶段 1：建立隔离边界

- [x] 创建隔离目录、`RESTORE.md` 和 sha256 清单，先复制活动系统配置作为快照。
- [x] 为隔离目录加入精确忽略规则，确认新建的恢复资料不会进入配置仓库。
- [x] 先移走无效 udev 规则并 reload/验证，再移动其 RUN 指向的旧 hybrid 脚本；随后移动无引用的
  `xinit` 和核对过的 Xorg 历史备份。
- [x] 确认没有第二条自动执行 `xrandr` 的链路；现有 watcher 行为保持不变。
- [x] 以既有开盖、合盖、热插和热拔实机结果作为行为基线，并在隔离后复查服务、进程和当前
  RandR 状态；布局代码修改后仍须重新执行完整矩阵。

### 阶段 2：只重构观测能力

- [x] 一次解析 RandR 输出为统一状态，支持负坐标、stale 和 pending，不改变布局策略。
- [x] 新增 `--status`、`--apply`、按 X server `DISPLAY` 隔离的私有锁目录、watcher generation
  和 manual marker 预留路径；保持无参数调用兼容。
- [x] 加入 X server 消失后的有界退出和 signal trap；模拟交接、当前会话受控换代及
  2026-07-16 整机重启后的真实 X11 换代均已通过。布局健康失败的退避仍属于阶段 4。
- [x] 用保存的快照覆盖单屏、扩展、镜像、负坐标、模式延迟和 disconnected geometry。
- [x] 实机确认 watcher 与 `displayselect` 使用同一 apply lock；新 watcher 唯一运行且日志为空。

### 阶段 3：迁移设备个性化

- [ ] 实现固定路径的可选设备适配器，并为本机创建未跟踪实现。
- [ ] 对两个适配器子命令都执行 timeout + kill-after，校验、去重并限制候选为当前已知输出。
- [ ] 从共享 `xprofile` 移除 `DP-1` 和恢复命令注入；标准设备在没有适配器时完成零配置验证。
- [ ] 验证本机内屏正常和延迟模式恢复后，将旧 innogpu helper 移入隔离目录。
- [ ] 检查适配器不存在、不可执行、超时和返回失败时不会破坏 X11 启动。

### 阶段 4：统一布局收敛

- [ ] 由同一规划器生成 desired/off 输出，所有非期望输出显式 `--off`。
- [x] 修正单屏捷径，关闭 `disconnected + geometry` 残留并重读验证；没有 connected 活屏时
  先按盖子策略激活并验证替代输出。
- [x] 独立比较基础 health 与拓扑，为 stale/pending 失败加入 3 次有界退避和低频恢复。
- [ ] 在 manual marker 实现后补齐期望 active、primary、geometry 和 framebuffer 的完整健康检查。
- [x] 解析 current/preferred 模式、刷新率、模式数量和完整能力签名；启动或能力签名变化后保留短时 settling
  探测，并让已激活但模式错误的输出在每个能力周期最多规范化一次。
- [x] 单屏、开盖扩展、合盖外屏和现有镜像回退均显式应用 preferred 或模式表首项目标，不再依赖
  `--auto`；这不等于已经实现最高共同镜像模式。
- [ ] 实现有盖子/无盖子设备的不同多屏回退，并保持合盖前先验证外屏。
- [ ] 让 `displayselect` 通过 `--manual-run` 写入手动所有权 marker，取消和失败路径不得写入。
- [x] 通过状态/锁 `11/11`、watcher 生命周期 `4/4`、显示回归 `11/11`，以及扩展坞拔出、接回、
  合盖、开盖和再次拔出的实机链路。
- [ ] 完成不同外屏预接冷启动、多个外屏、无盖桌面、设备适配器和手动 marker 的剩余矩阵。

### 阶段 5：受控 framebuffer 收缩

- [x] 已确认合盖关闭内屏时 innogpu/Xorg 会自动收缩 framebuffer；2026-07-16 A/B 同时确认该
  重建可能让外屏物理恢复慢于 RandR 逻辑收敛。
- [ ] 只有仍残留时才实现可诊断、可关闭的 `--fb <宽>x<高>` 路径。
- [ ] 调用前校验 RandR min/max、自动布局包围盒、非负坐标和 panning；不处理手动布局。
- [x] 自动布局最终仍把 framebuffer 收敛到有效输出包围盒；长期保留旧 framebuffer 不进入共享
  配置或设备适配器，只允许作为持有共享布局锁的临时 A/B 诊断。
- [ ] 单独实机验证并提交，不与状态解析或设备迁移合并。

本次 stale 输出使用普通 `--output ... --off` 后，Xorg 已自动把 framebuffer 收缩到有效输出
包围盒，因此当前缺陷不需要新增显式 `--fb` 路径；上述条件项只在以后仍观察到残留时恢复。

### 阶段 6：系统策略整理

- [ ] 将本机 `HandleLidSwitchExternalPower=ignore` 是否迁移为
  `/etc/systemd/logind.conf.d/60-xdisplay.conf` 作为独立系统变更审查。
- [ ] 使用 `systemd-analyze cat-config systemd/logind.conf` 验证合并结果；通过整机重启验证，
  不在图形会话中直接重启 logind。
- [ ] 明确开发指引中“接电合盖继续工作”是可选系统策略，不是通用引擎默认能力。

### 阶段 7：稳定验证与收尾

- [ ] 连续使用至少 14 天，并完成至少 3 次冷启动。
- [ ] 从隔离目录恢复并再次隔离一个无运行影响的文件，核对路径、所有者、mode 和校验和。
- [ ] 将已完成阶段移入 `history.md`，同步架构、依赖、用户指南和本机报告的最终行为。
- [ ] 满足挂起清理条件后再讨论删除整个隔离目录；删除前最后核对校验和和恢复必要性。

## 验证矩阵

每个涉及运行行为的阶段至少检查：

| 场景 | 必须观察的结果 |
| --- | --- |
| 开盖冷启动、无外屏 | 内屏 primary@`0x0`，没有 stale 输出 |
| 开盖热插外屏 | 内屏保持 primary，外屏向右扩展，DWM 无需重启 |
| 开盖热拔外屏 | 内屏恢复单屏，断开输出不再占用 geometry |
| 接电、外屏连接后合盖 | 外屏先变为有效 primary，再关闭内屏；会话不被 logind 挂起 |
| 接电、合盖后开盖 | 内屏快速恢复并成为 primary，外屏重新扩展 |
| 合盖冷启动且外屏枚举延迟 | 不先关闭最后一个安全活屏，外屏就绪后再收敛 |
| 外屏预接冷启动的不同模式集合 | 分别覆盖 EDID/preferred 正常、延迟和缺失；保存 Xorg 初始策略、实际模式和物理出光，不能用另一块外屏的成功替代 |
| 同一外屏在直连与扩展坞间切换 | 旧 connector 不再保留 geometry；只采用新路径实际暴露的模式和 preferred，不复用直连 EDID 能力 |
| 多个外屏 | 全部按确定顺序扩展；拔出任意一个后重新收敛 |
| `displayselect`/Arandr 手动布局 | 与 watcher 不并发；物理拓扑未变时不被立即覆盖 |
| 热插后 watcher 尚未收敛即手动布局 | 成功选择写入 manual marker，释放锁后旧自动计划不覆盖它 |
| 内屏无模式 | 适配器一次恢复有界，失败由 watcher 限频重试，不阻塞会话 |
| 适配器忽略 TERM 或输出非法名称 | kill-after 终止子进程并拒绝非法候选，watcher 保持可用 |
| 无适配器的标准笔记本 | 不修改任何设备变量即可完成自动布局 |
| 无盖子桌面设备 | 多输出扩展，不误用笔记本镜像回退 |
| lid 文件存在但状态不可读 | 按有盖设备安全降级，不误判为桌面设备 |
| 退出 X11 后重新登录同一 DISPLAY | 旧 watcher 有界退出，新 watcher 能立即取得会话锁 |
| 缺少依赖 | 缺少 `xrandr`/`flock` 时清楚报错，缺少可选适配器不影响登录 |

### 显示切换慢的 framebuffer A/B 诊断

只有布局最终正确、`health=ready`、无 stale/pending，且同一方向的肉眼黑屏恢复连续两次超过
5 秒时进入本分支。布局错误或软件收敛本身超过 3 秒，仍按 watcher/RandR 功能故障排查。

1. A 组先被动计时，不停止 watcher、不取锁、不执行 RandR 写命令。固定显示器、线缆、模式和
   切换方向，保存切换前后的 `xdisplay.sh --status`、`xrandr --current` 和盖子状态；用单调时钟
   记录物理事件 `T0`、期望 active/off 与 framebuffer 生效 `T1`、肉眼画面稳定 `T2`。
2. 若 `T1-T0` 不超过 2 秒而 `T2-T0` 超过 5 秒，才进入 B 组。若 `T1-T0` 超过 3 秒，先检查
   apply lock、退避、pending 和驱动 modeset，不用 framebuffer A/B 掩盖软件故障；介于 2 秒和
   3 秒之间时记为不确定并重复 A 组，不能直接归因。
3. B 组从 `--status` 动态取得 apply lock，从稳定快照动态取得输出、模式、位置和切换前 framebuffer；
   独占锁后执行相同目标布局，只额外保持切换前 framebuffer。不得硬编码输出名或分辨率，不得在
   锁内再次调用会取锁的 `xdisplay.sh --apply`，原 framebuffer 无法容纳目标包围盒时中止。
4. 启动 B 组前先保存 A 组的标准目标和恢复命令；诊断进程必须设置 30 秒总超时、TERM/INT/HUP
   trap 和有界 kill-after。完成测试后仍在持锁状态下恢复 A 组标准布局，确认至少一个输出可见且
   framebuffer 已收敛，再释放锁。恢复失败时先保留已验证活屏并释放锁，再让 watcher 或一次
   `xdisplay.sh --apply` 通过同一把锁重试；全黑时使用既有 TTY 回退，不继续试验。
5. 相同条件至少各做两次。A 超过 5 秒、B 不超过 2 秒且至少改善 3 秒时，可定位为 framebuffer
   尺寸变化触发驱动或输出链路重新同步；差值小于 1 秒不支持该结论，其余结果记为不确定并复测。

2026-07-16 本机在本流程固化前完成一次 B 组现场验证：通用收缩约 `1.07s` 完成逻辑布局但
肉眼超过 5 秒；保留 framebuffer 约 `0.65s` 完成且近乎瞬时出图。该结果是支持候选原因的初步
定位证据，不替代以后按本分支执行的重复性验证，也不改变继续采用通用 framebuffer 收敛的决定。

静态检查包括 `sh -n`、可用时执行 ShellCheck、文档链接与路径检查、凭据和个人信息扫描。
实机状态应同时记录 `xdisplay.sh --status`、`xrandr --current`、盖子状态和相关日志。

## 回退原则

1. 在仍可见的 X11 会话中停止新 watcher，恢复对应阶段提交的
   `.local/bin/xdisplay.sh`、`.local/bin/displayselect` 和 `.config/x11/xprofile`，再重新启动 watcher。
2. tracked 代码可从 `a191c3c` 恢复；阶段提交完成后优先回退最近的单阶段提交，避免覆盖其余配置。
3. home 和系统遗留项按隔离目录 `RESTORE.md` 逐项移回；恢复 udev 规则后 reload rules，恢复
   logind/Xorg 后通过整机重启验证。
4. 黑屏时使用 `Ctrl+Alt+F2` 进入 TTY，先恢复文件并停止 watcher，不在无可见输出时继续试验
   RandR 命令。
5. 隔离目录删除前不视为最终清理完成；发生问题时保留现场快照，不覆盖原校验和。

## 阶段 1 启动门槛（已满足）

阶段 1 开始前要求以下条件同时满足：本计划与设备适配器契约已确认；所有文档链接、术语、
当前/目标状态边界和实际路径复核通过；工作树没有混入无关文件；用户明确同意开始实施。
这些条件已在阶段 1 启动前满足。
