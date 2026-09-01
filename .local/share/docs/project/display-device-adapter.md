# 显示设备适配器开发指引

> 服务域：U06 显示、网络、挂载与系统控制；关联 U02 X11 桌面与输入、S02 验证

本文面向非标准 X11 显示硬件的适配器开发者，只定义扩展 API、输入输出校验、超时、缓存、日志、
降级和验证。状态、默认显示布局、配置、自定义显示布局、锁和 watcher 统一由
[X11 显示管理设计](display-management.md)维护，本文不复制这些策略。

> 适配器是已经实现但默认关闭的灰度路径。只有 `XDISPLAY_USE_ADAPTER=1` 且本地文件可执行时才调用；
> 缺失、失败或非法都会回到标准探测和 legacy 兼容路径。

## 目的与边界

标准内屏名称和 RandR 模式可用时不需要适配器。只有设备无法按 `eDP-*`、`LVDS-*`、`DSI-*` 识别
内屏，或驱动未暴露正确预期模式且需要一次有界恢复时，才创建：

```text
~/.config/x11/xdisplay-device.local
```

该路径由仓库 `.gitignore` 精确排除；文件应为用户所有、权限 `0700`，不得提交设备值或凭据。
引擎用独立进程执行它，不会 `source`、`eval` 或读取它来修改父进程变量。

职责边界：

- 引擎负责快照、状态、显示布局、primary、off、framebuffer、锁、重试和最终验证；
- 适配器只报告一个额外内屏候选、声明预期模式，或为该内屏执行一次幂等模式恢复；
- 驱动、Xorg、udev、login manager 和电源策略属于系统/平台层，不得放进适配器；
- 设备事实和实机恢复证据只写[平台档案](../platforms/index.md)，通用文档不复制。

## 启用与调用环境

先在标准路径验证，再在同一 X11 会话临时启用：

```sh
chmod 700 ~/.config/x11/xdisplay-device.local
XDISPLAY_USE_ADAPTER=1 xdisplay status
XDISPLAY_USE_ADAPTER=1 xdisplay apply
```

持久启用方式属于平台本地部署，不写入共享配置。引擎显式向子进程传递当前 `DISPLAY`、
`XAUTHORITY` 和 `PATH`；任一值缺失时记录 `missing_session_environment` 并跳过。适配器不得猜测
授权文件、扫描其他用户进程或依赖 GDM 登录前、SSH 等没有有效 X11 会话的环境。

每次调用使用 `timeout_seconds` 和 `kill_after_seconds`，默认等价于
`timeout --kill-after=1 2`。适配器必须是快速、确定、POSIX 兼容、无状态且可重复执行的程序；不得
自行休眠、轮询、重试或启动后台进程。

## 接口总览

| 子命令 | 必需性 | 标准输出 | 是否允许写入 |
| --- | --- | --- | --- |
| `internal-outputs` | 基础接口 | 空或一个 RandR 输出名 | 否，只读身份查询 |
| `expected-mode OUTPUT` | 可选 | `WIDTHxHEIGHT` 或 `WIDTHxHEIGHT@RATE` | 否，只读目标查询 |
| `restore-internal OUTPUT` | 与有效 expected mode 配套 | 无结构化输出 | 是，只允许一次幂等模式恢复 |

诊断只能写标准错误。返回 0 表示子命令正常结束，不表示显示布局或模式已经收敛；最终成功始终由引擎
重读 RandR 验证。

## `internal-outputs`

```sh
~/.config/x11/xdisplay-device.local internal-outputs
```

- 没有额外候选时输出为空并返回 0；有候选时只输出一个完整 RandR 名称和换行。
- 输出不得含空白、控制字符、说明文字或 DRM 名称猜测；名称必须存在于本轮 connected 列表。
- 标准候选已经存在时，引擎不会调用此查询；适配器不能覆盖标准识别结果。
- 同名重复行会折叠；未连接、非法或多个不同候选视为 `INVALID`，随后降级到
  `XDISPLAY_INTERNAL_OUTPUTS` 或无内屏回退。
- 此子命令不得调用 `xrandr` 写操作。

