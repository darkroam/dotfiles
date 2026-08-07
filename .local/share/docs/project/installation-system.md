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
│   ├── index.json         ← 节点索引（父子关系、时间戳、CODE、config_version、status）
│   └── {code}/
│       ├── manifest.txt   ← 备份文件清单
│       ├── backup/        ← 原始文件备份
│       └── files/         ← 该节点 checkout 的文件快照
├── HEAD                   ← 当前节点 CODE
├── DEPLOY_STATUS          ← deployed / uninstalled
├── CURRENT_CONFIG_VERSION ← 当前使用的配置文件版本号
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

> **注**：转换时的原始文件备份存储在 switch 操作创建的子节点中。
> 根节点（fresh，固定 CODE `fresh_root`）在首次安装/迁移时执行 $HOME 全量备份（按排除规则过滤），
> 作为 `uninstall` 的恢复锚点。`uninstall` 优先从 `fresh_root/backup/` 恢复原始文件；
> fresh 备份中不存在的文件回退到子节点备份链（按时间戳排序）。

### index.json 格式

节点索引文件 `~/.config-backup/nodes/index.json` 存储所有节点的元数据。
`timestamp` 格式为 ISO 8601：`YYYY-MM-DDTHH:MM:SS`（UTC 时间）。

```json
{
  "nodes": [
    {
      "code": "a1b2c3d4",
      "type": "fresh",
      "config_version": "1.0.0",
      "timestamp": "2026-08-06T10:00:00",
      "parent": null,
      "children": ["e5f6g7h8"],
      "status": "active"
    },
    {
      "code": "e5f6g7h8",
      "type": "desktop",
      "config_version": "1.0.0",
      "timestamp": "2026-08-06T10:05:00",
      "parent": "a1b2c3d4",
      "children": [],
      "status": "active"
    }
  ]
}
```

**字段说明**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `code` | string | 8 位随机码，唯一标识节点 |
| `type` | string | 节点类型：`fresh` / `desktop` / `server` |
| `config_version` | string | 创建该节点时使用的配置文件版本号（如 `"1.0.0"`） |
| `timestamp` | string | 节点创建时间（ISO 8601） |
| `parent` | string/null | 父节点 CODE，根节点为 `null` |
| `children` | array | 子节点 CODE 列表 |
| `status` | string | 节点状态：`active`（正常）或 `marked_for_removal`（待删除） |

**向后兼容**：旧格式 index.json（无 `config_version`/`status` 字段）可正常读取，缺失字段默认为 `config_version=""` 和 `status="active"`。

解析策略：使用 awk 行解析（不依赖 jq），格式由系统控制。

> **metadata 限制说明**：index.json **不存储**额外统计字段（如 fresh 节点的备份文件数/总大小）。
> awk 行解析器不支持嵌套结构，写入时会丢弃未知字段，因此节点统计信息不进入 JSON schema。
> fresh 节点的统计（文件数、总大小、按 status 分组）从 `nodes/fresh_root/manifest.txt` 实时派生
> （`fresh_backup_count` / `fresh_backup_size`，见 utils/fresh.sh）。

### CODE 生成

8 位随机码，字符集 `[a-z0-9]`（36 个字符），使用 `$RANDOM` 生成。碰撞时递归重试。

**例外**：根节点使用固定 CODE `fresh_root`（新安装与迁移均使用该码；旧的随机码根节点通过
`parent=null` 识别并继续兼容）。`fresh` 可作为根节点的别名在 `switch` 等命令中使用。

### CODE 唯一性保护（全局规则）

CODE 是节点的唯一标识符，整个节点树中**不能存在两个 CODE 相同的节点**。以下所有操作都必须遵守此规则：

| 操作场景 | 保护行为 |
|----------|----------|
| **自动生成**（`cfg_generate_node_code`） | 生成的 CODE 必须与 `index.json` 中所有现有节点比对，碰撞时递归重试，直至生成唯一 CODE |
| **用户/系统指定**（`cfg_node_create` 的 `code` 参数） | 创建前必须检查该 CODE 是否已被占用；如已存在，**拒绝创建**并报错 `Error: Code already exists: <code>` |
| **显式覆盖** | 不支持任何形式的 CODE 覆盖。如需复用某个 CODE，必须先删除原节点（或通过 `autoclean` 清理）后再创建 |

**适用范围**：
- `cfg_node_create`（无论 `code` 参数是否指定）
- `cfg_generate_node_code`
- 迁移过程中创建节点（`migrate.sh`）
- bootstrap 安装过程中创建节点（`bootstrap-lib.sh`）

**例外**：无例外。CODE 必须在整个节点树中保持全局唯一。

### 节点管理函数

`utils/nodes.sh` 提供节点管理的核心函数：

| 函数 | 用途 |
|------|------|
| `cfg_nodes_init [backup_root]` | 初始化节点目录和路径变量 |
| `cfg_generate_node_code` | 生成 8 位随机码，确保唯一 |
| `cfg_nodes_read_index` | 解析 index.json → shell 数组 |
| `cfg_nodes_write_index` | 写回 index.json |
| `cfg_node_create <type> <parent> [version] [code]` | 创建节点，返回 CODE（可选绑定配置版本；可选固定 CODE，用于根节点 `fresh_root`） |
| `cfg_node_get <code> <field>` | 读取节点字段（含 `config_version`、`status`） |
| `cfg_node_exists <code>` | 检查节点是否存在 |
| `cfg_head_set / cfg_head_get` | HEAD 指针管理 |
| `cfg_deploy_status_set / cfg_deploy_status_get` | 部署状态管理 |
| `cfg_nodes_get_root` | 获取根节点（parent=null） |
| `cfg_nodes_ancestors <code>` | 获取祖先链 |
| `cfg_nodes_count` | 节点总数 |
| `cfg_nodes_needs_migration` | 检测是否需要从旧系统迁移 |
| `cfg_node_set_status <code> <status>` | 设置节点状态（`active` / `marked_for_removal`） |
| `cfg_node_set_config_version <code> <version>` | 设置节点配置文件版本 |
| `cfg_nodes_list_marked` | 列出所有 `marked_for_removal` 状态的节点 |
| `cfg_nodes_delete <code>` | 从 index.json 中删除节点并更新父节点 children |
| `cfg_nodes_orphaned_children <code>` | 列出节点的子节点 CODE |
| `cfg_config_version_get_current` | 获取当前使用的配置文件版本（读 `CURRENT_CONFIG_VERSION`） |
| `cfg_config_version_set <version>` | 设置当前使用的配置文件版本 |
| `cfg_config_version_list` | 列出所有可用的配置文件版本 |

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

