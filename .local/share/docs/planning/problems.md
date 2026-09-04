# 问题与排查记录（错题本）

> 服务域：S03 文档与治理 · 读者：Agent/维护者
> 用途：沉淀可跨设备复用的问题诊断过程。遇到同类问题时先查本文及其权威链接，再进行外部检索。
> 边界：本文只保存脱敏摘要和索引；审计、历史、平台档案与本机私有协作档案仍是各自事实的权威来源。

相关规则：[维护策略](../project/maintenance-policy.md)、[文档质量规范](../project/docs-standard.md)。

## 记录规则

每个活动问题固定包含 11 个字段：**状态、现象、复现条件、影响、证据/证据等级、排查过程、根因、
解决、验证与回滚、下一步、关联轮次/权威来源**。未知内容明确写“待确认”，不得省略，也不得把
合理假设写成根因。

状态只使用以下 6 个值：

| 状态 | 含义 |
| --- | --- |
| 观察 | 随相关问题收集线索，不单独投入排查 |
| 待查 | 问题已登记，尚未开始决定性取证 |
| 排查中 | 正在收集证据或收敛根因 |
| 待验证 | 已实施候选解决方案，等待验收 |
| 已解决 | 根因、解决、验证和回滚均已记录 |
| 无法复现 | 在明确条件和次数下未复现，保留重新打开条件 |

证据按以下 4 档标注；等级表达来源，不代替对证据内容的判断：

| 证据等级 | 使用范围 |
| --- | --- |
| 实测 | 可重复命令输出、日志、硬件动作结果或前后状态快照 |
| 源码/配置审查 | 与运行版本对齐的源码、有效配置或实现路径审查 |
| 合理假设 | 能解释现象但尚缺决定性实验的推断 |
| 用户回忆 | 用户观察或历史记忆，条件可能不完整 |

## 活动问题索引

实际推进顺序为 P1 → P2 → P3 → P4 → P5；P0 只作观察项。

| 编号 | 问题 | 状态 |
| --- | --- | --- |
| P0 | 历史“能正常挂起”的条件不明 | 观察 |
| P1 | 未插电合盖不挂起（已澄清为接电/外屏策略） | 已解决 |
| P2 | 不同 USB 设备条件下合盖后的网络/SSH 行为不一致 | 排查中 |
| P3 | 挂起唤醒后屏幕不亮 | 已解决 |
| P4 | s2idle 外屏红屏（间歇竞态） | 无法复现 |
| P5 | 冷启动合盖仅外屏：startx 后外屏瞬时黑屏/分辨率错误 | 待验证 |

## P1：未插电合盖不挂起（已澄清为接电/外屏策略）

- **状态**：已解决。
- **现象**：未插电、无外屏时长时间合盖仍未挂起，设备继续运行且电量明显下降；当次开机的累计
  挂起时长为 0。
- **复现条件**：电池供电、只连接内屏、合盖；USB 接收器是否插入必须作为独立变量记录。
- **影响**：用户误以为设备已睡眠时仍持续运行和耗电，并阻塞后续网络行为与唤醒显示问题的可靠复现。
- **证据/证据等级**：
  - **实测**：logind 收到 `Lid closed.`，但没有后续挂起请求；当时
    `LidClosed=true`、`Docked=false`、`OnExternalPower=true`，同时主电源节点报告 offline。
  - **实测**：接电采样中主电池状态为 `Not charging`；它不能证明拔电状态，仍需决定性对照。
  - **源码/配置审查**：有效配置包含 `HandleLidSwitchExternalPower=ignore`。与已安装版本一致的 Debian
    systemd source package 显示：`Battery` 不按 `online=1` 计为 AC，`scope=Device` 的设备
    电池被忽略；没有在线非电池电源且没有电池报告 `Discharging` 时，systemd 保守判为 AC。
  - **合理假设**：拔电后主电池状态可能仍不是 `Discharging`，触发上述 fallback。