身份查询的缓存键包含适配器 mtime 和 RandR 输出连接/模式签名；文件或拓扑变化后下一快照重查。

## `expected-mode OUTPUT`

```sh
~/.config/x11/xdisplay-device.local expected-mode OUTPUT
```

`OUTPUT` 是引擎已确认的 connected 内屏。成功时标准输出必须恰好一行：

```text
1920x1080
1920x1080@60
1920x1080@59.94
```

宽高必须为非零十进制整数；刷新率为正数，不得带 `Hz`、空格、注释或额外字段。没有设备特定目标、
未实现查询或查询失败时返回非零，引擎直接使用 RandR preferred/模式表首项。

合法且已存在的 expected mode 会覆盖错误的 RandR preferred，并参与实际 `--mode/--rate` 参数和最终
目标模式验证。合法但缺失的 expected mode 才允许触发一次 `restore-internal`。缓存键除适配器 mtime
和拓扑外还包含内屏名及其 `mode_signature`，因此模式表变化会自动重查。

引擎不会从面板物理尺寸推断像素分辨率，也不解析 EDID 来替代此契约。适配器不实现本查询时，
即使 RandR 只暴露了较低模式，引擎也会把现有 preferred/首项视为可用目标，不擅自恢复。

## `restore-internal OUTPUT`

```sh
~/.config/x11/xdisplay-device.local restore-internal OUTPUT
```

该命令只在有效 expected mode 尚未出现在目标内屏模式表时调用，每次显示布局事务最多一次，并在
`apply.lock` 内执行。允许的动作仅限为这个输出恢复模式，例如一次已验证的驱动命令，或幂等的
`xrandr --newmode`/`--addmode`：

- 创建前检查全局模式是否已存在，关联前检查输出是否已经拥有该模式；
- 重复调用不能创建重复 Modeline、改变 primary、位置、缩放或其他输出；
- 关键写入失败必须返回非零，不能用 `|| true` 掩盖；“已存在”竞态可显式视为成功；
- 不得使用 `--primary`、`--off`、相对位置、`--same-as` 或 `--fb`；
- 不适用于该输出时返回 0，实际失败时返回非零并写简短诊断。

返回后引擎重新读取 RandR。预期模式出现时继续默认/自定义显示布局；仍缺失时先尝试可用的
`XDISPLAY_RESTORE_COMMAND`，然后在已有其他模式时降级到 preferred/首项。模式表仍为空则保持安全
活屏并交给 pending 与 watcher 有界重试。

legacy `XDISPLAY_RESTORE_COMMAND` 仍是兼容层：使用 `timeout_seconds`，丢弃输出且没有显式
kill-after。新适配器不得依赖该差异，也不得为新设备扩展 legacy 变量。

## 缓存、重试与安全

只读查询在同一稳定快照内缓存，避免 watcher 重复启动适配器：

| 变化 | `internal-outputs` | `expected-mode` |
| --- | --- | --- |
| 适配器 mtime | 失效 | 失效 |
| RandR topology | 失效 | 失效 |
| 任一输出 mode signature | 失效 | 目标内屏变化时失效 |

适配器不拥有重试循环。失败由引擎的状态级计数、冷却、pending 探测和低频硬件探测统一调度。
合盖路径在关闭内屏前先保证外屏可用；适配器失败不能主动关闭已有输出，也不能造成所有输出同时
关闭。查询或恢复非零不会永久禁用适配器，后续缓存失效或新快照仍可重试。

## 日志与退出码

诊断默认写 `~/.local/share/x11/xdisplay-adapter.log`，可由引擎配置改写。目录和文件按私有 umask
创建，日志权限为 `0600`；达到 `log_max_bytes` 后覆盖轮转为 `.1`。日志创建或轮转失败不得阻塞
显示布局。

每条事件包含时间戳、`subcommand`、`output`、PID、退出码和 `status`；stderr 最多保留 4096 字节并
过滤绝对 home、XAUTHORITY、EDID、序列号和主机名。适配器自身也必须避免输出用户名、主机名、
序列号、原始 EDID、授权路径、环境值或凭据。

