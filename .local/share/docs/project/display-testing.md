# X11 显示管理测试方案

本文是显示管理系统的可操作验收方案，覆盖 `.local/bin/xdisplay`、兼容包装
`.local/bin/xdisplay.sh`、`.local/bin/displayselect`、`.local/lib/xdisplay/`、可选设备适配器以及
两个可选配置文件。适配器调用契约和状态定义见
[`display-device-adapter.md`](display-device-adapter.md)。

## 1. 测试范围与环境

### 1.1 必要环境

- POSIX `sh`、`awk`、`sed`、`grep`、`stat`、`mktemp`、`date`、`flock`、GNU `timeout` 和 `xrandr`。
- 已登录的 X11 会话，且 `DISPLAY`、`XAUTHORITY`、`PATH` 可用。真实硬件测试应在 watcher 使用的同一用户会话中执行。
- 测试前确认没有第二个 watcher 持有布局锁：`~/.local/bin/xdisplay status`。
- 真实多屏验收按需准备 1、2 或 3 块外屏；没有硬件时使用 1.2 节的 mock 方式。

### 1.2 Mock 测试方式

显示 fixture 测试脚本为 `.local/share/test/display/xdisplay-adapter.sh`。它通过
`XDISPLAY_STATE_TEST=1`、`XDISPLAY_LAYOUT_TEST=1` 和 `XDISPLAY_CONFIG_TEST=1` 调用引擎的只读测试入口，
不连接真实 X Server。应用测试通过 `XDISPLAY_TEST_MODE=1`、`XDISPLAY_TEST_ROOT` 和 mock `xrandr`，
将 RandR 输出重定向到 fixture；适配器测试则在临时 `$HOME/.config/x11/xdisplay-device.local`
中生成可控脚本。

执行完整显示 fixture 套件：

```sh
sh .local/share/test/display/xdisplay-adapter.sh
```

当前基线输出末行为 `PASS: 36 adapter fixture tests`。显示管理开发期间只运行该脚本；安装系统测试
不属于本方案，也不需要随显示改动反复执行。

语法检查：

```sh
for file in .local/lib/xdisplay/*.sh; do sh -n "$file"; done
sh -n .local/bin/xdisplay
sh -n .local/bin/xdisplay.sh
sh -n .local/bin/displayselect
sh -n .config/x11/xprofile
sh -n .local/share/test/display/xdisplay-adapter.sh
```

## 2. 单元与规划器测试

这些用例不执行布局写入，优先用于每次代码修改后的快速回归。

| 编号 | 场景与步骤 | 预期结果与验收标准 |
| --- | --- | --- |
| U-01 | `XDISPLAY_STATE_TEST=1 xdisplay open eDP-1 ''` | 输出 `INTERNAL_ONLY`。 |
| U-02 | 以 `open`、1 个外屏调用状态入口 | 输出 `DUAL_EXTEND`。 |
| U-03 | 以 `open`、2 个或 3 个外屏调用状态入口 | 输出 `MULTI_EXTEND`。 |
| U-04 | 以 `closed`、1 个外屏调用状态入口 | 输出 `EXTERNAL_ONLY`。 |
| U-05 | 以 `closed`、2 个或 3 个外屏调用状态入口 | 输出 `MULTI_EXTERNAL`。 |
| U-06 | 内屏和外屏均为空 | 输出 `NONE`。 |
| U-07 | `XDISPLAY_LAYOUT_TEST=1` 传入 2 个外屏 | 按 RandR 接口顺序排序，第二块使用前一块作为锚点。 |
| U-08 | layout planner 的方向参数分别设为 `right`、`left`、`above`、`below` | 关系参数分别为 `--right-of`、`--left-of`、`--above`、`--below`。 |
| U-09 | 运行 `xdisplay help`、`xdisplay version` 和 `xdisplay.sh --help` | 新入口输出命令接口和版本，旧包装器转发到相同帮助。 |
| U-10 | 运行 `displayselect help`，再用临时目录执行 `save`、`list`、`delete` | 新参数可用，旧 `--save`、`--list`、`--delete` 仍兼容。 |

## 3. 状态切换集成测试

真实测试应在 watcher 运行期间执行；mock 测试可依次替换 `FAKE_XRANDR_FIXTURE` 和 lid fixture。

### I-01 开盖基础状态

