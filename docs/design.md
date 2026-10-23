# 访问子系统 · 整体规划设计

> 状态：v1 代码已在本目录（2026-10-15）。v1.1 已实现（2026-10-20）。用户单元模板在 `units/`，复制到用户 systemd 后 enable。
> 依据：R23 要求 §十一、§十二；v1.1 依据 §十九、§二十，修订依据 §二十一、§二十二（2026-10-19），实现依据 §二十四（2026-10-20）。阶段二实施方案里依赖 Verge、写入 `~/.config/mihomo`、包装 codex 的部分作废。
> 权威：默认值、子命令、退出码只维护在本文。README、roadmap、constraints、轮次档案只引用，不另写一套数。

## 1. 功能清单

v1 只做从无到有的最小闭环。下面每一项都要能单独验证，做完再加下一档。

### v1（必要）

| 能力 | 行为 |
| --- | --- |
| 服务 | 已实现 `start` / `stop` / `status` / `restart` / `ensure`。随登录会话，不设 lingering |
| 订阅 | 用户自己提供一条地址。`get` 只显示流量与剩余有效期；`refresh` 拉取、校验、合并、必要时重载 |
| 节点 | 已实现 `groups`（含 now）、`list`、`test`、`switch`、`net test`。`test` 仍是控制器延迟，不是端到端 |
| 规则 | 域名或后缀，持久保存。方向只有 `via`（进指定策略组）和 `direct`。路径、查询、关键字不做 |
| 状态 | `status` 给人读：进程、端口、控制器、订阅、关键组与测试缓存 |

### 明确不在 v1

交互菜单、多条订阅、路径级规则、TUN 启用、包装或改名其它命令、开机无人值守、读 Verge 数据目录、把任何文件提交进主仓库。

### 迭代（v1 之后，另授权）

1. TUN 透明转发（见 §2）。
2. 多条订阅、本地规则集文件（规则变多、前置列表难维护时再换）。
3. 跨机器再议。v1 只在本机。

节点列表、手动切换、端到端连通性已收进 §10，2026-10-20 已实现。

## 2. 透明性

原则：其它工具保持原来的用法，不必知道代理存在。

三条路：

| 路径 | 是否改变用法 | v1 |
| --- | --- | --- |
| 环境变量 | 要。SSH 与不认变量的程序盖不住。`axs proxy user` 与现有 `setproxy` 都是显式打开 | 默认不注入；显式 opt-in |
| 包装器 | 要。占命令名会挡住原命令。codex 包装器取消 | 不做 |
| TUN | 不必改命令。流量在网卡层转发 | 候选，不启用 |

v1 的实现路径：只在回环上跑 mihomo（rule），用域名规则决定 via 或 direct。不改其它工具的启动方式。默认不注入代理变量；三层是显式开关，`proxy user` 与 `setproxy` 对齐。因此 v1 **还没有**做到「工具无感」；无感仍待 TUN。

TUN 评估：现二进制带 `with_gvisor`，具备用户态栈条件。启用还要 `CAP_NET_ADMIN` 或 root，会改路由，配错会把本机网络切黑，也越过「先不落地系统服务」的门禁。v1 的覆盖文件固定 `tun.enable: false`，不写栈、不写地址。启用留到系统落地另一次授权。

## 3. 工具选型

- 内核：本机已有的自编译二进制 `~/.local/bin/mihomo`。用户口径是 v1.19.21。阶段一 `mihomo -v` 只打出 Mihomo Meta、go1.27.1，没有打出该版本标签。实现就用这个文件，文档不把未印出的标签写成已证实事实。
- 订阅：用户写入运行目录里的地址文件，由本子系统下载。不读 Verge，不依赖它的数据目录，Verge 可卸。
- v1 只有一条订阅。
- 控制面只走 mihomo 控制器 API。不另存节点凭据。日志、文档、规则文件不写地址、密钥、节点名。操作者自己的终端可以显示组名、节点名、延迟和 `net test` 的目标网址，因为操作者要看。这些输出不另存文件。测试缓存记时间戳和 `ok`/`fail`。`node-test` 成功时再记节点名到延迟，不记组名、地址、密钥。

## 4. 目录与脚本

本地 git 只跟踪代码和文档。密钥与订阅放在 `run/`，该目录不入库。

```
~/.local/lib/access/
  bin/axs                 唯一入口
  lib/merge.py            订阅与覆盖的合并
  lib/common.sh           锁、原子写入、控制器调用
  tests/                  夹具与回归
  docs/                   README、design、constraints、roadmap
  run/                    不入库。0700
```

