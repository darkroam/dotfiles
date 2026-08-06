# 安装系统

本文面向 Agent 和维护者。

## 概述

本配置库实现了一套幂等性安装、卸载和状态切换系统，支持在三种配置状态之间安全转换。系统以 bare git repo 为版本控制核心，通过 MANIFEST 和备份链实现完整可追溯性，保证任意时刻均可恢复到历史状态。

### 设计原则

1. **幂等性**：同一操作可重复执行，结果一致，不产生多余副作用
2. **状态感知**：自动检测当前状态，选择正确操作路径
3. **智能备份**：只备份真正需要保护的文件，通过 MD5 内容对比跳过未修改文件
4. **可恢复性**：`.config-backup/` + `.cfg/`  Together 足以恢复到任意历史状态
5. **安全卸载**：不自动删除仓库，防止误操作
6. **可追溯性**：MANIFEST.txt 和 `.cfg-checkout-state` 记录所有变更

---

## 版本控制思路

### 核心架构

系统使用 **bare git repo** 作为配置源真相（source of truth）：

```
~/.cfg/              ← bare git repo（git --git-dir=~/.cfg/ --work-tree=~）
~/.config-backup/    ← 备份链（状态转换时自动创建）
~/.cfg-checkout-state ← 文件指纹记录（path:md5 格式）
```

**为什么选择 bare repo + work-tree 模式**：
- `git checkout` 直接将文件写入 `$HOME`，无需符号链接管理
- `status.showUntrackedFiles = no` 隐藏未跟踪文件，保持 `git status` 清洁
- 所有配置文件（包括桌面和服务器模式）均在同一个 repo 中跟踪
- "模式"区别不在于 repo 内容，而在于 **哪些文件被 checkout 到 work-tree**

### 仓库身份验证

共享验证库 `cfg-validate.sh` 通过双重验证确认仓库身份：

- **方法 A**：规范化 remote URL（SSH→HTTPS 统一比较）匹配 `git@github.com:darkroam/dotfiles.git`
- **方法 B**：检查 HEAD 中是否存在签名文件 `.local/bin/dotcfg`
- 任一方法通过即确认为本项目的 dotfiles 仓库

仓库状态分类：`missing`（不存在）、`not_git`（非 git 目录）、`foreign_repo`（其他 git 仓库）、`valid`（本项目的仓库）。

### 共享验证库

`.local/lib/dotfiles/cfg-validate.sh` 提供所有脚本共享的核心函数：

| 函数 | 用途 |
|------|------|
| `cfg_validate()` | 验证 `.cfg` 仓库身份，设置 `CFG_STATE`/`CFG_IS_OURS`/`CFG_NEEDS_PULL`/`CFG_REMOTE_URL` |
| `cfg_detect_state()` | 检测当前安装状态（fresh/desktop/server） |
| `cfg_should_backup_file()` | MD5 内容对比，判断文件是否需要备份 |
| `cfg_check_updates()` | 检查远程是否有新提交 |
| `cfg_print_validation_result()` | 人类可读的验证结果输出 |

安装脚本通过 `DOTFILES_LIB_DIR` 加载此库。命令脚本位于 `.local/lib/dotfiles/commands/`，通过 `.local/lib/dotfiles/utils/common.sh` 加载所有工具库。

---

## 状态机

### 三种基本状态

| 状态 | 检测条件 | 含义 |
|------|----------|------|
| **fresh** | `.cfg` 不存在 | 未安装，可能有系统默认配置文件 |
| **desktop** | `.cfg` 存在 + 桌面指标文件存在 | 完整桌面环境配置已激活 |
| **server** | `.cfg` 存在 + 无桌面指标文件 | 仅服务器/终端配置已激活 |

**桌面指标文件**（任一存在即为 desktop）：
- `.xinitrc`（文件或符号链接）
- `.xprofile`（文件或符号链接）
- `.config/x11`（目录或符号链接）
- `.asoundrc`（文件或符号链接）
- `.gtkrc-2.0`（文件或符号链接）
- `.config/alsa`（目录或符号链接）
- `.config/mpd`（目录或符号链接）
- `.config/nsxiv`（目录或符号链接）
- `.config/zathura`（目录或符号链接）