**节点创建时的版本选择策略**：

执行 `dotcfg switch desktop` 或 `dotcfg switch server` 创建新节点时：

1. 读取 `~/.config-backup/CURRENT_CONFIG_VERSION` 文件
2. 如果文件存在且对应的版本化配置文件存在：
   - 使用该版本号，记录到节点的 `config_version` 字段
3. 如果文件不存在或对应的配置文件不存在：
   - 扫描 `$DOTFILES_LIB_DIR/categories-*.conf`，使用版本号最大的文件
   - 更新 `CURRENT_CONFIG_VERSION` 为该版本号，记录到节点的 `config_version` 字段
4. 如果没有任何版本化配置文件，但存在 `categories.conf`：
   - `config_version` 设为空字符串 `""`
5. 如果只有内置默认类别：
   - `config_version` 设为 `"default"`

**默认行为**：用户无需手动指定版本，版本管理是系统内部行为。系统自动使用 `CURRENT_CONFIG_VERSION` 中记录的版本，若不存在则自动选择最新版本。通过 `dotcfg list` 的 `VERSION` 列可查看每个节点的版本绑定。

**注意**：`dotcfg switch <CODE>`（切换到历史节点）不创建新节点，因此不涉及版本绑定。

---

## 统一命令行入口

`dotcfg` 命令提供 git 风格的统一入口：

```bash
dotcfg                          # 显示当前节点状态（等同于 dotcfg status）
dotcfg status                   # 当前节点 + 部署状态 + 可用操作
dotcfg list                     # 六列表：DEPLOY / TYPE / VERSION / STATUS / TIME / CODE
dotcfg history                  # Git log --graph 风格 ASCII 分支图
dotcfg switch <target>          # 切换到状态名（desktop|server|fresh）或 CODE；fresh = 根节点别名
dotcfg deploy                   # 在当前节点部署配置
dotcfg undeploy                 # 卸载当前节点配置，恢复原始文件
dotcfg uninstall                # 回到根节点（fresh）；恢复源优先 fresh_root 备份
dotcfg remove <code>            # 标记节点为待删除
dotcfg unremove <code>          # 恢复标记的节点
dotcfg autoclean [--dry-run]    # 智能清理标记删除的节点
dotcfg categories [subcommand]  # 配置文件版本管理
dotcfg migrate                  # 手动迁移旧会话到节点系统
dotcfg validate                 # 详细仓库验证
dotcfg track <file>             # 把文件增量加入 fresh 根备份
dotcfg untrack <file>           # 从 fresh 根备份移除文件
dotcfg fresh-status             # fresh 根备份统计（数量/大小/分组/Top5/最近添加）
dotcfg fresh-diff [path]        # $HOME 与 fresh 备份对比（Modified/New/Missing）
dotcfg fresh-update             # 以当前 $HOME 重建 fresh 根备份
dotcfg doctor                   # 系统完整性自检
dotcfg repair                   # 自动修复（逐项确认，--force 跳过）
dotcfg check-exclude <path>     # 查询某路径被哪条排除规则排除
dotcfg help                     # 使用帮助
```

> **库缺失时**：任何 `dotcfg` 命令检测到库不存在都会进入 **bootstrap 安装模式**
> （见下文「自举安装」章节），因此 `curl dotcfg | bash` 即可完成全新安装。

### `dotcfg status` 输出

```
Current node: xk7f9a2m (desktop)
Created: 2026-08-06 10:05:00
Deploy status: deployed
Config version: 1.0.0
Node status: active
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
  DEPLOY TYPE       VERSION  STATUS      TIME                 CODE
  [*]    desktop    1.0.0    active      2026-08-06 10:05:00  xk7f9a2m
  [ ]    fresh      bootstrap active     2026-08-06 10:00:00  fresh_root ●
  [ ]    server     1.0.0    [REMOVED]   2026-08-06 09:00:00  e5f6g7h8
```

标记说明：`[*]` = HEAD + deployed，`[>]` = HEAD + uninstalled，`[ ]` = 非 HEAD。
行尾 `●` = fresh 根节点。
STATUS 列：`active` = 正常节点，`[REMOVED]` = 标记为待删除（`marked_for_removal`）。

### `dotcfg history` 输出

Git log --graph 风格，最新节点在顶部，根在底部：