`run/` 内容：

| 文件 | 权限 | 内容 |
| --- | --- | --- |
| `subscription.url` | 0600 | 地址原文。只有刷新读取 |
| `secret` | 0600 | 首次启动在本地生成。不从 Verge 复制，命令不打印 |
| `override.yaml` | 0600 | 本文默认值的落地件。无节点、无地址 |
| `rules.list` | 0600 | 本机域名规则 |
| `config.yaml` | 0600 | 合并结果。`mihomo -d` 指向 `run/` |
| `config.yaml.bak` | 0600 | 安装前备份。只在成功安装或回滚时更新。拉取或前置校验失败不改它 |
| `userinfo` | 0600 | 上次刷新缓存的流量与到期，不含地址 |
| `refresh.lock` | — | 刷新与规则改写共用 |
| `urls` | 0600 | 可选。`net test` 的目标，一行一个。没有这个文件就用 §10 的三个默认网址 |
| `cache/` | 0700 | `node-test` 与 `net-test`，各 0600。都有 `ts` 和 `result=ok|fail`。`node-test` 成功时再加一行 JSON：节点名到延迟，不含组名、地址、凭据 |

阶段二把运行目录放在 `~/.config/mihomo`。那个目录主仓库没有忽略。v1 改到已经全局忽略的本树 `run/`，避免订阅被宽 glob 扫进公开仓库。

用户单元模板在 `units/`。`axs.service` 只启动 `bin/mihomo-run`。脚本校验并原子写下自己的数字 PID，再 exec `mihomo -d <run>`。单元里不写进程号，systemd 会先展开。`axs-refresh.timer` 每 12 小时跑 `axs sub refresh`。复制到 `~/.config/systemd/user/` 后 enable。没有合格 `config.yaml` 之前不 enable。登录后由用户会话拉起。代理的登录脚本见后文。`axs.service` 的 LoadState 为 loaded 时，`start` / `stop` / `restart` / `ensure` 委派 `systemctl --user`。`AXS_SYSTEMD=0` 强制直接管进程，`AXS_SYSTEMD=1` 强制委派。未设置时入口只探测一次 `LoadState`，结果放在 `AXS_SYSTEMD_MODE`。`use_systemd` 只读它，不写其它全局。已 active 的 `start` 与 `ensure` 不再 start。没有配置时 `ensure` 仍先 refresh，再 `systemctl start`。刷新前若地址含反斜杠或空白（单独的行尾换行不算），退出 3，提示去掉反斜杠。空正文，或 Content-Type 不是 YAML 类（`text/html` 等），退出 3，并带上 HTTP 状态和类型。

## 5. 子命令与退出码

命令名 `axs`。避开已有的 `/usr/bin/proxy`，也避开 mihomo / clash 字样。

```
axs start|stop|status|restart|ensure
axs sub get|refresh
axs rule list
axs rule add via <域名> <策略组>
axs rule add direct <域名>
axs rule del <域名>
axs node groups
axs node test [策略组]
axs node list [--full]
axs node switch <策略组> <节点>
axs net test [url ...]
axs service enable|disable
axs clean [--yes]
axs sub clean [--yes]
```

`ensure`、`list`、`switch`、`net test`，以及 `groups` 带上 `now`，已实现。内部取默认组名的命令仍只打印组名，避免把制表符带进 `node test`。`start` 仍是没有配置就退出 3，不代为刷新。

`axs service enable` 和 `disable` 只改开机自启，同时作用于 `axs.service` 与 `axs-refresh.timer`，不启停进程。没有 systemd 退出 3。成功打印 `开机自启：enabled` 或 `disabled`。

颜色只在终端输出。`NO_COLOR` 或非终端是纯文本。`AXS_COLOR=always` 强制颜色，优先于 `NO_COLOR`，`never` 强制关闭。只染语义，不整行刷色，色码不嵌套。粗体：帮助分区和表头。一级强调是一条码 `1;32` / `1;33` / `1;31`，只用在运行中或未运行、剩余天数或已过期、节点行的叶子、`node list` 的 `[*]` 和选中名、`node groups` 的 now、`sub get` 的剩余天数。灰 90：字段名、编号、路径、时间、`-`、类型。青 36：命令、组名、服务名。`node test` 的组名也是青，不加粗。绿 32：正常、enabled、延迟小于 100。黄 33：警告、延迟 100 到 200。红 31：失败、disabled、延迟大于 200、超时、`die`。帮助不用红色。清理成功和开机自启不加粗。`health` 不着色。测速缓存只存数字，不存颜色码。