1. 启动 `XDISPLAY_USE_ADAPTER=0 ~/.local/bin/xdisplay watch`。
2. 保持内屏连接且不连接外屏，运行 `xdisplay status`。
3. 插入一块外屏，再运行 `xdisplay status`；再插入第二、第三块外屏。

验收：状态依次为 `INTERNAL_ONLY`、`DUAL_EXTEND`、`MULTI_EXTEND`；`layout` 在扩展状态为
`extend_chain`，内屏在原点，外屏按 RandR 接口顺序链式排列。

### I-02 合盖安全活屏

1. 开盖并确认外屏已连接、模式可用。
2. 触发合盖，观察 `xdisplay status` 和实际画面。
3. 在外屏尚未完成链路训练时重复一次，等待 watcher 的下一轮探测。

验收：状态为 `EXTERNAL_ONLY` 或 `MULTI_EXTERNAL`；第一块外屏成为主屏并保持可见，其他外屏
依次扩展，内屏最后关闭；模式延迟时不出现所有输出同时关闭。

### I-03 插拔与回退

1. 在多屏状态拔出任一外屏，等待一个稳定快照。
2. 再插回该屏，随后开盖。
3. 临时将适配器改名或去掉执行权限，重复一次插拔。

验收：断开的输出不再出现在活动布局；剩余输出继续可用；适配器缺失时静默回到标准探测和
RandR preferred/首项策略。

## 4. 配置系统测试

配置文件均为可选项。测试使用临时 `$HOME`，避免修改真实用户配置。

### C-01 默认与部分配置

1. 删除 `display-engine.conf` 和 `display-layouts/default.conf`，运行 `XDISPLAY_CONFIG_TEST=1`。
2. 只写入 `[engine] timeout_seconds = 7`，再次运行。

验收：无文件时使用 `timeout=2`、`kill-after=1`、`position=right` 等内置值；只写一个键时仅该
键变为 7，其余键保持默认。

### C-02 合法配置加载

写入：

```ini
[engine]
timeout_seconds = 7
kill_after_seconds = 4
apply_failure_limit = 8
apply_retry_ticks = 12
hardware_probe_ticks = 30
pending_probe_ticks = 5
log_max_bytes = 2048
log_path = ~/.cache/xdisplay/test.log

[defaults]
external_position = above
external_primary = largest
mirror_on_duplicate = true
```

验收：`xdisplay status` 的 `config:` 摘要反映这些值；`XDISPLAY_LAYOUT_TEST=1` 显示 `direction=above`，
应用规划器记录 `--above` 关系；合盖时 `external_primary=largest` 选择模式面积最大的外屏。

### C-03 非法配置容错

将 `timeout_seconds` 设为 `2s`、`log_max_bytes` 设为 `nope`，将 `external_position` 设为
`diagonal`。

验收：引擎继续启动；标准错误有简短 `invalid value` 诊断；对应字段回退默认值，布局不被阻塞。

## 5. 自定义布局端到端测试

### E-01 保存、列表与删除

1. 在 X11 会话中调整至少两块活动输出。
2. 执行 `displayselect save test-dock`。
3. 检查 `~/.config/x11/display-layouts/custom/test-dock.conf` 的 `[identity]` 和 `[layout]`。
4. 执行 `displayselect list`，再执行 `displayselect delete test-dock`。

验收：目录权限为 `700`、配置文件权限为 `600`；文件记录输出、绝对坐标、模式、刷新率、主屏和
lid；列表包含名称，删除后文件消失。`displayselect save` 不停止 watcher。

### E-02 exact 匹配与恢复

1. 保存一个 `lid=open`、`match_mode=exact` 的布局。
2. 改变输出位置或模式，触发一次 topology 快照。
3. 运行 `xdisplay status` 并观察画面。

验收：输出集合完全相同时应用保存的绝对坐标和模式，状态仍显示 `DUAL_EXTEND` 或
`MULTI_EXTEND`，并额外显示 `layout=custom` 与 `custom=<name>`。

### E-03 contains 匹配与多配置优先级

1. 创建一个 `match_mode=contains` 的两屏配置，实际连接三屏。
2. 同时创建 `lid=any` 或 `contains` 的竞争配置。
3. 触发新快照。

