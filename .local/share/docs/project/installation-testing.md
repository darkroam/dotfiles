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

**模式 A：本地 Git Mirror（默认）**

从真实 `~/.cfg/` 归档创建本地 bare mirror，不依赖网络：

```bash
setup_git_mirror()  # 创建 /tmp/dotfiles-test-git-mirror/dotfiles.git
setup_source_repo() # 创建带签名文件的测试源仓库，设置 DOTFILES_REPOSITORY
```

**模式 B：真实远程仓库**

```bash
export USE_REAL_REMOTE=true  # 使用真实 GitHub 远程
```

---

## 测试文件结构

```
.local/share/test/
└── installation/               ← 安装系统专题
    ├── helpers.bash            ← 共享辅助函数和隔离环境
    ├── backup-logic.bats       ← 普通节点备份逻辑
    ├── bootstrap.bats          ← 自举安装
    ├── categories.bats         ← category 解析、继承和排除
    ├── commands-lifecycle.bats ← 生命周期命令集成
    ├── config-versions.bats    ← category 配置版本管理
    ├── deploy-undeploy.bats    ← 节点部署与撤销
    ├── detect-state.bats       ← 状态检测
    ├── doctor-repair.bats      ← 完整性诊断与修复
    ├── dotcfg.bats             ← 统一 CLI、帮助与 TAG 行为
    ├── e2e-state-machine.bats  ← 端到端生命周期
    ├── exclude-rules.bats      ← Fresh 排除和跟踪判断
    ├── fresh-node.bats         ← Fresh 混合备份与管理命令
    ├── history-graph.bats      ← 节点历史图
    ├── install-desktop.bats    ← full 兼容入口安装
    ├── install-server.bats     ← min 兼容入口安装
    ├── migration.bats          ← 旧会话迁移到节点系统
    ├── nodes.bats              ← 节点数据结构
    ├── nodes-lifecycle.bats    ← 节点状态和删除生命周期
    ├── restore-desktop.bats    ← 切换到 full 的兼容入口
    ├── restore-server.bats     ← 切换到 min 的兼容入口
    ├── refactor-contract.bats  ← 重构期间的用户接口契约
    ├── uninstall.bats          ← 卸载与恢复
    ├── validate.bats           ← 仓库验证
    └── generate-conflicts.sh   ← 冲突文件生成器
```

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

### TC-04..10：备份逻辑（backup-logic.bats）

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

### TC-11..16：全量安装（install-desktop.bats → 兼容入口映射到 `--type=full`）

| 用例 | 描述 |
|------|------|
| TC-11 | fresh 安装：创建 .cfg，checkout 所有文件 |
| TC-12 | 备份已有用户文件到 `.config-backup/` |
| TC-13 | `--dry-run` 预览不修改 |
| TC-14 | `--force` 替换有效仓库（备份旧仓库） |
| TC-15 | checkout state 文件记录所有跟踪文件 |
| TC-16 | `showUntrackedFiles = no` 配置 |

### TC-17..21：最小安装（install-server.bats → 兼容入口映射到 `--type=min`）

| 用例 | 描述 |
|------|------|
| TC-17 | fresh 安装：只 checkout 服务器白名单文件 |
| TC-18 | 备份已有用户文件 |
| TC-19 | `--dry-run` 预览 |
| TC-20 | 白名单排除桌面文件 |
| TC-21 | checkout state 和 git 配置 |

### TC-22..26b：切换到 full（restore-desktop.bats → 兼容入口）

| 用例 | 描述 |
|------|------|
| TC-22 | min → full：添加全量文件 |
| TC-23 | 备份已修改文件 |
| TC-24 | `--dry-run` 预览 |
| TC-25 | `--auto-stash` 覆盖不备份 |

### TC-27..30b：切换到 min（restore-server.bats → 兼容入口）

| 用例 | 描述 |
|------|------|
| TC-26 | full → min：移除 category 差集，验证命令行文件 |
| TC-27 | 备份已修改桌面文件 |
| TC-28 | `--dry-run` 预览 |
| TC-29 | checkout state 和 git 配置更新 |

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

### TC-C01..C15：category 解析（categories.bats）

覆盖 `macos/min/full` 默认分类、旧 `server/desktop` 名称兼容、继承、增删项、循环引用、目录路径、
排除规则和分类差异。测试使用隔离的库副本，不写入真实 `DOTFILES_LIB_DIR`。