裸 `axs` 和未知子命令把 7 行命令清单打到标准错误，不着色，退出 1。歧义前缀不打清单，只打一行 `候选：` 加空格分隔的名字，退出 1。`axs help`、`h`、`?`、`--help`、`-h` 把分组帮助打到标准输出，退出 0。再带参数仍退出 1。长帮助在用法下加命令和别名两列。命令列只用 ASCII，按 `%-22s`，别名列 6 宽。示例另起灰色一行。尾行说明颜色只是增强。`health` 是低调入口（内部入口）：不在帮助与用法列出，可用 `health` 或 `he` 调用，候选可含。

精确别名优先于前缀。未命中别名时，只接受该层唯一前缀。`st` 同时是 `start`、`stop` 和 `status` 的前缀，所以退出 1；`sta` 是 `start` 的别名，`stat` 仍是 `status`。缺了下一层子命令仍打用法清单，不把空串当成歧义。

| 层 | 别名 |
| --- | --- |
| 顶层 | `s` status，`su` sub，`se` service，`sta` start，`sto` stop，`e` ensure，`h` help，`?` help，`n` node，`ne` net，`p` proxy，`r` rule，`re` restart，`c` clean，`he` health |
| node | `g` groups，`l` list，`t` test，`s` switch |
| proxy | `u` user，`sy` system，`se` session |
| sub | `g` get，`r` refresh，`c` clean |
| rule | `l` list，`a` add，`d` del |
| net | `t` test，`i` ip |
| service | `e` enable，`d` disable |

`re`、`ne`、`se` 是顶层精确别名。旧的 `x`、`o`、`k`、`u` 不再识别。

域名规则：无方案、无路径、无问号。前缀 `.` 表示后缀（`DOMAIN-SUFFIX`），否则是整域（`DOMAIN`）。`via` 的策略组必须由调用者写明，不猜测「主组」。

`rule add via` 在服务运行时先向控制器查询组名。组不存在，或这次查询失败，则退出 3，不写 `rules.list`，也不重载。服务未运行时控制器不可用，仍只把规则记下来，启动时再生效。mihomo 遇到未知组会拒绝加载：配置测试报 `proxy [NOTAGROUP] not found`，退出码 1（2026-10-15，真内核实测）。via 把流量送进策略组。这条链已验证（仿真，2026-10-15）：官方 check 的 c 段经由节点，direct 覆盖后走直连。运行中重载未知组时，内核经 API 拒绝，HTTP 400，进程仍在（同一次 check）。

退出码：

| 码 | 含义 |
| --- | --- |
| 0 | 成功。快到期只是提示，仍为 0 |
| 1 | 用法错误。裸 `axs` 也是 1。清理时非交互且没有 `--yes` 也是 1。`axs help` 与 `axs --help` 是 0 |
| 2 | 服务或端口不可用；`start` 与 `ensure` 在端口已被占用时也是 2。`clean` 与 `sub clean` 在服务运行时也是 2 |
| 3 | 拉取、校验、合并、重载失败；组或节点不存在；select 失败；`net test` 至少有一个目标不通；`ensure` 没有订阅地址或刷新失败；清理越界或删除失败。组不存在时不写规则列表。节点不存在时不发 select。越界时一个都不删 |
| 4 | 锁被占用。`ensure` 调用的 refresh 遇锁透传 4 |
| 5 | `status`，以及低调入口 `health`：进程与端口正常、控制器可达，但订阅已过期 |

`node test` 里单个节点超时是结果数据，不是失败。API 本身失败才是 3。`net test` 相反：有目标不通就是 3，见 §10。

## 6. 默认值

只改这一张表，再生成 `run/override.yaml`。

| 项 | 值 |
| --- | --- |
| 模式 | `rule`。订阅自带规则保留 |
| 入站 | 只留 mixed，`7897`，仅回环。与现有 `setproxy` 相同，便于人工桥继续可用 |
| 控制器 | `127.0.0.1:9097` |
| DNS | 开。监听 `127.0.0.1:1053`。用户服务绑不了 53，也不改系统解析 |
| ipv6 | 开 |
| allow-lan | 关 |
| tun | `enable: false` |
| 日志 | info，走 journal。不写订阅与密钥 |
| 刷新 | 12 小时。手动与定时器共用一把锁 |
| 到期提示 | 剩余不足 3 天：`status` 打印警告，退出码仍 0。已过期退出 5 |
| 测速目标 | `https://www.gstatic.com/generate_204` |
| 前置直连 | `localhost`、`local`、`goproxy.cn`，以及 gh-proxy 一类后缀。回环与私网网段由脚本在运行时插入，不写进文档 |
| 密钥 | 本地新生成 |