这些文件仅在桌面模式安装时被 checkout，因此是区分 desktop/server 的可靠信号。状态检测与 switch-server.sh 的移除列表保持一致。

注：switch-server.sh 移除列表包含 12 项（7 符号链接 + 5 目录），其中 `.tmux.conf`、`.gitconfig`、`.gitignore` 属于 server 共用文件，移除后会立即重新 checkout，因此不作为状态检测指标。

### 状态转换矩阵

```
┌─────────────┐
│   FRESH     │
└──────┬──────┘
       │
       ├─ dotcfg switch desktop ──→ DESKTOP   (switch-desktop.sh)
       └─ dotcfg switch server ───→ SERVER    (switch-server.sh)

┌─────────────┐
│  DESKTOP    │
└──────┬──────┘
       │
       ├─ dotcfg switch desktop --reinstall ─→ DESKTOP  (幂等重装)
       ├─ dotcfg switch server ──────────────→ SERVER   (switch-server.sh)
       └─ dotcfg switch fresh ───────────────→ FRESH*   (uninstall.sh)

┌─────────────┐
│   SERVER    │
└──────┬──────┘
       │
       ├─ dotcfg switch server --reinstall ──→ SERVER   (幂等重装)
       ├─ dotcfg switch desktop ─────────────→ DESKTOP  (switch-desktop.sh)
       └─ dotcfg switch fresh ───────────────→ FRESH*   (uninstall.sh)
```

\* uninstall.sh 移除 checkout 的文件但保留 `.cfg` 仓库，需用户手动删除。

### 统一命令行入口

`dotcfg` 命令提供 git 风格的统一入口，自动调度到正确的底层脚本：

```bash
dotcfg                        # 显示当前状态（等同于 dotcfg status）
dotcfg status                 # 当前状态 + 可用转换
dotcfg graph                  # ASCII 状态图，标记当前位置
dotcfg history                # 从备份 MANIFEST 重建转换时间线
dotcfg switch <target>        # 切换到目标状态（fresh|desktop|server）
dotcfg validate               # 详细仓库验证
dotcfg help                   # 使用帮助
```

`dotcfg switch` 根据（当前状态, 目标状态）对自动选择脚本，通过 `exec` 调度并透传所有参数（`--dry-run`、`--force` 等）。

---

## 核心脚本

### 脚本总览

**命令脚本**（位于 `.local/lib/dotfiles/commands/`）：

| 脚本 | 用途 | 转换 |
|------|------|------|
| `switch-desktop.sh` | 切换到桌面模式 | FRESH/SERVER → DESKTOP |
| `switch-server.sh` | 切换到服务器模式 | FRESH/DESKTOP → SERVER |
| `uninstall.sh` | 卸载并恢复备份 | DESKTOP/SERVER → FRESH |

**工具库**（位于 `.local/lib/dotfiles/utils/`）：

| 文件 | 职责 |
|------|------|
| `common.sh` | 顶层加载器，source 所有工具库 |
| `args.sh` | 参数解析（`cfg_parse_common_args`） |
| `backup.sh` | 备份创建和文件备份（`cfg_create_backup_dir`, `cfg_backup_file`） |
| `rollback.sh` | 回滚判断和执行（`cfg_should_rollback`, `cfg_rollback_from_backup`） |
| `checkout.sh` | 文件 checkout、路径安全检查和状态记录（`cfg_checkout_files`, `cfg_validate_path_safety`） |
| `repo.sh` | 仓库克隆和激活（`cfg_setup_repository`, `cfg_activate_repository`） |
| `files.sh` | 文件分类和常量定义（`cfg_analyze_files`, `cfg_load_server_files`） |

### 通用参数

所有命令脚本支持：
- `--dry-run` — 预览操作，不修改文件
- `--force` — 强制操作（备份并替换无效/外部仓库）

特定脚本额外支持：
- `--reinstall` — 跳过交互提示，直接重新安装（switch-desktop / switch-server）
- `--auto-stash` — 自动备份冲突文件，不提示用户，直接继续操作（仅 switch-desktop）
- `--latest` — 恢复最新备份而非最早（仅 uninstall）
- `--clean-backups` — 卸载后清理备份目录（仅 uninstall）