**颜色方案**（终端支持时启用）：
- 绿色：`<- HEAD` 标签
- 黄色：`[deployed]` 状态、`[REMOVED]` 标记
- 灰色：`[uninstalled]` 状态
- 蓝色：图形元素（`*`、`o`、`|`、`/`、`\`）

**线性历史：**
```
*  a1b2c3d4  desktop  2026-08-06 12:00:00  [deployed]  v1.0.0  <- HEAD
| 
o  e5f6g7h8  server   2026-08-06 11:00:00  v1.0.0
| 
●  fresh_root fresh    2026-08-06 10:00:00  vbootstrap  [root]
```

**分支历史：**
```
*  a1b2c3d4  desktop  2026-08-06 12:00:00  [deployed]  v2.0.0  <- HEAD
| 
o  e5f6g7h8  server   2026-08-06 11:00:00  v1.0.0
| 
●  fresh_root fresh    2026-08-06 10:00:00  vbootstrap  [root]
|\
| o  m3n4o5p6  server   2026-08-06 10:30:00  v1.0.0  [REMOVED]
|/
```

**多分支历史：**
```
*  a1b2c3d4  desktop  2026-08-06 12:00:00  [deployed]  v2.0.0  <- HEAD
|
o  e5f6g7h8  server   2026-08-06 11:00:00  v1.0.0
|\
| o  m3n4o5p6  server   2026-08-06 10:30:00  v1.0.0  [REMOVED]
|/
●  fresh_root fresh    2026-08-06 10:00:00  vbootstrap  [root]
```

**符号说明：**
- `*` = HEAD 节点（当前所在）
- `o` = 普通节点
- `●` = fresh 根节点（附 `[root]` 标签）
- `|` = 主线垂直延续
- `|\` = 分支起点（从主线分叉）
- `|/` = 分支合并（分叉回到主线）

### 自动迁移

首次运行 `dotcfg` 命令时（除 help/version/migrate/doctor/repair/check-exclude 外），系统自动检测旧备份会话目录（格式 `{from}-to-{to}-{timestamp}`）。如果检测到旧会话，自动执行迁移：

1. 创建根 fresh 节点（固定 CODE `fresh_root`）
2. 按时间顺序为每个旧会话创建子节点
3. 复制备份文件和 MANIFEST 到节点目录
4. 旧会话移入 `sessions/` 归档
5. 设置 HEAD 为最后节点

### `dotcfg categories` — 配置文件版本管理

```bash
dotcfg categories                    # 显示所有版本和当前版本（同 list）
dotcfg categories list               # 列出所有可用版本
dotcfg categories switch <version>   # 切换当前版本
dotcfg categories current            # 显示当前版本
dotcfg categories show <version>     # 显示某个版本的详细信息
```

**`list` 输出示例**：

```
Available configuration versions:
  v1.0.0    (default, 2 categories: server, desktop)
  v2.0.0    (3 categories: server, desktop, workstation)
  v2.1.3    (2 categories: server, desktop)

Current version: v2.1.3

Nodes using each version:
  v1.0.0: a1b2c3d4 (1 node)
  v2.1.3: xk7f9a2m, e5f6g7h8 (2 nodes)
```

**版本切换行为**：

```bash
$ dotcfg categories switch 1.0.0

Switching from v2.1.3 to v1.0.0...
Warning: Some nodes use v2.1.3. They will continue to use v2.1.3 on recovery.
Current version set to v1.0.0.
New nodes will use v1.0.0 by default.
```

切换版本只影响**新创建的节点**，已有节点的版本绑定不变。

---

## 部署与卸载

### deploy — 部署当前节点

`dotcfg deploy` 在当前 HEAD 节点上激活配置：

1. 读取 HEAD → current_code，检查部署状态
2. 如果已部署，提示退出（`--force` 覆盖）
3. 根据节点类别确定文件列表
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

1. 检测 fresh 根节点备份（`nodes/fresh_root/backup/`），存在则作为优先恢复源
2. 卸载前比对 fresh manifest 与 $HOME，输出两类警告：
   - 系统中存在但 fresh 没有 → 列出"将被删除"，提示 `dotcfg track` 保留
   - fresh 有且 MD5 不同 → 列出"将被恢复"到安装前状态
3. y/N 确认（`--force` 跳过）
4. 删除仓库管理的配置文件（保留安装基础设施）
5. 恢复备份：优先 `fresh_root/backup/`；fresh 中不存在的文件回退到子节点备份链
   （`--latest` 取备份链最新，不使用 fresh 优先）
6. 输出清理提示（保留 `.cfg` 仓库，需手动删除）

---

## 节点清理

### remove — 标记节点为待删除

`dotcfg remove <code>` 将节点标记为 `marked_for_removal` 状态：

1. 检查节点是否存在
2. 检查是否为根节点（type=fresh 或 code=fresh_root）→ 拒绝，报错
3. 检查是否为 HEAD 指向的节点 → 拒绝，报错
4. 检查子节点中是否有 `active` 状态的节点 → 如果有，报错（需先处理子节点）
5. 将节点状态改为 `marked_for_removal`

**报错信息**：
```
# 根节点
Error: Cannot remove root node (fresh_root).

# HEAD 节点
Error: Cannot remove current HEAD node. Please switch to another node first.

# 有活跃子节点
Error: Cannot remove node with active children.
  Active children: a1b2c3d4, e5f6g7h8
  Remove children first or use 'dotcfg autoclean'.
```

### unremove — 恢复标记的节点

`dotcfg unremove <code>` 将 `marked_for_removal` 节点恢复为 `active`：

1. 检查节点是否存在
2. 检查节点状态是否为 `marked_for_removal`
3. 如果是，将状态改回 `active`

### remove / unremove 对 switch 的影响

- 状态为 `marked_for_removal` 的节点**不能**作为 `switch` 目标
- 必须先执行 `unremove` 恢复为 `active` 才能 `switch`

### autoclean — 智能清理

```bash
dotcfg autoclean              # 执行清理
dotcfg autoclean --dry-run    # 预览，不执行
```

**清理算法（完整递归）**：

1. 检查 HEAD 节点是否被标记为 `marked_for_removal` → 如果是，报错退出
2. 从根节点开始，深度优先遍历整棵树
3. 对每个节点执行以下判断：

   a. 如果节点状态为 `marked_for_removal`：
      - 递归检查所有子节点（按规则 1-5）
      - 如果子节点全部可删除 → 当前节点变为叶子 → 可删除
      - 如果有子节点保留 → 当前节点不能删除

   b. 如果节点状态为 `active`：
      - 检查子节点中是否有 `marked_for_removal` 的
      - 如果有，递归处理这些标记的子节点
      - 处理后，统计保留的 `active` 子节点数量：
        * 0 个 → 当前节点变为叶子 → 可删除（删除此节点，注意父节点处理见下方接续规则）
        * 1 个 → 将该子节点接到父节点，当前节点可删除（见接续规则）
        * ≥2 个 → 当前节点不能删除

4. 如果指定 `--dry-run`：打印候选删除列表和接续操作，不执行
5. 否则：按候选列表执行物理删除

**接续规则（删除中间节点时）**：

当删除一个中间节点时，其 `active` 子节点需要重新连接到父节点：

| 被删除节点的子节点情况 | 处理方式 |
|------------------------|----------|
| 0 个子节点 | 直接删除 |
| 1 个 `active` 子节点 | 将该子节点的 `parent` 指向被删除节点的父节点，更新父节点的 `children` 列表 |
| 多个 `active` 子节点 | **拒绝删除**，报错提示用户手动处理（`autoclean` 不进行多分支接续） |
| 子节点均为 `marked_for_removal` | 递归处理这些子节点，全部删除后当前节点变为叶子 → 可删除 |

**示例**：
```
删除前：A → B → C（B 被标记删除，C 为 active）
删除后：A → C

