# 安装测试系统

本文面向 Agent 和维护者。

## 概述

基于 Bats（Bash Automated Testing System）的自动化测试框架，覆盖安装系统全部功能：状态检测、备份逻辑、所有状态转换路径、卸载恢复、统一 CLI 和端到端生命周期验证。

### 设计目标

1. **完整性**：覆盖所有状态转换路径、边界条件和错误处理
2. **隔离性**：每个测试在临时 `$HOME` 目录中运行，不影响真实配置
3. **可重复性**：结果确定且可重复，支持回归测试
4. **自动化**：支持本地和 CI 环境
5. **可追溯**：TAP 格式输出，便于问题定位

---

## 测试框架

### Bats 环境

- **Bats 版本**：>= 1.11.0
- **运行命令**：`bats -r .local/share/test/`（全部）或 `bats .local/share/test/installation/`（单个专题）
- **过滤运行**：`bats --filter "TC-11" .local/share/test/installation/`
- **TAP 输出**：`bats -r .local/share/test/ --tap`（CI 适用）

### 环境隔离

每个测试在独立的临时 `$HOME` 中运行：

```bash
setup_test_home() {
    TEST_HOME=$(mktemp -d "/tmp/dotfiles-test-XXXXXX")
    export HOME="$TEST_HOME"
    export GIT_CONFIG_GLOBAL="$TEST_HOME/.gitconfig-test"
    export GIT_CONFIG_SYSTEM=/dev/null
    export DOTFILES_LIB_DIR="$REAL_HOME/.local/lib/dotfiles"
    export DOTCFG_BIN_DIR="$DOTFILES_ROOT/.local/bin"
}
```

**安全保障**：
- `REAL_HOME` 在加载时保存，永远不被修改
- `teardown_test_home()` 有安全检查：拒绝删除 `REAL_HOME`，只删除 `/tmp/dotfiles-test-*` 路径
- Git 配置隔离：`GIT_CONFIG_GLOBAL` 指向独立文件，`GIT_CONFIG_SYSTEM=/dev/null`

### Git 仓库源策略

测试默认在 `/tmp` 中创建临时 bare 源仓库，不读取或修改真实 `~/.cfg/`：

```bash
setup_source_repo() # 创建带签名文件的测试源仓库，设置 DOTFILES_REPOSITORY
setup_bootstrap_env() # 从当前工作树构造自举安装用的临时 remote
```

需要真实远程行为时，应在独立测试环境中显式提供 `DOTFILES_REPOSITORY`；常规回归不依赖网络。

---

## 测试文件结构

```
.local/share/test/
└── installation/               ← 安装系统专题
    ├── helpers.bash            ← 共享辅助函数和隔离环境
    ├── node-backup.bats        ← 普通节点备份逻辑
    ├── bootstrap.bats          ← 自举安装
    ├── categories.bats         ← category 解析、继承和排除
    ├── commands-lifecycle.bats ← 生命周期命令集成
    ├── config-boundary.bats    ← 配置驱动与固定语义边界
    ├── config-versions.bats    ← category 配置版本和元数据管理
    ├── deploy-undeploy.bats    ← 节点部署与撤销
    ├── detect-state.bats       ← 状态检测
    ├── doctor-repair.bats      ← 完整性诊断与修复
    ├── dotcfg.bats             ← 统一 CLI、帮助与 TAG 行为
    ├── e2e-state-machine.bats  ← 端到端生命周期
    ├── exclude-rules.bats      ← Fresh 排除和跟踪判断
    ├── fresh.bats              ← Fresh 混合备份与管理命令
    ├── history.bats            ← 节点历史图
    ├── switch-full.bats        ← full 切换（含旧 switch-desktop 兼容）
    ├── switch-min.bats         ← min 切换（含旧 switch-server 兼容）
    ├── switch-macos.bats       ← macos 切换
    ├── migration.bats          ← 旧会话迁移到节点系统
    ├── nodes.bats              ← 节点数据结构
    ├── nodes-lifecycle.bats    ← 节点状态和删除生命周期
    ├── refactor-contract.bats  ← 重构期间的用户接口契约
    ├── uninstall.bats          ← 卸载与恢复
    ├── validate.bats           ← 仓库验证
    └── generate-conflicts.sh   ← 冲突文件生成器
```

测试文件属于配置库的可复现验证基础设施，必须全部被 `.cfg` 跟踪；新增或恢复测试后先用
`git --git-dir="$HOME/.cfg" ls-files .local/share/test/installation/` 核对纳管状态，再运行套件。
当前目录包含 `nodes-lifecycle.bats`、`refactor-contract.bats` 等新增回归用例，不依赖真实
`$HOME`，也不应把测试产物或缓存加入仓库。

