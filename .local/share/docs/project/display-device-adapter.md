# 显示设备适配器开发指引

本文面向适配器开发者和维护者。

> 状态：已实现灰度路径，默认关闭。设置 `XDISPLAY_USE_ADAPTER=1` 且适配器可执行时，
> `xdisplay.sh` 才调用本文三个子命令；未设置时仍只使用 `XDISPLAY_INTERNAL_OUTPUTS` 和
> `XDISPLAY_RESTORE_COMMAND` 兼容路径。

## 目的与边界

通用显示引擎负责读取 RandR 和盖子状态、决定布局、串行应用、验证结果、超时及重试。
绝大多数以 `eDP-*`、`LVDS-*` 或 `DSI-*` 暴露内屏且模式正常的设备应当零配置运行。

只有设备无法按标准输出名识别内屏，或驱动在开盖后不能自行恢复内屏模式时，才创建平台本地适配器：

```text
~/.config/x11/xdisplay-device.local
```

该文件是未跟踪的平台本地可执行文件，是显示管理唯一预期的设备个性化入口。它只回答“哪些输出可能是
内屏”和“怎样对指定内屏做一次模式恢复”，不得决定单屏、扩展、镜像、主屏或输出位置。
目标实现必须通过 Git ignore 规则保持它未跟踪；创建后应使用
`c check-ignore -v ~/.config/x11/xdisplay-device.local` 复核。

驱动模块、Xorg 配置和电源策略属于系统层，不得复制进适配器。确有系统级配置时，应在对应
[平台档案](../platforms/index.md)记录来源和恢复方法，不能以适配器存在为由假设其他设备也具备。

## 调用契约

### 状态定义

引擎在每次 RandR 快照完成后，以当前 lid 状态、已连接的内屏列表和外屏列表执行只读状态计算，
结果写入 `CURRENT_DISPLAY_STATE`，不修改任何 X 状态。当前状态枚举为：

| 状态 | 判定 |
| --- | --- |
| `INTERNAL_ONLY` | lid 未关闭，存在内屏且没有外屏 |
| `EXTERNAL_ONLY` | lid 关闭（或内屏有效数量为零），恰好一块外屏 |
| `DUAL_EXTEND` | lid 未关闭，存在内屏且恰好一块外屏 |
| `MULTI_EXTEND` | lid 未关闭，存在内屏且至少两块外屏 |
| `MULTI_EXTERNAL` | lid 关闭（或内屏有效数量为零），至少两块外屏 |
| `NONE` | 没有可用的内屏或外屏 |
| `MIRROR` | 预留状态，本批次不主动计算 |
| `CUSTOM` | 预留状态，本批次不主动计算 |

外屏和内屏均以换行分隔的输出名列表在 POSIX Shell 中传递；状态层只统计列表，不改变现有
`configure_open()`、`configure_closed()` 或兼容恢复路径。`--status` 输出 `state=... internal=...
external=...` 摘要，便于观察当前状态。

### 执行环境约定

`xdisplay.sh` 默认不接入 `xdisplay-device.local`。设置 `XDISPLAY_USE_ADAPTER=1` 后，
引擎通过 `run_adapter()` 调用适配器；未启用或适配器不可执行时立即回到兼容路径。旧的
`XDISPLAY_RESTORE_COMMAND` 仍由 `try_internal_restore()` 通过 `timeout 2
"$restore_command" "$output"` 启动，未构造独立的 `envp`，因此旧子进程继承 `xdisplay.sh`
的完整环境。

在本机标准 X11 会话中，`xdisplay.sh --watch` 由 `.config/x11/xprofile` 后台启动：
`DISPLAY` 和 `XAUTHORITY` 来自父级图形会话环境，xprofile 不为它们设置默认值；`PATH`
则由 xprofile 显式确保包含 `$HOME/.local/bin` 后导出。灰度适配器路径通过 `env` 显式传递
当前会话的 `DISPLAY`、`XAUTHORITY` 和 `PATH`，并在任一变量
缺失时报告环境不可用而跳过适配器调用。适配器不得假定 SSH、GDM 登录前或 systemd
冷启动会自动提供这些变量，也不得通过猜测显示器或授权文件路径来替代会话环境。

