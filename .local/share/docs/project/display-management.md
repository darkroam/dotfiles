# X11 显示管理设计

## 目的与边界

本文面向维护者，说明共享 X11 显示引擎的所有权、状态模型、布局策略、诊断和扩展边界。
具体设备的输出名、驱动、系统服务、模式、实测结果和恢复路径不在本文维护；从
[平台档案索引](../platforms/index.md)进入对应记录。用户操作见
[桌面使用指南](../user/desktop-guide-zh.md)，非标准硬件扩展见
[设备适配器指引](display-device-adapter.md)。

## 当前实现与目标状态

当前共享实现已经具备：单份 RandR 快照解析、`--status`/`--apply`/`--watch`、按 X server
隔离的运行目录和锁、watcher generation、stale/pending 基础 health、current/preferred/target
模式、模式能力签名、短时 settling、有界失败退避，以及关闭 `disconnected + geometry` 输出后的
重读验证。单屏、开盖扩展、合盖外屏和现有镜像回退均显式使用 target 模式，不依赖 `--auto`。

以下仍是目标状态，不得按已实现行为描述：由一个规划器生成完整 `desired_outputs`/`off_outputs`、
最高共同模式镜像、有盖/无盖设备的不同多屏回退、设备适配器运行接口、`--manual-run` 与有效
manual marker、完整自动布局 health，以及可选的显式 `--fb` 收敛路径。本文在相应章节分别标明
当前边界和目标约束。

## 所有权与运行链

共享显示管理只允许两类 RandR 写入口：

```text
X11 会话 -> xprofile -> xdisplay.sh --watch -> 自动布局
Mod+F3 ----------------> displayselect ---------> 手动布局
                                      \----------> Arandr（可选）
```

`xdisplay.sh --watch` 由 X11 会话启动，以继承正确的 `DISPLAY`、`XAUTHORITY` 和用户 D-Bus
环境。不得同时启用 udev 直接 `xrandr`、第二个 watcher 或缺少图形会话环境的服务。目标平台
若必须使用系统服务修复驱动/设备节点，该服务只能准备 Xorg 前置条件，不能取得布局所有权。

自动与手动入口共用 `apply.lock`；每个规范化 X server 只有一个 `watch.lock`。锁前缀包含 UID
和 X server，`:0` 与 `:0.0` 共享锁，不同 X server 互不干扰。旧 watcher 必须有界退出，新
watcher 必须有界等待，不得永久阻塞登录。

锁、generation 和 marker 优先放在有效的 `XDG_RUNTIME_DIR`。该目录必须存在、可写可搜索、
不是符号链接、归当前 UID 所有且权限严格为 `0700`。无法使用时，只接受绝对 `TMPDIR`，否则
回退 `/tmp`，并在其下创建归当前 UID 所有、非符号链接且权限为 `0700` 的私有目录；任一所有权
或权限检查失败都必须拒绝运行，不能退回共享可写的固定锁文件。

当前 watcher 为 `HUP`、`INT`、`TERM` 和正常退出设置清理，只删除与本代 generation 匹配的
运行状态。连续 6 次 RandR 快照失败时把 X server 视为已经消失并退出；单次探测失败只进入重试，
不能中断会话。新 watcher 最多等待 watch lock 8 秒，该窗口长于旧 watcher 的连续失败退出时间，
避免重新登录同一 `DISPLAY` 时因旧进程尚在清理而丢失 watcher。

## 状态模型

每轮从一份 RandR 原始快照解析固定状态，不能在同一轮混用多次读取结果。screen 状态保留
minimum/current/maximum framebuffer；全局盖子状态和每个 `connected` 或 `disconnected` 输出
至少记录：

| 字段 | 定义与用途 |
| --- | --- |
| `lid_present` | 是否存在 lid 状态接口，不以本轮读取成功为前提；用于区分无盖设备和暂时读取失败 |
| `lid_state` | 有 lid 时为 `open`、`closed` 或 `unknown`；没有 lid 时为 `absent` |
| `connection`、`primary` | RandR 的连接和主屏事实 |
| `geometry`、宽高、x/y | CRTC 占用的区域；必须支持负坐标 |
| `active` | 存在 geometry，不要求输出仍为 `connected` |
| `mode_ready` | 已连接且至少有一个可用模式 |
| `stale` | 已断开但仍有 geometry，必须进入待关闭集合 |
| `pending` | 已连接、未激活且模式尚未就绪，必须保留安全活屏并重试 |
| `current_mode/current_rate` | 带 current `*` 的实际模式与刷新率 |
| `preferred_mode/preferred_rate` | 首个带 preferred `+` 的模式与刷新率 |
| `target_mode/target_rate` | preferred，缺失时回退到模式表首项及其首个刷新率 |
| `mode_count/mode_signature` | 全部模式、刷新率和 preferred 标记组成的能力摘要 |