---

## 测试用例目录

### TC-01..03：状态检测（detect-state.bats）

| 用例 | 描述 |
|------|------|
| TC-01 | 无 `.cfg` → fresh |
| TC-02a..02d | `.cfg` + 图形指标（.xinitrc / .xprofile / .config/x11/xinitrc / 符号链接）→ full |
| TC-03a..03b | `.cfg` 无图形指标 → min |
| TC-03c | 空 `.config/x11/` 目录不是图形指标，仍判定为 min |
| TC-03d | HEAD 节点类型为 macos 时，节点元数据优先于图形兼容指标 |
| TC-03e | category 版本元数据提供自定义状态指标 |

### TC-04..10：节点备份逻辑（node-backup.bats）

| 用例 | 描述 |
|------|------|
| TC-04 | 文件不存在 → 跳过备份 |
| TC-05 | 文件存在但未跟踪 → 备份 |
| TC-06 | 文件已跟踪但已修改 → 备份 |
| TC-07 | 文件已跟踪且相同 → 跳过 |
| TC-07b | 符号链接按链接文本与 Git blob 比较，不跟随目标内容 |
| TC-08 | 备份目录命名约定 `(fresh\|desktop\|server)-to-(fresh\|desktop\|server)-[0-9]{8}T[0-9]{6}` |
| TC-09 | 备份目录权限 0700 |
| TC-10 | MANIFEST 格式：`relative_path\tmd5\tstatus`（tab 分隔） |

### TC-11..16：Fresh full 切换（switch-full.bats）

| 用例 | 描述 |
|------|------|
| TC-11 | fresh `switch full`：创建 .cfg，checkout 所有文件 |
| TC-12 | 备份已有用户文件到 `.config-backup/` |
| TC-13 | `--dry-run` 预览不修改 |
| TC-14 | `--force` 替换有效仓库（备份旧仓库） |
| TC-15 | checkout state 文件记录所有跟踪文件 |
| TC-16 | `showUntrackedFiles = no` 配置 |

### TC-17..21：Fresh min 切换（switch-min.bats）

| 用例 | 描述 |
|------|------|
| TC-17 | fresh `switch min`：只 checkout 命令行 category 文件 |
| TC-18 | 备份已有用户文件 |
| TC-19 | `--dry-run` 预览 |
| TC-20 | 白名单排除桌面文件 |
| TC-21 | checkout state 和 git 配置 |

### TC-SF01..SF07：已有状态切换到 full（switch-full.bats）

| 用例 | 描述 |
|------|------|
| TC-SF01 | min → full：添加全量文件 |
| TC-SF02 | 备份已修改文件 |
| TC-SF03 | `--dry-run` 预览 |
| TC-SF04 | `--auto-stash` 覆盖不备份 |
| TC-SF05 | fresh → full 的统一入口 |
| TC-SF06 | full 状态接受 `--reinstall` |
| TC-SF07 | 旧 `switch-desktop.sh` wrapper 仍固定转发 full |

### TC-SM01..SM07：已有状态切换到 min（switch-min.bats）

| 用例 | 描述 |
|------|------|
| TC-SM01 | full → min：移除 category 差集，验证命令行文件 |
| TC-SM02 | 备份已修改桌面文件 |
| TC-SM03 | `--dry-run` 预览 |
| TC-SM04 | checkout state 和 git 配置更新 |
| TC-SM05 | fresh → min 的统一入口 |
| TC-SM06 | min 状态接受 `--reinstall` |
| TC-SM07 | 旧 `switch-server.sh` wrapper 仍固定转发 min |

### TC-MC01..MC04：macos 切换（switch-macos.bats）

覆盖跨平台核心 category 的 fresh 安装、冲突备份、dry-run，以及从 full 移除非核心文件。

### TC-30..33, TC-38..44b：卸载与恢复（uninstall.bats）

| 用例 | 描述 |
|------|------|
| TC-30 | 移除所有 checkout 文件，同时保留 dotcfg 命令与运行库 |
| TC-31 | 从最早备份恢复用户文件，并保持符号链接类型和链接文本 |
| TC-32 | `--dry-run` 预览 |
| TC-33 | 无仓库时报错 |
| TC-38 | 移除 checkout state 文件 |
| TC-39 | `--latest` 恢复最新版本 |
| TC-40 | 多转换链：从所有会话恢复文件 |
| TC-41 | 幂等性：两次卸载结果相同 |
| TC-43 | 无备份的管理文件直接删除 |
| TC-44/44b | 按目录名时间戳选择最早/最新备份，不受 mtime 干扰 |