### `--auto-stash` 语义定义

`--auto-stash` 的精确行为：

1. **自动备份冲突文件**：与默认行为相同，冲突文件会被备份到 `.config-backup/`
2. **不提示用户**：跳过冲突文件处理的交互提示，直接继续操作
3. **直接继续**：备份完成后立即执行 checkout，无需用户确认

**与 `--dry-run` 的交互**：

当同时使用 `--auto-stash` 和 `--dry-run` 时：
- 打印将要备份的文件列表
- 不执行实际备份操作
- 不执行 checkout 操作
- 在打印报告后退出

这使得用户可以在执行前预览 `--auto-stash` 的影响范围。

### 1. switch-desktop.sh — 桌面模式切换

合并了原 install-2.sh 和 restore-desktop.sh 的功能。

**状态检测与自主决策**：
```
当前状态？
  ├─ fresh   → 全新安装：克隆仓库，checkout 所有文件
  ├─ server  → 复用现有 .cfg，获取更新，checkout 桌面文件
  └─ desktop → 提示重新安装（--reinstall 跳过提示）
```

**执行流程**：
1. 解析参数（`cfg_parse_common_args`）
2. 验证仓库身份（`cfg_validate`）
3. 处理无效/外部仓库（`--force` 时备份并删除）
4. 根据当前状态准备仓库（克隆或复用）
5. 分析所有跟踪文件（`cfg_analyze_files`）
6. 打印安装前报告
7. 如果 `--dry-run`，退出
8. 备份冲突文件（`--auto-stash` 时自动备份不提示）
9. Checkout 所有桌面配置（`cfg_checkout_files`）
10. 若 checkout 失败数 >5 或失败率 >10% 则自动回滚（`cfg_rollback_from_backup`）
11. 激活仓库（如果是 fresh 克隆）
12. 记录 `.cfg-checkout-state`，设置 `showUntrackedFiles = no`

### 2. switch-server.sh — 服务器模式切换

合并了原 install-server.sh 和 restore-server.sh 的功能。

**状态检测与自主决策**：
```
当前状态？
  ├─ fresh   → 全新安装：克隆仓库，只 checkout 服务器白名单文件
  ├─ desktop → 复用现有 .cfg，先删除桌面指标文件，再 checkout 服务器文件
  └─ server  → 提示重新安装（--reinstall 跳过提示）
```

**服务器文件清单**（`server-files.txt`）：

服务器模式 checkout 的文件列表由仓库根目录的 `server-files.txt` 配置文件管理。用户可自定义此文件以添加或删除服务器模式下的配置文件。

配置文件位置：`~/.cfg/server-files.txt`（bare repo 根目录）

格式：每行一个文件路径（相对于 `$HOME`），`#` 开头的行为注释。

**默认文件列表**（21 个）：

```
Shell:    .config/shell/profile, .config/shell/aliasrc, .config/shell/zshrc,
          .config/shell/tmux.conf.local, .bashrc, .zshrc, .profile
Tmux:     .config/tmux/tmux.conf, .config/tmux/tmux.conf.local, .tmux.conf
Git:      .config/git/gitconfig, .config/git/ignore, .gitconfig, .gitignore
LF:       .config/lf/lfrc, .config/lf/scope, .config/lf/cleaner,
          .config/lf/icons, .config/lf/shortcutrc
文档:     .local/share/docs/README.md, .local/share/docs/user/desktop-guide-zh.md
```

**自定义方法**：

```bash
# 查看当前配置
git --git-dir=~/.cfg/ show HEAD:server-files.txt

# 编辑配置（需要 commit）
git --git-dir=~/.cfg/ --work-tree=~ edit server-files.txt
git --git-dir=~/.cfg/ --work-tree=~ add server-files.txt
git --git-dir=~/.cfg/ --work-tree=~ commit -m "Customize server file list"
```

如果 `server-files.txt` 不存在，系统会回退到内置的默认列表。

**桌面指标文件移除**（从 desktop 切换时）：