模式能力签名保留模式、刷新率和 preferred `+`，忽略 current `*`，因此驱动稍后补充模式或更改
preferred 会触发重新规划，而一次正常 modeset 不会制造签名循环。物理拓扑签名包含 lid 是否存在
及其状态，以及每个输出的连接状态、首个模式和完整模式能力签名；不包含 current `*`、primary、
坐标或缩放。拓扑签名能发现连接与能力变化，但不能单独证明布局已经收敛，也不能保护手动布局。

基础 health 与拓扑独立，只报告 stale、pending、无连接输出或 ready。完整自动布局 health 还应
验证期望输出的 active/off、primary、geometry、target 模式和 framebuffer；它必须与 manual
marker 同步实现，否则可能把合法的手动负坐标、缩放或排列误判为故障。

`xdisplay.sh --status` 只读取并解释状态，不执行恢复或布局。输出应包含 lid、各输出模式与几何、
stale/pending、策略、锁、watcher generation、manual marker 和当前设备注入，便于保存可复现
诊断。

`XDISPLAY_TEST_MODE=1` 只允许测试通过绝对 `XDISPLAY_TEST_ROOT` 把 `/proc` 和 `/sys` 观测根
指向 fixture；正常模式始终使用真实系统路径。测试模式不得改写默认观测根，也不得绕过 RandR
状态解析、锁或输出校验。

## 内屏与盖子识别

通用内屏候选来自标准 RandR 前缀 `eDP-*`、`LVDS-*`、`DSI-*`。标准候选不足时，当前兼容接口
允许 `XDISPLAY_INTERNAL_OUTPUTS` 补充候选；模式异常时可通过
`XDISPLAY_RESTORE_COMMAND` 调用一次有界恢复。二者只能描述内屏身份/模式恢复，不能决定布局。

目标接口是单个未跟踪设备适配器 `.config/x11/xdisplay-device.local`。适配器必须受 timeout 和
kill-after 限制，输出经过当前 RandR 快照校验；迁移完成前不能把目标接口写成已生效行为。

盖子状态从可用系统接口读取。没有 lid 接口的设备按桌面设备处理；接口存在但不可读时按有盖
设备安全降级，不能因为读取失败关闭最后一个可见输出。合盖是否挂起由平台电源策略决定，显示
引擎不得自动改写 logind 或其他电源管理配置。

## 通用布局策略

目标状态要求每次规划同时生成完整 `desired_outputs` 和 `off_outputs`，后者是所有已知输出减去
期望输出，并包含 `disconnected + geometry` 的 stale 输出。两组动作必须由同一规划器产生，串行
应用并重读验证；不能只配置期望输出后提前返回。当前实现已经有独立 stale 清理和各布局分支，
但尚未完成统一 desired/off 规划器，因此不能宣称所有非期望输出都由同一计划显式关闭。

| 场景 | 目标行为 | 安全条件 |
| --- | --- | --- |
| 只有一个可用输出 | 设为 primary、定位 `0x0`，其他已知输出进入 off 集合 | 合盖且只剩内屏时不强制重新 modeset，但仍清理 stale |
| 开盖或 lid 状态未知且识别内屏 | 内屏为 primary，外屏按稳定顺序向右扩展 | 内屏无模式时只做一次有界恢复，再由 watcher 重试 |
| 合盖且外屏可用 | 先激活外屏并设为 primary，再关闭内屏 | 外屏验证 active 前不得关闭最后一个安全活屏 |
| 合盖且外屏尚未就绪 | 保留当前安全活屏并标记 pending | 不提交成功状态，只做有限频率主动探测 |
| 有盖但无法识别内屏，多输出 | 选择最高共同模式后镜像 | 未找到共同模式时保留一个已验证活屏，不提交部分布局 |
| 无 lid 设备，多输出 | 选择已有 primary 或首个输出并稳定向右扩展 | 不因缺少“内屏”概念退化为笔记本镜像回退 |
| 没有 connected 活屏 | 不执行破坏性布局 | 优先激活并验证安全候选，失败后保留旧状态等待重试 |