删除前：A → B → C, D（B 被标记删除，C、D 均为 active）
处理：报错 "Cannot remove node B: multiple active children (C, D). Please handle manually."
```

**物理删除操作**：

1. 扫描节点的 `files/` 目录，删除已部署到 `$HOME` 下的对应文件
2. 删除 `~/.config-backup/nodes/{code}/` 整个目录（含 `backup/` 和 `files/`）
3. 从 `index.json` 中移除该节点，并更新父节点的 `children` 列表

**`--dry-run` 输出示例**：

```
$ dotcfg autoclean --dry-run

The following nodes will be deleted:
  e5f6g7h8  (server, v1.0.0, 2026-08-06 09:00:00)  - leaf node, marked_for_removal
  f9g8h7i6  (desktop, v1.0.0, 2026-08-06 07:00:00)  - leaf node, marked_for_removal

Total: 2 nodes will be deleted.

Use 'dotcfg autoclean' without --dry-run to execute.
```

---

## 自举安装与 Fresh 根节点

### 自举安装（bootstrap）

`dotcfg` 支持单文件自举安装：当检测到库（`$DOTFILES_LIB_DIR/cfg-validate.sh`）不存在时，
任意 `dotcfg` 命令都会进入 bootstrap 模式，无需预先安装任何库文件。

```bash
# 全新机器上一条命令完成安装
curl -fsSL https://.../dotcfg | bash
```

bootstrap 流程（内联实现，只依赖 git/md5sum/coreutils）：

1. 检测 `~/.cfg`：
   - 存在且为 dotfiles 仓库（ours）→ 从 HEAD 恢复库，继续安装
   - 存在但是外部仓库 → 报错并提示 `rm -rf ~/.cfg` 后重跑
   - 不存在 → `git clone --bare $REMOTE_URL ~/.cfg`
2. 从 `HEAD` 提取库文件到 `$DOTFILES_LIB_DIR`（cfg-validate.sh、utils/*、commands/*、categories-*.conf、exclude.conf）
3. 安装 `dotcfg` 自身到 `$BIN_DIR`
4. source 新装的库，创建 `fresh_root` 节点并执行 $HOME 全量备份
5. 按 server 类别过滤后 checkout（冲突文件备份到 `$BACKUP_ROOT/conflict/`）
6. 写 `HEAD=fresh_root`、`DEPLOY_STATUS=deployed`、`CURRENT_CONFIG_VERSION=bootstrap`
7. re-exec `dotcfg <原参数>`，保证幂等

**远程地址**：默认 `git@github.com:darkroam/dotfiles.git`，可用环境变量 `DOTCFG_REMOTE_URL` 覆盖
（测试即通过该变量指向本地 mock 仓库）。

### Fresh 根节点定位与保护

根节点使用固定 CODE `fresh_root`（`parent=null`），是 uninstall 的恢复锚点。

| 保护项 | 行为 |
|--------|------|
| **`cfg_node_create` 创建时** | `cfg_node_create` 必须检查 `code=fresh_root` 是否已存在；如已存在则**拒绝创建**，报错 `Error: Root node already exists. Cannot create another root.` |
| `remove fresh_root` | 拒绝（type=fresh 与 code=fresh_root 双重判断） |
| `autoclean` | `_autoclean_evaluate` 对 `parent=null` 节点直接拒绝 |
| `switch fresh` | `fresh` 别名解析为根节点 CODE（无根时报错提示 doctor） |
| `list` / `history` | 行尾 `●` 标记，history 附 `[root]` 标签 |

### Fresh manifest 格式（5 列）

fresh 节点专用，区别于普通节点的 3 列格式：

```
# Created: 2026-08-07 03:48:42
# Node: fresh_root
#
# relative_path	md5	size_bytes	status	timestamp
.bashrc	d41d8c…	1024	tracked_at_install	2026-08-07 03:48:42
.myconfig	abc123…	512	tracked_by_user	2026-08-07 04:00:00
```

- `status` ∈ {`tracked_at_install`（安装时全量备份）, `tracked_by_user`（用户手动 track）}
- 备份采用 **cp 语义**（区别于普通节点备份的 mv 语义），原文件保留在 $HOME
- 统计信息（文件数/大小/分组）从该 manifest 实时派生，不写入 index.json

### track / untrack

```bash
dotcfg track <file> [--dry-run] [--force] [--no-add]   # 加入 fresh 备份
dotcfg untrack <file> [--dry-run] [--force]            # 从 fresh 备份移除
```

- `track`：存在性检查 → fresh manifest 查重 → `.cfg` 仓库查重（已跟踪则警告）→
  cp 到 `fresh_root/backup/` → manifest 追加 `tracked_by_user` 条目 → 引导 `git add`
  （默认执行 `git add`，`--no-add` 跳过，不 commit）
- 命中排除规则时警告但允许继续
- `untrack`：manifest 查重 → 删除 backup 文件与 manifest 条目 → 提示 uninstall 不再恢复；
  需 y/N 确认（`--force` 跳过）

### fresh-* 管理命令

```bash
dotcfg fresh-status        # 总数/大小/按 status 分组/Top5 最大/最近添加
dotcfg fresh-diff [path]   # 全量：Modified/New/Missing 三组；单文件：diff -u
dotcfg fresh-diff --summary
dotcfg fresh-update [--force] [--dry-run] [--no-backup]  # 以当前 $HOME 重建备份
```

- `fresh-update` 重建前先把旧节点目录复制为 `fresh_root.bak`（`--no-backup` 跳过）
- `New` 分组来自对 $HOME 的扫描（应用排除规则），默认限前 50 条

### doctor / repair

`doctor` 执行以下 9 项完整性检测：

| 序号 | 检测项 | 检测内容 |
|------|--------|----------|
| 1 | 仓库存在性 | `~/.cfg` 是否存在 |
| 2 | 仓库有效性 | `~/.cfg` 是否为有效的 git 仓库（`git rev-parse --git-dir`） |
| 3 | 仓库归属 | `~/.cfg` 是否为本项目的 dotfiles 仓库（remote URL 或签名文件） |
| 4 | 备份目录存在性 | `~/.config-backup/` 是否存在 |
| 5 | index.json 有效性 | `~/.config-backup/nodes/index.json` 是否存在且可解析 |
| 6 | fresh 节点存在性 | `~/.config-backup/nodes/fresh_root/` 是否存在 |
| 7 | HEAD 指向有效性 | HEAD 指向的节点 CODE 是否在 index.json 中存在 |
| 8 | DEPLOY_STATUS 有效性 | `DEPLOY_STATUS` 文件是否存在且值为 `deployed` 或 `uninstalled` |
| 9 | 配置文件版本存在性 | `$DOTFILES_LIB_DIR/categories-*.conf` 至少存在一个（或存在 `categories.conf` 回退） |

每项输出 ✅/❌ 并计数；有问题时 exit 1。

`repair` 逐项修复（每项前 y/N 确认，`--force` 跳过），修复项与 doctor 检测项对应：

| 序号 | 检测项 | 修复策略 |
|------|--------|----------|
| 1 | ~/.cfg 不存在 | 进入 bootstrap 安装模式（需用户确认） |
| 2 | ~/.cfg 非有效 git 仓库 | 尝试 `git fsck --no-dangling`；失败则报错建议手动处理 |
| 3 | ~/.cfg 非本项目仓库 | 报错，提示用户手动处理（`rm -rf ~/.cfg` 后重跑） |
| 4 | ~/.config-backup/ 缺失 | 创建目录，初始化 index.json，创建 fresh 节点 |
| 5 | index.json 无效/为空 | 尝试从 manifest.txt 重建；失败则报错建议 `migrate` |
| 6 | fresh 节点缺失 | 从 index.json 中的根节点重建 fresh 节点目录；若无根节点则创建 |
| 7 | HEAD 指向缺失节点 | 重置到根节点（fresh_root） |
| 8 | DEPLOY_STATUS 缺失 | 写入 `deployed` |
| 9 | 配置文件版本缺失 | 使用内置默认类别，写入 `CURRENT_CONFIG_VERSION="default"` |

**注意**：`repair` 不处理需要用户介入的复杂问题（如外部仓库误用），此类问题仅输出诊断和建议。

**启动自检**：`dotcfg` 每次调度前做轻量自检（仅 stat + 一次 HEAD 读取，<0.5s）：

| 检测条件 | 触发行为 |
|----------|----------|
| `~/.cfg` 不存在 | 自动进入 bootstrap 安装模式（首次安装） |
| `~/.cfg` 存在但 `~/.config-backup/` 不存在 | 打印 `⚠️  Backup directory missing. Run 'dotcfg doctor' to diagnose.`，不阻塞命令 |
| HEAD 指向的节点在 index.json 中不存在 | 打印 `⚠️  HEAD points to missing node. Run 'dotcfg doctor' to diagnose.`，不阻塞命令 |
| `~/.config-backup/nodes/fresh_root/` 不存在 | 打印 `⚠️  Root node missing. Run 'dotcfg doctor' to diagnose.`，不阻塞命令 |
| 全部正常 | 无输出，直接执行用户命令 |

**设计目标**：启动自检应足够轻量（不扫描文件列表、不解析完整 index.json），仅验证系统关键路径的完整性，避免拖慢每次命令的执行速度。

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
| `uninstall.sh` | 回到根节点（fresh），优先从 fresh_root 备份恢复 |
| `remove.sh` | 标记节点为待删除 |
| `unremove.sh` | 恢复标记的节点 |
| `autoclean.sh` | 智能清理标记删除的节点 |
| `migrate.sh` | 迁移旧会话到节点系统 |
| `track.sh` | 把文件加入 fresh 根备份 |
| `untrack.sh` | 从 fresh 根备份移除文件 |
| `fresh-status.sh` | fresh 根备份统计 |
| `fresh-diff.sh` | $HOME 与 fresh 备份对比 |
| `fresh-update.sh` | 重建 fresh 根备份 |
| `doctor.sh` | 系统完整性自检 |
| `repair.sh` | 自动修复 |
| `check-exclude.sh` | 查询路径的排除规则来源 |
| `bootstrap-lib.sh` | bootstrap 安装收尾逻辑（供 dotcfg 自举调用） |

**工具库**（位于 `.local/lib/dotfiles/utils/`）：

| 文件 | 职责 |
|------|------|
| `common.sh` | 顶层加载器，source 所有工具库（含 `nodes.sh`、`exclude.sh`、`fresh.sh`） |
| `nodes.sh` | 节点管理（CRUD、HEAD、deploy status、树操作） |
| `args.sh` | 参数解析（`cfg_parse_common_args`） |
| `backup.sh` | 备份创建和文件备份（含节点备份适配） |
| `rollback.sh` | 回滚判断和执行（含节点备份恢复） |
| `checkout.sh` | 文件 checkout、路径安全检查和状态记录 |
| `repo.sh` | 仓库克隆和激活 |
| `files.sh` | 文件分析（install/backup/skip 分类） |
| `categories.sh` | 声明式文件类别系统（categories.conf 解析、继承、排除） |
| `exclude.sh` | fresh 备份排除规则（硬编码 + exclude.conf、$HOME 扫描） |
| `fresh.sh` | fresh 根节点与 manifest 管理（创建/读写/统计/增删） |

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
5. 分析文件（根据目标状态的类别定义）
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
1. 检测 fresh 根节点备份（`fresh_root`），加载其 manifest 构建 path→md5 映射
2. 扫描所有备份源（节点目录 + 旧会话目录），按时间戳排序，构建文件→备份会话映射
3. 卸载前比对 fresh manifest 与 $HOME，输出"将被删除"（提示 track）与"将被恢复"警告
4. y/N 确认（`--force` 跳过）
5. 选择恢复源：fresh manifest 中存在的文件优先用 `fresh_root/backup/`；
   其余默认恢复**最早**版本，`--latest` 恢复备份链**最新**版本（不用 fresh 优先）
6. 移除用户配置文件（保留安装基础设施）
7. 从备份中 `cp`（非 `mv`）恢复用户文件——保持备份完整，支持幂等
8. 打印手动清理说明

### migrate.sh — 迁移

将旧会话备份系统迁移到节点系统：

1. 扫描旧会话目录（匹配 `{from}-to-{to}-{timestamp}` 格式）
2. 按时间排序
3. 创建根 fresh 节点（固定 CODE `fresh_root`）
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
| `switch.sh --type=desktop` | desktop 类别定义的文件 | fresh 时克隆仓库；server 时复用现有仓库 |
| `switch.sh --type=server` | server 类别定义的文件 | desktop 时先删除桌面类别差集文件 |
| `deploy.sh` | 当前节点类型对应的文件 | 备份到节点目录 |
| `undeploy.sh` | 节点 files/ 中记录的文件 | 从节点 backup/ 恢复 |
| `uninstall.sh` | `.cfg-checkout-state` 或 `git ls-tree` 列出的文件 | 移除 + 从备份恢复 |

### 文件分类系统

文件分类由 `utils/categories.sh` 和声明式配置文件管理。

#### 配置文件版本化

配置文件支持多版本共存，节点创建时绑定使用的配置文件版本，恢复时使用对应版本。

**文件内部版本号声明**：

每个 `categories-*.conf` 文件头部包含版本元数据：

```
# ============================================
# VERSION = "1.0.0"
# NAME = "categories"
# DESCRIPTION = "默认配置分类定义"
# ============================================