**符号链接**（7 个）：`.xinitrc`、`.xprofile`、`.asoundrc`、`.gtkrc-2.0`、`.tmux.conf`、`.gitconfig`、`.gitignore`

**目录**（5 个）：`.config/x11`、`.config/alsa`、`.config/mpd`、`.config/nsxiv`、`.config/zathura`

其中 `.tmux.conf`、`.gitconfig`、`.gitignore` 属于服务器文件白名单，移除后会立即重新 checkout 服务器版本。

### 3. uninstall.sh — 恢复到 fresh 状态

**安全性设计**：
- 只删除用户配置文件，恢复到 fresh 状态（如同从未安装）
- 安装基础设施（脚本、库）永远不被删除，支持重新安装
- 不自动删除备份，由用户手动决定是否清理（或使用 `--clean-backups`）
- 任何状态都可恢复，所有操作幂等

**恢复流程**：
1. 确定要移除的文件（优先从 `.cfg-checkout-state` 读取，回退到 `git ls-tree`）
2. 过滤出安装基础设施文件（不删除）：
   - `.local/bin/dotcfg`
   - `.local/lib/dotfiles/*`
3. 扫描 `.config-backup/` 下所有会话目录
4. **按目录名称时间戳排序**（格式：`{from}-to-{to}-{YYYYMMDDTHHMMSS}`）
   - 优先使用目录名中的时间戳（确定性高，不受文件系统影响）
   - 如果目录名不符合格式，回退到 mtime 排序
5. 解析每个 MANIFEST.txt，构建文件→备份会话的关联映射
6. 选择恢复源：默认恢复**最早**版本（原始文件），`--latest` 恢复**最新**版本
7. 移除用户配置文件（保留安装基础设施）
8. 从备份中 `cp`（非 `mv`）恢复用户文件——保持备份完整，支持幂等
9. 打印手动清理说明（可选）：
   - 备份目录：`~/.config-backup`
   - 仓库：`~/.cfg`

**保护的安装文件**：
以下文件在 uninstall 时永远不被删除，确保系统可以重新安装或恢复：
- 入口脚本：`dotcfg`
- 运行时库：`.local/lib/dotfiles/*`

文档和测试文件不保护，会在 uninstall 时删除。

---

## 文件处理逻辑

### 文件分类决策树

每个安装/切换脚本对仓库中的每个跟踪文件执行以下判断：

```
文件在 $HOME 中存在？
  ├─ 否 → 直接 checkout（无需备份）
  └─ 是
      ├─ 文件在仓库中被跟踪？
      │   ├─ 否 → 备份为「未跟踪文件」(untracked)
      │   └─ 是
      │       ├─ MD5 与仓库 HEAD 相同 → 跳过（未修改）
      │       └─ MD5 与仓库 HEAD 不同 → 备份为「已修改文件」(modified)
```

### 三种文件状态

| 状态 | 含义 | 备份？ | 示例 |
|------|------|--------|------|
| `untracked` | 用户自己的文件，不在仓库中 | 是 | 用户自建的 `.bashrc` |
| `modified` | 仓库跟踪的文件，但内容已修改 | 是 | 用户修改过的 `.gitconfig` |
| （相同） | 仓库跟踪的文件，内容一致 | 否 | 上次 checkout 的 `.tmux.conf` |

### 不同脚本的处理差异

| 脚本 | 处理的文件范围 | 特殊逻辑 |
|------|----------------|----------|
| `switch-desktop.sh` | 仓库中所有跟踪文件 | fresh 时克隆仓库；server 时复用现有仓库 |
| `switch-server.sh` | 服务器白名单内的文件 | desktop 时先删除桌面指标文件 |
| `uninstall.sh` | `.cfg-checkout-state` 或 `git ls-tree` 列出的文件 | 移除 + 从备份恢复 |

### 桌面特有产物（switch-server.sh 移除列表）

switch-server.sh 从 desktop 切换到 server 时，移除以下桌面特有文件和目录：

**符号链接**（7 个）：`.xinitrc`、`.xprofile`、`.asoundrc`、`.gtkrc-2.0`、`.tmux.conf`、`.gitconfig`、`.gitignore`

