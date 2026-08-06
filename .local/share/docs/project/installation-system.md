# 安装系统

本文面向 Agent 和维护者。

## 概述

本配置库实现了一套基于节点模型的幂等性安装、卸载和状态切换系统。系统以 bare git repo 为版本控制核心，通过节点树（node tree）管理状态历史，支持 deploy/undeploy 生命周期和任意历史节点的切换。

### 设计原则

1. **幂等性**：同一操作可重复执行，结果一致，不产生多余副作用
2. **节点追溯**：每次状态转换创建新节点，形成完整的状态树
3. **智能备份**：只备份真正需要保护的文件，通过 MD5 内容对比跳过未修改文件
4. **可恢复性**：节点树 + `.cfg/`  Together 足以恢复到任意历史状态
5. **安全卸载**：不自动删除仓库，防止误操作
6. **部署分离**：deploy/undeploy 独立于节点创建，支持灵活的配置管理

---

## 版本控制思路

### 核心架构

系统使用 **bare git repo** 作为配置源真相（source of truth），配合节点系统管理状态历史：

```
~/.cfg/                    ← bare git repo（git --git-dir=~/.cfg/ --work-tree=~）
~/.config-backup/
├── nodes/
│   ├── index.json         ← 节点索引（父子关系、时间戳、CODE）
│   └── {code}/
│       ├── manifest.txt   ← 备份文件清单
│       ├── backup/        ← 原始文件备份
│       └── files/         ← 该节点 checkout 的文件快照
├── HEAD                   ← 当前节点 CODE
├── DEPLOY_STATUS          ← deployed / uninstalled
└── sessions/              ← 旧会话目录（迁移后归档）
~/.cfg-checkout-state      ← 文件指纹记录（path:md5 格式）
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

## 节点系统

### 节点模型

每次状态转换创建一个**节点**（node），节点通过父子关系形成树结构。节点模型借鉴 Git 的 commit 概念：

| 概念 | 类比 | 说明 |
|------|------|------|
| CODE | commit hash | 8 位随机码 `[a-z0-9]`，唯一标识节点 |
| type | branch label | `fresh` / `desktop` / `server` |
| parent | parent commit | 父节点 CODE，根节点为 `null` |
| children | child commits | 子节点 CODE 列表（支持分支） |
| HEAD | HEAD pointer | 当前活动节点的 CODE |
| DEPLOY_STATUS | working tree | `deployed`（配置已激活）/ `uninstalled`（已卸载） |

### 节点目录结构

每个节点在 `~/.config-backup/nodes/{code}/` 下有独立目录：

```
nodes/{code}/
├── manifest.txt    ← 备份文件清单（从旧 MANIFEST.txt 格式继承）
├── backup/         ← 原始文件备份（转换前 $HOME 中的文件）
└── files/          ← 该节点 checkout 的文件快照（转换后部署的文件）
```

> **注**：首次执行 `switch server/desktop` 时，系统创建根节点（fresh, parent=null），
> 然后创建子节点（desktop/server）。原始文件备份存储在**子节点**的 `backup/` 目录，
> 根节点的 `backup/` 通常为空。

### index.json 格式

节点索引文件 `~/.config-backup/nodes/index.json` 存储所有节点的元数据：

```json
{
  "nodes": [
    {
      "code": "a1b2c3d4",
      "type": "fresh",
      "timestamp": "2026-08-06T10:00:00",
      "parent": null,
      "children": ["e5f6g7h8"]
    },
    {
      "code": "e5f6g7h8",
      "type": "desktop",
      "timestamp": "2026-08-06T10:05:00",
      "parent": "a1b2c3d4",
      "children": []
    }
  ]
}
```

解析策略：使用 awk 行解析（不依赖 jq），格式由系统控制。

### CODE 生成

8 位随机码，字符集 `[a-z0-9]`（36 个字符），使用 `$RANDOM` 生成。碰撞时递归重试。

### 节点管理函数

`utils/nodes.sh` 提供节点管理的核心函数：

| 函数 | 用途 |
|------|------|
| `cfg_nodes_init [backup_root]` | 初始化节点目录和路径变量 |
| `cfg_generate_node_code` | 生成 8 位随机码，确保唯一 |
| `cfg_nodes_read_index` | 解析 index.json → shell 数组 |
| `cfg_nodes_write_index` | 写回 index.json |
| `cfg_node_create <type> <parent>` | 创建节点，返回 CODE |
| `cfg_node_get <code> <field>` | 读取节点字段 |
| `cfg_node_exists <code>` | 检查节点是否存在 |
| `cfg_head_set / cfg_head_get` | HEAD 指针管理 |
| `cfg_deploy_status_set / cfg_deploy_status_get` | 部署状态管理 |
| `cfg_nodes_get_root` | 获取根节点（parent=null） |
| `cfg_nodes_ancestors <code>` | 获取祖先链 |
| `cfg_nodes_count` | 节点总数 |
| `cfg_nodes_needs_migration` | 检测是否需要从旧系统迁移 |

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

### 状态转换与节点创建

每次 `dotcfg switch` 操作创建新节点：

```
┌─────────────┐
│   FRESH     │  ← 根节点 (type=fresh, parent=null)
└──────┬──────┘
       │
       ├─ dotcfg switch desktop ──→ DESKTOP  (新节点, parent=当前)
       └─ dotcfg switch server ───→ SERVER   (新节点, parent=当前)