category = server
+ .bashrc
...
```

| 字段 | 必填 | 说明 |
|------|------|------|
| `VERSION` | 是 | 语义化版本号，格式 `MAJOR.MINOR.PATCH`（如 `1.0.0`、`2.1.3`） |
| `NAME` | 否 | 配置文件名，便于识别 |
| `DESCRIPTION` | 否 | 简要说明该版本的用途 |

**文件名规范**：推荐 `categories-{VERSION}.conf`（如 `categories-1.0.0.conf`）。

**冲突处理规则**：

文件名中的版本号与文件内部 `VERSION` 字段冲突时，**以内部 `VERSION` 字段为准**。

示例：
- 文件名：`categories-1.0.0.conf`，内部 `VERSION = "2.0.0"` → 实际版本号为 `2.0.0`
- 文件名：`categories-v1.0.0.conf`，内部 `VERSION = "1.5.0"` → 实际版本号为 `1.5.0`

若文件内部无 `VERSION` 字段，则回退到从文件名提取的版本号。
若文件名也无法提取版本号，该文件被忽略（不参与版本管理）。

**文件存放位置**：所有版本配置文件统一存放在 `$DOTFILES_LIB_DIR/` 下：

```
$DOTFILES_LIB_DIR/
├── categories-1.0.0.conf
├── categories-2.0.0.conf
├── categories-2.1.3.conf
└── exclude.conf
```

**版本发现与默认版本**：

**`v` 前缀处理规则**：

- 文件名中的 `v` 前缀（如 `categories-v1.0.0.conf`）在**内部排序和比较时自动去除**
- 展示时保留用户使用的格式：
  - `categories-1.0.0.conf` → 展示为 `1.0.0`
  - `categories-v1.0.0.conf` → 展示为 `v1.0.0`
  - 内部 `VERSION = "2.0.0"` → 展示时与文件名风格保持一致（优先使用文件名的前缀风格）

**示例**：
- `categories-v1.0.0.conf` + `VERSION = "2.0.0"` → 实际版本号为 `2.0.0`，展示为 `v2.0.0`（沿用文件名的 `v` 前缀风格）
- `categories-1.0.0.conf` + `VERSION = "2.0.0"` → 实际版本号为 `2.0.0`，展示为 `2.0.0`

**版本发现流程**：

- 扫描 `$DOTFILES_LIB_DIR/categories-*.conf`，从文件名提取版本号（支持 `categories-v{VERSION}.conf` 格式，自动去除 `v` 前缀）
- 按语义化版本排序（`1.0.0` < `1.0.1` < `1.1.0` < `2.0.0`）
- 若 `~/.config-backup/CURRENT_CONFIG_VERSION` 存在，以其内容为当前版本
- 否则自动使用版本号最大的文件作为当前版本
- `dotcfg categories switch <version>` 可手动切换当前版本

**节点与版本绑定**：

- 节点创建时，记录当前配置文件版本号到 `index.json` 的 `config_version` 字段
- 切换到历史节点时，读取其 `config_version`，检查对应版本文件是否存在

**版本缺失时的恢复行为**：

当切换到历史节点时，系统检查该节点的 `config_version` 对应的配置文件是否存在：

1. **配置文件存在** → 正常使用该版本解析文件列表，执行切换

2. **配置文件不存在** → 默认拒绝恢复，报错退出：
   ```
   Error: Cannot restore node xk7f9a2m.
   Config version 1.5.0 not found.
   Please restore categories-1.5.0.conf to $DOTFILES_LIB_DIR/ and try again.
   ```

3. **强制恢复（绕过版本检查）**：
   用户可指定 `--force` 参数强制恢复，使用当前版本的配置文件解析文件列表：
   ```bash
   dotcfg switch xk7f9a2m --force
   ```
   输出警告：
   ```
   Warning: Node xk7f9a2m was created with config version 1.5.0, but this version is not found.
   Forcing recovery using current config version 2.1.3.
   This may cause file list mismatch. Use with caution.
   ```

4. **原因**：不同版本的配置文件可能包含不同的文件列表。使用错误的版本恢复可能导致文件被错误删除或遗漏。系统默认拒绝恢复，除非用户明确使用 `--force` 承担风险。

#### categories.conf 语法规则

**文件位置**：`$DOTFILES_LIB_DIR/categories-{VERSION}.conf`（版本化配置文件，推荐使用）或 `$DOTFILES_LIB_DIR/categories.conf`（无版本时的回退）。两者均不存在时使用内置默认值。

**回退文件处理优先级**：

1. 如果存在任何 `categories-*.conf` 版本化文件：
   - 忽略无版本的 `categories.conf` 文件
   - 从所有版本化文件中进行版本发现和排序
   - `dotcfg categories list` 仅显示版本化文件

2. 如果不存在任何版本化文件，但存在 `categories.conf`：
   - 使用 `categories.conf` 作为当前配置
   - `CURRENT_CONFIG_VERSION` 设为空字符串 `""`（表示无版本）
   - `dotcfg categories list` 显示 "No versioned config files found. Using unversioned categories.conf."

3. 如果两者均不存在：
   - 使用内置默认类别
   - `CURRENT_CONFIG_VERSION` 设为 `"default"`

**格式**：每行一个定义语句，`#` 开头的行为注释，空行忽略。

