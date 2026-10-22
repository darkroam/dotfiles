# 访问子系统 · 重构架构（R31 阶段 1）

> 状态：设计稿。阶段 2 之前不改行为代码，不建重构分支，不改活体检出。
> 现行契约仍是 `design.md`（默认值、子命令、退出码）。本文件只定目标结构。阶段 3 把仍需要的段落并回 `design.md`，然后删除本文件。
> 基线：本地 git `dd9985b`。行为等价相对这一提交。盘点全文在 R31 汇报。文件怎么摆，只以第 10 章为准。

## 1. 语言与依赖

| 选项 | 做法 | 取舍 |
| --- | --- | --- |
| A. 维持现状 | `bin/axs` 继续 source `common.sh`，重活留在 `merge.py` | 零迁移。冗余留着：命令表、颜色、读端口各有两份 |
| B. 薄 shell + 现有 Python | 用户入口仍是 `bin/axs`。命令、渲染、服务、订阅都进现在这块 Python。shell 只负责找到根目录并 exec | 一次进程做完现在多次 `python3 -c` 的事。不新依赖 |
| C. 改成 Go | 与 mihomo 同一语言，编一个静态二进制 | 不共享 mihomo 的代码。多一套编译。订阅合并和测试要重写 |

建议用 B。

- 启动时延：未计时。慢在 shell 路径上反复拉起解释器（读端口、探活、状态各节），不在 shell 语法本身。收成一次 Python 进程即可。不值得为这件事换语言。
- 无依赖：继续用已经在用的 PyYAML。不新增包，不写依赖清单。
- 可测试性：`merge.py` 已经能被测试直接 import。shell 里的别名、颜色、状态行现在只能靠起子进程。这些纯函数搬进 Python 后，用现有的 `python3` 断言测，不引入新的测试框架。
- `bin/mihomo-run` 保持 shell。它只校验 PID、原子写下 PID 文件、再 exec 内核。用 Python 重写更长，没有收益。

不采纳 C。也不把入口改成别的语言。

## 2. 模块边界

依赖只向下。上层不被下层调用。

```
bin/axs  bin/mihomo-run
    |
   cli
    |
 service  subscription  rules  nodes  net  proxy
    |
   core ---------------- mihomo
    |                      |
 config                  config

render 不在这条链上。只有 cli 和各命令模块为了输出才调用它。
```

| 模块 | 拥有 | 不拥有 |
| --- | --- | --- |
| config | 路径、`run/` 文件名、默认值、端口与控制器地址的唯一读取 | 不打网络，不着色 |
| render | 颜色码、对齐、status 与帮助的排版 | 不读订阅，不打控制器 |
| core | 锁、原子安装、快照与回滚、systemd 探测缓存 | 不解析订阅，不画输出，不调用命令模块 |
| mihomo | 控制器 HTTP、探活、重载请求 | 不决定回滚，不读规则语义 |
| service | 启停、health、清理名单、status 编排 | 不解析订阅正文，不自己实现锁 |
| subscription | 拉取、校验、合并、流量与到期 | 不画 status |
| rules | `rules.list`，以及「合并后安装、重载、失败回滚」这条链 | 不自己读端口，不把锁再写一遍 |
| nodes | 组、列表、延迟、切换 | 不改 `config.yaml` |
| net | 连通性、出口地址 | 不写订阅 |
| proxy | 三层开关与 status 用词 | 不改 mihomo 进程 |
| cli | 命令表、别名、分发、退出码名 | 不被下层调用 |

阶段 2 按这些边界搬家，不顺手改算法。一个模块一个文件。文件名、上限和哪一步搬，见第 10 章。

允许的唯一斜向调用：`rules` 可以调用 `subscription` 的合并函数。`subscription` 不得调用 `rules`。除此以外，同层互不 import。刷新和改规则各自编排「合并、安装、重载、回滚」，用的锁和快照只来自 `core`，重载请求只来自 `mihomo`。

现在就要收口的重复（阶段 2 做，本阶段只登记）：

- 命令字面量写了三处：`bin/axs` 的分发表、`show_usage`、`show_help`。文档再写一份。
- 颜色有两套：shell 的 `tone` 与 `merge.py` 的 `ansi`，色码相同。
- 读端口有四条：`read_ports`、`load_status_ports`、`api_addr`、`proxy_mixed`。只有 `load_status_ports` 在没有覆盖文件时用字面量兜底。
- `paint` 无调用。删。
- `restore_bak` 无调用。删函数。`config.yaml.bak` 仍由 `install_file` 和 `restore_snapshot` 维护，文件契约不变。