┌─────────────┐
│  DESKTOP    │  ← 节点 (type=desktop)
└──────┬──────┘
       │
       ├─ dotcfg switch desktop --reinstall ─→ DESKTOP  (新节点, 幂等重装)
       ├─ dotcfg switch server ──────────────→ SERVER   (新节点)
       └─ dotcfg uninstall ──────────────────→ FRESH    (HEAD 移回根节点)

┌─────────────┐
│   SERVER    │  ← 节点 (type=server)
└──────┬──────┘
       │
       ├─ dotcfg switch server --reinstall ──→ SERVER   (新节点, 幂等重装)
       ├─ dotcfg switch desktop ─────────────→ DESKTOP  (新节点)
       └─ dotcfg uninstall ──────────────────→ FRESH    (HEAD 移回根节点)
```

### 分支支持

`dotcfg switch <CODE>` 可切换到任意历史节点，从该节点产生分支：

```bash
dotcfg list                     # 查看所有节点和 CODE
dotcfg switch xk7f9a2m          # 切换到历史节点，产生新分支
```

切换流程：undeploy 当前节点 → 移动 HEAD → deploy 目标节点。

---

## 统一命令行入口

`dotcfg` 命令提供 git 风格的统一入口：

```bash
dotcfg                          # 显示当前节点状态（等同于 dotcfg status）
dotcfg status                   # 当前节点 + 部署状态 + 可用操作
dotcfg list                     # 四列表：DEPLOY / TYPE / TIME / CODE
dotcfg history                  # Git log --graph 风格 ASCII 分支图
dotcfg switch <target>          # 切换到状态名（desktop|server）或 CODE
dotcfg deploy                   # 在当前节点部署配置
dotcfg undeploy                 # 卸载当前节点配置，恢复原始文件
dotcfg uninstall                # 回到根节点（fresh）
dotcfg migrate                  # 手动迁移旧会话到节点系统
dotcfg validate                 # 详细仓库验证
dotcfg help                     # 使用帮助
```

### `dotcfg status` 输出

```
Current node: xk7f9a2m (desktop)
Created: 2026-08-06 10:05:00
Deploy status: deployed
Chain: fresh -> desktop

Available operations:
  dotcfg switch desktop    Install/switch to desktop mode
  dotcfg switch server     Install/switch to server mode
  dotcfg deploy            Deploy current node
  dotcfg undeploy          Undeploy current node
  dotcfg uninstall         Return to fresh state
  dotcfg list              List all nodes
  dotcfg history           Show node tree
```

### `dotcfg list` 输出

```
  DEPLOY TYPE       TIME                 CODE
  [*]    desktop   2026-08-06 10:05:00  xk7f9a2m
  [ ]    fresh     2026-08-06 10:00:00  a1b2c3d4