因此，直接从无图形会话的 systemd/SSH 环境触发当前恢复命令可能得到
`xrandr: Can't open display`；现行调用会丢弃恢复命令的标准错误并继续兼容探测，故可能
表现为静默的恢复失败。灰度适配器路径会把该失败记录为 `missing_session_environment`；旧
兼容路径仍保持历史的静默降级行为。由引擎传递会话环境可保持适配器 POSIX、无状态且与 X11
会话边界一致。

### 诊断与日志

当前实现与目标适配器接口的诊断行为必须区分：

- 当前 `try_internal_restore()`（`.local/bin/xdisplay.sh`）只执行
  `XDISPLAY_RESTORE_COMMAND`，并将其标准输出和标准错误重定向到 `/dev/null`，同时忽略
  `timeout` 的退出码。灰度适配器调用由 `run_adapter()` 捕获并记录；旧兼容命令仍保持历史
  的丢弃行为。当前没有 `XDISPLAY_DEBUG`、`--verbose` 或 `--debug` 入口。
- 当前 `xdisplay.sh` 没有全局 `exec 2>>...` 重定向。`--status` 输出
  RandR 快照、健康状态、锁路径、generation 和 legacy 配置可用性，但不包含适配器 stderr、
  适配器退出码或恢复诊断；灰度开启时，输出的 `target_mode`/`target_rate` 会反映已验证的
  `expected-mode`。

灰度适配器路径中，统一由引擎捕获每个子进程的 stderr，并追加到用户私有日志：
`~/.local/share/x11/xdisplay-adapter.log`（若设置了 `XDG_STATE_HOME`，实际路径为
`$XDG_STATE_HOME/x11/xdisplay-adapter.log`）。每条记录至少包含 ISO-8601 时间戳、
子命令名、输出名（如有）、退出码，以及 `timeout`/格式校验结果。建议级别为 `INFO`、`WARN`、
`ERROR`；正常空 stderr 不产生额外噪声。日志写入失败不得阻塞布局流程，且不得改变子命令返回码。

后续可提供受控调试开关（推荐 `XDISPLAY_DEBUG=1`，或等价的显式调试选项），仅在开启时
记录调用参数、解析决策和 RandR 重读摘要；默认级别不记录高频轮询细节。日志必须设置用户私有
权限（`umask 077`，文件不应可被其他用户读取），并采用有界大小和轮转/截断策略，避免 watcher
长期运行导致无限增长。当前灰度路径使用 1 MiB 上限和 `.1` 单次轮转：每次向
`xdisplay-adapter.log` 写入日志事件前，引擎检查当前文件大小；达到或超过 1 MiB 时，将现有文件
重命名为 `xdisplay-adapter.log.1`（覆盖已存在的 `.1` 文件），然后创建新的空日志文件继续写入。
同一次调用的 stderr 摘要与该事件一并写入。日志写入失败（例如磁盘已满）不得阻塞布局流程，
也不得改变适配器子命令的返回码。

适配器 stderr 只能包含非敏感、可操作的摘要，例如“`PANEL-1: expected mode 1920x1080 not
present`”。禁止输出用户名、主机名、序列号、完整 EDID/`xrandr --prop` 原始内容、授权文件
路径或环境变量值；需要诊断 EDID 时只输出经过验证的非敏感字段（如分辨率和刷新率）。引擎
不应假定适配器已经脱敏，必要时应在写日志前进行长度限制和敏感字段过滤。

`run_adapter()` 返回的退出码含义如下，引擎据此决定降级或重试：

- `0`：适配器正常退出且返回 0，但不代表模式恢复成功；引擎仍须重读 RandR 验证。
- `1`-`127`：适配器自身返回的错误码，由适配器定义，引擎仅记录并传递；但适配器自身返回
  `127` 时，无法与下述包装器的 `127` 保留值区分。