当前尚未实现“最高共同模式镜像”和有 lid/无 lid 的独立多屏回退；表中相应行是验收目标。
扩展前还必须计算计划包围盒并与 RandR maximum framebuffer 比较。超限时采用已验证的安全镜像
或只保留一个安全活屏，不得执行会留下半完成布局的命令序列。

目标模式优先使用 preferred；没有 preferred 时使用模式表首项及其首个刷新率。不得从 EDID
猜测驱动未暴露的模式，不得复用另一 connector 的能力，也不得把 `--auto` 当作确定策略。
镜像只有在所有输出的模式和缩放都已确定时才执行；RandR 没有事务回滚，失败路径必须重读实际
状态并继续有界恢复。

自动布局最终把 framebuffer 收敛到有效输出包围盒。长期保留旧 framebuffer 会产生不可见区域、
鼠标越界和整屏截图尺寸错误，不能作为通用性能优化。

## 事件、能力迟到与退避

盖子和 DRM sysfs 状态每 0.5 秒读取；RandR 稳定时约每 1 秒读取一次 `--current`。盖子、connector、
拓扑或 health 变化后进入约 5 秒快速窗口，布局成功也不提前结束；窗口内约每 1 秒执行一次
`--query`，捕捉扩展坞或驱动晚于连接事件提供的模式、刷新率和 preferred。稳定期保留约 60 秒的
主动 `--query` 兜底，其余观测使用 `--current`，避免持续 EDID 探测给驱动施压。

相同拓扑与基础 health 下的失败布局最多连续写入 3 次，间隔约 5 秒；达到上限后只在低频主动
探测时恢复尝试。lid、连接、首个模式、完整 mode signature 或 health 变化会形成新状态并重置退避。
模式能力变化即使 connector 仍为 connected 也必须触发重新规划；不能只比较输出数量或连接位。

布局成功不应仅依据命令退出码。至少重读并验证 active/off、primary、geometry、target 模式、
扩展/镜像关系、stale-free 状态和 framebuffer。新一代 watcher 只清理自己可证明过期的 marker，
不能继承无法验证的手动所有权。

## 手动布局与 DWM

`displayselect` 取得同一 `apply.lock`，支持单屏、扩展、镜像和可选 Arandr。内置布局成功后可刷新
壁纸、键盘映射和通知；Arandr 分支只负责释放锁，不得假定用户保存了某种布局。

共享锁只能防止并发写，不能阻止 watcher 在手动命令释放锁后继续应用较早的自动计划。目标接口
因此增加 `xdisplay.sh --manual-run`：`displayselect` 的外部入口立即委托它，由引擎取得 apply lock，
再调用 `displayselect --unlocked` 的内部 UI，避免递归和双重加锁。只有确认布局实际变化且命令成功
时，才在仍持锁的状态下写入绑定当前物理拓扑和 watcher generation 的 manual marker；dmenu
取消、命令失败或 Arandr 前后布局相同都不得写 marker。

每个 watcher 启动时生成新 generation，并清理无法证明属于当前 X 会话的旧 marker。marker 有效时，
自动路径只观察物理拓扑并确认至少一个活屏，不覆盖 primary、geometry、缩放、合法负坐标或
framebuffer；输出连接、首个模式、mode signature 或 lid 状态变化后 marker 立即失效，恢复自动
收敛。旧自动计划在释放锁后不得覆盖较新的手动结果。

当前实现只有 generation、marker 路径和 `--status` 报告，尚未提供 `--manual-run`，也不会写有效
marker；现有 `displayselect` 串行行为不能等同于完整的手动所有权保护。

DWM 在根窗口尺寸变化时通过 ConfigureNotify/Xinerama 重新读取几何、更新状态栏并排列窗口。
正常 RandR 布局变化不需要重启 DWM。

## 依赖与缺失行为

自动 watcher 的基础能力是 `xrandr` 和 `flock`；手动入口还使用 `dmenu`，镜像缩放使用 `bc`，
Arandr 是可选界面。缺少基础依赖时必须明确拒绝运行；缺少可选界面、通知或壁纸工具时只影响
相应分支，不能阻塞 X11 登录。