`merge.py` 里 `group_names` 与 `show_groups` 都留：一个只出名字，一个带当前选择。不是死代码。

## 3. 单一权威源

权威在代码常量，不在散文。

| 事实 | 唯一位置 | 其它地方 |
| --- | --- | --- |
| 命令、别名、帮助短句、是否低调入口 | cli 的一张表 | `axs help` / 用法从这张表生成。design 不再抄表 |
| 退出码 | cli 的一张表：用法 1，未运行或端口 2，控制器或校验 3，锁 4，过期 5 | 调用点用名字，不写裸数字 |
| 默认值 | config 的一份字典 | design 只写键和策略（回环、TUN 关、不改系统解析）。不复制字面量 |
| 颜色语义 | render 的一张表 | shell 不再定义色码 |

`health` 留在分发表，标记为低调入口：帮助和用法不列出，全名和 `k` 仍可用，前缀候选仍可出现。这是现行为，不是新开关。

阶段 3 之前，design 仍是给人读的契约。阶段 2 用测试把「生成的帮助」锁在现在的文案上，避免两份权威同时改。阶段 3 再删 design 里的重复表。

## 4. 测试分层

不引入新框架。离线总入口仍是 `sh tests/run.sh`。真内核检查在阶段 2 最后一步改为 `sh tests/lab/run.sh check`（现为 `tests/env/run.sh`）。目录名以第 10 章为准。

| 层 | 测什么 | 落点 |
| --- | --- | --- |
| 单元 | 别名与前缀、合并、规则行、颜色、时间跨度、定时器 JSON | 直接 import。现有 `tests/check_merge.py` 是这一层的样子 |
| 集成 | 假 systemd、假控制器、假 gsettings、假拉取 | 现有 `tests/run.sh`。阶段 2 按模块拆文件，一个入口跑完。断言跟着搬家，不改预期 |
| lab | 真内核、回环替身、回滚、锁、via/direct | `tests/env/`。只改被测入口，不改场景 |
| 冒烟 | 真会话里的 status、三层开关、重登后的 flag | 阶段 4 的人工清单。不进默认回归 |

夹具纪律（沿用 design 已有的一条，并写死）：假命令的输出复刻真实工具的字段，不为了好解析而改名。systemd 用 `list-timers --output=json` 的 `next` / `left`。每个假命令文件头注明它模仿哪条真实命令。

已知失真，阶段 2 不得再扩大：

- 离线控制器是目录替身，不是 HTTP。编码与状态码要靠 lab 补。
- `fake-systemctl` 的 `show` 只回两个属性，不是完整的 systemctl 文本。
- `fake-mihomo` 只睡眠，不说控制器协议。
- `check_merge.py` 与 `prep_run.py` 自己写入端口。默认值收口后，这两处必须改读 config 常量，否则字面量会假绿。
- `lab.py` 里还有一份合并自检，和 `check_merge.py` 重叠。阶段 2 留一份。

## 5. 迁移与兼容

保持，不另做兼容层：

- 用户能敲的命令、单字符别名、唯一前缀、歧义时退出 1 并列出候选。
- 退出码含义，见 §3。
- `run/` 的文件名、权限、两个存在性开关的路径。主仓库登录脚本按这两个路径工作；本轮不改主仓库。
- `proxy session` 只有 enable / disable / status。`proxy system on` 不写开关。
- enable 时删掉改名前的旧开关文件。
- 不把地址、密钥、节点名写进文档、提交和日志。

已经删掉的 `session on|off` 保持不存在。不为旧习惯加别名。

## 6. 文档结构

阶段 3 才改下面四份。不另建 `file-layout.md`、运维手册或决策记录。文档子树见第 10 章。

| 文件 | 只写 | 不写 |
| --- | --- | --- |
| design.md | 行为契约：谁在什么状态下做什么、退出码、代理三层 | 目录漫游、历史门禁、第二份命令表 |
| constraints.md | 隐私、不进主仓库、回滚、明确不做 | 透明性长文、health 口径（改由 design 与帮助一处说明） |
| README.md | 是什么、测试怎么跑、契约在哪 | 「未跟踪」。改成：主仓库不跟踪，本目录有本地 git |
| roadmap.md | 还没授权的事 | 已经落地的功能说明 |
| 本文件 | 重构目标 | 阶段 3 之后删除 |