- **排查过程**：R07 先确认当前合盖策略、无第二个睡眠动作所有者且系统从未实际挂起；R08 对齐
  Debian 精确源包，否定“HID 设备电池 `online=1` 被直接算作 AC”的早期假设，并把决定性取证改为
  同时采集主电源 online、主电池 status、全部 power_supply 和 login1 `OnExternalPower`。
  R08 阶段二（2026-09-02）：拔电+接收器在的快照为 `BAT0=Discharging`、`systemd-ac-power=no`、
  `OnExternalPower=false`——决策层电源判定正常；随后两次合盖实测（接收器在/拔）均在 4 分钟内
  无任何挂起请求、风扇不停、累计挂起 0。两次测试时未确认 DRM 输出与 `Docked` 属性，头号嫌疑为
  **外屏仍连接导致 `Docked=true` → `HandleLidSwitchDocked=ignore`**（新位置接有外屏）；待补
  「拔电 + 拔外屏 + Docked=false 确认」的第三次决定性测试。
  第三次测试（拔电 + 拔外屏 + 合盖 2 分钟）后开盖黑屏且系统无响应，只能强制重启——本次疑似
  发生了真实挂起（P1 决策层可能已通过），唤醒失败转入 P3 主线；待上一 boot journal 确认。
- **根因**：待确认。已确认的是 logind 当时选择了外部电源策略；该判定来自主电池遥测 fallback 仍是
  头号嫌疑，但尚缺拔电现场证据。
- **解决**：待确认。优先级依次为修正 AC/主电池遥测源、在用户接受行为变化时把外部电源合盖策略
  改为 suspend；本地 systemd 补丁仅作最后手段。不得实施没有源码作用点的 HID 电池 udev 排除规则。
- **验证与回滚**：验收必须同时看到主电源 offline、主电池 `Discharging`、
  `systemd-ac-power=no`、login1 `OnExternalPower=false`，以及 logind 请求、内核 suspend/resume 和累计
  挂起时长增加。当前尚未修改系统，无需回滚；后续修复必须记录原配置/内核并可精确恢复。
- **下一步**：无（已澄清）；残留问题转 P2/P3。
- **结论**：2026-09-02 实测「拔电+无外屏+合盖」deep 挂起事务正常进入与退出
  （`PM: suspend entry/exit`、systemd-suspend 正常结束），P1 决策层通过；唤醒后显示栈未恢复，见 P3。
  历史「合盖不睡」均为接电或外屏连接状态，属设计行为而非缺陷。