**三部分顺序（强制）**：

每个 `category` 块内的行必须按以下顺序排列：

1. `include = <类别名>` — 继承另一个类别的所有文件（**必须在最前面**）
2. `+ <路径>` — 添加文件或目录路径（**中间部分**）
3. `- <路径>` — 从当前类别中移除路径（**最后面**）

**顺序错误处理**：任何顺序错误的行将被**静默忽略**（不报错，不起效）。例如 `+` 出现在 `include` 之前，或 `-` 出现在 `+` 之前，这些行会被跳过。

**目录前缀匹配**：当 `+ <path>` 指向一个目录路径时，系统保留该路径作为前缀。在与实际仓库跟踪文件取交集时（`cfg_get_files_for_state`），所有以该目录为前缀的跟踪文件都会被匹配。例如 `+ .config/x11` 会匹配仓库中的 `.config/x11/xinitrc`、`.config/x11/xresources` 等。

**应用顺序**（每个类别独立）：
1. 如果存在 `include`，从父类别的解析结果开始
2. 按顺序添加所有 `+` 指定的路径（去重）
3. 按顺序移除所有 `-` 指定的路径

**正确示例**：

```
category = desktop
include = server
+ .xinitrc
+ .xprofile
+ .config/x11
- .config/x11/xresources
```