```

标记说明：`[*]` = HEAD + deployed，`[>]` = HEAD + uninstalled，`[ ]` = 非 HEAD。

### `dotcfg history` 输出

Git log --graph 风格，最新节点在顶部，根在底部：

**颜色方案**（终端支持时启用）：
- 绿色：`<- HEAD` 标签
- 黄色：`[deployed]` 状态
- 灰色：`[uninstalled]` 状态
- 蓝色：图形元素（`*`、`o`、`|`、`/`、`\`）

**线性历史：**
```
*  a1b2c3d4  desktop  2026-08-06 12:00:00  [deployed]  <- HEAD
| 
o  e5f6g7h8  server   2026-08-06 11:00:00
| 
o  i9j0k1l2  fresh    2026-08-06 10:00:00
```

**分支历史：**
```
*  a1b2c3d4  desktop  2026-08-06 12:00:00  [deployed]  <- HEAD
| 
o  e5f6g7h8  server   2026-08-06 11:00:00
| 
o  i9j0k1l2  fresh    2026-08-06 10:00:00
|\
| o  m3n4o5p6  server   2026-08-06 10:30:00
|/
```

**多分支历史：**
```
*  a1b2c3d4  desktop  2026-08-06 12:00:00  [deployed]  <- HEAD
|
o  e5f6g7h8  server   2026-08-06 11:00:00
|\
| o  m3n4o5p6  server   2026-08-06 10:30:00
|/
o  i9j0k1l2  fresh    2026-08-06 10:00:00
```

**符号说明：**
- `*` = HEAD 节点（当前所在）
- `o` = 普通节点
- `|` = 主线垂直延续
- `|\` = 分支起点（从主线分叉）
- `|/` = 分支合并（分叉回到主线）

### 自动迁移

首次运行 `dotcfg` 命令时（除 help/version/migrate 外），系统自动检测旧备份会话目录（格式 `{from}-to-{to}-{timestamp}`）。如果检测到旧会话，自动执行迁移：

1. 创建根 fresh 节点
2. 按时间顺序为每个旧会话创建子节点
3. 复制备份文件和 MANIFEST 到节点目录
4. 旧会话移入 `sessions/` 归档
5. 设置 HEAD 为最后节点

---

## 部署与卸载

### deploy — 部署当前节点

`dotcfg deploy` 在当前 HEAD 节点上激活配置：

1. 读取 HEAD → current_code，检查部署状态
2. 如果已部署，提示退出（`--force` 覆盖）
3. 根据节点类型确定文件列表（desktop=全部跟踪文件，server=白名单文件）
4. 备份当前 `$HOME` 中可能被覆盖的文件 → `nodes/{code}/backup/`
5. checkout 节点配置 → `$HOME`
6. 记录到 `nodes/{code}/files/`，更新 manifest
7. 设置 `DEPLOY_STATUS = deployed`

### undeploy — 卸载当前节点

`dotcfg undeploy` 撤销当前节点的部署：

1. 读取 HEAD，检查部署状态
2. 如果已未部署，提示退出
3. 删除 `nodes/{code}/files/` 中记录的所有文件
4. 从 `nodes/{code}/backup/` 恢复原始文件
5. 设置 `DEPLOY_STATUS = uninstalled`

### uninstall — 回到根节点

`dotcfg uninstall` 返回到初始 fresh 状态：

1. undeploy 当前节点（如有部署）
2. 移动 HEAD 到根节点（fresh）
3. 根节点标记为 deployed（恢复原始文件）
4. 输出清理提示（保留 `.cfg` 仓库，需手动删除）

---

## 核心脚本

### 脚本总览

**命令脚本**（位于 `.local/lib/dotfiles/commands/`）：

| 脚本 | 用途 |
|------|------|
| `switch.sh` | 统一切换逻辑（`--type=desktop` / `--type=server`） |
| `switch-desktop.sh` | 转发到 `switch.sh --type=desktop` |
| `switch-server.sh` | 转发到 `switch.sh --type=server` |
| `deploy.sh` | 部署当前节点配置 |
| `undeploy.sh` | 卸载当前节点配置 |
| `uninstall.sh` | 回到根节点（fresh） |
| `migrate.sh` | 迁移旧会话到节点系统 |

**工具库**（位于 `.local/lib/dotfiles/utils/`）：

| 文件 | 职责 |
|------|------|
| `common.sh` | 顶层加载器，source 所有工具库（含 `nodes.sh`） |
| `nodes.sh` | 节点管理（CRUD、HEAD、deploy status、树操作） |
| `args.sh` | 参数解析（`cfg_parse_common_args`） |
| `backup.sh` | 备份创建和文件备份（含节点备份适配） |
| `rollback.sh` | 回滚判断和执行（含节点备份恢复） |
| `checkout.sh` | 文件 checkout、路径安全检查和状态记录 |
| `repo.sh` | 仓库克隆和激活 |
| `files.sh` | 文件分类和常量定义 |

### 通用参数

所有命令脚本支持：
- `--dry-run` — 预览操作，不修改文件
- `--force` — 强制操作（覆盖部署状态、替换仓库等）

特定脚本额外支持：
- `--reinstall` — 跳过交互提示，直接重新安装（switch-desktop / switch-server）
- `--auto-stash` — 自动备份冲突文件，不提示用户（仅 switch-desktop）
- `--latest` — 恢复最新备份而非最早（仅 uninstall）
- `--type=<state>` — 目标状态类型（仅 switch.sh 内部使用）

### switch.sh — 统一切换

合并了 switch-desktop 和 switch-server 的共享逻辑（~70% 相同代码）。

**执行流程**：
1. 解析参数（`--type=desktop|server`）
2. 验证仓库身份（`cfg_validate`）
3. 处理无效/外部仓库（`--force` 时备份并删除）
4. 根据当前状态准备仓库（克隆或复用）
5. 分析文件（desktop=全部跟踪文件，server=白名单文件）
6. 打印安装前报告
7. 如果 `--dry-run`，退出
8. 备份冲突文件
9. desktop→server 时删除桌面指标文件
10. Checkout 新配置
11. 若 checkout 失败数 >5 或失败率 >10% 则自动回滚
12. 激活仓库（如果是 fresh 克隆）
13. 记录 `.cfg-checkout-state`，设置 `showUntrackedFiles = no`
14. **创建新节点**，更新 HEAD，设置 `DEPLOY_STATUS = deployed`

**服务器模式特殊处理**：checkout state 文件只记录服务器白名单内的文件（过滤掉桌面专有文件）。

### deploy.sh — 部署

详见上方"部署与卸载"章节。

### undeploy.sh — 卸载

详见上方"部署与卸载"章节。

### uninstall.sh — 恢复到 fresh 状态

**安全性设计**：
- undeploy 当前节点，移动 HEAD 到根节点
- 安装基础设施（脚本、库）永远不被删除
- 不自动删除 `.cfg` 仓库，由用户手动决定
- 任何状态都可恢复，所有操作幂等

**恢复流程**：
1. 扫描所有备份源（节点目录 + 旧会话目录）
2. 按时间戳排序
3. 解析 MANIFEST，构建文件→备份会话的关联映射
4. 选择恢复源：默认恢复**最早**版本，`--latest` 恢复**最新**版本
5. 移除用户配置文件（保留安装基础设施）
6. 从备份中 `cp`（非 `mv`）恢复用户文件——保持备份完整，支持幂等
7. 打印手动清理说明

### migrate.sh — 迁移

将旧会话备份系统迁移到节点系统：

1. 扫描旧会话目录（匹配 `{from}-to-{to}-{timestamp}` 格式）
2. 按时间排序
3. 创建根 fresh 节点
4. 为每个旧会话创建子节点，复制备份数据
5. 设置 HEAD = 最后节点
6. 旧目录移入 `sessions/`（不删除）

支持 `--dry-run` 模式。

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
| `switch.sh --type=desktop` | 仓库中所有跟踪文件 | fresh 时克隆仓库；server 时复用现有仓库 |
| `switch.sh --type=server` | 服务器白名单内的文件 | desktop 时先删除桌面指标文件 |
| `deploy.sh` | 当前节点类型对应的文件 | 备份到节点目录 |
| `undeploy.sh` | 节点 files/ 中记录的文件 | 从节点 backup/ 恢复 |
| `uninstall.sh` | `.cfg-checkout-state` 或 `git ls-tree` 列出的文件 | 移除 + 从备份恢复 |

### 服务器文件清单

服务器模式 checkout 的文件列表由仓库根目录的 `server-files.txt` 配置文件管理。

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

如果 `server-files.txt` 不存在，系统回退到内置默认列表。

---

## 备份系统

### 节点备份结构

```
~/.config-backup/
├── nodes/
│   ├── index.json
│   └── {code}/
│       ├── manifest.txt        ← 备份清单
│       ├── backup/             ← 原始文件备份
│       │   ├── .bashrc
│       │   └── .config/shell/zshrc
│       └── files/              ← 部署的文件快照
│           ├── .bashrc
│           └── .config/shell/zshrc
├── HEAD
├── DEPLOY_STATUS
└── sessions/                   ← 旧会话归档
```

### manifest.txt 格式

```
# Created: Wed Aug  6 10:05:00 UTC 2026
# Node: xk7f9a2m
#
# relative_path	md5	status
.bashrc	d41d8cd98f00b204e9800998ecf8427e	modified
.config/shell/zshrc	098f6bcd4621d373cade4e832627b4f6	untracked
```

### Checkout 状态记录

每次安装/恢复后记录文件指纹到 `.cfg-checkout-state`：

```
.bashrc:e99a18c428cb38d5f260853678922e03
.zshrc:d8e8fca2dc0f896fd7cb4cb0031ba249
```

用于 uninstall.sh 快速确定需要移除的文件列表。

---

## 幂等性

### 安装幂等性

- 重复执行 `dotcfg switch desktop --reinstall` 或 `dotcfg switch server --reinstall` 创建新节点
- 已跟踪且内容相同的文件被跳过（不备份、不重新 checkout）
- `.cfg-checkout-state` 记录上次 checkout 的文件指纹

### 部署幂等性

- `dotcfg deploy` 已部署时直接退出（除非 `--force`）
- `dotcfg undeploy` 已卸载时直接退出（除非 `--force`）

### 卸载幂等性

- 重复执行 `dotcfg uninstall` 产生相同结果
- 恢复使用 `cp`（非 `mv`），备份文件不被消耗
- 已移除的文件再次执行时直接跳过

---

## 可恢复性

### 恢复场景

| 场景 | 恢复方法 |
|------|----------|
| 安装过程中断 | 备份已创建，手动恢复或重新运行脚本 |
| checkout 大面积失败 | 自动回滚（失败数 >5 或失败率 >10%），从节点备份恢复 |
| 切换后不满意 | `dotcfg switch <旧CODE>` 回到历史节点 |
| 完全卸载后恢复 | `dotcfg uninstall`（从节点备份恢复） |
| 多次切换后恢复原始文件 | `dotcfg uninstall`（默认恢复最早备份） |

---

## 安全机制

### 卸载保护

`dotcfg uninstall` 不自动删除 `.cfg` 仓库，防止误操作导致数据丢失。用户需手动执行 `rm -rf ~/.cfg`。

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
dotcfg switch desktop            # 安装（创建节点）
exec zsh                         # 重启 shell
```