订阅里的端口、控制器、单独的 http/socks/redir/tproxy、打开的 tun，合并时被上表压掉。映射项只覆盖写明的键，DNS 上游仍留订阅里的值。

## 7. 订阅与规则怎样生效

刷新每次用**刚下载的订阅**重新合并，不往旧配置上叠。顺序：运行时生成的回环与私网直连、覆盖文件里的前置直连、`rules.list`、订阅原规则。

校验至少要看到代理节点列表。拉取失败，或正文为空、类型不对、以 `<` 开头，退出 3，不改 `config.yaml`、订阅正文和 `config.yaml.bak`。合并失败留下旧配置与旧正文。`config.yaml.bak` 是安装前备份：成功安装时写成被替换的那份；重载失败回滚时写成回滚后的好配置。前置校验失败不更新 bak。服务已在跑时，校验通过才调控制器重载；重载失败回滚配置和正文。服务没在跑时，写完配置即停，不重载。

`sub get` 只读 `userinfo`。没有这块缓存就打印「未知」，不当成故障。流量按 B/K/M/G/T 显示，保留 1 位小数。

## 8. 健康与并发

健康不是「节点都能用」。节点死活看 `node test`。

`status` 是唯一状态命令。先打完五节，再退出。优先级：未运行或端口不通是 2，控制器不通是 3，订阅过期是 5，快到期仍是 0。不刷新，不跑延迟，不拉全量节点，不创建 `override.yaml` 或 `secret`。节序是服务、节点、订阅、测试、代理。节标题粗体，标签灰，缩进两格，标签占 8 列。非终端同一布局，没有颜色。

- 服务 / 状态：运行中或未运行，括号里是 systemd 或手动、pid、时长。`运行中` / `未运行` 是一级强调。systemd 时长取 `ActiveEnterTimestamp`，没有就写 `-`
- 服务 / 端口：mixed 监听或不通，同一行写控制器可达或不通。值着色，不加粗
- 服务 / 自启：有 systemd 时是 `enabled` 或 `disabled`，并附 `下次 HH:MM（N 后）`。时间来自 `systemctl list-timers --output=json` 的 `next` 和 `left`。两者都是绝对微秒：`next` 定钟点，`left` 定还要多久。缺一就是 `-`。单调定时器的 `NextElapseUSecRealtime` 为空，不能用它。没有 systemd，这一格是 `-`
- 节点 / 主代理：`→ 中间组 → 叶子`。叶子是一级强调，没有叶子写 `-`。端口或控制器不通时不查 `/proxies`，写 `→ -`
- 节点 / GLOBAL：当前 now，没有写 `-`
- 订阅 / 剩余：天数。已过期、快到期仍是一级强调。流量在括号里，按 B/K/M/G/T，保留 1 位小数。未知写 `未知`。只读 `userinfo`
- 测试 / net、node：距今时间。net 再写全部通或有不通。没有缓存写 `-`
- 代理：见 §11。`on` / `enabled` / `active` 为绿，其余为灰

`node test` 不写组名时，默认组优先「主代理」，否则按名称取第一个 `url-test` / `fallback` / `load-balance`，再否则第一个非 `GLOBAL` 组。都没有则退出 3，并列出剩余组。延迟接口失败只打一行原因。每次真正测完都写缓存。成功时再写一行节点延迟，并丢掉与所测组同名的键。`net test` 只在进入实测后写。预检失败、用法错误、端口不通不写。`status` 只读缓存，不读延迟表。

`health` 是低调入口（内部入口）：不在帮助与用法列出，可用 `health` 或 `he` 调用，候选可含。不对外承诺信息格式。脚本契约：通过时无输出，退出 0。失败时标准错误只有一行：`未运行` 或 `端口不通` 退出 2，`控制器不通` 退出 3，`订阅过期` 退出 5。不读测试缓存，不拉订阅，不跑延迟。快到期仍是静默 0。

| 操作 | 服务未运行 | 服务在运行 |
| --- | --- | --- |
| start | 端口空闲则启动；占用则退出 2，不提示某个具体程序 | 已是本服务则退出 0 |
| stop | 退出 0 | 停止 |
| rule add/del | 只改 `rules.list`，退出 0，并说明启动时生效 | `via` 先查组，通过后才持锁、重复合并、重载。失败则配置和规则列表一起回到改前 |
| refresh | 持锁、拉取、合并、不重载 | 持锁、拉取、合并、重载。失败保留旧配置 |
| 定时器与手动同时 | 后到的退出 4 | 同左 |
| via 的组名不存在 | 规则先记下（此时查不了控制器） | 先查控制器；不存在则退出 3，不写列表、不重载 |