### TC-34..35：仓库验证（validate.bats）

| 用例 | 描述 |
|------|------|
| TC-34a..34k | `cfg_validate` 各种仓库状态分类（missing/not_git/foreign_repo/valid） |
| TC-35 | 库不可用时回退到内联验证 |

### TC-36..39：端到端生命周期（e2e-state-machine.bats）

| 用例 | 描述 |
|------|------|
| TC-36 | fresh → full → min → full → fresh（完整循环） |
| TC-37 | fresh → min → full → min → fresh（反向循环） |
| TC-38 | full → min 移除普通 `.local/bin` 脚本及其 checkout state 项，保留 dotcfg 安装基础设施 |
| TC-39 | switch 先读取 `CURRENT_CONFIG_VERSION`，再按该版本的 category 选择文件 |

### TC-B01..B03：自举安装（bootstrap.bats）

| 用例 | 描述 |
|------|------|
| TC-B01 | 空 HOME 自举安装、建立 Fresh；冲突备份保持符号链接，基础设施不进入 category |
| TC-B02 | 拒绝覆盖外部仓库 |
| TC-B03 | 重复执行自举保持幂等 |

### TC-C01..C16：category 解析（categories.bats）

覆盖 `macos/min/full` 默认分类、普通名称与唯一保留名称的边界、继承、增删项、循环引用、目录路径、
排除规则和分类差异。TC-C16 逐项比较内置回退与 `categories-1.0.0.conf`，防止两份定义漂移。
测试使用隔离的库副本，不写入真实 `DOTFILES_LIB_DIR`。

### TC-CV01..CV12：配置版本与元数据（config-versions.bats）

覆盖版本发现、空目录成功返回、语义版本排序、头部元数据、按版本加载、缺失版本回退，以及
`full` 的保留语义和 `empty` 的普通名称语义。TC-CV08 验证版本文件改变后，显式失效可刷新版本
发现和元数据缓存；TC-CV09..CV12 分别锁定 `VALID_TAGS`、`CATEGORY_ALIASES`、`STATE_DEFAULT`
和 `STATE_INDICATORS` 的配置驱动行为，其中 CV10 同时验证 `switch cli` 的成功与缺失别名时报错。

### TC-CB01..CB05：配置驱动边界（config-boundary.bats）

固定配置存在时的 category 定义、配置缺失时的内置回退、`full` 动态展开及不可覆盖语义，并验证
`.local/bin/dotcfg` 和 `.local/lib/dotfiles/` 安装基础设施在所有 category 中保持不变。

### TC-CL01..CL09：命令生命周期（commands-lifecycle.bats）

覆盖节点 `remove/unremove/autoclean` 和 `categories list/show/current/switch`。子进程修改索引后，
测试显式失效父进程缓存再验证持久化结果。TC-CL08 验证 `categories list` 不把动态 `full` 计入普通
category 数量且版本不带 `v` 前缀；TC-CL09 固定 `categories show` 的 full 动态标记。

### TC-NL01..NL07：节点生命周期（nodes-lifecycle.bats）

覆盖配置版本和状态字段持久化、标记、删除、孤立子节点查询，以及旧格式 `index.json` 的默认值兼容。

### TC-D01..DS02：部署与撤销（deploy-undeploy.bats）

覆盖 HEAD 缺失、重复部署、强制部署、Fresh 节点、dry-run、状态更新和撤销恢复；其中 TC-U03
验证符号链接按链接本身恢复，TC-DS02 验证撤销后 dotcfg 命令与运行库仍存在。

### TC-D01..D06：诊断与修复（doctor-repair.bats）

覆盖健康状态、HEAD 和部署状态修复、启动自检提示，以及备份根或节点存储缺失时重建索引并立即
重新加载节点数据。

### TC-ST09、TC-45..63：统一 CLI（dotcfg.bats）