### 场景 2：服务器部署
```bash
dotcfg switch server --dry-run   # 预览
dotcfg switch server             # 安装（创建节点）
```

### 场景 3：桌面 ↔ 服务器切换
```bash
dotcfg switch server             # 桌面 → 服务器（创建新节点）
dotcfg switch desktop            # 服务器 → 桌面（创建新节点）
```

### 场景 4：查看状态和历史
```bash
dotcfg                           # 当前节点状态
dotcfg list                      # 所有节点列表
dotcfg history                   # 节点树（ASCII 图）
dotcfg validate                  # 仓库验证详情
```

### 场景 5：切换到历史节点
```bash
dotcfg list                      # 查看节点 CODE
dotcfg switch xk7f9a2m           # 切换到历史节点（产生分支）
```

### 场景 6：部署/卸载
```bash
dotcfg undeploy                  # 卸载当前节点配置
dotcfg deploy                    # 重新部署
```

### 场景 7：完全卸载
```bash
dotcfg uninstall                 # 回到 fresh 根节点
rm -rf ~/.cfg                    # 手动删除仓库
```

---

## 故障排除

### 安装失败后恢复
```bash
dotcfg list                          # 查看节点列表
dotcfg history                       # 查看节点树
dotcfg undeploy                      # 卸载当前节点
dotcfg switch <parent_code>          # 切换到父节点
```

### 节点系统损坏
```bash
dotcfg migrate                       # 重新迁移（如果旧会话仍在 sessions/）
# 或手动重建 index.json
```

### 符号链接指向错误
```bash
rm ~/.bashrc
git --git-dir=$HOME/.cfg/ --work-tree=$HOME checkout HEAD -- .bashrc
```

### 状态检测不准确
```bash
dotcfg validate                      # 检查仓库状态
dotcfg status                        # 检查当前节点状态
# 或手动检查全部 9 个桌面指标文件
ls -la ~/.xinitrc ~/.xprofile ~/.config/x11 ~/.asoundrc ~/.gtkrc-2.0 \
       ~/.config/alsa ~/.config/mpd ~/.config/nsxiv ~/.config/zathura
```

---

## 相关文档

- [安装测试系统](installation-testing.md) — 测试框架和 145 个测试用例
- [安装系统修复记录](../planning/installation-fixes.md) — 已知问题和修复方案
- [依赖清单](dependencies.md) — 项目依赖的软件包
- [架构文档](architecture.md) — 配置库整体架构

---

**最后更新**: 2026-08-06
**版本**: 3.0 — 节点系统 + deploy/undeploy + 分支支持 + 自动迁移
