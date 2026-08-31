# X11 显示管理设计

本文面向维护者，是共享 X11 显示引擎的唯一权威设计文档，负责命令结构、状态、配置、默认布局、
自定义布局、锁、重试和当前/目标边界。非标准硬件扩展接口见
[设备适配器指引](display-device-adapter.md)，操作与回归步骤见[显示管理测试](display-testing.md)。
设备输出名、驱动、系统服务、模式和实测结果只写入[平台档案](../platforms/index.md)。

## 当前实现与未完成边界

当前 `xdisplay 2.0.0` 已实现：

- 单份 RandR 快照解析和只读枚举状态；
- 单屏、开盖扩展、合盖外屏和无法识别内屏时的镜像回退；
- 任意数量外屏按 RandR 接口顺序形成 `right|left|above|below` 链；
- 可选引擎参数与默认布局配置，非法项逐项诊断并回退；
- 自定义布局的保存、精确/包含匹配、恢复和删除；
- 默认关闭的设备适配器运行接口及 legacy 环境变量降级；
- 按 X server 隔离的 apply/watch 锁、watcher generation、stale/pending 清理、有界重试和日志；
- 每次 RandR 写入后的活动输出、主屏、目标模式、方向和自定义位置重读验证。

尚未实现的目标不能写成现状：统一 `desired_outputs`/`off_outputs` 规划器、最高共同模式镜像、无 lid
设备的独立多屏扩展回退、有效 manual marker 与完整自动布局 health，以及可选显式 `--fb` 收敛。
保留的 `MIRROR`、`CUSTOM` 状态常量不是当前对外状态；镜像是回退布局，自定义配置命中后仍保留
物理/lid 状态名。

## 核心设计原则

以下原则是后续修改的阅读导引，具体契约以括号所列章节为准：

1. **引擎管策略，适配器管设备差异。** 通用引擎统一负责状态、布局、锁、验证和重试；适配器只
   报告非标准内屏身份、预期模式或执行一次设备恢复。（“内屏、lid 与设备适配器”）
2. **用户命令只分派，共享实现统一进入库。** `xdisplay` 和 `displayselect` 保持窄入口，复用
   `.local/lib/xdisplay/` 中带 `xdisplay_` 前缀的函数，避免入口间复制策略。（“命令、库与所有权”）
3. **状态来自只读快照计算，不靠副作用猜测。** lid、内屏和外屏列表只产生明确枚举，状态计算本身
   不修改 RandR，自定义布局也不覆盖物理状态名。（“快照与状态模型”）
4. **多外屏是列表问题，不是固定接口或固定数量问题。** 输出由运行时快照发现并按接口顺序形成
   扩展链，不硬编码输出名和屏幕数量。（“默认布局与安全活屏”）
5. **配置覆盖策略，内置值只提供可靠默认。** 可选配置优先；文件或单项缺失、值非法时只回退对应
   默认值，不能阻止 watcher 启动。（“配置系统”）
6. **匹配的自定义布局优先于默认布局。** 引擎按 lid、匹配模式、输出数量和 mtime 选择最佳快照；
   没有有效候选时使用默认策略。（“自定义布局”）
7. **始终优先保留安全活屏。** 合盖时先激活并验证外屏再关闭内屏；恢复、pending 或 stale 处理
   不得制造所有输出同时关闭的瞬间。（“默认布局与安全活屏”）
8. **所有写操作都必须串行、有界并经重读验证。** 自动、手动、自定义和设备恢复共用写锁，命令
   返回 0 也不能替代 RandR 收敛验证。（“命令、库与所有权”、“Watcher、健康与手动布局”）
9. **可观测性不能成为新的故障源。** `xdisplay status` 保持只读，日志有界且脱敏；日志失败不得
   改变布局结果。（“状态、日志与故障排查”）
10. **测试矩阵是设计契约的一部分。** 状态、布局、配置、自定义匹配、适配器和降级均需 fixture
    或真实硬件验收，测试数字由显示测试文档维护。（“验证矩阵”）