同一事实只出现在上表的「只写」列。帮助文本不算第二份文档，它从命令表生成。

## 7. 版本与分支

- 阶段 2 开工时从本设计提交拉 `refactor/2026-10`。本阶段不拉。
- 活体工作树的检出恒为 `master`。用户服务和刷新定时器的 `ExecStart` 指向这棵树，切走就会跑未验收的代码。
- 重构提交只进该分支，并且只在另一个 worktree 里做。worktree 不放进本目录，用完即删。
- 分支验证只用测试树：单独的 `AXS_RUN` 和假命令。不用活体的 `run/`。
- 若必须拿分支里的 `bin` 对真机试跑，先停刷新定时器和服务，试完回到 `master` 再启用。
- 回滚：丢掉该分支，或把它重置到本设计提交。不改写 `dd9985b` 及更早的历史。
- 本地 git，无远端。不推送。主仓库本轮不提交。
- 每步重构都要能在该提交上跑通当时的离线套件。不允许堆积一个跑不过的大提交。

## 8. 验收

阶段 2 结束时：

- 离线套件与改前同一批断言通过。允许改的只有导入路径和「假绿字面量改读常量」。
- 能 bind 的环境下，lab 检查通过。第 9 步起路径是 `tests/lab/run.sh`；在那之前仍是 `tests/env/run.sh`。
- `axs help` 的命令、别名和短句与 `dd9985b` 一致。着色可以换实现，词不能换。
- `run/` 不出现新的开关文件名。
- 订阅地址、密钥、具体端口不出现在新增文档和提交说明里。

阶段 4 再做真会话冒烟。阶段 2 不把冒烟失败当成设计错误。

切割顺序以第 10 章的迁移表为准。本节不再另列一套步骤。

另两条验收：

- 步 0 打下的 `tests/golden/` 之后每步逐字节对上。例外只允许第 10.4 节写明的那几条。
- 离线套件禁止新增裸数字退出。存量在退出码改名时只减不增。

## 9. 不做

新功能、TUN、多条订阅、开机前代理、改 mihomo 参数、改已安装单元的外部行为、把本子系统放进主仓库。范围外的问题只登记，不在重构里顺手修。

## 10. 文件架构

这章是项目文件怎么摆的唯一说明。文档只是其中的 `docs/` 子树。阶段 2 之前不创建这些路径，不移动现文件。

### 10.1 目录

```
bin/axs                      用户入口。路径冻住
bin/mihomo-run               内核包装。路径冻住
lib/axs/                     Python 包。逻辑只放这里
units/                       单元模板。文件名冻住
tests/run.sh                 离线总入口。只转调，不写断言
tests/unit/                  直接 import 的断言
tests/integration/           假命令、假控制器下跑 bin/axs
tests/lab/                   真内核。现 tests/env/
tests/fixtures/              假命令与假订阅
tests/golden/                纯文本快照。入库，不是临时文件
tests/support/               造运行目录、打快照。不是测试
docs/                        见 10.7
run/                         运行时。不入库
```

不新增 `logs/`、`tmp/`、`generated/`。帮助在运行时从命令表打出，不落成仓库里的帮助文件。控制器与合并的缓存仍在 `run/cache/`。

`run/`、`__pycache__/`、`*.pyc` 继续忽略。`tests/env/var/` 在 lab 搬家时改成 `tests/lab/var/`。

### 10.2 每个文件

上限是天花板，不是目标。到了就按本表已有的模块拆，不发明新层。一行一种职责。

