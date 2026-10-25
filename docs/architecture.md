# 访问子系统 · 文件结构

本文是文件怎么摆的唯一说明。行为在 [design.md](design.md)。术语与规则见 [design.md](design.md#模型与术语)。命令表在 `axs help`。

## 形态

入口是薄 shell：`bin/axs` 找到根目录，把 `lib/` 放进模块路径，再 `exec python3 -m axs`。逻辑在 `lib/axs/`。不新增依赖，继续用已经在用的 PyYAML。`bin/mihomo-run` 仍是 shell，只校验 PID、写下 PID 文件、exec 内核。

## 并入

并入 dotfiles 时，再把包从 `lib/axs/` 迁到顶层 `axs/`，并改入口的模块路径。在那之前保持现在的位置。不在本文件之外另写一份布局。

## 依赖

只向下。上层不被下层调用。`from axs.service import` 只允许出现在 `cli.py`。

```
bin/axs  bin/mihomo-run
    |
   cli
    |
 tree     service
    |
 subscription  rules  proxy
    |
  net   nodes   rulelist
    |
 core ---------------- mihomo
    |
 config              codes
```

`render` 不在这条链上，也不得引用任何 axs 模块。为了输出调用它，不算斜边。`service` 是编排，可以调用它下面的模块。命令模块不调用 `service`。`tree` 只被 `cli` 调用。

斜边台账：

| 从 | 到 | 原因 |
| --- | --- | --- |
| rules | subscription | 合并后的安装复用订阅模块 |

反向不行。import 只能指向更下层，或台账里的这一条。锁、持锁和进程存活只来自 `core`。入站端口是否打开只来自 `net`。内核路径、内置网段和原子写只来自 `config`。重载请求只来自 `mihomo`。

| 模块 | 拥有 | 不拥有 |
| --- | --- | --- |
| config | 路径、`run/` 文件名、默认值、端口、控制器地址、内核路径、内置网段、原子写 | 网络、颜色 |
| render | 颜色、对齐、帮助和 status 的排版 | 任何 axs 模块 |
| core | 锁、持锁、进程存活、安装、快照与回滚、systemd 探测、会话 environ | 订阅正文、命令模块、端口探测、原子写 |
| mihomo | 控制器 HTTP、探活、重载请求 | 回滚、规则语义 |
| service | 启停、health、清理、status 编排 | 订阅解析、锁、进程探测、端口探测 |
| subscription | 拉取、校验、合并、流量与到期 | status 排版 |
| rulelist | `RID`、来源分类、`rule show` 行、删除参数解析 | 安装、重载、回滚 |
| rules | 规则增删，以及合并后的安装、重载、回滚 | 读端口、再写一遍锁、`RID` |
| nodes | 组、列表、延迟、切换、测速缓存 | 改配置 |
| net | 连通性、出口地址、入站是否打开 | 写订阅 |
| proxy | 三层开关和状态词 | 改内核进程 |
| cli | 命令表、别名、分发 | 被下层调用 |
| codes | 退出码常量 | 任何其它逻辑 |

## 目录

```
bin/axs                      用户入口。路径冻住
bin/mihomo-run               内核包装。路径冻住
lib/axs/                     Python 包
units/                       单元模板。文件名冻住
tests/run.sh                 离线总入口。只转调
tests/unit/                  直接 import
tests/integration/           假命令下跑 bin/axs
tests/lab/                   真内核
tests/fixtures/              假命令与假订阅
tests/golden/                纯文本快照。入库
tests/support/               造运行目录、对快照。不是测试
docs/                        本目录的五份说明
run/                         运行时。不入库
```

不另建 `logs/`、`tmp/`、`generated/`。帮助在运行时打出，不落成仓库文件。缓存仍在 `run/cache/`。忽略 `run/`、`__pycache__/`、`*.pyc`、`tests/lab/var/`。

## 文件

上限是天花板，不是目标。到了就按上面的模块拆，不发明新层。

| 文件 | 职责 | 上限 |
| --- | --- | --- |
| `bin/axs` | 找到根目录并 exec Python | 30 行 |
| `bin/mihomo-run` | 校验 PID，原子写 PID，exec 内核 | 30 行 |
| `lib/axs/__init__.py` | 包标记 | 20 行 |
| `lib/axs/__main__.py` | 记下真实终端，再调 cli | 40 行 |
| `lib/axs/codes.py` | 退出码常量 | 20 行 |
| `lib/axs/cli.py` | 命令表、别名、前缀、分发 | 400 行 |
| `lib/axs/render.py` | 颜色、对齐、帮助排版（`SECTIONS`/`help_text`） | 300 行 |
| `lib/axs/config.py` | 默认值、路径、端口、内核路径、内置网段、原子写 | 200 行 |
| `lib/axs/core.py` | 锁、持锁、进程存活、安装、快照、systemd、会话探测 | 400 行 |
| `lib/axs/mihomo.py` | 控制器 HTTP，规则类型词和来源表。不是内核二进制 | 300 行 |
| `lib/axs/service.py` | 启停、ensure、health、清理、status | 400 行 |
| `lib/axs/subscription.py` | 拉取、校验、合并、流量与到期 | 400 行 |
| `lib/axs/rulelist.py` | `RID`、来源分类、`rule show` 行、删除参数解析 | 200 行 |
| `lib/axs/rules.py` | 规则增删、安装回滚 | 220 行 |
| `lib/axs/nodes.py` | 组、列表、延迟、切换 | 400 行 |
| `lib/axs/tree.py` | `node list` 的树，以及 `node members` 表。编号仍问 nodes | 250 行 |
| `lib/axs/net.py` | 连通、出口、入站是否打开 | 250 行 |
| `lib/axs/proxy.py` | 三层开关和状态词 | 300 行 |
| `units/*` | 已安装单元的模板。外部行为不改 | 各 40 行 |
| `tests/run.sh` | 先单元，再集成。不含 lab | 40 行 |
| `tests/unit/test_<模块>.py` | 该模块的 import 断言 | 各 400 行；`test_rules.py` 450 |
| `tests/integration/<模块>.sh` | 该模块的假环境断言 | 各 400 行 |
| `tests/lab/run.sh` | 真内核场景驱动 | 450 行 |
| `tests/lab/lab.py` | 回环替身 | 400 行 |
| `tests/lab/audit.py` | 内核套接字审计 | 400 行 |
| `tests/fixtures/fake-*` | 一个真实命令一个文件 | 各 80 行 |
| `tests/golden/<命令>--<状态>.txt` | 无色快照 | 单份 200 行 |
| `tests/support/prep.py` | 造临时运行目录 | 40 行 |
| `tests/support/snap.py` | 重打或比对 golden | 120 行 |
| `docs/README.md` | 使用者看：怎么用、怎么测、契约在哪 | — |
| `docs/design.md` | 维护者看的行为契约 | — |
| `docs/constraints.md` | 隐私、不入库、回滚、明确不做 | — |
| `docs/roadmap.md` | 还没授权的事 | — |
| `docs/architecture.md` | 本文件。文件结构只写在这里 | — |

不另建命令参考。要看命令，跑 `axs help`。

## 命名

- 包内文件名就是模块名。函数小写加下划线，动词开头。
- 退出码常量只在 `codes.py`。颜色函数只在 `render.py`。端口、默认值和 `run/` 文件名的字面量只在 `config.py`。
- 已有的 `AXS_*` 不改名，不新增第二套同义变量。
- 测试文件 `test_<模块>.py`。夹具 `fake-<真实命令>`。快照 `<命令>--<状态>.txt`。
- 不留 `common.sh` 或 `merge.py` 这种转发层。

## 测试

- 单元：import 包，不启动子进程。
- 集成：假命令、假控制器下跑 `bin/axs`。假命令的输出复刻真实工具的字段。systemd 定时器用 JSON 的 `next` 与 `left`。
- golden：`AXS_COLOR=never` 的纯文本，逐字节比对。例外只存在于当时的提交说明，不在这里再开一张过程表。步 22：`--select` 自动组行尾改为「自动·手选会被覆盖」，只重打 `node-list--select`。
- lab：能 bind 的环境里跑真内核。不进 `tests/run.sh`。
- 离线套件里的裸数字退出只减不增。

快照和夹具不写真实订阅、密钥、节点名。测试用的运行目录放系统临时目录或 `tests/lab/var/`，不入库。