11. **新能力默认灰度启用，旧路径始终可退。** 设备适配器默认关闭，未启用或失败时保留标准探测和
    legacy 兼容行为。（“内屏、lid 与设备适配器”）
12. **失败应降级而不是阻塞显示流程。** 配置损坏、适配器失败和自定义布局失效进入对应默认或有界
    重试路径，优先维持 X11 会话和已有可见输出。（“默认布局与安全活屏”、“自定义布局”）

## 命令、库与所有权

正常运行链只有一条自动 RandR 写入口：

```text
X11 会话 -> xprofile -> xdisplay watch -> 状态计算 -> 默认或自定义布局
Mod+F3 ----------------> displayselect -> 交互布局或 Arandr
```

| 路径 | 职责 |
| --- | --- |
| `.local/bin/xdisplay` | `apply`、`watch`、`status`、`version`、`help` 的用户入口 |
| `.local/bin/xdisplay.sh` | 旧参数兼容包装，原样转发到 `xdisplay` |
| `.local/bin/displayselect` | 交互选屏及 `save`、`list`、`delete` 自定义布局命令 |
| `.local/lib/xdisplay/` | 状态、配置、布局、适配器、自定义布局、日志和 watcher 的共享实现 |
| `.config/x11/xprofile` | 在正确的 X11 会话环境中启动唯一 `xdisplay watch` |

所有共享库函数使用 `xdisplay_` 前缀。自动和手动入口共用 `apply.lock`；每个规范化 X server 只有
一个 `watch.lock`。不得同时增加 udev 直接 `xrandr`、第二个 watcher 或缺少图形会话环境的布局服务。

锁和 generation 优先放在有效 `XDG_RUNTIME_DIR`。该目录必须归当前 UID 所有、权限 `0700`、
可写可搜索且不是符号链接；否则只接受绝对 `TMPDIR`，最终回退到 `/tmp` 下同样受检查的用户私有
目录。任一所有权或权限检查失败都拒绝运行，不得使用共享可写固定锁。

## 快照与状态模型

每轮只从一份 RandR 原始快照计算状态，不能混用多次读取结果。screen 保存 minimum/current/maximum
framebuffer；每个已知输出至少保存：

| 字段 | 含义 |
| --- | --- |
| `connection`、`primary` | RandR 连接与主屏事实 |
| `geometry`、宽高、x/y | 当前 CRTC 区域，支持负坐标 |
| `active` | 存在 geometry，即使输出刚变为 disconnected |
| `mode_ready` | connected 且至少存在一个模式 |
| `stale` | disconnected 但仍占有 geometry，必须安全关闭 |
| `pending` | connected、未激活且模式尚未就绪，需要保留活屏并重试 |
| `current_mode/current_rate` | 当前 `*` 模式和刷新率 |
| `preferred_mode/preferred_rate` | 首个 `+` 模式和刷新率 |
| `target_mode/target_rate` | 适配器有效目标，否则 preferred，再否则模式表首项 |
| `mode_count/mode_signature` | 模式、刷新率与 preferred 标记组成的能力摘要 |

模式签名忽略 current `*`，保留刷新率和 preferred `+`，因此正常 modeset 不制造循环，而驱动稍后
补充模式会触发重算。拓扑签名包含 lid 状态、输出连接、首项模式、能力签名和自定义布局名称/mtime。

状态由 lid、有效内屏数量和外屏数量直接计算：

| 状态 | 条件 | 默认布局 |
| --- | --- | --- |
| `NONE` | 没有有效输出 | 不执行破坏性写入 |
| `INTERNAL_ONLY` | 非合盖且只有内屏 | 内屏 primary@`0x0` |
| `EXTERNAL_ONLY` | 无有效内屏且一块外屏 | 外屏 primary@`0x0` |
| `DUAL_EXTEND` | 非合盖、内屏加一块外屏 | 内屏为主屏，外屏按配置方向扩展 |
| `MULTI_EXTEND` | 非合盖、内屏加多块外屏 | 内屏为锚点，所有外屏形成链 |
| `MULTI_EXTERNAL` | 无有效内屏且多块外屏 | 合盖路径形成外屏链；无 lid/未识别内屏路径当前镜像回退 |