| 用例 | 描述 |
|------|------|
| TC-ST09 | status：输出不包含 `Available operations`，命令帮助独立展示 |
| TC-45 | status：full 状态检测（含节点信息） |
| TC-46 | status：min 状态检测（含节点信息） |
| TC-47 | list：无节点时显示提示 |
| TC-48 | list：显示节点表头 |
| TC-49 | history：无节点时显示"No history" |
| TC-50 | history：自动迁移后显示节点树 |
| TC-51 | history：跳过畸形目录名 |
| TC-52 | `switch fresh`：解析根节点别名；根节点不存在时报错 |
| TC-53 | switch：无效目标报错 |
| TC-54 | `switch full` 通过统一切换实现完成安装 |
| TC-55 | `switch full` 到 `min` 完成切换 |
| TC-56 | switch：`--dry-run` 透传 |
| TC-56b | switch：`desktop` 被配置为普通 category 后可正常使用 |
| TC-57 | validate：仓库验证详情 |
| TC-58 | 默认 status + 未知子命令报错 |
| TC-59 | 顶层和子命令 `--help` 与 `dotcfg help` 输出一致 |
| TC-60 | TAG 列表标记、切换提示、版本删除和节点删除警告 |
| TC-61 | 正式 `1.0.0 stable` 只展示 full、min、macos，未定义的 desktop/server 不被映射 |
| TC-62 | `fresh-adopt-legacy --help` 展示完整调用参数 |
| TC-63 | `categories show` 将 full 标记为动态全部跟踪文件且不显示数量 |

### TC-L01..L05 / TC-H01..H07：节点清单与历史图（history.bats）

覆盖节点列表表头、节点类型、HEAD 标记、节点代码、空记录、线性与分支历史图以及部署状态。
TC-H07 固定验证 `bootstrap` 是特殊版本标识，历史图不会错误添加 `v` 前缀。

### TC-N01..N30：节点索引（nodes.bats）

覆盖节点创建、读取、父子关系、HEAD、部署状态、迁移检测和索引持久化。TC-N29 验证进程内
`code -> index` 缓存可读取节点；TC-N30 验证外部修改索引后，显式失效可重新加载磁盘数据。

### TC-R01..R07：重构接口契约（refactor-contract.bats）

锁定 `dotcfg help` 的完整文本、`check-exclude` 的兼容标签、`categories show` 的 `full` 动态标记，
未知切换目标的错误文字和返回码，以及 help 不加载业务库。TC-R06 验证长 category 和版本号不会
破坏 `list` 列对齐；TC-R07 检查所有已知参数缺失和未知子命令分支只输出错误，usage 仅由帮助入口
显示。后续内部重构不得无意改变这些用户可见行为。

### TC-E01..E09：Fresh 排除规则（exclude-rules.bats）

覆盖安装保护、兼容排除区段、普通 `exclude.conf` 规则、绝对路径拒绝和仓库跟踪判断。TC-E06 固定验证
`.config-backup.bak` 以及 Microsoft Edge、NVM、Chromium、Chrome for Testing 可变状态不会进入
Fresh 选择集；TC-E07 验证配置缺失时 Linux 与 macOS 规则的默认回退；TC-E08 验证兼容区段和用户
规则的文案标签；TC-E09 覆盖 macOS 标准用户目录和 Finder 元数据，并验证显式跟踪的
`Library/...` 配置仍可由 `full` 部署、进入 Fresh，且 30 项配置与回退完全一致。

### TC-F01..F12：Fresh 根节点（fresh.bats）

覆盖 5 列 manifest、track/untrack、统计、diff、update、根节点保护和 `switch fresh`。TC-F12 先
验证旧备份采纳 dry-run 不创建元数据，再验证只复制旧备份中的跟踪原件和当前未跟踪配置，跳过
当前跟踪文件、浏览器状态并保持急救备份不变；同时验证符号链接备份及单路径 `fresh-diff` 均按
链接文本处理。

### TC-M01..M18：旧会话迁移（migration.bats）

| 用例 | 描述 |
|------|------|
| TC-M01 | 无旧会话时迁移提示无需操作 |
| TC-M02 | 已迁移时提示已完成 |
| TC-M03 | 单个会话迁移：创建根节点 + 子节点，并保留历史 `desktop` type |
| TC-M04 | 多个会话按时间顺序迁移，并保留历史 `desktop/server` type |
| TC-M05 | 迁移后父链正确 |
| TC-M06 | 迁移后 HEAD 设为最后节点 |
| TC-M07 | 迁移复制备份文件到节点目录 |
| TC-M08 | 迁移复制 MANIFEST 到 manifest.txt |
| TC-M09 | 旧会话移入 sessions/ 归档 |
| TC-M10 | 迁移后 DEPLOY_STATUS 为 deployed |
| TC-M11 | `--dry-run` 预览迁移计划 |
| TC-M12 | 非会话目录被忽略 |
| TC-M13 | 自动迁移在 dotcfg status 前触发 |
| TC-M14 | help 命令不触发自动迁移 |
| TC-M15 | version 命令不触发自动迁移 |
| TC-M16 | 迁移后父子链接正确 |
| TC-M17 | 节点备份与文件目录正确创建 |
| TC-M18 | 显式 `dotcfg migrate` 执行迁移 |