- `124`：`timeout` 超时，默认超时信号为 `SIGTERM`，进程未在时限内退出。
- `137`：超过 `--kill-after` 宽限期后由 `SIGKILL` 强制终止。
- `127`：适配器未启用（`XDISPLAY_USE_ADAPTER=0`）或文件不可执行；运行时工具、会话环境
  缺失以及临时文件创建失败等调用基础设施错误在当前实现中也通常映射为 `127`，并另行记录
  具体诊断。
- 其他：调用基础设施错误或包装器返回的其他状态；引擎记录该状态并按失败处理。

任何非零退出码均视为本次尝试未收敛，可触发状态级退避计数或降级；引擎不会因此永久禁用
适配器，后续快照仍可能重新查询。

目标契约包含 `internal-outputs`、`restore-internal` 两个基础子命令，以及可选的
`expected-mode` 查询。适配器应使用 POSIX Shell，保持快速、确定且可重复执行。灰度开启后，
`xdisplay.sh` 会按以下规范调用并验证三个子命令。

### `internal-outputs`

```sh
~/.config/x11/xdisplay-device.local internal-outputs
```

- 标准输出每行只能包含一个完整的 RandR 输出名；空行由引擎忽略。
- 诊断信息只能写入标准错误，不能与输出名混在一起。
- 返回的候选补充标准 `eDP-*`、`LVDS-*`、`DSI-*` 探测，不替代标准探测。
- 此命令只能报告身份，不能调用 `xrandr` 修改状态。
- 没有额外候选时输出为空并返回 `0`；参数或适配器配置错误时返回非零。

引擎把该子命令作为独立进程执行，使用 `timeout 2 --kill-after=1`；不会 `source` 或 `eval`
适配器。引擎拒绝包含空白或控制字符的值，只保留
当前 RandR 快照中确实存在的单个输出名，并对重复候选去重。因此适配器不得依赖修改父进程变量或
工作目录。

输出名必须来自目标会话当前的 `xrandr --query`，大小写和连字符完全一致。不要因为 DRM connector 名
相似就直接假定 RandR 名称相同。

引擎优先使用当前快照中的标准内屏候选；只有标准候选为零时才采用适配器候选。任一层级同时匹配
多个已连接候选都视为身份歧义，引擎不得按输出顺序任选一个，而应使用有盖设备的安全回退并在
`--status` 中报告。若设备确有多个同时工作的内置面板，需要先扩展通用契约，不能在适配器中
偷偷关闭其中一个。

### `expected-mode OUTPUT`（可选）

```sh
~/.config/x11/xdisplay-device.local expected-mode OUTPUT
```

- `OUTPUT` 必须是引擎已经确认的已连接内屏候选。该查询只声明设备预期模式，不得调用 `xrandr`
  修改状态。
- 成功时标准输出必须恰好包含一个非空行，格式只能是 `WIDTHxHEIGHT` 或
  `WIDTHxHEIGHT@RATE`。宽高必须是非零十进制整数；刷新率必须是正十进制数，不带 `Hz`、空格、
  注释或其他字段。例如 `1920x1080`、`1920x1080@60`、`1920x1080@59.94` 均合法。
- 返回 `0` 表示已经输出格式有效的预期模式。没有设备特定预期、未实现此子命令或查询失败时返回
  非零；适配器可将简短原因写入标准错误。返回 `0` 但输出为空、多行或格式非法视为适配器错误。
- 引擎以有界 timeout 独立执行查询。适配器缺失、不支持该子命令、超时、返回非零或输出非法时，
  引擎记录诊断并直接降级到现有 RandR preferred/模式表首项策略，不阻塞布局流程，也不关闭输出。
- 如果预期模式已存在于当前模式表中，引擎把它作为该内屏的有效目标并直接按现有布局流程启用；
  指定刷新率时还必须在该模式的刷新率列表中匹配。预期目标优先于错误的 RandR preferred。
- 如果预期模式不存在，引擎最多调用一次 `restore-internal OUTPUT`，随后用 `--query` 重新读取 RandR。
  恢复后模式存在时将其作为有效目标；仍不存在但模式表中有其他可用模式时，记录恢复未收敛并
  降级到 RandR preferred/首项，以保留可见输出。若模式表仍为空，则保持内屏未激活，交给现有
  pending 和有界重试流程处理。若 `restore-internal` 返回非零或超时，引擎记录诊断并降级到
  兼容路径：尝试 `XDISPLAY_RESTORE_COMMAND`（若设置且可执行）。兼容路径也失败后，引擎使用
  RandR preferred/模式表首项策略，优先保留可见输出。