发行版软件包映射和设备安装状态见[平台档案索引](../platforms/index.md)。

## 验证矩阵

修改共享显示逻辑后至少检查：

| 场景 | 验收结果 |
| --- | --- |
| 开盖冷启动、无外屏 | 内屏 primary@`0x0`，没有 stale 输出 |
| 登录前/后接入外屏 | 输出自动扩展，模式迟到后仍能收敛 |
| 热拔任一外屏 | 断开输出不再占用 geometry，framebuffer 收敛 |
| 同一外屏切换 connector 或扩展坞 | 关闭旧 connector，只采用新路径实际暴露的模式和 preferred |
| 合盖且外屏就绪 | 外屏先成为安全活屏，再关闭内屏 |
| 合盖冷启动且外屏延迟 | 不关闭最后一个安全输出，能力就绪后重试 |
| 再次开盖 | 内屏恢复为 primary，其余输出重新扩展 |
| 多外屏 | 稳定排序；拔出任一输出后重新规划 |
| 手动布局与热插竞争 | 共享锁串行，旧自动计划不覆盖新手动结果 |
| 手动布局后拓扑未变 | marker 保留手动 primary、位置、缩放和负坐标 |
| 无适配器的标准笔记本 | 零配置完成启动、开合盖和插拔 |
| 适配器缺失/失败/超时 | 会话可用并降级到标准探测 |
| 适配器忽略 TERM 或返回非法输出 | kill-after 终止进程并拒绝候选，watcher 继续运行 |
| 内屏连接但没有模式 | 单次恢复有界，失败由 watcher 限频重试 |
| 无盖桌面设备 | 不误用 lid 策略，多屏仍可扩展 |
| lid 存在但不可读 | 安全降级，不关闭最后一个活屏 |
| 计划包围盒超过 RandR maximum | 不提交部分扩展，保留安全活屏或采用已验证镜像 |
| 退出并重新登录 X11 | 旧 watcher 有界退出，新 watcher 取得锁 |
| 缺少依赖 | 基础依赖明确报错，可选依赖只禁用相应功能 |

静态 fixture 应覆盖单屏、扩展、镜像、负坐标、stale、pending、模式迟到、preferred/刷新率变化、
锁竞争和 watcher 换代。实机验证必须保存不含个人信息的 `--status`、`xrandr --current`、盖子
状态和必要日志；单块外屏成功不能替代其他 connector/扩展坞分支。

## 显式 framebuffer 边界

共享目标仍是让 framebuffer 与自动布局的有效输出包围盒一致。普通 `--output ... --off` 能让
Xorg 自行收敛时，不得增加显式 `--fb`。只有统一 desired/off 规划已经完成、布局重读验证无误，
但 framebuffer 仍持续残留时，才可以设计可诊断、可关闭的 `--fb <宽>x<高>` 路径。

调用前必须同时校验 RandR minimum/maximum、自动布局包围盒、所有输出坐标非负且没有 panning；
目标尺寸必须容纳完整包围盒并处于 RandR 范围内。该路径只处理自动布局，不得改写 manual marker
保护的手动负坐标、缩放或排列。校验或应用失败时保留至少一个已验证活屏，不提交部分成功状态，
并让 watcher 通过同一布局锁有界重试。实现、fixture 和实机会话验证必须作为独立变更完成。

## framebuffer 延迟诊断

只有布局已经正确、health ready、无 stale/pending，且同一方向的肉眼黑屏连续两次超过 5 秒，
才进入 framebuffer A/B；布局错误或软件收敛超过 3 秒仍按 watcher/RandR 故障处理。

1. A 组只被动计时：不停止 watcher、不取锁、不执行额外 RandR 写入。固定显示器、线缆、模式和
   切换方向，保存切换前后的 `xdisplay.sh --status`、`xrandr --current` 和 lid 状态；使用单调时钟
   记录物理事件 `T0`、期望 active/off 与 framebuffer 生效 `T1`、肉眼稳定 `T2`。
2. 仅当 `T1-T0 <= 2s` 且 `T2-T0 > 5s` 时做 B 组；2 至 3 秒之间重复 A 组，超过 3 秒先查锁、
   退避、pending 和 modeset，不用 framebuffer A/B 掩盖软件故障。