验收：contains 配置命中，额外输出按默认 `external_position` 追加；候选优先级依次为 lid 精确、
exact、配置输出数量更多、mtime 更新较近。结果只选择一个配置。

### E-04 删除和损坏回退

1. 删除当前命中的配置，触发下一次快照。
2. 将另一个配置的坐标、模式或区段改为非法值，重新触发快照。

验收：删除后回到默认扩展链；损坏配置不会阻塞 watcher，默认布局生效，日志记录
`custom-layout` 的 `parse_failed` 诊断。

### E-05 三块以上外屏

使用三块外屏保存自定义布局，再插拔其中一块并触发匹配。

验收：配置中的所有输出按保存的绝对位置应用；contains 多出的输出仍全部保留并按链式策略追加，
不能只启用前两块。

## 6. 适配器灰度路径测试

以下场景均设置 `XDISPLAY_USE_ADAPTER=1`，并在适配器脚本中明确记录调用。未设置或设为 0 时应
完全不调用适配器，也不创建适配器日志。

| 编号 | 步骤 | 预期结果 |
| --- | --- | --- |
| A-01 | 适配器返回一个有效 `internal-outputs` 候选 | 非标准内屏被识别；标准候选优先。 |
| A-02 | 返回空、重复、未连接或含空白的候选 | 记录格式诊断并回退 `XDISPLAY_INTERNAL_OUTPUTS`/标准探测。 |
| A-03 | `expected-mode` 返回 `1920x1080@60` | 目标模式和刷新率优先于 RandR preferred。 |
| A-04 | 预期模式缺失，`restore-internal` 返回 0 | 恢复调用最多一次，重新读取 RandR 并验证。 |
| A-05 | 恢复返回非零或超时 | 记录 stderr、退出码和超时，随后尝试 `XDISPLAY_RESTORE_COMMAND`，最终回退 preferred/首项。 |
| A-06 | 适配器文件缺失、不可执行或会话环境缺失 | 快速降级，不阻塞布局；日志包含 `UNAVAILABLE` 诊断。 |
| A-07 | 日志超过 1 MiB | 写入前将旧日志覆盖轮转为 `.1`，新日志继续写入；日志失败不改变布局结果。 |
| A-08 | 修改适配器 mtime、RandR topology 或 mode signature | 下一快照重新查询；同一稳定快照内不重复查询。 |

验证日志：

```sh
sed -n '1,120p' ~/.local/share/x11/xdisplay-adapter.log
```

每条事件应包含时间戳、`subcommand`、`output`、`exit` 和 `status`；stderr 只保留经过长度限制和
脱敏的可操作摘要。

## 7. 故障排查

### `xrandr: Can't open display`

确认 `DISPLAY`、`XAUTHORITY`、`PATH` 在 watcher 和适配器进程中存在：

```sh
printf 'DISPLAY=%s\nXAUTHORITY=%s\nPATH=%s\n' "$DISPLAY" "$XAUTHORITY" "$PATH"
~/.local/bin/xdisplay status
```

GDM 登录前、systemd 冷启动或 SSH 环境通常没有有效 X11 会话。适配器灰度路径会记录
`missing_session_environment`；不要在适配器中猜测授权文件路径。

### 自定义布局未命中

检查 `[identity] outputs` 是否与当前连接输出一致，`lid` 和 `match_mode` 是否正确，配置文件是否
可读且权限为 `600`：

```sh
displayselect list
stat -c '%a %n' ~/.config/x11/display-layouts/custom/*.conf
~/.local/bin/xdisplay status | sed -n '1,8p'
```

### 配置不生效

查看 `xdisplay status` 的 `config:` 行和标准错误中的 `invalid value`。未知键、未知区段和非法数值只影响
对应配置项，不会阻止 watcher 启动。

### 恢复后仍为低分辨率

检查适配器是否返回合法 `expected-mode`，以及日志中是否有 `expected_mode_missing`、
`restore-internal` 非零或 `TIMEOUT`。适配器返回 0 不是恢复成功证明，必须以 RandR 重读后的目标模式
验证为准。

## 8. 验收记录

建议每次发布将以下信息附在变更记录中：fixture 测试末行、全部库及入口语法检查结果、真实硬件场景（如有）、
配置和自定义布局文件摘要，以及适配器日志中是否出现非预期错误。共享文档不得记录用户名、主机名、
序列号、完整 EDID 或授权文件路径。
