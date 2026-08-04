# 安装测试系统

本文面向 Agent 和维护者。

## 概述

状态机测试框架，自动化验证安装脚本在所有状态转换路径下的正确性和幂等性。覆盖 3 种基本状态之间的 9 种转换路径。

### 设计目标

1. **完整性**：覆盖所有可能的状态转换路径
2. **隔离性**：测试在临时 HOME 目录中进行，不影响真实配置
3. **可重复性**：结果确定且可重复，支持回归测试
4. **自动化**：支持本地和 CI 环境
5. **可追溯**：详细日志和报告便于问题定位

---

## 状态机模型

### 三种基本状态

- **FRESH**：`.cfg` 不存在，无符号链接
- **DESKTOP**：`.cfg` 存在，checkout 所有文件（含 X11、音频、图形工具）
- **SERVER**：`.cfg` 存在，只 checkout 服务器白名单文件

### 九种状态转换

```
FRESH → DESKTOP   (install-2.sh)
FRESH → SERVER    (install-server.sh)
DESKTOP → DESKTOP (install-2.sh --reinstall，幂等)
DESKTOP → SERVER  (restore-server.sh)
DESKTOP → FRESH   (uninstall.sh)
SERVER → SERVER   (install-server.sh --reinstall，幂等)
SERVER → DESKTOP  (restore-desktop.sh)
SERVER → FRESH    (uninstall.sh)
FRESH → FRESH     (基准测试，无操作)
```

---

## 测试架构

### 环境隔离

采用临时用户目录隔离：

```bash
TEST_HOME=$(mktemp -d /tmp/cfg-test-home.XXXXXX)
export HOME="$TEST_HOME"
```

- 完全隔离，不影响真实 `$HOME`
- 无需 root 权限
- 易于清理
- CI 友好

### Git 仓库源策略

**模式 A：本地 Git Mirror（默认）**
```bash
git clone --bare git@github.com:darkroam/dotfiles.git /tmp/cfg-git-mirror/dotfiles.git
export DOTFILES_REPOSITORY="/tmp/cfg-git-mirror/dotfiles.git"
```
优势：不依赖网络、速度快、可离线运行。

**模式 B：真实远程仓库**
```bash
export USE_REAL_REMOTE=true
```
适用于验证真实网络环境和 CI 定期验证。

---

## 核心组件

### 1. 冲突文件生成器

`scripts/test/state-machine-tester.sh` 内嵌的 `generate_*_conflicts` 函数为每种状态生成逼真的冲突场景：

- **Fresh 冲突**：系统默认 `.bashrc`、`.zshrc`
- **Desktop 冲突**：用户修改的 `.bashrc`、`.gitconfig`、未跟踪的 `.tmux.conf.local`
- **Server 冲突**：服务器模式修改的 `.bashrc`、自定义 `.config/server-tools/`

### 2. 状态验证器

`verify_*_state` 函数（内嵌在测试脚本中）：

- `verify_fresh_state` — 验证 `.cfg` 不存在或仓库保留但符号链接已移除
- `verify_desktop_state` — 验证 `.cfg` 存在、桌面文件存在（.xinitrc 等）、`showUntrackedFiles = no`
- `verify_server_state` — 验证 `.cfg` 存在、桌面文件不存在、服务器文件存在

### 3. 测试执行器

`scripts/test/state-machine-tester.sh` 核心功能：
- 初始化隔离测试环境
- 设置初始状态并生成冲突
- 执行状态转换脚本
- 验证结果状态
- 生成详细测试报告

**文件快照机制**：
```bash
snapshot_files() {
    find "$HOME" -maxdepth 3 \( -type f -o -type l \) | sort
    find "$HOME" -maxdepth 3 -type l -exec ls -la {} \;
    find "$HOME" -maxdepth 1 -name ".config-backup-*" -type d
}
```

### 4. 单元测试

`scripts/test/cfg-validate-test.sh` 提供 11 个单元测试，验证共享验证库 `cfg-validate.sh` 的各个函数：
- `cfg_validate` 的各种仓库状态
- `cfg_should_backup_file` 的文件过滤逻辑
- `cfg_detect_state` 的状态检测

---

## 测试执行

### 本地运行

```bash
# 运行全部 9 个状态转换测试
bash scripts/test/state-machine-tester.sh all

# 运行单个测试
bash scripts/test/state-machine-tester.sh single fresh desktop

# 运行单元测试
bash scripts/test/cfg-validate-test.sh

# 使用真实远程仓库
USE_REAL_REMOTE=true bash scripts/test/state-machine-tester.sh all

# 更新本地 Mirror
UPDATE_MIRROR=true bash scripts/test/state-machine-tester.sh all
```