**错误示例（顺序错误的行被忽略）**：

```
category = test
+ .bashrc          # ← 被忽略：+ 出现在 include 之前
include = server   # ← 被忽略：include 不是第一行
+ .xinitrc
- .bashrc          # ← 被忽略：- 出现在 + 之后又遇到 +（section 已切回 add 不生效）
```

#### 内置默认类别

当 `categories.conf` 不存在时，系统使用以下内置定义：

- **`server`**（21 个文件）：Shell（`.bashrc`、`.zshrc`、`.profile`、`.config/shell/*`）、Tmux（`.tmux.conf`、`.config/tmux/*`）、Git（`.gitconfig`、`.gitignore`、`.config/git/*`）、LF（`.config/lf/*`）、文档（`.local/share/docs/*`）
- **`desktop`**（继承 server + 9 个桌面专有路径）：`.xinitrc`、`.xprofile`、`.asoundrc`、`.gtkrc-2.0`、`.config/x11`、`.config/alsa`、`.config/mpd`、`.config/nsxiv`、`.config/zathura`

#### 内置特殊类别

除配置文件定义的类别外，系统内置两个特殊类别，无需在 `categories.conf` 中定义即可使用：

| 类别名 | 解析结果 | 使用场景 |
|--------|----------|----------|
| `full` | 所有被 git 跟踪的文件（`git ls-tree -r --name-only HEAD`） | 全量部署 |
| `empty` | 空列表（无任何文件） | 作为空基类 |

**使用示例**：

```
category = desktop
include = full
- .config/private/
- .local/share/secret

category = minimal
include = empty
+ .bashrc
+ .profile
```

**解析行为**：
- `full` 在类别解析时动态展开，每次调用都重新执行 `git ls-tree`
- `empty` 直接返回空列表
- 两者可作为普通类别使用 `include`、`+`、`-` 进行定制

#### exclude.conf 排除规则

**文件位置**：`$DOTFILES_LIB_DIR/exclude.conf`（不存在时仅使用内置保护）

**格式**：每行一个通配符模式（支持 `*`、`?`），`#` 开头为注释。

