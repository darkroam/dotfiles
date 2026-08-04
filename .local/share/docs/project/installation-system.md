# 安装系统

## 概述

本配置库实现了一套幂等性安装、卸载和状态切换系统，支持在三种配置状态（未安装、桌面模式、服务器模式）之间安全转换。所有操作保证幂等性——重复执行不改变结果或产生副作用。

### 设计原则

1. **幂等性**：同一操作可重复执行，结果一致
2. **状态感知**：自动检测当前状态，选择正确操作路径
3. **智能备份**：只备份真正需要保护的文件，通过 MD5 内容对比跳过未修改文件
4. **安全卸载**：不自动删除仓库，防止误操作
5. **可追溯性**：MANIFEST.txt 和 `.cfg-checkout-state` 记录所有变更

---

## 三种配置状态

### State 0: FRESH（未安装）

- `.cfg` 目录不存在
- 可能有系统默认配置文件（`.bashrc`, `.zshrc`, `.profile` 等）
- 无符号链接指向仓库文件

### State 1: DESKTOP（桌面模式）

- `.cfg` 存在且 checkout 了所有跟踪文件
- 包含完整桌面环境配置：X11（`.xinitrc`, `.xprofile`）、音频（`.asoundrc`）、图形工具、状态栏等
- `status.showUntrackedFiles = no`
- `.cfg-checkout-state` 记录文件指纹

### State 2: SERVER（服务器模式）

- `.cfg` 存在但只 checkout 了服务器相关文件（白名单控制）
- 排除图形化组件，只保留 Shell、Tmux、Git、LF 等终端工具
- 桌面特有文件不作为符号链接存在
- `status.showUntrackedFiles = no`
- `.cfg-checkout-state` 记录文件指纹

---

## 状态转换矩阵

```
┌─────────────┐
│   FRESH     │
└──────┬──────┘
       │
       ├─ install-2.sh ──────────────→ DESKTOP
       └─ install-server.sh ─────────→ SERVER

┌─────────────┐
│  DESKTOP    │
└──────┬──────┘
       │
       ├─ install-2.sh ──────────────→ DESKTOP  (幂等，交互提示)
       ├─ restore-server.sh ─────────→ SERVER
       └─ uninstall.sh ──────────────→ FRESH*

┌─────────────┐
│   SERVER    │
└──────┬──────┘
       │
       ├─ install-server.sh ─────────→ SERVER  (幂等，交互提示)
       ├─ restore-desktop.sh ────────→ DESKTOP
       └─ uninstall.sh ──────────────→ FRESH*

FRESH → FRESH  (基准测试，无操作)
```

*uninstall.sh 移除符号链接但保留 `.cfg` 仓库，需用户手动删除。

---

## 核心脚本

### 脚本总览

| 脚本 | 用途 | 转换 |
| --- | --- | --- |
| `install-2.sh` | 桌面模式安装（推荐） | FRESH/SERVER → DESKTOP |
| `install-server.sh` | 服务器模式安装 | FRESH/DESKTOP → SERVER |
| `restore-desktop.sh` | 切换到桌面模式 | SERVER → DESKTOP |
| `restore-server.sh` | 切换到服务器模式 | DESKTOP → SERVER |
| `uninstall.sh` | 卸载（保留仓库） | DESKTOP/SERVER → FRESH |
| `install.sh` | 桌面安装（经典版，保留兼容） | FRESH → DESKTOP |

### 通用参数

所有 Gen 2 脚本支持：
- `--dry-run` — 预览操作，不修改文件
- `--reinstall` — 跳过交互提示，直接重新安装（仅 install-2.sh / install-server.sh）

### 1. install-2.sh — 桌面模式安装

**状态检测与自主决策**：
```
检测到 .cfg？
  ├─ 否（fresh）→ 直接全新安装
  └─ 是
      ├─ desktop → 提示：1. 重新安装  2. 取消
      └─ server  → 提示：1. 用 restore-desktop.sh  2. 强制安装  3. 取消
```

**执行流程**：
1. 检测当前状态（fresh/desktop/server）
2. 自主决策（如已安装，交互式提示）
3. 分析文件冲突（未跟踪 → 备份 / 已跟踪已修改 → 备份 / 已跟踪相同 → 跳过）
4. 创建备份 `.config-backup-{from}-to-desktop-{timestamp}/`
5. Checkout 所有桌面配置
6. 记录 `.cfg-checkout-state`