| 退出码 | 引擎解释 |
| --- | --- |
| `0` | 子命令正常结束，随后仍需格式或 RandR 验证 |
| `1`–`123`、`125`–`136`、`138`–`255` | 适配器或调用失败，记录并降级 |
| `124` | timeout 到期 |
| `137` | kill-after 后被强制终止 |
| `127` | 未启用、文件不可执行或调用环境/工具不可用；具体原因看日志 |

适配器自身应避免返回 127，以免与包装器保留语义混淆。

## 新设备接入步骤

1. 不创建适配器，先验证标准内屏、默认模式、开合盖和插拔路径。
2. 在正确 X11 会话记录非敏感的 `xdisplay status` 与 `xrandr --query` 摘要，以 RandR 名称为接口值。
3. 若只是名称不符合标准前缀，只实现 `internal-outputs`。
4. 只有设备有明确、已验证的预期模式时实现 `expected-mode`；不要从另一设备复制参数。
5. 只有 expected mode 缺失且一次可重复操作确实能恢复时实现 `restore-internal`。
6. 先逐个调用三个接口，再用 `XDISPLAY_USE_ADAPTER=1 xdisplay status/apply` 验证日志与降级。
7. 运行[显示管理测试](display-testing.md)，再按平台档案完成实际开盖、合盖、插拔和失败恢复。

探测记录不得包含用户名、主机名、序列号、MAC/IP、UUID、完整 EDID 或授权文件路径。

## 适配器示例

以下只演示结构，`PANEL-1` 是虚构名称，恢复动作必须换成目标设备已验证且幂等的实现：

```sh
#!/bin/sh

internal_outputs() {
	printf '%s\n' 'PANEL-1'
}

expected_mode() {
	case $1 in
		PANEL-1)
			# 验证真实设备参数后才输出，例如：
			# printf '%s\n' '1920x1080@60'
			return 1
			;;
	esac
	return 1
}

restore_internal() {
	case $1 in
		PANEL-1)
			# 只执行一次已验证、可重复的模式恢复；不做显示布局。
			return 1
			;;
	esac
	return 0
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
		printf 'usage: %s {internal-outputs|expected-mode OUTPUT|restore-internal OUTPUT}\n' "$0" >&2
		exit 64
		;;
esac
```

接口级检查：

```sh
chmod 700 ~/.config/x11/xdisplay-device.local
~/.config/x11/xdisplay-device.local internal-outputs
~/.config/x11/xdisplay-device.local expected-mode PANEL-1
~/.config/x11/xdisplay-device.local restore-internal PANEL-1
```

不要把示例输出名、模式或恢复返回值当成真实默认值。

## 禁止事项

- 不在适配器里计算状态、选择主屏、排列外屏、关闭输出或收敛 framebuffer。
- 不另起 watcher、常驻守护、递归调用 `xdisplay` 或绕过共享锁。
- 不写系统配置、加载内核模块、控制服务、改写 logind 或模拟 lid 事件。
- 不把一台设备的输出名、modeline、驱动命令或恢复时序复制进通用代码和文档。
- 不吞掉关键失败，不把返回 0 当作最终成功，不在适配器内部无限重试。
- 不提交本地适配器；只有接口规范和虚构示例属于共享仓库。

## 验证与故障回退

显示 fixture 的适配器部分覆盖：默认关闭、文件缺失、候选校验、expected mode、恢复成功/失败、
legacy 降级、超时、日志轮转和环境传递。权威命令与当前数量见
[显示管理测试](display-testing.md)，本文不重复固定测试数字。

运行时按以下顺序回退：

1. `XDISPLAY_USE_ADAPTER=0` 或文件不可执行：标准探测；
2. `internal-outputs` 失败：legacy 内屏候选或无内屏回退；
3. `expected-mode` 失败：RandR preferred/首项；
4. expected mode 缺失且适配器恢复失败：legacy 恢复，再回到 RandR 目标；
5. 显示布局验证失败：保留安全活屏，由 watcher 有界重试。

若适配器导致异常，先设 `XDISPLAY_USE_ADAPTER=0` 回到零配置路径并保存脱敏日志，不删除现场或继续
增加设备特例。系统层问题按对应平台档案恢复，不能用延长适配器超时掩盖。