**行为**：文件分析时（`cfg_analyze_files`），如果文件路径匹配 `exclude.conf` 中任一模式，则直接跳过（归入 `CFG_TO_SKIP`，不备份、不 checkout）。

示例：

```
# 排除私密配置
.config/private/*
# 排除缓存
.config/cache/*
```

#### 例外保护（硬编码，始终生效）

以下路径在代码中硬编码排除，无需在 `exclude.conf` 中重复配置：

| 模式 | 说明 |
|------|------|
| `.local/lib/dotfiles/*` | 运行时库目录（含 `categories.conf`、`exclude.conf`） |
| `.cfg/*` | bare 仓库本身 |
| `.config-backup/*` | 节点备份目录 |
| `.cfg-checkout-state` | checkout 状态记录文件 |
| `.local/share/test/*` | 测试目录 |

#### 状态检测（动态）

`cfg_detect_state()` 从类别系统动态获取桌面指标，不再硬编码：

1. 如果 `~/.cfg` 不存在 → 返回 `fresh`
2. 加载 `categories.conf`（或内置默认）
3. 计算 `desktop - server` 差集（desktop 中有但 server 中没有的路径）
4. 遍历差集中的路径，检查是否存在于 `$HOME`（文件或目录或符号链接）
5. 任一存在 → 返回 `desktop`
6. 全部不存在 → 返回 `server`

如果类别系统不可用（如测试环境中未加载 `categories.sh`），回退到最小指标集：`.xinitrc`、`.xprofile`、`.config/x11`。

**设计意图**：差集中的路径是桌面专有文件/目录，server 模式下不会被部署。它们的存在可靠标识当前处于 desktop 模式。动态检测确保状态判断与配置文件定义一致——修改 `categories.conf` 后，状态检测自动适配。

#### dotcfg list 的 TYPE 来源

`dotcfg list` 输出的 TYPE 列来自节点创建时记录的 `type` 字段（存储在 `index.json`）。值等于 `switch.sh` 执行时的目标状态名称（`desktop`、`server`）。根节点固定为 `fresh`。TYPE 的值由 `categories.conf` 中定义的类别名决定，系统不预设固定类型。

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
├── CURRENT_CONFIG_VERSION      ← 当前使用的配置文件版本
└── sessions/                   ← 旧会话归档
```

### manifest.txt 格式

**普通节点**（3 列）：

```
# Created: Wed Aug  6 10:05:00 UTC 2026
# Node: xk7f9a2m
#
# relative_path	md5	status
.bashrc	d41d8cd98f00b204e9800998ecf8427e	modified
.config/shell/zshrc	098f6bcd4621d373cade4e832627b4f6	untracked
```

**fresh 根节点**（5 列，fresh_root 专用）：

```
# Created: 2026-08-07 03:48:42
# Node: fresh_root
#
# relative_path	md5	size_bytes	status	timestamp
.bashrc	d41d8c…	1024	tracked_at_install	2026-08-07 03:48:42
.myconfig	abc123…	512	tracked_by_user	2026-08-07 04:00:00
```

status 取值：`tracked_at_install`（安装时全量备份）/ `tracked_by_user`（用户 `dotcfg track` 添加）。
节点统计（数量/大小/分组）从该 manifest 派生，不存入 index.json。

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
| 完全卸载后恢复 | `dotcfg uninstall`（优先从 fresh_root 备份恢复） |
| 多次切换后恢复原始文件 | `dotcfg uninstall`（优先 fresh_root，其余回退最早备份） |

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

### 场景 8：节点生命周期管理
```bash
dotcfg list                      # 查看所有节点
dotcfg remove e5f6g7h8           # 标记节点为待删除
dotcfg unremove e5f6g7h8         # 取消标记（恢复为 active）
dotcfg autoclean --dry-run       # 预览将删除的节点
dotcfg autoclean                 # 永久删除标记的节点
```

### 场景 9：配置文件版本管理
```bash
dotcfg categories list           # 查看所有可用版本
dotcfg categories current        # 查看当前版本
dotcfg categories show 1.0.0     # 查看某版本的类别详情
dotcfg categories switch 1.0.0   # 切换默认版本（新节点使用）
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
dotcfg doctor                        # 诊断（HEAD 悬空、文件缺失等）
dotcfg repair                        # 自动修复（--force 跳过确认）
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

### 急救：doctor/repair 与自举安装

节点系统异常时优先使用内置工具：

```bash
dotcfg doctor          # 诊断问题
dotcfg repair          # 自动修复（HEAD/DEPLOY_STATUS 等）
```

如果库文件丢失或系统完全损坏，`dotcfg` 的 bootstrap 模式可重建整个安装
（见「自举安装与 Fresh 根节点」章节）。独立 `install.sh` 仍可作为最后的绕过手段：

```bash
# 从仓库历史恢复 install.sh（如果不存在）
git --git-dir=$HOME/.cfg --work-tree=$HOME checkout HEAD -- .local/bin/install.sh

# 或直接下载
curl -fsSL https://raw.githubusercontent.com/darkroam/dotfiles/main/.local/bin/install.sh -o ~/.local/bin/install.sh
chmod +x ~/.local/bin/install.sh

# 执行急救安装
~/.local/bin/install.sh
```

`install.sh` 是独立的安装脚本，不依赖节点系统。它直接克隆仓库并 checkout 配置文件，
适用于节点系统损坏、需要全新安装或绕过节点管理的场景。

---

## 相关文档

- [安装测试系统](installation-testing.md) — 测试框架和测试用例
- [安装系统修复记录](../planning/installation-fixes.md) — 已知问题和修复方案
- [依赖清单](dependencies.md) — 项目依赖的软件包
- [架构文档](architecture.md) — 配置库整体架构

---

**最后更新**: 2026-08-07
**版本**: 5.0 — 自举安装（bootstrap）+ Fresh 根节点全量备份 + track/untrack + doctor/repair + fresh-* 管理命令