---

## 辅助函数

### 状态模拟

| 函数 | 用途 |
|------|------|
| `setup_source_repo [files...]` | 创建测试源仓库（含签名文件），设置 `DOTFILES_REPOSITORY` |
| `create_valid_existing_cfg [files...]` | 创建通过 `cfg_validate` 的 `.cfg` 仓库 |
| `setup_installed_state()` | 模拟完整安装（clone + checkout + state 文件） |
| `create_mock_cfg_repo [files...]` | 轻量 bare repo（用于单元测试） |
| `create_mock_cfg_repo_with_remote <url> [files...]` | 带 remote URL 的 mock repo |

### 脚本执行

| 函数 | 用途 |
|------|------|
| `run_switch_full [args...]` | 运行统一 `dotcfg switch full` |
| `run_switch_min [args...]` | 运行统一 `dotcfg switch min` |
| `run_switch_macos [args...]` | 运行统一 `dotcfg switch macos` |
| `run_legacy_switch_full [args...]` | 运行旧 `switch-desktop.sh` wrapper，验证兼容转发 full |
| `run_legacy_switch_min [args...]` | 运行旧 `switch-server.sh` wrapper，验证兼容转发 min |
| `run_install_desktop/server`、`run_restore_desktop/server` | 端到端和卸载旧流程仍使用的兼容辅助入口 |
| `run_uninstall [args...]` | `yes \| yes \| bash uninstall.sh` |
| `run_dotcfg [args...]` | `bash dotcfg` |

### 断言函数

| 函数 | 用途 |
|------|------|
| `assert_state_is <state>` | 验证当前状态（fresh/full/min/macos） |
| `assert_cfg_exists` / `assert_cfg_not_exists` | `.cfg` 存在性 |
| `assert_file_exists` / `assert_file_not_exists` | 文件存在性 |
| `assert_file_contains <path> <pattern>` | 文件内容匹配 |
| `assert_node_backup_exists` | 节点备份目录存在 |
| `assert_node_backup_contains <path>` | 节点备份中包含指定相对路径 |
| `assert_node_backup_count <n>` | 节点备份目录数量 |
| `assert_node_manifest_exists` | 任意节点 manifest.txt 存在 |
| `assert_backup_count <n>` | 旧式备份目录数量（兼容测试） |
| `assert_backup_naming <name>` | 命名约定匹配 |
| `assert_checkout_state_exists` / `assert_checkout_state_not_exists` | checkout state 文件 |
| `assert_show_untracked_no` | git 配置验证 |
| `assert_output_contains <pattern>` | 命令输出匹配 |

---

## 测试执行

### 本地运行

```bash
# 运行全部测试（递归扫描子目录）
bats -r .local/share/test/

# 只运行仓库跟踪的安装系统测试（不受本机未跟踪夹具影响）
bats $(git --git-dir="$HOME/.cfg" --work-tree="$HOME" \
    ls-files '.local/share/test/installation/*.bats')

# 运行单个专题
bats .local/share/test/installation/

# 过滤特定用例
bats --filter "TC-36" .local/share/test/installation/

# TAP 格式（CI 适用）
bats -r .local/share/test/ --tap
```

### 当前测试结果

**验证环境**：2026-08-12 在[平台档案索引](../platforms/index.md)所列当前 Debian 平台执行；
Bats 满足本文 `>= 1.11.0` 的前置要求。

```
Total:  271
Passed: 271
Failed: 0
```

---

## 已知限制

1. **SSH 密钥依赖**：只有显式测试真实远程时才需要有效的 GitHub SSH 密钥
2. **网络要求**：默认测试使用本地临时仓库，不需要网络；真实远程验证另行准备网络环境
3. **磁盘空间**：每个测试约占用 50-100MB
4. **并行限制**：不建议同时运行超过 5 个测试实例（Git lock 冲突）

---

## 相关文档

- [安装系统](installation-system.md) — 安装系统设计文档（v3.0 节点系统）
- [安装系统修复记录](../planning/installation-fixes.md) — 已知问题和修复方案
- [依赖清单](dependencies.md) — 项目依赖的软件包

---

**最后更新**: 2026-08-12
**版本**: 5.5 — 271 个受管测试 + 配置驱动边界 + full/min/macos 切换专题