不实现该可选查询的适配器可以直接对 `expected-mode` 返回非零。引擎不得从面板物理尺寸推断像素
分辨率，也不得把查询失败解释为应禁用该输出。

### `restore-internal OUTPUT`

```sh
~/.config/x11/xdisplay-device.local restore-internal OUTPUT
```

- `OUTPUT` 是通用引擎已经判定为内屏候选的 RandR 输出名。
- 兼容路径只在该输出为 `connected`、未激活且模式表为空（`mode_ready=0`）时执行
  `timeout 2 "$restore_command" "$output"`。GNU `timeout` 的默认超时信号为 `TERM`；兼容调用
  没有 `--kill-after`，也没有显式的强制 `SIGKILL` 阶段，标准输出、标准错误和超时退出码仍会被
  `try_internal_restore()` 丢弃/忽略。灰度适配器路径使用 `timeout 2 --kill-after=1`，并在日志中
  记录 stderr、退出码和超时。两条路径都不会为 disconnected 输出调用恢复。
- 灰度启用且 `expected-mode` 返回有效值时，预期模式缺失是第二个恢复触发条件，即使模式表非空
  也最多调用一次 `restore-internal`；查询失败/未实现时清除 adapter target，降级到 RandR
  preferred/首项策略。恢复成功后重新读取 RandR 并验证；仍缺失但存在其他模式时继续使用
  preferred/首项。
  灰度路径下，恢复决策顺序为：
  1. 若适配器实现 `expected-mode` 且返回有效预期模式，但该模式在当前模式表中缺失，则调用一次
     适配器的 `restore-internal`。
  2. 若适配器未实现 `expected-mode` 或查询失败，则不调用适配器恢复，直接按兼容的 RandR
     preferred/首项策略处理；若适配器 `restore-internal` 返回非零/超时，则立即降级到兼容路径，
     尝试 `XDISPLAY_RESTORE_COMMAND`（若设置且可执行）。预期模式已存在时直接使用该已验证目标，
     不执行恢复调用。
  3. 兼容路径失败后，按现有 RandR preferred/模式表首项策略处理，优先保留可见输出。
- 上述目标模式校验不等同于面板原生模式校验。灰度路径会读取适配器可选的
  `expected-mode OUTPUT`；适配器不实现该查询、返回非零或输出非法时，当前引擎不解析
  `xrandr --prop` 的 EDID，而是将 RandR preferred/首项作为兼容目标。如果驱动只暴露了错误的
  低分辨率/低刷新率，或把它标成 preferred，且适配器没有声明 expected mode，引擎会将其视为
  可用目标，不会调用恢复。不得仅凭物理尺寸推断像素分辨率。
- 该命令最多做一次有界恢复，例如为这个输出执行必要的 `xrandr --newmode`、`--addmode`，
  或调用一次驱动提供的恢复命令。恢复操作必须幂等：相同的
  `restore-internal OUTPUT` 重复执行时，不得重复创建同名 Modeline、重复关联已有模式，
  也不得改变已经收敛的输出布局。适配器在 `--newmode` 前必须检查全局模式表中是否已有
  完全相同的模式名，在 `--addmode` 前必须检查该输出是否已经关联该模式；已存在时跳过
  对应操作。检查和修改之间的竞态仍应把“已存在”视为成功，而不是把该结果当作恢复失败。
- 适配器不得用 `|| :` 或 `|| true` 掩盖关键恢复失败。对“已存在”这类幂等结果可以显式
  转换为成功；其他 `xrandr`/驱动错误应返回非零并写入简短诊断。引擎不会替适配器删除
  未使用的 Modeline，也不记录这些 Modeline 的所有权，因此模式生命周期由适配器负责。
- 目标适配器命令不得自行休眠、轮询或重试。当前兼容恢复命令在共享布局锁内只受 `timeout 2` 限制；
  灰度适配器调用固定使用 `timeout 2 --kill-after=1`，并在重新读取 RandR 后由 watcher 调度重试。