### TC-CV01..CV08：配置版本（config-versions.bats）

覆盖版本发现、空目录成功返回、语义版本排序、头部元数据、按版本加载、缺失版本回退，以及
`full`、`empty` 的特殊查询语义。TC-CV08 验证版本文件改变后，显式失效可刷新版本发现和元数据缓存。

### TC-CL01..CL07b：命令生命周期（commands-lifecycle.bats）

覆盖节点 `remove/unremove/autoclean` 和 `categories list/show/current/switch`。子进程修改索引后，
测试显式失效父进程缓存再验证持久化结果。

### TC-NL01..NL07：节点生命周期（nodes-lifecycle.bats）

覆盖配置版本和状态字段持久化、标记、删除、孤立子节点查询，以及旧格式 `index.json` 的默认值兼容。

### TC-D01..DS02：部署与撤销（deploy-undeploy.bats）

覆盖 HEAD 缺失、重复部署、强制部署、Fresh 节点、dry-run、状态更新和撤销恢复；其中 TC-U03
验证符号链接按链接本身恢复，TC-DS02 验证撤销后 dotcfg 命令与运行库仍存在。

### TC-D01..D06：诊断与修复（doctor-repair.bats）

覆盖健康状态、HEAD 和部署状态修复、启动自检提示，以及备份根或节点存储缺失时重建索引并立即
重新加载节点数据。

### TC-44..63：统一 CLI（dotcfg.bats）

| 用例 | 描述 |
|------|------|
| TC-44 | status：fresh 状态显示可用操作 |
| TC-45 | status：full 状态检测（含节点信息） |
| TC-46 | status：min 状态检测（含节点信息） |
| TC-47 | list：节点列表 |
| TC-48 | list：fresh 状态节点列表 |
| TC-49 | history：无节点时显示"No history" |
| TC-50 | history：自动迁移后显示节点树 |
| TC-51 | history：跳过畸形目录名 |
| TC-52 | `switch fresh`：解析根节点别名；根节点不存在时报错 |
| TC-53 | switch：无效目标报错 |
| TC-54 | 旧 `desktop` 入口映射到 full 并完成安装 |
| TC-55 | 旧 `server` 入口映射到 min 并完成切换 |
| TC-56 | switch：`--dry-run` 透传 |
| TC-57 | validate：仓库验证详情 |
| TC-58 | 默认 status + 未知子命令报错 |
| TC-59 | 顶层和子命令 `--help` 与 `dotcfg help` 输出一致 |
| TC-60 | TAG 列表标记、切换提示、版本删除和节点删除警告 |
| TC-61 | 正式 `1.0.0 stable` 只展示 full、min、macos，并验证旧名称映射 |
| TC-62 | `fresh-adopt-legacy --help` 展示完整调用参数 |
| TC-63 | `categories show` 将 full 标记为动态全部跟踪文件且不显示数量 |

### TC-L01..L05 / TC-H01..H07：节点清单与历史图（history-graph.bats）

覆盖节点列表表头、节点类型、HEAD 标记、节点代码、空记录、线性与分支历史图以及部署状态。
TC-H07 固定验证 `bootstrap` 是特殊版本标识，历史图不会错误添加 `v` 前缀。

### TC-N01..N30：节点索引（nodes.bats）

覆盖节点创建、读取、父子关系、HEAD、部署状态、迁移检测和索引持久化。TC-N29 验证进程内
`code -> index` 缓存可读取节点；TC-N30 验证外部修改索引后，显式失效可重新加载磁盘数据。

### TC-R01..R05：重构接口契约（refactor-contract.bats）

锁定 `dotcfg help` 的完整文本、`check-exclude` 的兼容标签、`categories show` 的 `full` 动态标记，
未知切换目标的错误文字和返回码，以及 help 不加载业务库。后续内部重构不得改变这些用户可见行为。

### TC-E01..E06：Fresh 排除规则（exclude-rules.bats）

覆盖硬编码排除、普通配置、`exclude.conf`、绝对路径拒绝和仓库跟踪判断。TC-E06 固定验证
`.config-backup.bak` 以及 Microsoft Edge、NVM、Chromium、Chrome for Testing 可变状态不会进入
Fresh 选择集。

### TC-F01..F12：Fresh 根节点（fresh-node.bats）