```bash
bash ~/.local/bin/install-2.sh            # 首次安装或交互提示
bash ~/.local/bin/install-2.sh --reinstall # 跳过提示直接重装
bash ~/.local/bin/install-2.sh --dry-run   # 预览
```

### 2. install-server.sh — 服务器模式安装

与 install-2.sh 相同的决策模式，但只 checkout 服务器文件白名单。

**服务器文件白名单**（install-server.sh 实际代码）：
```
Shell:    .config/shell/profile, .config/shell/aliasrc, .config/shell/zshrc,
          .config/shell/tmux.conf.local, .bashrc, .zshrc, .profile
Tmux:     .config/tmux/tmux.conf, .config/tmux/tmux.conf.local, .tmux.conf
Git:      .config/git/gitconfig, .config/git/ignore, .gitconfig, .gitignore
LF:       .config/lf/lfrc, .config/lf/scope, .config/lf/cleaner,
          .config/lf/icons, .config/lf/shortcutrc
文档:     .local/share/docs/README.md, .local/share/docs/user/desktop-guide-zh.md
```

> **注意**：restore-server.sh 的白名单只包含 11 个文件，与 install-server.sh 的 22 个文件不一致。详见 [installation-fixes.md](../planning/installation-fixes.md)。

```bash
bash ~/.local/bin/install-server.sh            # 首次安装
bash ~/.local/bin/install-server.sh --reinstall # 跳过提示
bash ~/.local/bin/install-server.sh --dry-run   # 预览
```

### 3. restore-desktop.sh — 切换到桌面模式

从 SERVER → DESKTOP：
1. 检测当前状态（已是 desktop 则提示并退出）
2. 分析冲突文件并备份
3. 创建备份 `.config-backup-server-to-desktop-{timestamp}/`
4. Checkout 所有桌面配置
5. 更新 `.cfg-checkout-state`

```bash
bash ~/.local/bin/restore-desktop.sh          # 切换
bash ~/.local/bin/restore-desktop.sh --dry-run # 预览
```

> **注意**：`--auto-stash` 参数可被解析但未实现，实际行为与不加参数相同。详见 [installation-fixes.md](../planning/installation-fixes.md)。

### 4. restore-server.sh — 切换到服务器模式

从 DESKTOP → SERVER：
1. 检测当前状态（已是 server 则提示并退出）
2. 分析冲突文件并备份
3. 创建备份 `.config-backup-desktop-to-server-{timestamp}/`
4. 删除桌面符号链接（.xinitrc, .xprofile, .asoundrc 等）
5. 验证服务器配置
6. 更新 `.cfg-checkout-state`

```bash
bash ~/.local/bin/restore-server.sh          # 切换
bash ~/.local/bin/restore-server.sh --dry-run # 预览
```

### 5. uninstall.sh — 完全卸载

1. 检测仓库存在（不存在则退出）
2. 移除所有符号链接
3. 可选恢复备份（检测所有备份目录，用户选择）
4. 提示手动删除 `.cfg` 仓库

```bash
bash ~/.local/bin/uninstall.sh          # 卸载
bash ~/.local/bin/uninstall.sh --dry-run # 预览
rm -rf ~/.cfg                           # 手动删除仓库
```

---

## 智能备份系统

### 备份命名约定

```
.config-backup-{from}-to-{to}-{timestamp}
```

示例：
- `.config-backup-fresh-to-desktop-20260803T143000/`
- `.config-backup-server-to-desktop-20260803T150000/`
- `.config-backup-desktop-to-server-20260803T160000/`

### 智能文件过滤

```
文件存在？
  ├─ 否 → 跳过
  └─ 是
      ├─ 已跟踪？
      │   ├─ 否 → 备份（未跟踪文件）
      │   └─ 是
      │       ├─ MD5 相同 → 跳过（未修改）
      │       └─ MD5 不同 → 备份（已修改）
```

典型场景下减少 80-90% 的备份文件数量。

### MANIFEST.txt 格式

```
# Backup manifest created at Mon Aug  3 14:30:00 CST 2026
# State transition: server -> desktop
# Format: original_path -> backup_path (status)

/home/ok/.bashrc -> /home/ok/.config-backup-server-to-desktop-20260803T143000/.bashrc (modified)
/home/ok/.zshrc -> /home/ok/.config-backup-server-to-desktop-20260803T143000/.zshrc (untracked)
```

### Checkout 状态记录

每次安装/恢复后记录文件指纹到 `.cfg-checkout-state`：