- 返回 `0` 仅表示本次尝试已正常结束，不表示模式一定恢复；最终成功只能由引擎重新探测和验证。
- 不适用于该 `OUTPUT` 时应直接返回 `0`；执行失败时返回非零并将简短原因写入标准错误。

适配器不能执行布局操作。尤其不得在这里设置 `--primary`、`--off`、`--right-of`、`--left-of`、
`--same-as` 或 `--fb`。模式恢复之后的启用、定位和 framebuffer 收敛仍由通用引擎完成。

实现 `expected-mode` 不能只扩大 `try_internal_restore()` 的调用条件。引擎还必须让目标模式选择、
`xrandr --mode/--rate` 参数构造和 `output_at_target_mode()` 最终验证共同使用同一个有效预期目标；
否则恢复脚本即使成功添加模式，现有 preferred/首项逻辑仍可能再次选择错误模式。不要改变
`internal-outputs` 的逐行输出名格式。直接解析 EDID 可作为后续通用能力，但 EDID 瞬态失败正是本
故障的一种来源，不能作为唯一依据。

### 当前 watcher 的超时、重试与退避

以下是现行 `xdisplay.sh --watch` 的实际参数，不是适配器目标接口的示例值：

| 项目 | 当前实现 | 作用 |
| --- | --- | --- |
| 兼容恢复单次超时 | `timeout 2`（2 秒） | `XDISPLAY_RESTORE_COMMAND` 单次调用；默认发送 `TERM` |
| `--kill-after` | 未设置 | 超时后没有显式强制 `SIGKILL` 阶段 |
| 同一状态失败上限 | `APPLY_FAILURE_LIMIT=3` | 对未变化的 topology + lid + health 状态最多连续 3 次布局写入 |
| 失败冷却 | `APPLY_RETRY_TICKS=10` × 0.5 秒，约 5 秒 | 每次失败后等待；不是指数退避 |
| 达到失败上限后 | 普通布局尝试暂停 | 拓扑、模式能力、lid 或 health 变化会重置计数并立即允许新尝试 |
| 低频主动探测 | `HARDWARE_PROBE_TICKS=120` × 0.5 秒，约 60 秒 | 状态不变时以 `xrandr --query` 重新探测；查询轮次允许再次尝试 |
| pending 能力探测 | `PENDING_PROBE_TICKS=10` × 0.5 秒，约 5 秒 | 仅已有成功布局且保留 pending 输出时触发主动查询 |
| RandR 快照失败上限 | `SNAPSHOT_FAILURE_LIMIT=6` | 连续 6 次快照失败后 watcher 退出，不是适配器重试次数 |

watcher 主循环每 0.5 秒运行，稳定时约每 1 秒读取 `--current`；事件或能力变化会进入快速查询窗口。
恢复命令在 `apply.lock` 内执行；只读的 `internal-outputs` 和 `expected-mode` 在快照读取阶段执行，
不修改布局。灰度路径对稳定快照缓存适配器查询，拓扑、模式签名或适配器文件变化时重新查询；单次
查询使用 `timeout 2 --kill-after=1` 且适配器不得自行重试。`restore-internal` 只在布局锁内执行，
其重试继续由同一状态级 watcher 调度，而不是在适配器内部等待。

灰度路径在同一个稳定快照周期内缓存 `internal-outputs` 和 `expected-mode` 的查询结果，避免同一
状态反复调用适配器。缓存失效条件为以下任一变化：

- 适配器文件 `~/.config/x11/xdisplay-device.local` 的 mtime 发生变化；
- RandR topology（输出连接/断开）发生变化；
- 目标内屏的模式签名（`mode_signature`）发生变化。

缓存失效后，下一次快照将重新查询适配器；失效前即使适配器内容被修改，也不会重新执行查询。

恢复失败期间，引擎不会主动关闭已有外屏。合盖路径先激活并验证外屏，再关闭内屏；开盖扩展路径
若内屏恢复/布局失败，会在失败返回前保留已有输出状态。达到失败上限后，内屏保持当前未激活或
驱动已有状态，watcher 等待状态变化或低频主动探测，不会提交破坏性布局。