**目录**（5 个）：`.config/x11`、`.config/alsa`、`.config/mpd`、`.config/nsxiv`、`.config/zathura`

**状态检测指标**（9 个）：上述列表中除去 `.tmux.conf`、`.gitconfig`、`.gitignore` 的剩余 9 项。这 3 个文件在服务器模式下也存在（属于 CFG_SERVER_FILES），因此不作为桌面指标。switch-server.sh 会先移除它们，然后立即从服务器白名单重新 checkout。

---

## 备份系统

### 目录结构

```
~/.config-backup/
  ├── {from}-to-{to}-{YYYYMMDDTHHMMSS}/    ← 会话目录
  │   ├── MANIFEST.txt                      ← 转换记录
  │   ├── .bashrc                           ← 备份的文件（保持相对路径）
  │   └── .config/
  │       └── shell/
  │           └── zshrc
  ├── invalid-{YYYYMMDDTHHMMSS}/            ← --force 备份的无效仓库
  ├── foreign-{YYYYMMDDTHHMMSS}/            ← --force 备份的外部仓库
  └── valid-to-fresh-{YYYYMMDDTHHMMSS}/     ← --force 备份的有效仓库
```

**命名约定**：`{当前状态}-to-{目标状态}-{时间戳}`

**权限**：所有会话目录 `chmod 700`，仅当前用户可访问。

### MANIFEST.txt 格式

```
# Created: Mon Aug  4 10:00:00 UTC 2026
# Transition: fresh -> desktop
#
# relative_path	md5	status
.bashrc	d41d8cd98f00b204e9800998ecf8427e	modified
.config/shell/zshrc	098f6bcd4621d373cade4e832627b4f6	untracked
.ssh/config	a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6	modified
```

**字段说明**：
- `relative_path`：相对于 `$HOME` 的路径
- `md5`：文件备份前的 MD5 哈希（通过 `md5sum` 计算）
- `status`：`modified`（仓库跟踪但内容不同）或 `untracked`（仓库未跟踪）

### Checkout 状态记录

每次安装/恢复后记录文件指纹到 `.cfg-checkout-state`：

```
.bashrc:e99a18c428cb38d5f260853678922e03
.zshrc:d8e8fca2dc0f896fd7cb4cb0031ba249
.profile:5d41402abc4b2a76b9719d911017c592
```

用于 uninstall.sh 快速确定需要移除的文件列表，以及判断文件是否被用户修改。

---

## 部署与恢复原则

### 部署原则

1. **先检测后操作**：所有脚本先检测当前状态，再决定操作路径
2. **先备份后修改**：冲突文件在修改前必须备份到 `.config-backup/`
3. **先预览后执行**：`--dry-run` 可在任何操作前使用
4. **失败可回滚**：checkout 失败数 >5 或失败率 >10% 时自动从备份恢复

### 恢复原则

1. **备份链完整性**：`.config-backup/` + `.cfg/`  Together 足以恢复到任意历史状态
2. **默认恢复最早版本**：uninstall 默认从最早的备份会话恢复（还原用户原始文件）
3. **可选恢复最新版本**：`--latest` 从最近的备份会话恢复
4. **按文件粒度选择**：每个文件独立选择恢复源，不同文件可来自不同会话
5. **复制而非移动**：恢复使用 `cp` 而非 `mv`，保持备份完整，支持多次执行

### 时间排序策略

备份会话优先按目录名称时间戳排序（格式：`{from}-to-{to}-{YYYYMMDDTHHMMSS}`）。如果目录名不符合格式，回退到文件系统 mtime 排序。

---

## 幂等性

### 安装幂等性

- 重复执行 `dotcfg switch desktop --reinstall` 或 `dotcfg switch server --reinstall` 不会产生多余备份
- 已跟踪且内容相同的文件被跳过（不备份、不重新 checkout）
- `.cfg-checkout-state` 记录上次 checkout 的文件指纹，用于快速对比

### 卸载幂等性

- 重复执行 `dotcfg switch fresh` 产生相同结果
- 恢复使用 `cp`（非 `mv`），备份文件不被消耗
- 已移除的文件再次执行时直接跳过