```
.bashrc:e99a18c428cb38d5f260853678922e03
.zshrc:d8e8fca2dc0f896fd7cb4cb0031ba249
.profile:5d41402abc4b2a76b9719d911017c592
```

用于快速判断文件是否被用户修改，避免重复计算 hash。

---

## 安全机制

### 卸载保护

`uninstall.sh` 不自动删除 `.cfg` 仓库，防止误操作导致数据丢失。用户需手动执行 `rm -rf ~/.cfg`。

### 符号链接检查

安装前检查符号链接目标，拒绝跟随符号链接祖先，验证所有符号链接在 `$HOME` 内。

### 权限保护

备份目录权限设为 `0700`，只允许当前用户访问。

### 状态检测

所有脚本自动检测当前状态，检测逻辑：
```bash
detect_state() {
    if [ ! -d "$HOME/.cfg" ]; then
        echo "fresh"; return
    fi
    if [ -e "$HOME/.xinitrc" ] || [ -L "$HOME/.xinitrc" ]; then
        echo "desktop"; return
    fi
    echo "server"
}
```

---

## 共享验证库

`.local/share/dotfiles-lib/cfg-validate.sh` 提供共享函数：

- `cfg_validate()` — 验证 `.cfg` 仓库状态，设置 `CFG_STATE`（missing/not_git/foreign_repo/valid）
- `cfg_should_backup_file()` — MD5 内容对比，判断文件是否需要备份
- `cfg_detect_state()` — 检测当前状态（fresh/desktop/server）

安装脚本通过 `DOTFILES_LIB_DIR` 加载此库。如果库不可用，脚本回退到内联副本。

---

## 使用场景

### 场景 1：全新桌面安装
```bash
bash ~/.local/bin/install-2.sh --dry-run  # 预览
bash ~/.local/bin/install-2.sh            # 安装
exec zsh                                  # 重启 shell
```

### 场景 2：服务器部署
```bash
curl -fsSL https://github.com/darkroam/dotfiles/raw/master/.local/bin/install-server.sh | bash
source ~/.profile
```

### 场景 3：桌面 ↔ 服务器切换
```bash
bash ~/.local/bin/restore-server.sh    # 桌面 → 服务器
bash ~/.local/bin/restore-desktop.sh   # 服务器 → 桌面
```

### 场景 4：完全卸载
```bash
bash ~/.local/bin/uninstall.sh  # 移除符号链接
rm -rf ~/.cfg                   # 手动删除仓库
```

---

## 故障排除

### 安装失败后恢复
```bash
ls ~/.config-backup-*/                    # 检查备份
cp ~/.config-backup-*/.bashrc ~/          # 手动恢复
rm -rf ~/.cfg                             # 删除仓库
bash ~/.local/bin/install-2.sh            # 重新安装
```

### 符号链接指向错误
```bash
rm ~/.bashrc
git --git-dir=$HOME/.cfg/ --work-tree=$HOME checkout HEAD -- .bashrc
```

### 状态检测不准确
```bash
ls -la ~/.xinitrc ~/.xprofile ~/.asoundrc  # 检查桌面文件
git --git-dir=$HOME/.cfg/ --work-tree=$HOME checkout HEAD -- .xinitrc .xprofile .asoundrc
```

---

## 已知问题

以下问题已记录，待修复。详见 [installation-fixes.md](../planning/installation-fixes.md)。

- B1: `uninstall.sh` 备份匹配模式与 Gen 2 命名不一致
- B2: `uninstall.sh` MANIFEST 解析捕获 `(modified)` 后缀为文件路径
- B3: `install-2.sh --force` 对有效仓库执行 `rm -rf` 无备份
- B4: install-server.sh 与 restore-server.sh 白名单不一致
- B5: `restore-desktop.sh --auto-stash` 可解析但未实现
- B6: Gen 2 脚本 checkout 失败时无回滚机制
- B7: `scripts/test/helpers.sh` 存在但未被任何脚本加载

---

## 相关文档

- [安装测试系统](installation-testing.md) — 状态机测试框架
- [安装系统修复记录](../planning/installation-fixes.md) — 已知问题和修复方案
- [依赖清单](dependencies.md) — 项目依赖的软件包
- [架构文档](architecture.md) — 配置库整体架构

---

**最后更新**: 2026-08-04
**版本**: 1.0 — 合并 idempotent-installation.md + server-mode.md + optimization-report