3. B 组从稳定快照动态取得输出、模式、位置、标准目标、恢复命令和切换前 framebuffer；独占
   apply lock 后执行相同目标布局，只改变是否暂时保留旧 framebuffer。不得硬编码输出名或
   分辨率，不得在锁内再次调用会取锁的 `xdisplay.sh --apply`；旧 framebuffer 无法容纳目标包围盒
   时立即中止。
4. 诊断进程必须设置 30 秒总超时、`TERM`/`INT`/`HUP` trap 和有界 kill-after。测试完成后仍在
   持锁状态恢复标准布局，确认至少一个输出可见且 framebuffer 已收敛，再释放锁。恢复失败时先
   保留已验证活屏并释放锁，再让 watcher 或一次 `--apply` 通过同一把锁重试；全黑时转入 TTY
   回退，不继续试验。
5. 同条件至少各做两次。只有 A 持续超过 5 秒、B 不超过 2 秒且改善至少 3 秒，才支持 framebuffer
   重建触发驱动/链路重同步的判断；差值小于 1 秒不支持该结论，其余结果记为不确定并复测。

A/B 只是定位方法，不能把旧 framebuffer 规避写入共享引擎或设备适配器。平台实测数据只写入
对应档案。

## 通用回退顺序

1. 仍有可见输出时，先保存 `xdisplay.sh --status`、`xrandr --current` 和必要错误日志，不用新的
   RandR 写入覆盖现场。
2. 停止本次变更新启动的 watcher，确认没有第二条自动布局链；不要同时运行新旧 watcher、udev
   helper 或图形会话外的布局服务。
3. 优先回退最近一个可独立验证的提交，只恢复该阶段改动的 `.local/bin/xdisplay.sh`、
   `.local/bin/displayselect`、`.config/x11/xprofile` 或设备适配接口，避免覆盖无关配置。适配器导致
   故障时先将其禁用，使下次启动回到标准探测，再决定是否移除恢复子命令。
4. 在正确的 `DISPLAY`、`XAUTHORITY` 和用户 D-Bus 环境中重新启动唯一 watcher；先确认至少一个
   输出可见，再恢复自动布局和手动入口。
5. 系统层驱动、Xorg、电源策略、udev 或服务变更按对应平台档案逐项恢复原路径、所有者、权限和
   校验和。需要 reload 或重启才能生效的对象在档案中单独说明，不能用用户会话脚本猜测。
6. 全黑时从可用 TTY 停止 watcher 并恢复文件，不继续试验 RandR。恢复资料和原始诊断在完整验证
   通过前不得删除或覆盖。

## 未完成的通用工作

- 由同一规划器生成完整 `desired_outputs`/`off_outputs`，所有非期望和 stale 输出都进入明确动作，
  并在执行前校验 RandR maximum framebuffer；
- 完成最高共同模式镜像以及有 lid/无 lid 设备的不同多屏回退；
- 实现设备适配器运行接口、timeout/kill-after、候选校验和全部失败降级，再移除旧兼容注入；
- 实现 `--manual-run`、绑定 topology/generation 的 marker，以及尊重 marker 的完整布局 health；
- 只有自动布局仍留下 framebuffer 残留时才实现可关闭的显式 `--fb`，并补齐 min/max、坐标、
  panning、失败恢复和手动布局隔离测试；
- 补齐多外屏、无 lid 桌面、不同 connector/扩展坞、登录前预接、模式迟到、适配器异常、手动布局
  与 watcher 竞争、退出后重新登录等矩阵；
- 按平台档案记录各系统的 lid/电源边界，不把一种服务管理或挂起策略写入共享引擎。

恢复条件和项目状态见[挂起项](../planning/suspended.md)，平台进度见
[平台档案索引](../platforms/index.md)。

## 维护约束

- 不在共享代码或本文硬编码设备输出名、固定分辨率、modeline、PCI 地址或服务路径。
- 自动布局、手动布局和设备适配器必须遵守同一布局锁和状态验证。
- 系统服务只能准备设备，不能形成第二条布局写链。
- 新平台先验证零配置路径，再添加最小设备适配；个性化事实只写平台档案。
- 修改后同步检查架构、依赖、用户指南、平台索引和相应平台档案。