## 新设备探测步骤

1. 不创建适配器，先验证通用引擎的零配置路径。标准内屏名称且模式可用时，到此结束。
2. 在开盖、合盖和插拔外屏后分别运行 `xrandr --query`，记录输出名、连接状态、可用模式和当前几何。
3. 读取 `/proc/acpi/button/lid/*/state`，确认设备是否有可用的盖子状态；桌面设备没有该路径是正常情况。
4. 查看 `/sys/class/drm/card*-*/status`，用连接变化辅助识别物理 connector，但仍以 RandR 输出名作为
   适配器接口值。必要时结合 Xorg 日志确认 DRM 与 RandR 的映射。
5. 如果内屏只是名称不符合标准前缀，仅实现 `internal-outputs`；不要添加模式恢复逻辑。
6. 只有开盖后内屏为 `connected` 却长期没有可用模式，且一次明确的驱动或 RandR 操作能够恢复时，
   才实现 `restore-internal`。若设备还会暴露错误的非原生模式，应同时实现 `expected-mode`，不要把
   设备分辨率硬编码进通用引擎。
7. 使用 `cvt` 或驱动资料生成 modeline 时，必须核对面板原生分辨率、刷新率和像素时钟；不得从另一台
   设备复制数值。先在当前 X11 会话中手动验证，再写入适配器。

探测记录不得包含用户名、主机名、序列号、EDID 原始数据或其他个人信息。共享项目文档只记录
通用行为；必要的非敏感设备边界写入对应平台档案。

## 适配器示例

以下示例使用虚构输出名 `PANEL-1`。它只展示接口结构；模式恢复部分默认无操作，
必须先按上一节取得并验证目标设备参数后才能补充。

```sh
#!/bin/sh

internal_outputs() {
	printf '%s\n' 'PANEL-1'
}

expected_mode() {
	output=$1

	case "$output" in
		PANEL-1)
			# 取得并验证真实设备参数后才输出，例如：
			# printf '%s\n' '1920x1080@60'
			return 1
			;;
	esac
	return 1
}

restore_internal() {
	output=$1

	case "$output" in
		PANEL-1)
			# 仅在确有需要时执行一次已验证的模式恢复操作。每个修改动作
			# 先查询当前状态，使重复调用不会创建或关联重复模式。
			mode='PANEL-NATIVE'
			if ! xrandr 2>/dev/null | awk -v mode="$mode" \
				'$1 == mode { found = 1 } END { exit !found }'; then
				xrandr --newmode "$mode" ... || return 1
			fi
			if ! xrandr --query 2>/dev/null | awk -v output="$output" -v mode="$mode" '
				/^[^[:space:]]/ {
					in_output = ($1 == output && $2 ~ /^(connected|disconnected)$/)
					next
				}
				in_output && $1 == mode { found = 1 }
				END { exit !found }
			'; then
				xrandr --addmode "$output" "$mode" || return 1
			fi
			;;
	esac
}

case ${1-} in
	internal-outputs)
		[ "$#" -eq 1 ] || exit 64
		internal_outputs
		;;
	expected-mode)
		[ "$#" -eq 2 ] || exit 64
		expected_mode "$2"
		;;
	restore-internal)
		[ "$#" -eq 2 ] || exit 64
		restore_internal "$2"
		;;
	*)
		printf '用法: %s {internal-outputs|expected-mode OUTPUT|restore-internal OUTPUT}\n' "$0" >&2
		exit 64
		;;
esac
```

安装并做接口级检查：

```sh
chmod 700 ~/.config/x11/xdisplay-device.local
~/.config/x11/xdisplay-device.local internal-outputs
~/.config/x11/xdisplay-device.local expected-mode PANEL-1
~/.config/x11/xdisplay-device.local restore-internal PANEL-1
```

不要把示例中的 `PANEL-1` 当作真实默认值。外屏始终由运行时连接状态发现，不应出现在候选列表或
`restore_internal` 分支中。

## logind 与合盖边界