合盖时内屏仍保留在诊断列表，但不计入有效状态。自定义布局命中时 `layout=custom`、`custom=NAME`，
状态名仍是上表的实际状态。

`XDISPLAY_TEST_MODE=1` 只允许测试用绝对 `XDISPLAY_TEST_ROOT` 重定向 `/proc` 和 `/sys` 观测根；正常
模式始终读取真实系统路径，也不会因测试模式绕过 RandR 解析、锁或输出校验。

## 内屏、lid 与设备适配器

标准内屏候选依次来自 `eDP-*`、`LVDS-*`、`DSI-*`。没有标准候选时，启用的设备适配器可以提供
一个经当前 RandR 快照验证的候选；再失败才读取兼容变量 `XDISPLAY_INTERNAL_OUTPUTS`。模式恢复优先
使用启用且给出有效 expected mode 的适配器，之后可降级到 `XDISPLAY_RESTORE_COMMAND`。

设备适配器位于 `.config/x11/xdisplay-device.local`，默认 `XDISPLAY_USE_ADAPTER=0`；启用条件、三个
子命令、缓存和失败语义只在[适配器指引](display-device-adapter.md)维护。通用引擎不包含设备输出名、
固定分辨率、modeline、PCI 地址、驱动命令或系统服务路径。

lid 为 `open`、`closed`、`unknown` 或无接口时的 `absent`。接口存在但读取失败按有 lid 设备安全
降级，不能关闭最后一个活屏。合盖是否挂起由 login manager 和平台电源策略决定；显示引擎只在仍
运行的 X11 会话中排列输出，不改写 logind 配置，也不模拟 lid 事件。

## 配置系统

两个 INI 风格文件均可选；缺失时静默使用内置默认值，未知区段、未知键、空值或非法值只记录诊断，
不阻止 watcher 启动。

引擎参数：`~/.config/x11/display-engine.conf`

```ini
[engine]
timeout_seconds = 2
kill_after_seconds = 1
apply_failure_limit = 3
apply_retry_ticks = 10
hardware_probe_ticks = 120
pending_probe_ticks = 10
log_max_bytes = 1048576
log_path = ~/.local/share/x11/xdisplay-adapter.log
```

默认布局：`~/.config/x11/display-layouts/default.conf`

```ini
[defaults]
external_position = right
external_primary = first
mirror_on_duplicate = false
```

`external_position` 支持 `right|left|above|below`。合盖外屏主屏支持 `first|largest|manual`；`first`
按 RandR 接口顺序，`largest` 按当前快照中活动 geometry 的宽高面积选择（未激活输出面积视为 0，
同面积保持接口顺序），`manual` 当前作为占位并按 first 处理。
`mirror_on_duplicate` 当前只解析和显示，不改变布局。

配置在 `XDISPLAY_USE_ADAPTER=0` 时仍加载。`xdisplay status` 输出实际值：

```text
config: timeout=... kill-after=... position=... limit=... retry=... probe=... pending=... log=... log_max=...
```

示例文件为 `.config/x11/display-engine.conf.example` 和
`.config/x11/display-layouts/default.conf.example`；不会因示例存在而自动启用配置。

## 默认布局与安全活屏

`xdisplay_sort_external_outputs()` 按 `xrandr --query` 的接口顺序排序。
`xdisplay_apply_extend_layout()` 将主屏置于 `0x0`，每块后续输出相对前一块使用配置方向；它复用目标
模式和刷新率辅助函数，不重新实现模式选择。