不再探测 Verge。端口冲突一律是「端口已被占用」。

`node list` / `groups` / `switch` / `net test` 不持 `refresh.lock`，也不改 `config.yaml`。`switch` 只打控制器。`ensure` 在服务已跑时也不持锁、不刷新。未跑且没有配置时，锁在它调用的 `refresh` 里，不另加。重载是否留住 `now` 未实测，见 §10。v1.1 不加锁，也不把未测结果写成承诺。

## 9. 测试策略

先有失败测试，再写实现。每个 bug 先加一条能复现它的测试，修完保持为回归。改 `refresh` 或校验顺序的提交，必须跑普通终端 `tests/lab/run.sh check`。只跑离线套件不算过。

夹具输出必须复刻真实命令格式，不得按实现方便编。systemd 夹具同此，与错题本 P7 同族。

v1 基线（不连真实订阅、不启真实进程）：

| 夹具 | 断言 |
| --- | --- |
| ShellCheck | `bin/` 与 `lib/` 的 shell 为 0。合并逻辑用 Python 时另跑语法检查 |
| 假订阅合并 | 模式、入站、DNS 监听、tun 关闭、前置规则只出现一次、密钥来自文件而不是订阅正文 |
| 规则增删 | 服务未运行只改列表；服务在跑且组名不存在时退出 3、列表不变、不重载；其它重载失败时列表与配置都回到改前 |
| 并发锁 | 两路刷新，一路成功，另一路退出 4 |
| 健康样本 | 端口不通为 2；端口通但控制器不通为 3；已过期为 5；三天内到期仍为 0 且无输出。警告只属于 status |
| v1.1 节点列表 | 假 `/proxies`：选中行有 `*`，未选中没有；服务未运行退出 2；控制器失败退出 3；不把节点名写入 `run/` |
| v1.1 当前选择 | `groups` 每行含 `now`。实现时同步旧断言：`tests/lab/run.sh` 的 `grep -x PROXY` 会失败；`tests/run.sh` 的 `grep -q PROXY` 子串仍能过，要改成第一列是组名、第三列是 `now` |
| v1.1 手动切换 | 「组不存在」「节点不存在」与「不是策略组」文案分开，都退出 3，且没有 PUT；两者都在则 PUT select；服务未运行退出 2 |
| v1.1 两条仿真 | ① switch→stop→start→`now`。② switch→`rule add via`（现有夹具会重载）→`now`。都只记录，不断言必须保持 |
| v1.1 连通性 | lab 三态：全通退出 0，一部分不通退出 3，全不通退出 3。`AXS_FORBID_NET=1` 先验全表，有一条违规就整体退出 3，一行不测 |
| v1.1 ensure | 已在跑退出 0 且 pid 不变；无配置且无地址退出 3 且不启动；端口占用退出 2 且不刷新；无配置有地址则先刷新再启动，成功为 0 |

假订阅放在 `tests/fixtures/`，里面没有真实地址。

## 10. v1.1 节点与连通性

契约如下。2026-10-20 已实现。

### 确保可用

`axs ensure`

给登录或开机时用的入口。幂等。`start` 不改：没有 `config.yaml` 仍退出 3，不代为刷新。本命令不安装单元。

没有参数。多一个参数退出 1。成功不另打印。失败沿用 `refresh` / `start` 已有的提示。

| 状态 | 做什么 | 退出码 |
| --- | --- | --- |
| 已在跑 | 不动进程，不刷新，不重载 | 0 |
| 未跑，端口已被占用 | 不刷新，不启动 | 2 |
| 未跑，没有 `config.yaml`，也没有 `subscription.url` | 不启动 | 3 |
| 未跑，没有 `config.yaml`，有地址 | 先 `refresh`，成功再 `start` | 两步都成功才是 0；刷新失败是 3，且不启动 |
| 未跑，已有配置，端口空闲 | 只 `start`，不刷新 | 成功 0；启动失败沿用 `start` |

先看进程，再看端口，然后才可能刷新。端口已经被占时不去拉订阅。已有配置时，每次调用也不刷新。连续两次：第二次若已在跑，退出 0，pid 不变。内层 refresh 遇锁则透传 4，不改成其它码。

字段用制表符分开。节点名常常有空格，不能按空格切。名字里若有制表符，列会对不齐；真订阅出现再改。

### 节点列表

`axs node list [--full]`