### 切换幂等性

- `switch-desktop.sh` 和 `switch-server.sh` 重复执行结果一致
- 无冲突文件时不创建备份目录
- `--auto-stash` 模式自动备份冲突文件，不创建交互提示

---

## 可恢复性

### 恢复场景

| 场景 | 恢复方法 |
|------|----------|
| 安装过程中断 | 备份已创建，手动恢复或重新运行脚本 |
| checkout 大面积失败 | 自动回滚（失败数 >5 或失败率 >10%），从备份恢复 |
| 切换后不满意 | 运行反向切换脚本（如 desktop→server→desktop） |
| 完全卸载后恢复 | 从 `.config-backup/` 手动恢复文件 |
| 多次切换后恢复原始文件 | `uninstall.sh`（默认恢复最早备份） |

### 恢复保障机制

1. **MANIFEST.txt**：精确记录每个备份文件的来源路径、内容和状态
2. **备份链**：每次状态转换创建独立会话，不覆盖历史备份
3. **MD5 校验**：MANIFEST 中记录备份前的 MD5，可用于验证备份完整性
4. **备份保留**：恢复操作使用 `cp` 不消耗备份，支持反复恢复

---

## 安全机制

### 卸载保护

`uninstall.sh` 不自动删除 `.cfg` 仓库，防止误操作导致数据丢失。用户需手动执行 `rm -rf ~/.cfg`。

### 路径安全检查

安装前检查符号链接目标，拒绝跟随符号链接祖先，验证所有符号链接在 `$HOME` 内。

### 权限保护

备份目录权限设为 `0700`，只允许当前用户访问。

### 仓库身份验证

所有脚本在执行前验证 `.cfg` 是否为本项目的 dotfiles 仓库（双重验证：remote URL + 签名文件），防止误操作其他 git 仓库。

---

## 使用场景

### 场景 1：全新桌面安装
```bash
dotcfg switch desktop --dry-run  # 预览
dotcfg switch desktop            # 安装
exec zsh                         # 重启 shell
```

### 场景 2：服务器部署
```bash
dotcfg switch server --dry-run   # 预览
dotcfg switch server             # 安装
```

### 场景 3：桌面 ↔ 服务器切换
```bash
dotcfg switch server             # 桌面 → 服务器
dotcfg switch desktop            # 服务器 → 桌面
```

### 场景 4：查看状态和历史
```bash
dotcfg                           # 当前状态
dotcfg graph                     # 状态图
dotcfg history                   # 转换历史
dotcfg validate                  # 仓库验证详情
```

### 场景 5：完全卸载
```bash
dotcfg switch fresh              # 卸载并恢复备份
rm -rf ~/.cfg                    # 手动删除仓库
```

---

## 故障排除

### 安装失败后恢复
```bash
ls ~/.config-backup/                          # 检查备份会话
dotcfg history                                # 查看转换历史
cp ~/.config-backup/*/path/to/file ~/         # 手动恢复
rm -rf ~/.cfg                                 # 删除仓库
dotcfg switch desktop                         # 重新安装
```

### 符号链接指向错误
```bash
rm ~/.bashrc
git --git-dir=$HOME/.cfg/ --work-tree=$HOME checkout HEAD -- .bashrc
```

### 状态检测不准确
```bash
dotcfg validate                               # 检查仓库状态
dotcfg status                                 # 检查当前安装状态
# 或手动检查全部 9 个桌面指标文件
ls -la ~/.xinitrc ~/.xprofile ~/.config/x11 ~/.asoundrc ~/.gtkrc-2.0 \
       ~/.config/alsa ~/.config/mpd ~/.config/nsxiv ~/.config/zathura
```

---

## 相关文档

- [安装测试系统](installation-testing.md) — 测试框架和 77 个测试用例
- [安装系统修复记录](../planning/installation-fixes.md) — 已知问题和修复方案
- [依赖清单](dependencies.md) — 项目依赖的软件包
- [架构文档](architecture.md) — 配置库整体架构

---

**最后更新**: 2026-08-05
**版本**: 2.0 — 备份系统重设计 + dotcfg 统一 CLI + 完整可恢复性保障