| 场景 | 当前行为 | 安全条件 |
| --- | --- | --- |
| 单个可用输出 | primary@`0x0`，使用 target mode | 已收敛时不重复写入 |
| 开盖且识别内屏 | 内屏为主屏，所有外屏按接口顺序链式扩展 | 内屏模式缺失时只做有界恢复 |
| 合盖且外屏可用 | 选定第一/最大外屏为主屏，形成外屏链并关闭内屏 | 必要时先激活并验证外屏，不能瞬间关闭全部输出 |
| 合盖且外屏模式迟到 | 保留已有安全活屏，标记 pending 后重试 | 不提交部分成功 |
| 无法识别内屏且多输出 | 当前将可用输出置于同一原点做镜像回退 | 还没有最高共同模式规划器 |
| stale 输出 | 若没有其他活屏先启用替代输出，再关闭 stale CRTC | 关闭后重读确认 stale 消失 |

每次写入后都重读 RandR，验证 active、primary、原点、目标模式和链式方向；自定义布局还验证保存的
坐标、模式和主屏。任何验证失败由 watcher 的同一状态退避重试，不能把命令返回 0 当作收敛证明。

## 自定义布局

用户通过独立命令管理快照：

```sh
displayselect save [NAME]
displayselect list
displayselect delete NAME
```

无名称时生成 `auto-YYYY-MM-DD-HH-MM-SS`。目录
`~/.config/x11/display-layouts/custom/` 权限为 `700`，文件权限为 `600`。快照保存活动输出、绝对坐标、
当前模式与刷新率、主屏和 lid；绝对坐标能稳定还原非链式、负坐标和不规则排列。

配置的 `[identity]` 使用无序输出集合、`lid=open|closed|any` 和 `match_mode=exact|contains`。候选优先级：

1. lid 精确匹配高于 `any`；
2. `exact` 高于 `contains`；
3. 配置输出数量更多者优先；
4. mtime 更新者优先。

命中后按 `[layout]` 的顺序、坐标、模式和主屏恢复。`contains` 允许的额外输出按
`external_position` 接在最后一个已配置输出之后。解析或字段校验失败时记录 `custom-layout`
诊断、跳过该候选并使用默认布局；RandR 应用或收敛验证失败时返回 watcher 的有界重试路径，多输出
路径在应用成功但重读未收敛时还会清除本次命中并尝试默认布局。任何一种失败都不能阻塞 watcher
主循环。

`displayselect` 的 `switch`、`reset` 目前没有实现，不能写入命令参考或脚本调用。

## Watcher、健康与手动布局

watcher 主循环每 0.5 秒运行，稳定时约每秒读取 `--current`；事件或能力变化进入快速查询窗口。
同一状态布局失败默认最多连续 3 次，失败后等待 10 tick；稳定硬件默认每 120 tick 主动查询，pending
默认每 10 tick 探测。连续 6 次 RandR 快照失败时认为 X server 已消失并退出；新 watcher 最多等待
旧 watch lock 8 秒。

基础 health 为 `ready|stale|pending|no-connected-output`。它能驱动清理和重试，但尚未形成包含所有
期望 active/off、primary、geometry、target mode 和 framebuffer 的完整自动布局 health。

`displayselect` 取得同一 apply lock，支持单屏、双屏选择、有限三屏交互和可选 Arandr；自定义布局
管理也复用共享库。generation、manual marker 路径及只读状态已经存在，但当前没有 `--manual-run`，
也不会写有效 marker，所以 watcher 尚不能长期保留一个拓扑未变的任意手动布局。DWM 会在根窗口
尺寸变化后通过 ConfigureNotify/Xinerama 重新读取几何，正常 RandR 切换不要求重启 DWM。

## 状态、日志与故障排查

`xdisplay status` 只读，不恢复模式或写布局。它输出 lid、物理状态枚举、当前布局函数、自定义配置、
配置摘要、framebuffer、每个输出的模式/几何/stale/pending、policy、health、拓扑签名、锁、generation、
manual marker 和 legacy 配置可用性。