服务未运行退出 2。读一次控制器 `GET /proxies`。控制器失败退出 3。不调用延迟接口。不写 `run/`，不写日志。多一个不认识的参数退出 1。

默认按终端宽度排多列。宽度取 `COLUMNS`，没有就 `tput cols`，再没有就是 80。非策略组按名称排序，从 1 编号。同名只占一个号。刷新后编号可能变。East Asian Width 的 W/F 算 2 列，其余算 1。单元格以 4 列标记开头：选中是 `[*] `，否则四个空格。编号和延迟都右对齐，数字不被标记挤动。补到最宽单元格，中间空两格。列数仍是 `(宽度 + 2) // (单元格宽 + 2)`，至少 1。

`[*]` 只打主代理链解析出的叶子，不给其它组的 `now` 打星。沿 `now` 走到具体节点。第一跳是 `URLTest` / `Fallback` / `LoadBalance` 就是自动，标签写成 `url-test` / `fallback` / `load-balance`。否则是手动。自动链和手动链都写出叶子名和编号。走不到叶子写 `→ -`，不写编号。没有主代理，或主代理没有 `now`，首行是 `当前：无`。

```
当前：主代理 → 香港aw3（手动）→ 香港aw3 第3个
当前：主代理 → 自动选择（自动，url-test）→ 新加坡aw1 第48个
最近测速：3 分钟前
```

延迟来自 `run/cache/node-test`，没有就 `-`。第二行时间桶与 `status` 相同。没有测速缓存写 `最近测速：-`。

`--full` 或 `-l` 保持旧的每组一行，给脚本用。不打首行。不打印策略组本身。其余代理都打印，包括 `DIRECT` / `REJECT`。一个节点属于几个组就打几行。没有被任何组的 `all` 收录时，组列写 `-`。

```
[*]<TAB><节点名><TAB><类型><TAB><组名>
```

第一列只有 `*` 或空。`*` 表示这一行的组，其 `now` 就是这个节点。

### 当前选择

`axs node groups`

每个组一行：

```
<组名><TAB><类型><TAB><now>
```

`now` 缺了就写 `-`。类型用控制器原文（`Selector` 等），不翻译。服务未运行退出 2，控制器失败退出 3。只读，不切换。

### 手动切换

`axs node switch <策略组> <节点或编号>`

两个参数。名字有空格就由调用者加引号。参数个数不对退出 1。

第二个参数先看组的 `all` 里有没有同名成员。有就用这个名字，哪怕它是数字。否则纯数字，且 `str(int(token))` 仍等于原文，才按当前全局编号解析。解析出的名字必须在该组 `all` 里，否则「节点不存在」，不发 select。编号不是组内序号，刷新后可能变。

服务未运行退出 2。不能像规则那样先记下来，选择只存在于控制器。

服务在跑时先 `GET /proxies`：

- 组名不在 `/proxies`：退出 3，提示「组不存在」，不发 select。
- 名字在，但不是策略组：退出 3，提示「不是策略组」，不发 select。不要写成「组不存在」。
- 节点不在该组的 `all` 里：退出 3，提示「节点不存在」，不发 select。
- 查询失败：退出 3，不发 select。

通过后 `PUT /proxies/<组名>`，组名做百分号编码。正文是 `{"name":"<节点>"}`。HTTP 2xx 为成功，退出 0，终端打一行 `<组名><TAB><节点><TAB><延迟>`。延迟来自测速缓存，没有就 `-`。其它结果退出 3，不打成功行。

不改 `config.yaml`，不改 `rules.list`，不持刷新锁。非 `Selector` 组也允许发。内核拒绝 PUT 则退出 3。PUT 成功后内核又自动改回，本工具不追，退出 0。那是组类型自己的行为，不是切换失败。

仿真只记录，不断言必须保持。测完把结果和日期写回本段。未测之前不要写成已经保持。

1. `store-selected` 跨重启：switch → stop → start → 看 `now`。不在 `override.yaml` 里改这个键，测的是内核默认。**未实测**。
2. 重载是否留住 `now`：switch → `rule add via`（现有夹具会重载）→ 看 `now`。不新造订阅。**未实测**。不预设恢复或提示。

### 自动选择原则

本工具不做自动切换。选谁，由订阅里该组的类型交给内核：

| 订阅写法 | 控制器类型 | 谁选 |
| --- | --- | --- |
| `select` | `Selector` | 人通过 `switch`。`now` 能否留下，未实测 |
| `url-test` | `URLTest` | 内核按延迟。`node test` 只提供延迟，不代选 |
| `fallback` | `Fallback` | 内核按可用性，当前不可用才换。不代选 |
| `load-balance` | `LoadBalance` | 内核在成员间分流。不代选 |

