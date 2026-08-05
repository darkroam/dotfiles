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
    ├── helpers.bash            ← 共享辅助函数（460+ 行）
    ├── detect-state.bats       ← TC-01..03  状态检测
    ├── backup-logic.bats       ← TC-04..10  备份逻辑
    ├── install-desktop.bats    ← TC-11..16  桌面安装
    ├── install-server.bats     ← TC-17..21  服务器安装
    ├── restore-desktop.bats    ← TC-22..25  恢复桌面
    ├── restore-server.bats     ← TC-26..29  恢复服务器
    ├── uninstall.bats          ← TC-30..33, TC-38..43  卸载与恢复
    ├── validate.bats           ← TC-34a..34k, TC-35  仓库验证
    ├── e2e-state-machine.bats  ← TC-36..37  端到端生命周期
    ├── dotcfg.bats             ← TC-44..58  统一 CLI
    └── generate-conflicts.sh   ← 冲突文件生成器
```

---

## 测试用例目录

### TC-01..03：状态检测（detect-state.bats）

| 用例 | 描述 |
|------|------|
| TC-01 | 无 `.cfg` → fresh |
| TC-02a..02d | `.cfg` + 桌面指标（.xinitrc / .xprofile / .config/x11 / 符号链接）→ desktop |
| TC-03a..03b | `.cfg` 无桌面指标 → server |

### TC-04..10：备份逻辑（backup-logic.bats）

| 用例 | 描述 |
|------|------|
| TC-04 | 文件不存在 → 跳过备份 |
| TC-05 | 文件存在但未跟踪 → 备份 |
| TC-06 | 文件已跟踪但已修改 → 备份 |
| TC-07 | 文件已跟踪且相同 → 跳过 |
| TC-08 | 备份目录命名约定 `(fresh\|desktop\|server)-to-(fresh\|desktop\|server)-[0-9]{8}T[0-9]{6}` |
| TC-09 | 备份目录权限 0700 |
| TC-10 | MANIFEST 格式：`relative_path\tmd5\tstatus`（tab 分隔） |

### TC-11..16：桌面安装（install-desktop.bats）

| 用例 | 描述 |
|------|------|
| TC-11 | fresh 安装：创建 .cfg，checkout 所有文件 |
| TC-12 | 备份已有用户文件到 `.config-backup/` |
| TC-13 | `--dry-run` 预览不修改 |
| TC-14 | `--force` 替换有效仓库（备份旧仓库） |
| TC-15 | checkout state 文件记录所有跟踪文件 |
| TC-16 | `showUntrackedFiles = no` 配置 |

### TC-17..21：服务器安装（install-server.bats）

| 用例 | 描述 |
|------|------|
| TC-17 | fresh 安装：只 checkout 服务器白名单文件 |
| TC-18 | 备份已有用户文件 |
| TC-19 | `--dry-run` 预览 |
| TC-20 | 白名单排除桌面文件 |
| TC-21 | checkout state 和 git 配置 |

### TC-22..25：恢复桌面（restore-desktop.bats）

| 用例 | 描述 |
|------|------|
| TC-22 | server → desktop：添加桌面文件 |
| TC-23 | 备份已修改文件 |
| TC-24 | `--dry-run` 预览 |
| TC-25 | `--auto-stash` 覆盖不备份 |

### TC-26..29：恢复服务器（restore-server.bats）

| 用例 | 描述 |
|------|------|
| TC-26 | desktop → server：移除桌面指标，验证服务器文件 |
| TC-27 | 备份已修改桌面文件 |
| TC-28 | `--dry-run` 预览 |
| TC-29 | checkout state 和 git 配置更新 |

### TC-30..33, TC-38..43：卸载与恢复（uninstall.bats）

| 用例 | 描述 |
|------|------|
| TC-30 | 移除所有 checkout 文件 |
| TC-31 | 从最早备份恢复用户文件 |
| TC-32 | `--dry-run` 预览 |
| TC-33 | 无仓库时报错 |
| TC-38 | 移除 checkout state 文件 |
| TC-39 | `--latest` 恢复最新版本 |
| TC-40 | 多转换链：从所有会话恢复文件 |
| TC-41 | 幂等性：两次卸载结果相同 |
| TC-42 | `--clean-backups` 删除所有备份 |
| TC-43 | 无备份的管理文件直接删除 |

### TC-34..35：仓库验证（validate.bats）

| 用例 | 描述 |
|------|------|
| TC-34a..34k | `cfg_validate` 各种仓库状态分类（missing/not_git/foreign_repo/valid） |
| TC-35 | 库不可用时回退到内联验证 |

### TC-36..37：端到端生命周期（e2e-state-machine.bats）

| 用例 | 描述 |
|------|------|
| TC-36 | fresh → desktop → server → desktop → fresh（完整循环） |
| TC-37 | fresh → server → desktop → server → fresh（反向循环） |

### TC-44..58：统一 CLI（dotcfg.bats）

| 用例 | 描述 |
|------|------|
| TC-44 | status：fresh 状态显示可用转换 |
| TC-45 | status：desktop 状态检测 |
| TC-46 | status：server 状态检测 |
| TC-47 | graph：desktop 状态图 |
| TC-48 | graph：fresh 状态图 |
| TC-49 | history：无备份目录 |
| TC-50 | history：解析 MANIFEST 时间线 |
| TC-51 | history：跳过畸形目录名 |
| TC-52 | switch：同状态无操作 |
| TC-53 | switch：无效目标报错 |
| TC-54 | switch：fresh → desktop 完整安装 |
| TC-55 | switch：desktop → server 完整切换 |
| TC-56 | switch：`--dry-run` 透传 |
| TC-57 | validate：仓库验证详情 |
| TC-58 | 默认 status + 未知子命令报错 |

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
| `run_install_desktop [args...]` | `yes \| bash install-2.sh` |
| `run_install_server [args...]` | `yes \| bash install-server.sh` |
| `run_restore_desktop [args...]` | `yes \| bash restore-desktop.sh` |
| `run_restore_server [args...]` | `yes \| bash restore-server.sh` |
| `run_uninstall [args...]` | `yes \| yes \| bash uninstall.sh` |
| `run_dotcfg [args...]` | `bash dotcfg` |

### 断言函数

| 函数 | 用途 |
|------|------|
| `assert_state_is <state>` | 验证当前状态（fresh/desktop/server） |
| `assert_cfg_exists` / `assert_cfg_not_exists` | `.cfg` 存在性 |
| `assert_file_exists` / `assert_file_not_exists` | 文件存在性 |
| `assert_file_contains <path> <pattern>` | 文件内容匹配 |
| `assert_backup_dir_exists` / `assert_backup_count <n>` | 备份目录验证 |
| `assert_backup_contains <path>` / `assert_any_backup_contains <path>` | 备份内容验证 |
| `assert_manifest_exists` | MANIFEST.txt 存在 |
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

# 运行单个专题
bats .local/share/test/installation/

# 过滤特定用例
bats --filter "TC-36" .local/share/test/installation/

# TAP 格式（CI 适用）
bats -r .local/share/test/ --tap
```

### 当前测试结果

**环境**：Debian 13, Git 2.47.2, Bash 5.2.37, Bats 1.11.1

```
Total:  72
Passed: 72
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

- [安装系统](installation-system.md) — 安装系统设计文档
- [安装系统修复记录](../planning/installation-fixes.md) — 已知问题和修复方案
- [依赖清单](dependencies.md) — 项目依赖的软件包

---

**最后更新**: 2026-08-05
**版本**: 2.0 — Bats 迁移 + 72 个测试用例 + dotcfg CLI 测试