适配器和自定义布局诊断默认写入 `~/.local/share/x11/xdisplay-adapter.log`，或写入配置的 `log_path`。
文件以 `0600` 创建，达到 `log_max_bytes` 后覆盖轮转为 `.1`；日志失败不改变布局返回值。详细字段和
脱敏边界见[适配器指引](display-device-adapter.md#日志与退出码)。

排查顺序：

1. 保存 `xdisplay status` 和 `xrandr --current`，不要先用新写入覆盖现场；
2. 确认只有一个 watcher，且命令继承正确的 `DISPLAY`、`XAUTHORITY` 和 `PATH`；
3. 检查 stale/pending、target mode、自定义命中和配置摘要；
4. 暂时设置 `XDISPLAY_USE_ADAPTER=0` 区分通用路径与设备扩展；
5. 仍有可见输出时再运行一次 `xdisplay apply`；全黑时从 TTY 停止 watcher 并按平台档案恢复。

## Framebuffer 边界

共享目标是 framebuffer 与自动布局的有效输出包围盒一致。普通 `--output ... --off` 能让 Xorg 自动
收敛时不得增加显式 `--fb`。只有统一 desired/off 规划已完成且布局重读正确、framebuffer 仍稳定
残留时，才能另行设计可关闭的显式路径。

实现前必须校验 RandR minimum/maximum、计划包围盒、坐标和 panning；不得改写合法的手动负坐标、
缩放或排列。诊断 A/B 只允许在 apply lock 内动态取得输出、模式和旧 framebuffer，设置总超时与
恢复 trap，测试后恢复标准布局。设备实测耗时和结果只写平台档案。

## 验证矩阵

共享实现的权威可操作步骤和当前 fixture 数量见[显示管理测试](display-testing.md)。设计验收至少包括：

| 场景 | 验收结果 |
| --- | --- |
| 开盖，0/1/2/3 块外屏 | 状态正确；内屏为主屏，全部外屏按配置方向成链 |
| 合盖，1/2/3 块外屏 | 外屏先可见再关内屏；主屏规则和链方向正确 |
| 任一外屏热拔 | stale geometry 清除，剩余活屏保留 |
| `external_position=above` | 所有相邻关系使用 `--above` |
| `external_primary=largest` | 合盖时选择当前快照活动 geometry 面积最大的外屏 |
| exact/contains 自定义配置 | 恢复快照；contains 的多出输出按默认链追加 |
| 配置解析损坏 | 记录诊断、跳过候选并回退默认布局 |
| 自定义布局应用或验证失败 | 返回非零并进入 watcher 有界重试；不得停止主循环或关闭全部输出 |
| 适配器缺失、非法、失败或超时 | 不阻塞会话，回到标准/legacy 路径 |
| 无 lid 或无法识别内屏 | 当前镜像回退，不误报为链式扩展已完成 |
| watcher 退出并重登 | 旧 generation 有界清理，新 watcher 取得锁 |

## 未完成的通用工作

- 由一个规划器生成完整 `desired_outputs`/`off_outputs`，在写入前检查 maximum framebuffer；
- 为无 lid/未识别内屏多输出实现独立策略，并在扩展失败时选择最高共同模式安全镜像；
- 实现 `--manual-run`、绑定 topology/generation 的有效 marker，以及尊重 marker 的完整 health；
- 仅在标准自动收敛仍留下 framebuffer 残留时，设计可关闭的显式 `--fb` 路径；
- 扩展 `displayselect` 的任意数量交互布局；当前任意数量能力属于自动链和自定义布局；
- 按平台档案完成不同 connector/扩展坞、无 lid、登录前预接和模式迟到的真实硬件矩阵。

这些项目处于明确挂起状态，见[挂起项](../planning/suspended.md)，不得因文档列出目标就假定实现存在。

## 维护约束

- 状态由只读快照计算，布局函数不能反向修改状态事实。
- 自动、手动、自定义和适配器恢复共享同一写锁；适配器不得取得布局所有权。
- 先保留一个已验证活屏，再关闭其他输出；任何路径不得制造“所有输出都关闭”的瞬间。
- 配置缺失或损坏、适配器失败、自定义布局失效时必须降级，不阻塞 X11 会话。
- 通用代码和文档不保存设备输出名、固定模式、驱动命令或平台验证结论。
- 修改后运行显示专项 fixture，不因显示改动反复运行 installation 测试。