`Relay` 内核有，订阅表里不单列。本工具不给它加策略，只显示 `now`。

`list` 和 `groups` 不改 `now`。`node test` 不调用 select。`switch` 是唯一会改 `now` 的命令，而且只在操作者写明组和节点时执行。

重载是否保留 `now`：**未实测**。不要从本表读出「重载会留下」或「重载会清掉」。

`url-test` 的测速地址是订阅或内核自己的，不是 `net test` 的网址表。两套不要混用。

### 端到端连通性

`axs net test [url ...]`

这不是 `node test`。`node test` 问控制器某个节点的延迟。本命令经本机 mixed 入站，看这条代理出口能不能打开目标。不导出代理变量，不改其它命令的环境。mixed 不通退出 2，此时还没测网址。

目标，前者覆盖后者：

1. 命令行给了 url，就只用这些，不追加默认表。
2. 否则若 `run/urls` 至少有一行有效网址，用这个文件。
3. 否则用这三个：`https://www.github.com`、`https://www.google.com`、`https://www.youtube.com`。

这三个是公开地址，可以写在本文。它们不进 `override.yaml`。`run/urls` 一行一个，空行和 `#` 开头忽略，权限 0600，不入库。文件里的地址可能是私有的，其它命令不打印它。

不是 `http` 或 `https` 就退出 1，一个都不测。避免坏文件被看成网络故障。

每个目标超时 5 秒，失败再试 1 次。两次都失败才是不通。延迟是成功那一次的毫秒数，整数。不通的延迟写 `-`。收到任意 HTTP 响应就算通，包括 3xx 和 4xx。超时、连接失败、TLS 失败算不通。

测试可设 `AXS_NET_TIMEOUT_MS`（毫秒）。未设置就是 5000。这是夹具钩子，不是用户参数。

输出只到终端，一行一个目标：

```
通<TAB><毫秒><TAB><url>
不通<TAB>-<TAB><url>
```

全通退出 0。有一个不通，包括全不通，退出 3。不把结果写入日志或 `run/`。

开测前先验全表，通过后才拨号。不是 `http`/`https` 已在上面退出 1、一行不测。`AXS_FORBID_NET=1` 时再验主机名：有一条不是 `127.0.0.1`、`localhost`、`::1`，整体退出 3，一行不测，不拨号。不要测完合法的那几条再退出。仿真三态用命令行传入 lab 的本地网址：立即 204 为通，不回答或马上断开为不通。默认公网表不出现在离线夹具里。

### 清理

`axs clean [--yes]`

删运行态：`config.yaml`、`config.yaml.bak`、`userinfo`、`fetch.yaml`、`fetch.hdr`、`mihomo.pid`。保留 `subscription.url`、`secret`、`rules.list`、`override.yaml`。不删 `subscription.yaml`（订阅正文缓存，归 `sub clean`）、`urls`、锁和快照。

`axs sub clean [--yes]`

删订阅：`subscription.url`、`subscription.yaml`（上次订阅正文缓存）、`userinfo`、`fetch.yaml`、`fetch.hdr`。保留 `config.yaml`。要连配置一起清，先 `sub clean` 再 `clean`。

两边一样：

- 服务在跑就拒绝，退出 2，提示先 `axs stop`。不删。
- 只删上面这些名字。解析后的路径必须仍在 `run/` 里。符号链接指向外面则整次拒绝，退出 3，一个都不删。
- 没有 `--yes` 时，先把将删的已存在路径逐行打到标准输出。不是终端就退出 1。是终端再问 `确认删除？[y/N]`，只有 `y` 或 `yes` 才删。
- `--yes` 跳过确认。成功不打印。
- 名单里不存在的文件跳过。因此删不存在的也是 0。
- 删除本身失败退出 3。

### 实现放行清单

2026-10-20 已实现。两条仿真测完再把结果写回上面，未测之前仍是未实测。

- `node list`、`node groups`（带 `now`）、`node switch`、`net test`、`ensure`
- `tests/lab/lab.py` 增加第二个假节点。回环另一端口，或端口 9 空壳。`switch` 只验选择，不向该节点拨号
- 同步 `groups` 旧断言：`tests/lab/run.sh` 的 `grep -x PROXY`，以及 `tests/run.sh` 里只查子串 `PROXY` 的那条
- 两条仿真只记录：switch → stop → start → `now`；switch → `rule add via` → `now`
- 改 `refresh` 或校验顺序必跑普通终端 `tests/lab/run.sh check`。只跑离线套件不算过