覆盖 5 列 manifest、track/untrack、统计、diff、update、根节点保护和 `switch fresh`。TC-F12 先
验证旧备份采纳 dry-run 不创建元数据，再验证只复制旧备份中的跟踪原件和当前未跟踪配置，跳过
当前跟踪文件、浏览器状态并保持急救备份不变；同时验证符号链接备份及单路径 `fresh-diff` 均按
链接文本处理。

### TC-M01..M18：旧会话迁移（migration.bats）

| 用例 | 描述 |
|------|------|
| TC-M01 | 无旧会话时迁移提示无需操作 |
| TC-M02 | 已迁移时提示已完成 |
| TC-M03 | 单个会话迁移：创建根节点 + 子节点 |
| TC-M04 | 多个会话按时间顺序迁移 |
| TC-M05 | 迁移后父链正确 |
| TC-M06 | 迁移后 HEAD 设为最后节点 |
| TC-M07 | 迁移复制备份文件到节点目录 |
| TC-M08 | 迁移复制 MANIFEST 到 manifest.txt |
| TC-M09 | 旧会话移入 sessions/ 归档 |
| TC-M10 | 迁移后 DEPLOY_STATUS 为 deployed |
| TC-M11 | `--dry-run` 预览迁移计划 |
| TC-M12 | 非会话目录被忽略 |
| TC-M13 | 自动迁移在 dotcfg status 前触发 |
| TC-M14 | 自动迁移在 dotcfg switch 前触发 |
| TC-M15 | 显式 `dotcfg migrate` 执行迁移 |
| TC-M16 | 迁移后节点类型正确 |
| TC-M17 | 迁移后节点数量正确 |
| TC-M18 | 多次迁移幂等 |

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
| `run_install_desktop [args...]` | 运行旧 full 兼容入口 `switch-desktop.sh` |
| `run_install_server [args...]` | 运行旧 min 兼容入口 `switch-server.sh` |
| `run_restore_desktop [args...]` | 运行旧 full 兼容入口 `switch-desktop.sh` |
| `run_restore_server [args...]` | 运行旧 min 兼容入口 `switch-server.sh` |
| `run_uninstall [args...]` | `yes \| yes \| bash uninstall.sh` |
| `run_dotcfg [args...]` | `bash dotcfg` |

### 断言函数

| 函数 | 用途 |
|------|------|
| `assert_state_is <state>` | 验证当前状态（fresh/full/min/macos） |
| `assert_cfg_exists` / `assert_cfg_not_exists` | `.cfg` 存在性 |
| `assert_file_exists` / `assert_file_not_exists` | 文件存在性 |
| `assert_file_contains <path> <pattern>` | 文件内容匹配 |
| `assert_node_backup_exists <path>` | 任意节点 backup/ 中包含指定文件 |
| `assert_node_backup_contains <path>` | 同上（别名） |
| `assert_node_backup_count <n>` | 节点备份目录数量 |
| `assert_node_manifest_exists` | 任意节点 manifest.txt 存在 |
| `assert_node_backup_contains <path>` | 节点备份中包含指定相对路径 |
| `assert_backup_dir_exists` / `assert_backup_count <n>` | 旧式备份目录验证（兼容） |
| `assert_backup_contains <path>` / `assert_any_backup_contains <path>` | 旧式备份内容验证 |
| `assert_manifest_exists` | MANIFEST.txt 存在（旧式或节点） |
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

**验证环境**：2026-08-10 在[平台档案索引](../platforms/index.md)所列当前 Debian 平台执行；
Bats 满足本文 `>= 1.11.0` 的前置要求。

```
Total:  246
Passed: 246
Failed: 0
```

---

## 已知限制

1. **SSH 密钥依赖**：真实远程模式需要有效的 GitHub SSH 密钥
2. **网络要求**：首次创建 mirror 时需要网络连接（除非从本地 `~/.cfg/` 归档）
3. **磁盘空间**：每个测试约占用 50-100MB
4. **并行限制**：不建议同时运行超过 5 个测试实例（Git lock 冲突）

---

## 相关文档

- [安装系统](installation-system.md) — 安装系统设计文档（v3.0 节点系统）
- [安装系统修复记录](../planning/installation-fixes.md) — 已知问题和修复方案
- [依赖清单](dependencies.md) — 项目依赖的软件包

---

**最后更新**: 2026-08-11
**版本**: 3.9 — 246 个受管测试 + 节点/category 缓存 + dotcfg 按需加载
