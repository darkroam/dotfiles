# 访问子系统 · 文件结构

本文是文件怎么摆的唯一说明。行为在 [access-design.md](access-design.md)。术语与规则见 [access-design.md](access-design.md#模型与术语)。命令表在 `axs help`。

## 形态

入口是薄 shell：`bin/axs` 找到实现根，把该目录放进模块路径，再 `exec python3 -m axs`。逻辑在 `axs/`。不新增依赖，继续用已经在用的 PyYAML。`bin/mihomo-run` 仍是 shell，只校验 PID、写下 PID 文件、exec 内核。

## 并入

代码在 dotfiles 的 `.local/lib/access/`。包是该目录下的 `axs/`。测试在 `.local/share/test/access/`。六份文档在 `.local/share/docs/project/`，文件名以 `access-` 开头。PATH 入口是相对链接 `.local/bin/axs` → `../lib/access/bin/axs`。

`run/` 与 `.local/share/test/access/lab/var/` 不入库。根 `.gitignore` 忽略 `.local/lib/access/run/`、`.local/share/test/access/lab/var/` 和 `.local/share/test/access/**/__pycache__/`。实现目录的 `.gitignore` 再忽略 `run/`、`__pycache__/` 与 `*.pyc`。

只读归档是 `~/src/access-2026-10-28.git`。撤回并入用 `git revert -m 1 <subtree merge>`，不要用不带 `-m` 的 revert。

### C5

默认 `git status --short` 没有输出。`git -c status.showUntrackedFiles=normal status --short -- .local/lib/access .local/share/test/access` 为空。normal 下这两处以外的其余路径是 dotfiles 既有账，不算 access 失败。

## 依赖

只向下。没有同层斜边。`from axs.service import` 只允许出现在 `cli.py`、`nodecmd.py` 与 `status.py`。`view` 不引用 `service`，`service` 不引用 `view`。

```
bin/axs  bin/mihomo-run
    |
   cli
    |
 nodecmd    status
    |
 service    speed
    |
  view
    |
 proxy
    |
 proxylan
    |
 subscription    rules
    |
 progress    subslist
    |
 routes
    |
 net    nodes    rulelist
    |
 profile
    |
 core    render    mihomo
    |
 config    codes    catalog
```

`render` 只读 `catalog`，除此之外不得引用任何 axs 模块。`catalog` 不引用任何 axs 模块：命令树、帮助节、签名，以及第一层路由表（值是字符串）。`profile` 合并订阅与 override，并保存规则类型词与来源比较。`mihomo` 只做控制器 HTTP。`view` 把数据画成屏幕，不发控制器请求，不测速，不启停。`speed` 做节点与组测速。`status` 画状态页，启停仍在 `service`。`nodecmd` 编排 node 与 group 的视图命令，需要控制器数据时由它去取。

锁、持锁和进程存活只来自 `core`。入站端口是否打开只来自 `net`。内核路径、内置网段、规则类型词和原子写只来自 `config`。重载请求只来自 `mihomo`。

| 模块 | 拥有 | 不拥有 |
| --- | --- | --- |
| catalog | 命令树、帮助节、签名、第一层路由字符串 | 解析、分发、排版、业务模块 |
| profile | 合并配置、规则类型词、来源比较 | 拉取、控制器 |
| view | 可选树、完整拓扑、状态页排版、列表与测速行 | 控制器请求、测速、启停 |
| speed | 叶子测速与组测速 | 切换、改配置、画状态页 |
| status | 顶层状态与 `service status` 页 | 启停、ensure、clean |
| service | 启停、ensure、health、clean | 状态页、视图 |
| nodecmd | node/group 视图命令编排 | 画具体屏幕、测速 |

## 目录

不另建 `logs/`、`tmp/`、`generated/`。帮助在运行时打出，不落成仓库文件。缓存仍在 `run/cache/`。

## 文件

行数是警戒线，不是拆分指令。触顶先停下来过堂，不自动拆。

| 文件 | 职责 | 警戒 |
| --- | --- | --- |
| `bin/axs` | 找到根目录并 exec Python | 30 行 |
| `bin/mihomo-run` | 校验 PID，原子写 PID，exec 内核 | 30 行 |
| `axs/__init__.py` | 包标记 | 20 行 |
| `axs/__main__.py` | 记下真实终端，再调 cli | 40 行 |
| `axs/codes.py` | 退出码常量 | 20 行 |
| `axs/catalog.py` | 命令树、帮助节、签名、第一层路由字符串 | 200 行 |
| `axs/cli.py` | 前缀解析、用法、按路由表分发 | 400 行 |
| `axs/config.py` | 默认值、路径、端口、内核路径、内置网段、规则类型词、原子写 | 220 行 |
| `axs/core.py` | 锁、持锁、进程存活、安装、快照、systemd、会话探测 | 400 行 |
| `axs/render.py` | 颜色、对齐、帮助排版。命令树在 catalog | 300 行 |
| `axs/mihomo.py` | 控制器 HTTP。不是内核二进制 | 250 行 |
| `axs/profile.py` | 合并配置与规则来源比较。不拉取 | 200 行 |
| `axs/net.py` | 连通、出口、入站是否打开 | 250 行 |
| `axs/nodes.py` | 编号、切换、测速缓存 | 330 行 |
| `axs/rulelist.py` | `RID`、来源分类、`rule show` 行、删除参数解析 | 200 行 |
| `axs/routes.py` | 规则目标链与条数，以及 select 的根。不排版 | 160 行 |
| `axs/progress.py` | 可复用进度条。非 TTY 不输出 | 100 行 |
| `axs/subslist.py` | 订阅列表的解析与写入。不拉取 | 200 行 |
| `axs/subscription.py` | 拉取、校验、安装与回滚。合并在 profile | 400 行 |
| `axs/rules.py` | 规则增删、安装回滚 | 250 行 |
| `axs/proxylan.py` | 局域网监听。不改三层开关 | 150 行 |
| `axs/proxy.py` | 三层开关和状态词 | 300 行 |
| `axs/view.py` | 屏幕。不发请求、不测速、不启停 | 500 行 |
| `axs/speed.py` | 节点与组测速 | 400 行 |
| `axs/service.py` | 启停、ensure、health、clean | 250 行 |
| `axs/nodecmd.py` | node/group 视图命令编排 | 180 行 |
| `axs/status.py` | 状态页。不启停 | 200 行 |
| `units/*` | 已安装单元的模板。外部行为不改 | 各 40 行 |
| `.local/share/test/access/run.sh` | 先单元，再集成。不含 lab | 40 行 |
| `.local/share/test/access/unit/test_<模块>.py` | 该模块的断言 | 警戒 400 行；`test_rules.py` 450 |
| `.local/share/test/access/unit/test_render.py` | help、usage、别名着色。解析仍在 `test_cli.py` | 警戒 200 行 |
| `.local/share/test/access/integration/<模块>.sh` | 该模块的假环境断言 | 警戒 400 行 |
| `.local/share/test/access/lab/run.sh` | 真内核场景驱动 | 警戒 450 行 |
| `.local/share/test/access/lab/lab.py` | 回环替身 | 警戒 400 行 |
| `.local/share/test/access/lab/audit.py` | 内核套接字审计 | 警戒 400 行 |
| `.local/share/test/access/fixtures/fake-*` | 一个真实命令一个文件 | 各 80 行 |
| `.local/share/test/access/golden/<命令>--<状态>.txt` | 无色快照 | 单份 200 行 |
| `.local/share/test/access/support/prep.py` | 造临时运行目录 | 40 行 |
| `.local/share/test/access/support/snap.py` | 重打或比对 golden | 120 行 |
| `.local/share/docs/project/access-system.md` | 使用者看：怎么用、契约在哪 | — |
| `.local/share/docs/project/access-design.md` | 维护者看的行为契约 | — |
| `.local/share/docs/project/access-architecture.md` | 本文件。文件结构只写在这里 | — |
| `.local/share/docs/project/access-constraints.md` | 隐私、仓库边界、回滚、明确不做 | — |
| `.local/share/docs/project/access-roadmap.md` | 还没授权的事 | — |
| `.local/share/docs/project/access-testing.md` | 离线套件与 lab | — |

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
- golden：`AXS_COLOR=never` 的纯文本，逐字节比对。63 份 `.txt` = 62 份 `cases.json` 重放 + `network-test--ok.txt` 单测专用。
- lab：能 bind 的环境里跑真内核。不进 `.local/share/test/access/run.sh`。
- 离线套件里的裸数字退出只减不增。

快照和夹具不写真实订阅、密钥、节点名。测试用的运行目录放系统临时目录或 `.local/share/test/access/lab/var/`，不入库。