## 11. 三层代理接入

服务始终只监听 `127.0.0.1:<mixed>`；三层只是告诉谁去连它。

| 子命令 | 层 | 机制 | 契约 |
| --- | --- | --- | --- |
| `axs proxy user on` | 终端 | 环境变量 | 输出去 stdout（供 `eval "$(axs proxy user on)"`）；http/https/all/no proxy 大小写各一份，与 setproxy 对齐 |
| `axs proxy user off` | 终端 | 环境变量 | 输出 unset 行 |
| `axs proxy user status` | 终端 | 读环境变量 | 指向本代理打印 `on` 退 0，否则 `off` 退 1 |
| `axs proxy system on` | 指定应用 | gsettings 运行时 | mode=manual + http/https host/port + ignore-hosts；不写标识开关；无 gsettings 退 3 |
| `axs proxy system off` | 指定应用 | gsettings 运行时 | mode=none（不做 schema 级 reset）；不删标识开关 |
| `axs proxy system status` | 指定应用 | 运行时 + 持久 + dwm 环境 | 运行时 `on` 退 0，否则 `off` 退 1。持久为 `enabled` 或 `disabled`。dwm 的 `XDG_CURRENT_DESKTOP` 含 `GNOME` 打印 `effective`，否则 `pending`；没有 dwm 为 `no x session` |
| `axs proxy system enable` | 指定应用 | 标识开关 | 写 `run/proxy-system.flag`（0600）；重登 X 后导出桌面标识 |
| `axs proxy system disable` | 指定应用 | 标识开关 | 删标识开关 |
| `axs proxy session enable` | X 会话 | 开关文件 `run/proxy-session.flag`（空文件，0600） | 只作存在性开关；下次登录 X 生效。`on`/`off` 已移除 |
| `axs proxy session disable` | X 会话 | 删开关文件 | — |
| `axs proxy session status` | X 会话 | 开关 + dwm 环境 | 开关不在为 `disabled`，effect `-`，退 1；开关在但当前会话没有代理变量为 `pending` 退 1；已注入为 `active` 退 0；没有 dwm 且开关在为 `no-x-session` |

- xprofile 托管块（`# axs proxy session (managed)`，dwm 启动前）：条件导出
  http/https/all/no proxy；安装需判重（幂等）；
- no_proxy 只含 `localhost,127.0.0.1,::1`：私网段与 goproxy/gh-proxy 例外由 mihomo
  规则承载，不进环境变量（裁决，非疏漏）；
- 端口一律取 `override.yaml` 的 mixed-port，不写死；
- 三层都不改变 mihomo 服务本身；`die` 用法错误退 1。
- `axs status` 的代理节是三行。`persist disabled` 时 effect 为 `-`，不写 `no-x-session`。`pending` 只在 persist enabled 且当前会话还没注入时出现。已注入是 `active`。没有 dwm 且 persist enabled 才是 `no-x-session`。`on` / `enabled` / `active` 为绿，其余为灰：

```
  user    on|off
  system  on|off（persist enabled|disabled）
  session persist enabled|disabled · effect active|pending|-|no-x-session
```

- 读 dwm 用 `pgrep -x dwm` 的 `/proc/<pid>/environ`。`AXS_SESSION_PID` 可指定进程，供测试。没有进程或读不到，且持久开关开着，effect 是 `no-x-session`。
- `axs net ip`：经 mixed 入站请求 `https://ipinfo.io/ip`，输出代理出口 IP；入站不通退 2，
  查询失败退 3。
- system 层前提：libproxy 的 gnome 插件与 Edge 都要会话里有 `XDG_CURRENT_DESKTOP=GNOME` 才读 gsettings；没有标识时是 direct。推荐浏览器用 session 层。
- 条件式标识：`proxy system enable` 写 `run/proxy-system.flag`。xprofile 托管块 `# axs proxy system identity (managed)` 只在开关存在时导出 `XDG_CURRENT_DESKTOP=GNOME`，插入判重；重登 X 生效。`disable` 删开关。`on`/`off` 只改 gsettings，不再碰这个开关。旧脚本若靠 `on` 建开关，要改成 `enable`。
- `.flag` 后缀表示存在性开关，只看文件在不在：`run/proxy-session.flag`、`run/proxy-system.flag`。`enable` 会删掉改名前的旧文件。
- 副作用：该标识会让部分应用把会话当成 GNOME（桌面集成行为可能变化）。
- `axs proxy user on` 在标准错误打一行「需 eval」提示；标准输出仍是可 eval 的 export 行。