- **关联轮次/权威来源**：R07、R08 本机私有协作档案；与运行版本一致的 Debian systemd source
  package；[维护策略的睡眠动作所有权](../project/maintenance-policy.md#已接受的决定)。

## P2：不同 USB 设备条件下合盖后的网络/SSH 行为不一致

- **状态**：排查中。
- **现象**：用户观察到某一 USB 设备存在时合盖后 SSH 保持，移除后 SSH 断开，但两种条件下都没有
  已确认的实际挂起。
- **复现条件**：待确认。原始描述使用过“U 盘”和“接收器”，必须把无线接收器、USB 存储和无设备
  分成独立实验组；电源、外屏、网络接口和合盖时长保持一致。
- **影响**：SSH 断开可能被误判为已挂起；远程会话丢失也会中断故障现场取证。
- **证据/证据等级**：
  - **用户回忆**：有/无 USB 设备时 SSH 行为不同。
  - **实测**：设备电池节点是否出现会随无线接收器及其配对设备状态变化；接收器存在本身不保证该
    节点存在。
  - **源码/配置审查**：该设备电池不会因 `online=1` 被 systemd 直接视为 AC。
  - **合理假设**：SSH 断开可能来自真实挂起、失败挂起前的网络停用、物理链路变化或客户端超时；
    当前证据不能选择其中任何一个。
- **排查过程**：已将“USB 外设”拆为设备类别变量，并规定用 logind、systemd-suspend、内核 PM、
  NetworkManager 和 SSH 客户端时间线区分四类原因；尚无合盖瞬间的完整日志。
- **根因**：待确认。
- **解决**：待确认；在 P1 挂起决策稳定前不修改网络配置或 inhibitor。
- **验证与回滚**：每次只改变一种设备类别，记录前后电源/输出快照和有界日志。实验不修改网络配置，
  开盖后取回 `/tmp` 日志即可；若没有系统变更则无需回滚。
- **下一步**：P1 已澄清——真实挂起发生时 SSH 断属正常（睡眠期间网络关闭）；历史「有 USB 设备时
  SSH 保持」= 当时未挂起（接电/外屏状态）。残留低优先级复测：无接收器时「SSH 断但未挂起」的
  网络时序，待 P3 修复后顺带验证。
- **关联轮次/权威来源**：R07、R08 本机私有协作档案；P1 的 systemd 源码与配置证据。

## P3：挂起唤醒后屏幕不亮

- **状态**：已解决。
- **现象**：已确认在拔电、无外屏、合盖并完成 `deep` suspend/resume 事务后，开盖没有恢复可见画面，
  表现为黑屏且显示栈未恢复。
- **复现条件**：拔电 + 无外屏 + 合盖，`mem_sleep=deep`；必须先确认实际 suspend/resume 事务，再记录 USB 和锁屏条件。
- **影响**：本地 X11 会话不可见，且可能需要 TTY/SSH 恢复；盲目显示恢复命令会破坏故障现场。
- **证据/证据等级**：
  - **实测**：2026-09-02 在拔电、拔外屏、合盖条件下完成约 5.5 分钟的 `deep` suspend/resume；
    开盖后黑屏，SSH/TTY/盲输均无响应。journal 显示 `PM: suspend exit` 与 systemd-suspend 均正常完成，
    但 resume 瞬间出现 `PVR_K:(Error): PVRSRVEPowerLock() failed
    (PVRSRV_ERROR_SYSTEM_STATE_POWERED_OFF) in PVRSRVDevicePreClockSpeedChange()`；随后 logind
    仍能响应电源键，故障局限于 GPU/显示栈（fbcon 亦黑）。
  - **源码/配置审查**：与运行版本对齐的 innogpu 侧源码将失败定位在设备仍为 `POWERED_OFF` 时执行
    时钟切换（`PVRSRVDevicePreClockSpeedChange`）；其余 watcher、DPMS、RandR 和 locker 候选已排除，
    不再作为本问题根因候选。
  - **合理假设（第三方声明）**：innogpu 项目报告其交付包 `4.0.2-i3` 在 2026-09-03 完成
    6/6 次 `deep` 矩阵并通过；判据为每次均有成对的 `PM: suspend entry/exit`，唤醒窗口无
    `PVR_K 3900372`、PowerLock/`POWERED_OFF` 错误，且内外屏、键盘、鼠标和 TTY 均恢复。
    这是第三方项目的实测声明，本仓库不将其过程当作本机实测。
  - **实测（本机部分核实）**：已安装包为 `innogpu-fh2m-trixie 4.0.2-i3`；本机可取得的交付
    `.deb` SHA-256 为
    `177133eebda692092501a27d7d135662ddaedaf3634776b8aa1ea5153c9e1662`，与回传一致；
    `/sys/power/mem_sleep` 为 `s2idle [deep]`，`innogpu` 模块已加载，内屏连接且 HDMI 输出未连接。
    当前环境没有 `modinfo` 命令，模块 `.modinfo` 也没有 `version/srcversion` 字段；普通用户无权读取
    本次启动的完整内核 journal，因此模块版本字段和最近 resume 的无错误结论均不可由本机独立核实。
  - **用户回忆**：用户 2026-09-03 完成本侧 `deep` 合盖实测，4 种组合（拔电/接电 × 外屏/无外屏）全部
    确认通过；各组合的判据产物（`PM` entry/exit、`PVR_K` 计数、画面/输入/TTY 恢复记录）与日志未入档，
    补交后可升为「实测」。
- **排查过程**：R07 完成静态审查与现场取证设计；R08 按该方案复核电源、外屏和挂起链路，并于
  2026-09-02 实测拔电、拔外屏、合盖，`deep` suspend 约 5.5 分钟后唤醒黑屏，SSH/TTY/盲输均无响应，
  但电源键仍可触发干净关机。journal 显示 `PM: suspend entry/exit` 成对、systemd-suspend 正常结束，
  并记录 `PVR_K 3900372`；据此将故障层收敛到 GPU/显示栈。R09 重启后本侧只读复核确认
  `4.0.2-i3` 已安装、SHA 一致、`mem_sleep=s2idle [deep]` 已激活且模块已加载；`modinfo` 与完整
  journal 属不可核实项，已如实标注。
- **根因**：已确认——innogpu（PowerVR）驱动 resume 缺陷：设备电源状态仍为 POWERED_OFF 时执行
  时钟切换导致锁失败，显示栈（DRM/fbcon）未能恢复；与 xdisplay/locker 无关。依据为本机 journal
  实测及 innogpu 侧源码定位（`PVRSRVDevicePreClockSpeedChange`、`PVR_K 3900372`）。
- **解决**：规避已不再需要（用户本侧验收通过，2026-09-03）；如未来复发可临时切换为 `s2idle`。
  根治为 innogpu `4.0.2-i3`（本侧用户验收通过 + innogpu 侧 6/6 `deep` 矩阵通过）。交付 SHA-256
  为 `177133eebda692092501a27d7d135662ddaedaf3634776b8aa1ea5153c9e1662`。诚实边界：缺少厂商
  `hwinfo_g0m.bin` 时亮度调节不可用但点亮正常；红屏候选修复未包含且仍未验证；对方项目未正式发布
  （无 tag/Release），交付形式为本地 deb + 文档，发布许可门禁仍未开放；换用新设备必须重新执行图形
  基线和至少一次受控挂起验收。dotfiles 侧无可修项。
- **验证与回滚**：用户于 2026-09-03 完成本侧 `deep` 合盖实测并确认通过；证据链为 innogpu 侧
  6/6 矩阵、本侧只读复核（4.0.2-i3 已安装、SHA 一致、`mem_sleep=s2idle [deep]` 已激活、模块已加载）
  以及既有本机 journal 根因证据。若问题复发，可临时切换为 `s2idle` 并回传证据；当前无需回滚。
- **下一步**：无（已解决）。
- **关联轮次/权威来源**：R07、R08 本机私有协作档案；[显示管理设计](../project/display-management.md)、
  [平台档案索引](../platforms/index.md)。

## P4：s2idle 外屏红屏（间歇竞态）

- **状态**：无法复现。
- **现象**：使用 `s2idle` 挂起并连接外屏时，曾出现间歇性红屏；具体外屏型号、触发时机和显示状态以
  受控实验记录为准，不能将未复现的现象写成稳定回归。
- **复现条件**：外屏连接、`mem_sleep=s2idle`，并记录合盖/唤醒时机；`cursor_enable=0` 分支不纳入该组。
- **影响**：唤醒后外屏可能显示错误颜色，影响图形会话可用性与 P3 验证判断。
- **证据/证据等级**：**用户回忆**；innogpu 项目侧三次未复现尝试属于**合理假设（第三方声明）**，
  本仓库无法独立复核其过程；当前无可重复日志或截图证据。红屏候选修复不包含在 `4.0.2-i3` 中。
- **排查过程**：innogpu 项目侧三次尝试（编号属该项目，待确认）按外屏连接与 s2idle 组合进行，均未复现；
  后续应保留外屏型号、connector 状态、唤醒时序和内核日志的同一份快照。
- **根因**：待确认；候选为 innogpu 侧候选修复（编号见私有档案）涉及的 resume 竞态，不能据此提前定案。
- **解决**：暂无；不修改 dotfiles 显示逻辑，不以三次未复现替代根因修复。
- **验证与回滚**：重新出现时保留现场日志和截图，先记录再恢复；若实施候选修复，必须以相同外屏与
  时序重复验证，并可回退到修复前版本。
- **下一步**：保持无法复现；4.0.2-i3 已通过 P3 本侧验收，但不包含红屏候选修复，重开条件仍未满足；
  满足相同条件再次出现或 innogpu 侧红屏候选修复有可验证变更时重新打开。
- **关联轮次/权威来源**：innogpu 项目侧三次尝试（编号属该项目，待确认）；本仓库 R08/R09 仅作转交
  和复核索引；innogpu 侧候选修复（编号见私有档案）交付记录（待验证）。

## P5：冷启动合盖仅外屏：startx 后外屏瞬时黑屏/分辨率错误

- **状态**：待验证。
- **现象**：冷启动时合上笔记本盖、仅连接外部显示器，登录界面外屏正常；输入密码执行
  `startx` 后，外屏短暂正常，随后黑屏，等待 watcher 轮询后可能恢复。另一种表现是轮询恢复后
  分辨率明显过大，必须开盖再合盖触发重新布局才恢复正常。
- **复现条件**：冷启动或重新登录 X11；lid=closed；外部输出已连接且内屏不参与有效布局；通过
  `startx` 进入 X 会话。必须分别记录外屏型号/connector、启动前后 `xrandr` 状态、是否存在
  自定义布局和适配器开关，不能把显示管理器登录阶段与 startx 阶段混为一次实验。
- **影响**：X 会话初始阶段出现可见黑屏或错误分辨率，用户需要等待轮询或物理开合盖才能恢复；
  首轮 modeset 还可能使现场日志和后续判断失去原始状态。
- **证据/证据等级**：
  - **用户回忆**：登录界面外屏正常，`startx` 后出现“正常一瞬→黑屏→轮询恢复”或“恢复但分辨率过大”；
    开盖再合盖可以触发恢复。
  - **源码/配置审查**：R11 确认首轮必然使用 `--query`；R12 在
    `.local/lib/xdisplay/lib-engine.sh:201-223` 落地 A′：保存最近一次 `--query` 的权威能力快照，
    `--current` 连接投影未变时沿用该快照，投影变化时挂起 apply 并强制下一 tick probe。
    `.local/lib/xdisplay/lib-topology.sh:20-36` 将能力签名、连接投影和完整拓扑签名分开计算。
  - **源码/配置审查**：`.local/lib/xdisplay/lib-snapshot.sh:165-184` 仅以“connected 且有首个模式”
    判定 mode_ready，目标模式按 preferred、否则 first mode 选择；适配器有效 expected mode 由
    `.local/lib/xdisplay/lib-adapter-query.sh:124-184` 覆盖目标。preferred 标记或完整模式表迟到时，
    first mode 可能不是用户期望值。
  - **源码/配置审查**：`.local/lib/xdisplay/lib-layout-configure.sh:58-149`（legacy/extend-chain）
    和 `.local/lib/xdisplay/lib-layout.sh:95-136` 会设置外屏 primary、目标模式、位置，并在合盖路径
    对内屏执行 `--off`；这些是潜在的 Xorg/驱动 modeset 黑屏窗口。xdisplay 库没有 DPMS、背光或物理
    出图调用，当前 health 只反映 RandR 的 stale/pending/no-connected-output。
  - **源码/配置审查**：`.local/lib/xdisplay/lib-topology.sh:20-36` 的拓扑键包含连接、首项模式和
    mode_signature，但不包含当前几何/当前模式；R12 在 `.local/lib/xdisplay/lib-engine.sh:245-294`
    增加 preferred-ready + N=2 + 10 tick 首轮门禁，并在 apply 成功后使用归一 key。apply 期间连接
    投影变化时保留新观测、安排强制 probe，使下一 tick 重新规划；现有布局后重读验证未改变。
  - **实测**：`.local/share/test/display/xdisplay-adapter.sh` 的 G-01 至 G-06 使用现有 RandR 状态机
    fixture 复现异源 key 分歧并验证 A′；覆盖 tick 2 正常放行、preferred 延迟、tick 10 超时回退、
    20 tick 无重复 apply 和 apply 期间热插拔重规划。完整显示 fixture 为 42/42 通过。
- **排查过程**：R11 沿 `xinitrc → xprofile → xdisplay watch` 启动链静态审查；R12 先用异源 fixture
  复现 `--query`/`--current` raw key 分歧，再按 A′ 统一 watcher 的权威能力源，随后加入首轮门禁并以
  G-01 至 G-06 覆盖正常、延迟、超时、重复 apply 与热插拔路径。尚未执行真实冷启动验证。
- **根因**：待确认。当前最强解释是 X 启动后首轮快照尚未稳定即触发合盖外屏布局写入，且模式能力/当前
  模式变化未必进入重规划键；黑屏的具体责任边界仍需区分 RandR modeset、Xorg/innogpu 驱动和外屏
  链路训练。不能仅凭源码审查把任一项定为已确认根因。
- **解决**：R12 实现提交 `17cdea7` 已实施候选 ④①。④ 按 A′ 以最近一次 `--query` 为权威能力快照，
  用 `--current` 连接投影作为热插拔安全网；① 要求外屏 preferred 就绪且归一 key 连续 N=2，最迟
  第 10 tick 回退。该组合直击情况 2，并覆盖情况 1 的写入侧分支 1b；首轮 `--query` 探测侧分支 1a
  未修改，若黑屏仍存在则留待 D5 后续轮次。
- **验证与回滚**：显示 fixture 42/42 通过，其中 G-01 至 G-06 覆盖本轮机制；协作 Bats 35/35 通过。
  真实冷启动结果待用户日常验证。实现可回退 `17cdea7`，恢复 R12 基线 `8165170` 的 watcher
  行为；回退后重跑显示 fixture 并确认基线计数与文档一致。
- **下一步**：用户日常验证同一外屏下的冷启动、合盖、仅外屏、`startx` 场景，分别记录
  （1）是否仍出现瞬时黑屏及起止时间；（2）最终分辨率是否仍过大、是否仍需开盖再合盖。
  若分辨率正确但黑屏仍在，优先按 R11 取证设计核查首轮 `--query` 与 modeset 的重叠，再决定是否
  另轮实施 D5；两类现象都消失后再将 P5 推进为已解决。
- **关联轮次/权威来源**：R11 研究、R12 实施的本机私有协作档案；[显示管理设计](../project/display-management.md)、
  [显示管理测试](../project/display-testing.md)；本条为 dotfiles 侧研究记录，innogpu 驱动事实仍以
  innogpu 项目文档为准。

## P0：历史“能正常挂起”的条件不明

- **状态**：观察。
- **现象**：用户记忆中本设备历史上曾正常挂起/唤醒，当前无法复原当时条件。
- **复现条件**：待确认；可能涉及当时的电源、外屏、USB 设备、内核或配置组合。
- **影响**：若直接把历史记忆当作当前基线，可能错误归因 P1/P3；作为旁证则可能帮助识别回归点。
- **证据/证据等级**：**用户回忆**；历史日志可能已滚动，暂无同级实测或版本记录。
- **排查过程**：不建立独立调查线，只在 P1/P2 过程中记录能解释历史行为的新证据。
- **根因**：待确认。
- **解决**：不适用；它是观察项，不是独立修复对象。
- **验证与回滚**：若出现版本、配置或设备组合证据，必须能与 P1/P2 现象交叉验证；没有系统修改，
  无需回滚。
- **下一步**：随 P1/P2 更新；没有新证据时保持“观察”。
- **关联轮次/权威来源**：R07、R08 本机私有协作档案。

## 历史问题归档

历史项只保留可复用的“问题 → 判断 → 最终结论 → 权威来源”，不复制过程原文。功能开发、普通重构
和已接受约束不因出现在 history 或 collab 中就自动成为错题。

| 编号 | 问题 | 结论/处置 | 权威来源 |
| --- | --- | --- | --- |
| A1 | SSH 客户端拒绝读取系统配置并报告 owner/permissions 错误 | 容器的单 UID 映射造成所有权视图差异，宿主配置正常；容器内按次绕过，宿主不修 | R04 本机私有协作档案 |
| A2 | 设备适配器本地配置缺少精确 Git ignore 规则 | 已增加精确规则和机械门禁 | R03 本机私有协作档案 D4 |
| A3 | 安装系统缺陷 B1–B8 | 已全部修复并保留历史方案与验证 | [安装系统修复记录](installation-fixes.md) |
| A4 | 2026-07-31 的 112 项审计发现；2026-08-04 的 64 项修改计划 | 前者均已裁决/关闭，包含确认缺陷、设计判断和误报；后者全部完成 | [2026-07-31 审计](../audits/2026-07-31-full-review.md) · [2026-08-04 审计](../audits/2026-08-04-full-review.md) |
| A5 | 断开的显示输出残留 geometry 并扩大 framebuffer | 共享显示引擎已加入 stale 清理、重读验证和 framebuffer 收敛，实机链路已验证 | [显示管理设计](../project/display-management.md) · [平台档案](../platforms/kaitian-x7h-g1e-debian-13.md) |

## 排查工具速查（只读）

```sh
# logind 决策三要素
busctl get-property org.freedesktop.login1 \
  /org/freedesktop/login1 \
  org.freedesktop.login1.Manager \
  LidClosed Docked OnExternalPower

# systemd 对当前电源的判定
systemd-ac-power --verbose

# 电源设备完整快照
for d in /sys/class/power_supply/*; do
    [ -r "$d/type" ] || continue
    printf '%s type=%s' "${d##*/}" "$(cat "$d/type")"
    [ -r "$d/online" ] && printf ' online=%s' "$(cat "$d/online")"
    [ -r "$d/status" ] && printf ' status=%s' "$(cat "$d/status")"
    [ -r "$d/scope" ] && printf ' scope=%s' "$(cat "$d/scope")"
    printf '\n'
done

# DRM connector 状态
for f in /sys/class/drm/card*-*/status; do
    [ -r "$f" ] && printf '%s=%s\n' "${f%/status}" "$(cat "$f")"
done

# 从本次开机 wall time 与 uptime 的差值估算累计挂起时长
python3 -c "import time; w=time.time(); u=float(open('/proc/uptime').read().split()[0]); b=int([x for x in open('/proc/stat') if x.startswith('btime')][0].split()[1]); print(f'{w-b-u:.0f}s')"
```