适配器只影响 X11 RandR，不控制挂起。若 logind 先让系统挂起，用户会话中的 watcher 和适配器都
没有机会完成外屏切换。

接电合盖后继续使用外屏的设备，需要在系统层明确评估目标平台的 lid 电源策略；使用电池、
docked 状态和平台默认值仍可能采用不同策略。修改系统电源配置前应确认预期行为，并在平台档案
记录原值和恢复方式。通用引擎不得为了显示布局自动改写电源配置，设备适配器也不得调用服务
管理器或模拟盖子事件。

## 禁止事项

- 不得硬编码任何外接输出名、固定外屏数量或固定左右位置。
- 不得启动后台进程、另起 watcher、创建 udev 热插拔链路或 systemd user service。
- 不得使用长期 `sleep`、内部重试循环或等待 connector 出现；这些都由通用引擎限频调度。
- 不得绕过共享布局锁直接形成第二条布局写入链路。
- 不得依赖被通用引擎 `source`、`eval`，也不得通过标准输出传递输出名以外的数据。
- 不得关闭未知输出、修改全局 framebuffer、重启 DWM 或杀死其他显示管理进程。
- 不得把凭据、设备序列号、用户名或只对当前安装有效的临时路径写入仓库文档。

## 验证矩阵

适配器和通用引擎完成迁移后，至少逐项验证以下场景。单次成功不能替代完整矩阵。

| 场景 | 验收结果 |
| --- | --- |
| 无适配器、标准内屏 | 登录、开合盖和外屏插拔均走零配置路径 |
| 适配器缺失、不可执行、超时或返回非零 | 引擎降级到标准探测，X11 会话不被阻塞 |
| 开盖，仅内屏 | 内屏启用为主屏，布局不重复 modeset |
| 开盖，外屏在登录前或登录后出现 | 可用输出自动扩展，外屏名称无需配置 |
| 合盖且接电，外屏已就绪 | 外屏先成为安全活屏，再关闭内屏 |
| 合盖时外屏模式延迟出现 | 保留安全活屏，由引擎有界重试，不由适配器等待 |
| 合盖后拔出外屏 | 不执行会导致所有输出关闭的破坏性布局 |
| 再次开盖 | 内屏身份和模式均可恢复，适配器单次调用可重复 |
| 多个外屏 | 动态扩展或通用回退，不依赖固定接口名和数量 |
| 拔出任一外屏 | 已断开输出不再保留活动几何；其他输出仍可用 |
| `displayselect` 手动布局 | 与 watcher 共用锁，手动操作期间没有竞争写入 |
| 无盖子的桌面设备 | 不要求适配器或 lid 路径，多屏仍按通用策略工作 |
| 使用电池合盖 | 行为符合 logind 策略，文档不把挂起误判为布局失败 |

新设备至少完成一次冷启动、一次登录后热插拔、一次开合盖和一次故障降级测试。驱动枚举较慢的设备
还应分别测试外屏在启动前已连接和登录后延迟出现的情况。

## 故障回退

1. 先将 `xdisplay-device.local` 改为不可执行或临时改名，使下一次启动回到标准零配置探测。
2. 在仍有可见输出时使用 `displayselect` 或经过确认的 `xrandr` 命令恢复可用布局，再重启 watcher
   或重新进入 X11 会话。
3. 若问题只在加入模式恢复后出现，保留 `internal-outputs`，移除 `restore-internal` 中的设备操作，
   分开验证“身份识别”和“模式恢复”。
4. 若合盖直接挂起，检查 logind 和供电状态；不要通过延长适配器运行时间规避系统电源策略。
5. 目标引擎提供状态诊断后，应保存不含个人信息的状态摘要和标准错误，再按引擎验证结果定位问题；
   适配器返回 `0` 不能作为恢复成功的唯一证据。
6. 在迁移验证完成前保留平台旧恢复脚本和过渡文件的隔离备份。需要整体回退时，按对应平台档案
   记录的基线、原路径、权限和恢复步骤执行，不要同时启用新旧 watcher。

只有验证矩阵持续通过，旧恢复钩子才可以进入待清理隔离目录；平台档案记录其最终删除条件，
不能由适配器安装过程自动完成。