### CI 运行

GitHub Actions：
- **Push/PR**：使用本地 mirror 运行快速测试
- **每周调度**：使用真实远程仓库运行完整测试

---

## 测试报告

### 报告格式

```
Test: desktop_to_server
Timestamp: 2026-08-03T14:30:00+08:00
Duration: 12s
Script Exit Code: 0
Verify Exit Code: 0
Result: PASS

Files Before: 45
Files After: 38
Symlinks Before: 12
Symlinks After: 8
Backups Before: 0
Backups After: 1
```

### 日志文件

每个测试生成：
- `{test_name}.stdout` / `.stderr` — 标准输出/错误
- `{test_name}.report.txt` — 测试报告
- `{test_name}.before.filelist` / `.after.filelist` — 文件列表
- `{test_name}.before.symlinks` / `.after.symlinks` — 符号链接
- `{test_name}.before.backups` / `.after.backups` — 备份目录

日志位置：`/tmp/cfg-test-log-XXXXXX/`

---

## 测试结果

### 首次完整测试（2026-08-04）

**环境**：Debian 13, Git 2.47.2, Bash 5.2.37, 本地 Git Mirror

```
Total:  9
Passed: 9
Failed: 0
```

| 测试 | 说明 | 结果 |
| --- | --- | --- |
| fresh → desktop | 首次安装桌面模式 | PASS |
| fresh → server | 首次安装服务器模式 | PASS |
| desktop → desktop | 幂等性验证 | PASS |
| desktop → server | 切换到服务器模式 | PASS |
| desktop → fresh | 卸载桌面模式 | PASS |
| server → server | 幂等性验证 | PASS |
| server → desktop | 切换到桌面模式 | PASS |
| server → fresh | 卸载服务器模式 | PASS |
| fresh → fresh | 基准测试 | PASS |

执行时间：约 10-15 秒（全部 9 个测试）

### 测试过程中修复的问题

1. **测试框架**：缺少 `setup_test_env` 调用、算术运算在 `set -e` 下返回非零、`~` 路径展开错误、`yes |` 管道 SIGPIPE
2. **安装脚本**：`git checkout` 缺少 `HEAD` 参数、`local` 关键字在函数外使用
3. **验证逻辑**：`verify_fresh_state` 错误要求 `.cfg` 不存在（实际 uninstall 保留仓库）

### 覆盖验证

- 状态检测逻辑（fresh/desktop/server）
- 智能决策提示
- 文件冲突检测（已跟踪/未跟踪/已修改）
- 备份创建和 MANIFEST 生成
- Checkout 和符号链接创建
- `.cfg-checkout-state` 记录
- 卸载和符号链接清理
- 幂等性：重复安装不产生额外备份

---

## 故障排除

### Git Mirror 创建失败
```bash
ssh -T git@github.com                                    # 检查 SSH
rm -rf /tmp/cfg-git-mirror
git clone --bare git@github.com:darkroam/dotfiles.git /tmp/cfg-git-mirror/dotfiles.git
```

### 测试环境污染
```bash
rm -rf /tmp/cfg-test-home.* /tmp/cfg-test-log.* /tmp/cfg-git-mirror
bash scripts/test/state-machine-tester.sh all
```

### 调试技巧
```bash
# 详细日志
bash -x scripts/test/state-machine-tester.sh single fresh desktop 2>&1 | tee debug.log

# 保留测试环境
export KEEP_TEST_ENV=true
bash scripts/test/state-machine-tester.sh single fresh desktop
ls -la /tmp/cfg-test-home-*/
```

---

## 已知限制

1. SSH 密钥依赖：真实远程模式需要有效的 GitHub SSH 密钥
2. 网络要求：首次创建 mirror 时需要网络连接
3. 磁盘空间：每个测试约占用 50-100MB
4. 并行限制：不建议同时运行超过 5 个测试实例（Git lock 冲突）

---

## 相关文档

- [安装系统](installation-system.md) — 安装系统设计文档
- [安装系统修复记录](../planning/installation-fixes.md) — 已知问题和修复方案
- [依赖清单](dependencies.md) — 项目依赖的软件包

---

**最后更新**: 2026-08-04
**版本**: 1.0 — 基于 state-machine-testing.md 整合