| 文件 | 处置 | 职责 | 上限 |
| --- | --- | --- | --- |
| `bin/axs` | 保留，改薄 | 找到根目录，把 `lib/` 放进模块路径，`exec python3 -m axs` | 30 行 |
| `bin/mihomo-run` | 保留 | 校验 PID，原子写 PID 文件，exec 内核。单元文件指着这个路径 | 30 行 |
| `lib/axs/__init__.py` | 新增 | 包标记。不放逻辑 | 20 行 |
| `lib/axs/__main__.py` | 新增 | 进程入口，只调 cli | 40 行 |
| `lib/axs/cli.py` | 新增 | 命令表、别名、前缀、分发、退出码名 | 400 行 |
| `lib/axs/render.py` | 新增 | 颜色、对齐、帮助和 status 的排版 | 300 行 |
| `lib/axs/config.py` | 新增 | 默认值、路径、端口与控制器地址的唯一读取 | 200 行 |
| `lib/axs/core.py` | 新增 | 锁、原子安装、快照与回滚、systemd 探测缓存 | 400 行 |
| `lib/axs/mihomo.py` | 新增 | 控制器 HTTP、探活、重载请求。不是内核二进制 | 300 行 |
| `lib/axs/service.py` | 新增 | 启停、重启、ensure、health、清理、status 编排 | 400 行 |
| `lib/axs/subscription.py` | 新增 | 拉取、校验、合并、流量与到期 | 400 行 |
| `lib/axs/rules.py` | 新增 | 规则增删，以及合并后的安装、重载、回滚 | 250 行 |
| `lib/axs/nodes.py` | 新增 | 组、列表、延迟、切换、测速缓存 | 400 行 |
| `lib/axs/net.py` | 新增 | 连通性与出口地址 | 250 行 |
| `lib/axs/proxy.py` | 新增 | 三层代理的开关和状态词 | 300 行 |
| `lib/common.sh` | 拆完删除 | 现有 shell 实现 | 迁完即为 0 |
| `lib/merge.py` | 拆完删除 | 现有 Python 实现 | 迁完即为 0 |
| `units/*.service` `units/*.timer` | 保留 | 已安装单元的模板。外部行为不改 | 各 40 行 |
| `tests/run.sh` | 保留，改薄 | 先单元，再集成。不含 lab | 40 行 |
| `tests/unit/test_<模块>.py` | 新增 | 一个模块一个文件 | 各 400 行 |
| `tests/integration/<模块>.sh` | 新增 | 该模块的假环境断言 | 各 400 行 |
| `tests/lab/run.sh` | 由 `tests/env/run.sh` 移入 | 真内核场景驱动 | 450 行 |
| `tests/lab/lab.py` | 由 `tests/env/lab.py` 拆出 | 回环替身 | 400 行 |
| `tests/lab/audit.py` | 由 `lab.py` 拆出 | 内核套接字审计 | 400 行 |
| `tests/fixtures/fake-*` | 由 `tests/fake-*` 移入 | 一个真实命令一个文件 | 各 80 行 |
| `tests/fixtures/subscription.yaml` | 保留 | 假订阅 | 维持现状 |
| `tests/golden/<命令>--<状态>.txt` | 新增 | 无色纯文本快照 | 单份 200 行 |
| `tests/support/prep.py` | 由 `tests/prep_run.py` 移入 | 造临时运行目录 | 40 行 |
| `tests/support/snap.py` | 新增 | 重打 golden。测试只做 diff | 120 行 |

`tests/check_merge.py` 并入 `tests/unit/test_subscription.py` 后删除。`lab.py` 里的第二份合并自检一并删除，不进 `audit.py`。

### 10.3 命名

- 包内文件名就是模块名，不加前缀。
- 函数用小写加下划线，动词开头。退出码只在 `cli.py` 起名，调用点用名字。
- 颜色函数只在 `render.py` 定义。端口和默认值的字面量只在 `config.py` 出现。`run/` 里每个文件名的字符串也只在 `config.py` 出现。
- 已有的 `AXS_*` 环境变量不改名。不新增第二套同义变量。
- 测试文件 `test_<模块>.py`。夹具 `fake-<真实命令>`。快照 `<命令>--<状态>.txt`，名字里没有空格。
- 禁止两个文件定义同名函数。禁止留下 `common` 或 `merge` 这种转发层。函数搬走的那个提交里，旧文件必须失去它。

### 10.4 测试与夹具

- 单元：import 包，不启动子进程。别名矩阵、合并、规则行、颜色、定时器 JSON、退出码守卫在这里。
- 集成：跑 `bin/axs`，控制器仍是目录替身，systemd、gsettings、拉取都用夹具。
- lab：真内核。不进 `tests/run.sh`。
- golden：步 0 从当前行为抓住，存无色文本。之后每步 `diff`。允许的差异只有：导入路径、测试改读 `config` 常量、以及本表写明要删的死代码。

每个 `tests/fixtures/fake-*` 头两行写明它模仿的真实命令和字段名。字段名不准为了好解析而改。假 systemd 的定时器仍是 JSON 的 `next` 与 `left`。

步 0 另加一条守卫：仓库里裸数字退出的数量只减不增。现有调用在改名时消去，不在新代码里再写。

### 10.5 生成物与临时区

| 东西 | 放哪 | 入库 |
| --- | --- | --- |
| 帮助文本 | 运行时从命令表打出 | 否 |
| 命令参考 | 阶段 3 若要给人读，由同一张表生成 `docs/reference.md`，禁止手改 | 阶段 3 才有 |
| golden | `tests/golden/` | 是 |
| 订阅、密钥、PID、开关、缓存 | `run/` | 否 |
| 测试用运行目录 | 系统临时目录，或 `tests/lab/var/` | 否 |
| 字节码 | `__pycache__/` | 否 |
| 日志 | 不建目录。内核写在它自己的运行目录里 | 否 |
| 死代码调用清单 | R31 汇报 | 不进本仓库 |

快照和夹具里不写真实订阅、密钥、节点名。

### 10.6 迁移

活体树不切分支。步骤在 worktree 里做，一步一个提交。

| 步 | 新建或改 | 从现文件抽走 | 同时删 |
| --- | --- | --- | --- |
| 0 | `tests/golden/`、`tests/support/snap.py`、`tests/unit/test_cli.py` 的别名矩阵、裸退出守卫 | 不抽 | 不删。调用清单写入汇报 |
| 1 | `cli.py`、`render.py`、`__init__.py`、`__main__.py`；`bin/axs` 改薄 | `common.sh` 的解析、用法、帮助、颜色 | 这些函数。命令实现还留着 |
| 2 | `config.py`、`core.py` | 四条读端口、锁、安装、快照、systemd 模式缓存 | `paint`、`restore_bak`。备份文件的行为不变 |
| 3 | `mihomo.py` | `merge.py` 的请求、探活、重载、版本 | 旧请求函数 |
| 4 | `subscription.py`；其单元测试吃掉 `check_merge.py` | 合并、拉取、流量；`cmd_sub_*`、`cmd_refresh` | `check_merge.py`。两处自带端口改读 `config` |
| 5 | `rules.py` | 两边的规则函数 | 旧规则函数 |
| 6 | `nodes.py` | 组、列表、延迟、切换 | 旧函数 |
| 7 | `net.py` | 连通与出口 | 旧函数 |
| 8 | `proxy.py` | 三层代理 | 旧函数 |
| 9 | `service.py`；`tests/run.sh` 改成总入口；集成按模块剪开；`tests/env/` 改为 `tests/lab/`，审计拆出 | 启停、status、health、清理 | `common.sh`、`merge.py`、`prep_run.py`、lab 里的第二份合并自检 |

每步先让该步的 golden 和单元断言对着旧行为变红或锁住，再搬。不把两步并进一个提交。

### 10.7 文档子树

位置都在 `docs/`，不新建目录。阶段 1 的四份边界仍然有效。

| 文件 | 处置 | 读者 |
| --- | --- | --- |
| `README.md` | 保留。阶段 3 改「未跟踪」的说法，并写明 python3 是全部命令的依赖 | 使用者 |
| `design.md` | 保留为行为契约。阶段 3 删重复的命令表和过期句子 | 维护者 |
| `constraints.md` | 保留隐私、不入库、回滚 | 维护者 |
| `roadmap.md` | 保留未授权项 | 维护者 |
| `architecture.md` | 本设计。阶段 3 删除 | 维护者 |
| `reference.md` | 现在不创建。阶段 3 若创建，只能由命令表生成 | 使用者 |

盘点里 9 条不一致的去向，销项在阶段 3，不在本阶段改原文：

| 条 | 去向 |
| --- | --- |
| 1. design 写不另加登录脚本，后文又要求托管块 | 删前一句。以后文和实现为准 |
| 2. 功能清单仍像最小闭环 | 改成已落地的能力，或改成指向帮助。不留第二份命令表 |
| 3. 一处说缓存不记节点名，另一处要记 | 以实现为准：可记节点名到延迟，不记组名、地址、密钥 |
| 4. 健康样本写「含警告」，契约和测试是成功时无输出 | 删「含警告」。警告只属于 status |
| 5. 目录树缺包装器与单元 | 不再在 design 里画树。树只在本章 |
| 6. README 写未跟踪 | 改成：主仓库不跟踪，本目录有本地 git |
| 7. roadmap 停在视觉收口 | 删已经落地的功能说明，不把本轮过程写进去 |
| 8. constraints 复述透明性、开关和 health | 删这些段，改留一句「见 design」 |
| 9. 「还没测」「孵化中」 | 删过期句 |

阶段 2 结束时，design 里的旧测试路径可以暂时过期。阶段 3 再改。不为本阶段加转发脚本。
