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

## 核心开发契约与不可变规则

**本章节定义了后续所有开发、重构和维护工作必须遵守的最高优先级规则。任何修改（包括代码、测试和文档）均不得违背以下契约，除非先经过架构评审并同步修改本文档。**

### 1. 用户行为契约（不可破坏）

- **接口不变性**：所有用户可见的命令名称（如 `switch`、`list`、`status`）、参数（如
  `--force`、`--dry-run`）及输出格式均属于锁定契约。输出格式包括表格列宽与对齐、图形符号、
  颜色和固定文本片段；函数重命名、文件移动、模块拆分等内部重构不得改变这些外部行为。
- **错误输出规范**：除 `help` 命令外，任何命令遇到参数错误或执行失败时，只向用户输出简洁、
  可定位的错误信息，不附带 usage 提示，并返回非零退出码。完整用法只由 `dotcfg help` 提供。
- **版本号契约**：`dotcfg version` 必须输出与本文档及测试文档同步的版本号。
  `dotcfg categories list` 展示的配置版本号禁止添加 `v` 前缀，以保持与节点
  `config_version` 字段一致。
- **向后兼容契约**：已经公开的命令、历史节点字段、旧节点缺失字段的默认值和明确保留的兼容入口
  不得在普通重构中移除。必须先提供迁移或兼容层并经回归验证，才能在后续版本清理；否则已有节点
  可能失去可读性，自动化调用也会在无提示的情况下失效。

### 2. 数据存储与备份契约（不可破坏）

- **节点元数据权威性**：`cfg_detect_state()` 以 `index.json` 中 HEAD 节点的 `type` 字段为当前
  状态的最高权威来源。只有节点元数据缺失或不可用时，才允许回退到文件系统状态指标，例如
  `.xinitrc`、`.xprofile` 或 `.config/x11/xinitrc`。
- **Fresh 备份独立性**：`fresh_root` 节点保存“系统原始状态”，是 `uninstall` 的首选恢复锚点。
  默认恢复必须优先使用 `fresh_root/backup/`；只有目标文件在 Fresh 中不存在时，才可回退到子节点
  备份链。显式使用 `--latest` 时按备份链选择最新版本，不采用 Fresh 优先规则。不得因为某个子节点
  更新或删除而消费、移动或隐式替换 Fresh 备份。
- **系统自保原则**：运行时库 `.local/lib/dotfiles/`、入口 `.local/bin/dotcfg`、bare 仓库
  `.cfg/` 和备份根目录 `.config-backup/` 不得作为 category 或普通用户配置目标被覆盖、移动或整体
  删除；`switch`、`autoclean` 和 `uninstall` 均必须遵守。`.config-backup/` 内部仅允许节点/备份 API
  按既定协议更新元数据和受管节点；例如 `autoclean` 只能删除已确认可清理的节点，不能删除备份根
  目录或越界处理其他节点。
- **路径边界与符号链接安全**：所有写入、恢复和删除都必须限定在经过验证的 `$HOME` 相对路径内，
  不得跟随符号链接祖先越过该边界。符号链接本身作为配置对象处理而不跟随其目标；这是防止备份或
  卸载意外修改用户目录之外数据的必要保护。

### 3. 逻辑与幂等性契约（不可破坏）

- **历史与部署分离**：`deploy` 和 `undeploy` 只改变当前工作区状态及 `DEPLOY_STATUS`，严禁创建、
  删除或重写节点历史。节点只能由明确的状态转换、迁移或节点管理流程创建和清理。
- **幂等性保证**：所有 `switch` 和 `uninstall` 操作必须可安全重复执行。重复执行 `uninstall`
  不得报错，且不能消费备份；重复执行 `switch --reinstall` 应创建新节点，但不得覆盖或破坏已经
  存在且无冲突的用户文件。
- **回滚保护**：checkout 失败数 `>5` 或失败率 `>10%` 时必须触发回滚，不得继续提交新的 HEAD 和
  deployed 状态。回滚阈值属于行为契约，修改它必须同时更新实现、测试和本文档。
- **节点树完整性**：CODE 在整棵树中必须全局唯一，根节点必须保持唯一，所有非根节点必须引用存在
  的父节点，父节点 `children` 与子节点 `parent` 必须双向一致。该约束不可妥协，因为 HEAD、历史
  切换、恢复源遍历和清理都以这组关系作为寻址基础。
- **清理接续规则**：`autoclean` 删除中间节点时，若其只有一个存活子节点，必须把该子节点重新挂载
  到被删节点的父节点并同步双方关系；存在多个存活子节点时必须拒绝自动删除。任何清理都不得产生
  孤儿节点、悬空引用或多个根节点。

### 4. 配置驱动与开发契约（不可破坏）

- **配置优先**：新增或修改普通 category（如 `macos`、`min` 或未来的 `workstation`）必须通过
  `categories-*.conf` 完成，绝对禁止在 Shell 代码（包括 `utils/categories.sh`）中硬编码新的
  category 文件列表。通用切换代码只能解析和执行声明式配置。
- **硬编码白名单**：代码中的硬编码只允许用于系统自举所需的基础设施和固定协议，例如 `full` 的
  动态语义、`bootstrap` 标识和配置缺失时的排除规则回退值。新增业务策略（包括新的排除路径、状态
  指标或普通 category）必须优先写入配置文件；扩大白名单必须经过架构评审并在本文档说明理由。
- **测试覆盖锁**：任何新增功能或行为变更都必须同步新增或更新 Bats 用例，并在
  `installation-testing.md` 登记。`refactor-contract.bats` 的契约测试失败时，禁止绕过、弱化或删除
  测试；只能在确认新契约后同步修改代码、设计文档和测试预期。
- **测试环境隔离**：安装系统测试必须在独立临时 `$HOME`、独立 Git 配置和临时仓库中运行，禁止
  读取、修改或删除真实 `HOME`、`.cfg/` 与 `.config-backup/`。安装测试执行的是破坏性状态转换，
  环境隔离是保证回归测试本身不会损坏用户系统的必要前提。
- **文档同步**：`installation-system.md`（设计）与 `installation-testing.md`（验证）必须保持版本号
  一致。任何用户行为、存储格式、状态转换、配置字段或兼容边界发生变化时，必须在同一变更中同步
  更新两份文档及对应测试。

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
- 所有配置文件均在同一个 repo 中跟踪
- category 区别不在于 repo 内容，而在于 **哪些文件被 checkout 到 work-tree**

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
| `cfg_detect_state()` | 检测当前安装状态（fresh 或节点记录的 category） |
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
| type | branch label | `fresh` 或创建节点时选用的 category 名称 |
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
> 根节点（fresh，固定 CODE `fresh_root`）在首次安装/迁移时执行混合模式备份：`~/.config/`
> 全量扫描并应用排除规则，其他位置只选择仓库跟踪文件；跟踪文件可覆盖普通排除规则，但安装
> 基础设施始终排除。
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
      "type": "full",
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
| `type` | string | 节点类型：`fresh` / `full` / `min` / `macos` |
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

### 根状态与 category 状态

| 状态 | 检测条件 | 含义 |
|------|----------|------|
| **fresh** | `.cfg` 不存在，或 HEAD 指向 fresh 根节点 | 未部署 category；安装基础设施仍可保留 |
| **full** | HEAD 节点 `type=full` | 代码保留 category，部署仓库中的全部受管配置和普通辅助脚本 |
| **min** | HEAD 节点 `type=min` | `1.0.0` 定义的 Linux 命令行配置，不部署普通 `.local/bin/` 脚本 |
| **macos** | HEAD 节点 `type=macos` | `1.0.0` 定义的 Bash、Zsh、Git、Tmux、npm 等跨平台核心配置 |
| **其他 category** | HEAD 节点记录相应 type | 按当前版本配置中的普通 category 定义部署 |

节点元数据存在时，HEAD 节点的 `type` 是状态判断的权威来源，因此同为命令行配置的 `min` 与
`macos` 不依赖文件猜测。没有节点元数据的旧安装才使用兼容检测：`.xinitrc`、`.xprofile` 或
`.config/x11/xinitrc` 存在时映射为 `full`，否则映射为 `min`。

### 状态转换与节点创建

每次 `dotcfg switch` 操作创建新节点：

```
┌─────────────┐
│   FRESH     │  ← 根节点 (type=fresh, parent=null)
└──────┬──────┘
       │
       ├─ dotcfg switch full  ──→ FULL   (新节点, parent=当前)
       ├─ dotcfg switch min   ──→ MIN    (新节点, parent=当前)
       └─ dotcfg switch macos ─→ MACOS  (新节点, parent=当前)

┌─────────────┐
│ FULL/MIN/   │  ← 节点 (type=full|min|macos)
│ MACOS       │
└──────┬──────┘
       │
       ├─ dotcfg switch <其他 category> ─────→ 新 category 节点
       ├─ dotcfg switch <同一 category> --reinstall ─→ 幂等重装节点
       └─ dotcfg uninstall ──────────────────→ FRESH    (HEAD 移回根节点)
```

### 分支支持

`dotcfg switch <CODE>` 可切换到任意历史节点，从该节点产生分支：

```bash
dotcfg list                     # 查看所有节点和 CODE
dotcfg switch xk7f9a2m          # 切换到历史节点，产生新分支
```

切换流程：undeploy 当前节点 → 移动 HEAD → deploy 目标节点。

### 进入 Fresh 状态

当 `.cfg` 存在且 `dotcfg` 命令可用时，可显式切换到根节点：

```bash
dotcfg switch fresh
```

如果当前节点处于 `deployed`，该命令先 undeploy 当前节点，再把 `HEAD` 移到 `fresh_root`；
fresh 节点本身不 checkout 配置文件，最终将 `DEPLOY_STATUS` 记为 `deployed`。这不是保留原
节点配置，而是按标准节点切换流程恢复该节点转换前的文件后进入根状态。

| 操作 | 命令 | 行为 | 适用场景 |
|------|------|------|----------|
| 切换 | `dotcfg switch fresh` | 撤销当前节点并切到 `fresh_root`，保留节点历史 | 临时回到根状态，之后仍需切换历史节点或新建状态 |
| 卸载 | `dotcfg uninstall` | 回到根节点，移除受管配置并优先从 fresh 备份恢复 | 完全恢复安装前状态 |
| 自举 | 下载或运行 `dotcfg` | 库缺失时恢复或重建安装基础设施，再建立 fresh 根状态 | 首次安装或急救；不是已有节点间的切换方式 |

**节点创建时的版本选择策略**：

执行 `dotcfg switch <category>` 创建新节点时：

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

> 所有子命令均接受 `-h` 或 `--help` 并显示统一帮助；`dotcfg help`、`dotcfg -h` 和
> `dotcfg --help` 效果一致。

参数缺失、参数非法或执行失败时只输出简洁错误并保持非零返回码，不附带命令 usage；完整用法
仅由上述帮助入口显示。

```bash
dotcfg                          # 显示当前节点状态（等同于 dotcfg status）
dotcfg status                   # 当前节点 + 部署状态
dotcfg list                     # 六列表：DEPLOY / TYPE / VERSION / STATUS / TIME / CODE
dotcfg history                  # Git log --graph 风格 ASCII 分支图
dotcfg switch <target>          # 切换到配置的 category、full、fresh 或 CODE；fresh = 根节点别名
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
dotcfg fresh-adopt-legacy <path> [--dry-run] [--config-version VERSION]  # 采纳旧安装备份作为 Fresh 根
dotcfg help                     # 使用帮助（也可使用 dotcfg --help）
dotcfg version                  # 显示 dotcfg 版本
```

**确认**：`dotcfg help` 的输出包含上述所有顶层命令。新增命令时需同步更新 `help` 的静态文本
（入口脚本中的 `cmd_help()` 函数）。`refactor-contract.bats` 中的 TC-R01 锁定帮助文本的完整输出，
修改帮助内容时需同步更新测试。

> **库缺失时**：任何 `dotcfg` 命令检测到库不存在都会进入 **bootstrap 安装模式**
> （见下文「自举安装」章节），因此 `curl dotcfg | bash` 即可完成全新安装。

### `dotcfg status` 输出

```
Current node: xk7f9a2m (full)
Created: 2026-08-06 10:05:00
Deploy status: deployed
Config version: 1.0.0
Node status: active
Chain: fresh -> full
```

`status` 只报告仓库、当前节点和部署状态；可用命令统一由 `dotcfg help` 展示。

### `dotcfg list` 输出

```
  DEPLOY TYPE       VERSION  STATUS      TIME                 CODE
  [*]    full       1.0.0    active      2026-08-06 10:05:00  xk7f9a2m
  [ ]    fresh      bootstrap active     2026-08-06 10:00:00  fresh_root ●
  [ ]    min        1.0.0    [REMOVED]   2026-08-06 09:00:00  e5f6g7h8
```

标记说明：`[*]` = HEAD + deployed，`[>]` = HEAD + uninstalled，`[ ]` = 非 HEAD。
行尾 `●` = fresh 根节点。
STATUS 列：`active` = 正常节点，`[REMOVED]` = 标记为待删除（`marked_for_removal`）。
TYPE、VERSION、STATUS 和 TIME 的列宽以当前节点数据和表头的较大值动态计算；自定义长 category
或版本号不会挤乱后续列。现有短字段仍保持上述最小列宽。

### `dotcfg history` 输出

Git log --graph 风格，最新节点在顶部，根在底部：

**颜色方案**（终端支持时启用）：
- 绿色：`<- HEAD` 标签
- 黄色：`[deployed]` 状态、`[REMOVED]` 标记
- 灰色：`[uninstalled]` 状态
- 蓝色：图形元素（`*`、`o`、`|`、`/`、`\`）

**线性历史：**
```
*  a1b2c3d4  full     2026-08-06 12:00:00  [deployed]  v1.0.0  <- HEAD
| 
o  e5f6g7h8  min      2026-08-06 11:00:00  v1.0.0
| 
●  fresh_root fresh    2026-08-06 10:00:00  bootstrap  [root]
```

**分支历史：**
```
*  a1b2c3d4  full     2026-08-06 12:00:00  [deployed]  v2.0.0  <- HEAD
| 
o  e5f6g7h8  min      2026-08-06 11:00:00  v1.0.0
| 
●  fresh_root fresh    2026-08-06 10:00:00  bootstrap  [root]
|\
| o  m3n4o5p6  min      2026-08-06 10:30:00  v1.0.0  [REMOVED]
|/
```

**多分支历史：**
```
*  a1b2c3d4  full     2026-08-06 12:00:00  [deployed]  v2.0.0  <- HEAD
|
o  e5f6g7h8  min      2026-08-06 11:00:00  v1.0.0
|\
| o  m3n4o5p6  min      2026-08-06 10:30:00  v1.0.0  [REMOVED]
|/
●  fresh_root fresh    2026-08-06 10:00:00  bootstrap  [root]
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
dotcfg categories remove <version>   # 确认后删除版本配置文件
```

**`list` 输出示例**：

```
Available configuration versions:
  0.1.0   (test)     2 categories: macos, min   [TEST]
  1.0.0   (stable)   2 categories: macos, min

Current version: 1.0.0 (stable)

Nodes using each version:
  1.0.0: a1b2c3d4, e5f6g7h8 (2 nodes)
```

`full` 是内置特殊 category，不依赖 `categories-*.conf` 中的文件列表，解析时动态返回 HEAD 的
全部跟踪文件，因此不计入版本内普通 category 数量，仅在 `categories show` 中单独展示。

**注意**：`categories list` 输出的版本号不包含 `v` 前缀（显示 `1.0.0` 而非 `v1.0.0`），
以保持与节点 `config_version` 字段的一致性。`categories show` 同样使用不带前缀的版本号。

**`categories show 1.0.0` 输出示例**：

```
Version: 1.0.0
Name: categories
Description: full、min 和 macos 正式部署分类
Tag: stable

Categories:
  macos           17 files
  min             24 files
  full            (dynamic, all tracked files)
```

`full` 不显示具体文件数量，因为其内容随 HEAD 动态变化。

**版本切换行为**：

```bash
$ dotcfg categories switch 1.0.0

Switching from v2.1.3 to v1.0.0...
Warning: Some nodes use v2.1.3. They will continue to use v2.1.3 on recovery.
Current version set to v1.0.0.
New nodes will use v1.0.0 by default.
```

切换版本只影响**新创建的节点**，已有节点的版本绑定不变。

切换到 `test` 或 `experimental` 版本时，命令会先输出谨慎使用提示，但不阻止切换。
`dotcfg categories remove <version>` 删除的是 `categories-*.conf` 文件，不删除节点；命令会列出
绑定该版本的节点并要求 `y/N` 确认，`test` 和 `experimental` 版本另有醒目警告。版本文件删除后，
节点记录仍存在，但默认无法部署该节点；需恢复对应版本文件，或显式使用 `--force` 回退当前类别。

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
5. 读取节点绑定版本的 `TAG`；`test` 或 `experimental` 时输出警告，但不阻止
6. 将节点状态改为 `marked_for_removal`

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

# 测试版本节点（警告后继续）
Warning: node a1b2c3d4 uses TEST configuration version 2.0.0 (TAG=test).
```

`dotcfg remove` 处理节点；`dotcfg categories remove` 才删除版本配置文件。两者都不会自动删除
对方对象，避免把节点生命周期和配置文件生命周期混为一谈。

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
  e5f6g7h8  (min, v1.0.0, 2026-08-06 09:00:00)  - leaf node, marked_for_removal
  f9g8h7i6  (full, v1.0.0, 2026-08-06 07:00:00)  - leaf node, marked_for_removal

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
4. source 新装的库，创建 `fresh_root` 节点并执行混合模式备份：

   | 目录 | 备份策略 |
   |------|----------|
   | `~/.config/` | 全量遍历所有普通文件和符号链接，应用排除规则 |
   | `~/.config/` 以外 | 只备份 `git ls-tree -r --name-only HEAD` 返回且当前存在的跟踪文件 |
   | `~/.local/` | 只备份当前存在的跟踪文件；`~/.local/bin/dotcfg` 和 `~/.local/lib/dotfiles/` 始终排除 |

   仓库跟踪文件不受普通排除规则影响，因此被排除规则命中的跟踪配置仍进入备份；安装基础设施
   是强制例外。选择结果分为 `.config`、其他跟踪文件和 `.local` 跟踪文件三组，实际复制完成后
   输出分组数量与总数。`fresh-update` 和 `fresh-diff` 复用同一选择逻辑。
5. 按 `min` category 过滤后 checkout（冲突文件备份到 `$BACKUP_ROOT/conflict/`）；普通
   `.local/bin/` 脚本不属于 `min`，`dotcfg` 与运行库已在步骤 2–3 独立安装
6. 写 `HEAD=fresh_root`、`DEPLOY_STATUS=deployed`、`CURRENT_CONFIG_VERSION=bootstrap`
7. re-exec `dotcfg <原参数>`，保证幂等

`bootstrap` 是 fresh 根节点的特殊 `config_version` 标识，不对应
`categories-bootstrap.conf`：

- `dotcfg categories list` 的可用版本区只列出 `categories-*.conf`，因此不会把 `bootstrap`
  当作可切换版本；节点分组区仍可列出使用该标识的 `fresh_root`
- `dotcfg list` 的 `VERSION` 列对根节点显示 `bootstrap`
- `dotcfg categories switch bootstrap` 会因不存在相应版本文件而拒绝
- 该标识只用于记录首次自举建立的 fresh 原始状态

### 采纳早期安装备份

在 dotcfg 开发前通过旧 `install.sh` 部署、且旧脚本把冲突文件移到一个备份目录的设备，可显式
重建安装前 Fresh。该命令不会把当前已部署的仓库版本误记为安装前原件：

```bash
dotcfg fresh-adopt-legacy ~/.config-backup --dry-run
dotcfg fresh-adopt-legacy ~/.config-backup
dotcfg switch full
```

采纳选择器执行两部分工作：

1. 只采纳旧备份目录中仍由 `.cfg` HEAD 跟踪的文件，manifest 状态记为 `legacy_backup`。
2. 补充当前 `.config/` 中未被 HEAD 跟踪且未命中排除规则的文件，状态记为
   `untracked_config_at_adoption`；当前跟踪文件全部跳过。

命令只允许在节点元数据尚未建立时执行，默认使用最新 category 版本作为后续节点版本；
`--config-version VERSION` 可显式选择版本。`--dry-run` 只输出来源、数量与大小，不创建
`nodes/index.json`、HEAD 或 manifest。安装基础设施不会进入 Fresh，采纳完成后再显式切换到目标
category。

`.config-backup.bak` 是用户急救备份，属于硬排除路径；命令拒绝把它作为采纳源，也不会移动、修改
或删除它。确认迁移长期正常后，由用户自行决定是否删除该目录。

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

- `status` ∈ {`tracked_at_install`（混合选择器在安装或重建时加入）、`tracked_by_user`（用户手动
  track）、`legacy_backup`（旧安装备份中的原件）、`untracked_config_at_adoption`（采纳时的未跟踪
  `.config/` 文件）}
- 备份采用 **cp 语义**（区别于普通节点备份的 mv 语义），原文件保留在 $HOME；符号链接按链接
  本身复制和计算摘要，不跟随目标文件
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

### check-exclude 输出示例

`exclude.conf` 示例假设包含 `.config/private/*`：

```bash
$ dotcfg check-exclude ~/Downloads/file.pdf
Path is excluded by hardcoded rule: ~/Downloads/

$ dotcfg check-exclude ~/.config/private/secret
Path is excluded by exclude.conf: ~/.config/private/

$ dotcfg check-exclude ~/.bashrc
Path is NOT excluded.
```

未排除时命令返回 1，排除时返回 0；该命令只解释规则命中情况。混合模式下，仓库跟踪文件除
安装基础设施外仍可覆盖排除规则进入 fresh 备份。

### fresh-* 管理命令

```bash
dotcfg fresh-status        # 总数/大小/按 status 分组/Top5 最大/最近添加
dotcfg fresh-diff [path]   # 全量：Modified/New/Missing 三组；单文件：diff -u
dotcfg fresh-diff --summary
dotcfg fresh-update [--force] [--dry-run] [--no-backup]  # 以当前 $HOME 重建备份
```

- `fresh-update` 重建前先把旧节点目录复制为 `fresh_root.bak`（`--no-backup` 跳过）
- `New` 分组来自混合模式选择集合，默认限前 50 条；范围外的未跟踪根目录或 `.local` 文件不列出

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
| 9 | 配置类别来源可用性 | 优先报告 `categories-*.conf` 版本；没有版本文件时，确认使用 `categories.conf` 或内置 `macos/min/full` 默认类别 |

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
| 9 | 当前配置版本缺失 | 仅当存在 `categories-*.conf` 时写入最新可用版本；无版本 `categories.conf` 和内置默认类别均无需修复 |

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
| `status.sh` | `dotcfg status` 查询模块（由入口 source） |
| `list.sh` | `dotcfg list` 查询模块（由入口 source） |
| `history.sh` | `dotcfg history` 及 ASCII 图形渲染模块（由入口 source） |
| `categories.sh` | `dotcfg categories` 版本管理模块（由入口 source） |
| `switch.sh` | 统一切换逻辑（`--type=<category>`） |
| `switch-desktop.sh` | 旧直接脚本包装：转发到 `switch.sh --type=full`，不占用 `desktop` category 名称 |
| `switch-server.sh` | 旧直接脚本包装：转发到 `switch.sh --type=min`，不占用 `server` category 名称 |
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
| `utils/categories.sh` | 声明式文件类别系统（categories.conf 解析、继承、排除和 TAG） |
| `utils/exclude.sh` | fresh 备份排除规则和仓库路径跟踪检查 |
| `utils/fresh.sh` | fresh 混合选择器、旧备份采纳、根节点与 manifest 管理 |

`status.sh`、`list.sh`、`history.sh` 和 `categories.sh` 只提供入口所需的 `cmd_*` 函数，不能直接
执行；入口在 help/version 路径之外按需 source 它们。`switch.sh`、部署/撤销、Fresh、诊断和迁移
脚本仍由入口以独立 Bash 进程调用。这样既减少单次入口解析范围，又保留旧脚本的直接调用和
bootstrap 自举能力。

### 通用参数

所有命令脚本支持：
- `--dry-run` — 预览操作，不修改文件
- `--force` — 强制操作（覆盖部署状态、替换仓库等）

特定脚本额外支持：
- `--reinstall` — 跳过同 category 检查，重新安装
- `--auto-stash` — 自动备份冲突文件，不提示用户
- `--latest` — 恢复最新备份而非最早（仅 uninstall）
- `--type=<state>` — 目标状态类型（仅 switch.sh 内部使用）

### switch.sh — 统一切换

`switch.sh` 是所有 category 的统一切换实现；旧脚本只保留直接调用兼容。

**执行流程**：
1. 解析参数；只有配置文件显式声明的 `CATEGORY_ALIASES` 才进行名称映射
2. 验证仓库身份（`cfg_validate`）
3. 处理无效/外部仓库（`--force` 时备份并删除）
4. 根据当前状态准备仓库（克隆或复用）
5. 先确定 `CURRENT_CONFIG_VERSION`，加载该版本后再解析目标 category
6. 计算目标文件和 `current - target` 差集，打印安装前报告
7. 如果 `--dry-run`，退出
8. 备份目标冲突文件和差集中已修改的文件
9. 删除差集文件，但始终跳过安装基础设施
10. Checkout 目标配置
11. 若 checkout 失败数 >5 或失败率 >10% 则自动回滚
12. 激活仓库（如果是 fresh 克隆）
13. 按目标 category 过滤并记录 `.cfg-checkout-state`，设置 `showUntrackedFiles = no`
14. **创建新节点**，更新 HEAD，设置 `DEPLOY_STATUS = deployed`

`.local/bin/dotcfg` 与 `.local/lib/dotfiles/` 是 category 外的不变量：所有状态均保留，undeploy 和
uninstall 都不会删除；完全清除时只输出手动删除提示。

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
| `switch.sh --type=full` | HEAD 的全部跟踪文件 | 普通辅助脚本和桌面配置均部署；安装基础设施独立保留 |
| `switch.sh --type=min` | `min` 定义及安装基础设施 | 命令行配置；不部署普通 `.local/bin/` 脚本 |
| `switch.sh --type=macos` | `macos` 定义及安装基础设施 | 跨平台 Shell、Git、Tmux、npm 核心配置 |
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
# TAG = "stable"
# VALID_TAGS = "stable,test,experimental"
# STATE_DEFAULT = "min"
# STATE_INDICATORS = "full:.xinitrc,full:.xprofile,full:.config/x11/xinitrc"
# ============================================

category = macos
+ .bashrc
...
```

| 字段 | 必填 | 说明 |
|------|------|------|
| `VERSION` | 是 | 语义化版本号，格式 `MAJOR.MINOR.PATCH`（如 `1.0.0`、`2.1.3`） |
| `NAME` | 否 | 配置文件名，便于识别 |
| `DESCRIPTION` | 否 | 简要说明该版本的用途 |
| `TAG` | 否 | `stable`（默认）、`test` 或 `experimental`；非法值警告并回退 `stable` |
| `VALID_TAGS` | 否 | 逗号分隔的合法 TAG 值；缺失时使用 `stable,test,experimental` |
| `CATEGORY_ALIASES` | 否 | 逗号分隔的名称映射，例如 `cli:min,gui:workstation`；缺失时为空 |
| `STATE_DEFAULT` | 否 | 无节点元数据时的默认状态类别，默认 `min` |
| `STATE_INDICATORS` | 否 | 逗号分隔的 `类别:路径` 图形状态指标映射 |

- `STATE_INDICATORS` 用于无节点元数据时的兼容状态检测。示例中 `full:.xinitrc` 表示若
  `~/.xinitrc` 存在则判定为 `full`。旧配置缺少该字段时，回退到 `.xinitrc`、`.xprofile`、
  `.config/x11/xinitrc` 三个指标。

上述扩展字段均为可选注释元数据，不影响旧版 `categories-*.conf` 的类别语法。解析器只在版本
文件头部读取它们；缺少字段时使用现有兼容默认值。

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
├── categories-0.1.0.conf    # TAG=test，最小解析夹具
├── categories-1.0.0.conf    # TAG=stable，正式部署定义
└── exclude.conf
```

**版本发现与默认版本**：

**`v` 前缀处理规则**：

- 文件名中的 `v` 前缀（如 `categories-v1.0.0.conf`）在**内部排序和比较时自动去除**
- `categories list` 和 `categories show` 始终展示无前缀版本号，与节点 `config_version` 保持一致
- 历史图和版本切换提示可保留版本文件原有的 `v` 展示风格，仅作为兼容性显示，不影响存储值

**示例**：
- `categories-v1.0.0.conf` + `VERSION = "2.0.0"` → 实际和 `categories list/show` 展示均为 `2.0.0`
- `categories-1.0.0.conf` + `VERSION = "2.0.0"` → 实际和 `categories list/show` 展示均为 `2.0.0`

**版本发现流程**：

- 扫描 `$DOTFILES_LIB_DIR/categories-*.conf`，从文件名提取版本号（支持 `categories-v{VERSION}.conf` 格式，自动去除 `v` 前缀）
- 按语义化版本排序（`1.0.0` < `1.0.1` < `1.1.0` < `2.0.0`）
- 若 `~/.config-backup/CURRENT_CONFIG_VERSION` 存在，以其内容为当前版本
- 否则自动使用版本号最大的文件作为当前版本
- `dotcfg categories switch <version>` 可手动切换当前版本

**TAG 处理规则**：

- `utils/categories.sh` 解析头部 TAG，并通过 `CFG_CATEGORIES_TAGS[version]` 缓存；未声明时为 `stable`
- `VALID_TAGS` 控制该配置版本接受的 TAG 值；缺失时使用 `stable,test,experimental`
- `CATEGORY_ALIASES` 提供显式名称映射；缺失时为空，不隐式占用任何普通 category 名称
- `STATE_DEFAULT` 和 `STATE_INDICATORS` 为状态检测提供可选元数据；缺失时保留 `min` 以及
  `.xinitrc`、`.xprofile`、`.config/x11/xinitrc` 的兼容指标
- `dotcfg categories list/current/show` 显示 TAG，`test` 追加 `[TEST]`，`experimental` 追加
  `[EXPERIMENTAL]`
- 切换到 `test` 或 `experimental` 版本时输出谨慎使用提示，但不施加安全限制
- `dotcfg categories remove <version>` 列出关联节点并确认后删除版本文件；测试和实验版本额外警告
- 删除版本文件不删除节点，但该节点默认无法再部署，必须恢复对应文件或使用 `--force` 回退

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
category = min
include = macos
+ .config/lf/lfrc
+ .config/newsboat/config
- .config/newsboat/urls
```

**错误示例（顺序错误的行被忽略）**：

```
category = test
+ .bashrc          # ← 被忽略：+ 出现在 include 之前
include = macos    # ← 被忽略：include 不是第一行
+ .xinitrc
- .bashrc          # ← 被忽略：- 出现在 + 之后又遇到 +（section 已切回 add 不生效）
```

#### 内置默认类别

当版本文件和 `categories.conf` 均不存在或无法提供有效 category 时，系统使用与正式版本职责
一致的兼容回退。它只用于配置缺失或损坏时维持可用性，不是正常配置的数据源；正式定义始终以
选中的 `categories-*.conf` 为准。内置 `macos/min` 的精确成员当前与 `categories-1.0.0.conf`
同步；两者由回归测试逐项比较，后续修改任一处都必须同步另一处：

- **`macos`**：Bash、Zsh、profile、Git、Tmux、npm 和共享 Shell 配置。
- **`min`**：继承 `macos`，增加 LF、Wget、Emacs 和 Fbterm 配置；不包含 MPD、Ncmpcpp 或 Newsboat。
- **`full`**：特殊 category，动态返回 HEAD 的全部跟踪文件。

#### 内置特殊类别

系统只有一个内部特殊 category，无需在 `categories.conf` 中定义：

| 类别名 | 解析结果 | 使用场景 |
|--------|----------|----------|
| `full` | 所有被 git 跟踪的文件（`git ls-tree -r --name-only HEAD`） | 全量部署 |

**普通名称示例**：

```
category = empty
+ .bashrc
+ .profile
```

**解析行为**：
- `full` 在类别解析时动态展开，每次调用都重新执行 `git ls-tree`
- 配置文件中的 `category = full` 不覆盖上述语义，也不会导致列表重复
- `full` 不能作为 `CATEGORY_ALIASES` 的别名源；其他名称可以显式映射到 `full`
- `min`、`macos`、`desktop`、`server`、`empty` 及其他名称都没有代码特权，可按普通 category 定义

#### 配置驱动与硬编码边界

运行时把配置文件作为策略权威来源，代码中的同值数据仅承担配置缺失时的兼容回退。新增策略
应先修改配置文件；不得只修改代码回退后让正常配置与故障行为分叉。

| 数据或行为 | 正常数据源 | 代码回退或固定语义 | 可外部化判断 |
|------|------|------|------|
| `macos`、`min` 文件集合 | 当前 `categories-*.conf` | 无可用配置时使用内置同值集合 | 可迁到单独的 fallback 配置，但仍需保留配置完全缺失时的最小恢复能力 |
| TAG 合法值 | `VALID_TAGS` | `stable,test,experimental` | 可集中到默认元数据文件；当前保留以兼容旧配置 |
| 名称映射 | `CATEGORY_ALIASES` | 空 | 已完全配置化；只有配置显式声明时才映射 |
| 无节点状态检测 | `STATE_DEFAULT`、`STATE_INDICATORS` | `min` 及三个 X11 指标 | 可集中到默认元数据文件；`cfg-validate.sh` 独立加载时仍需故障回退 |
| Fresh 策略排除 | `exclude.conf` | 配置缺失或无兼容区段时使用 30 项同值回退 | 可完全配置化，但缺失配置会扩大 Fresh 范围，当前选择安全回退 |
| `full` | 无 | 动态返回全部跟踪文件且配置不能覆盖 | 必须保留，除非变更 category 协议 |
| `fresh_root`、`bootstrap` | 节点协议 | 根节点代码、首次安装版本标识 | 必须保留，已有节点和恢复流程依赖这些标识 |
| 安装基础设施与备份保护 | 无 | dotcfg、运行库、仓库、备份和测试路径 | 必须保留，防止 Fresh 或 category 操作破坏安装系统本身 |
| 官方入口的帮助文字 | `.local/bin/dotcfg`、bootstrap 提示 | “配置的 category”、`full` 和 `fresh` | 特定普通 category 只作为示例，不参与目标校验 |

**新增普通 category 的修改清单**：

新增普通 category 时，只需在新的 `categories-*.conf` 中增加 category 块，并按需调整同一文件的
`CATEGORY_ALIASES`、`STATE_DEFAULT` 或 `STATE_INDICATORS`；`dotcfg switch <category>` 会动态验证并
部署，不需要修改 Shell 代码。`desktop`、`server` 和 `empty` 可按此方式重新使用。只有修改保留的
`full` 语义、Fresh 节点协议，或调整 bootstrap 默认推荐目标时，才需要修改代码、测试和本文档。

#### exclude.conf 排除规则

**文件位置**：`$DOTFILES_LIB_DIR/exclude.conf`。正式库随配置跟踪该文件；文件缺失时仍使用内置
兼容回退，不改变既有 Fresh 行为。

**格式**：每行一个通配符模式（支持 `*`、`?`），`#` 开头为注释。默认迁移规则位于
`# DOTCFG_COMPATIBILITY_RULES_BEGIN` 与 `# DOTCFG_COMPATIBILITY_RULES_END` 之间；这些规则
仍在 `dotcfg check-exclude` 中显示为 `hardcoded rule`，以保持旧输出兼容。区段之外新增的规则
显示为 `exclude.conf`。

**行为**：Fresh 选择器处理未跟踪候选时，如果路径匹配 `exclude.conf` 中任一模式则跳过。
`exclude.conf` 不参与 category 部署过滤；`full` 仍部署全部跟踪配置，普通 category 由自身的
`include`、`+` 和 `-` 行控制。安装基础设施保护是独立且始终生效的例外。

当前兼容区段共 30 项：除 Linux 常见用户目录、缓存、浏览器状态、历史和临时文件外，还覆盖
macOS 的 `Applications/`、`Library/`、`Movies/`、`Public/`、`Sites/`、`.Trash/` 和
`*.DS_Store`。混合模式不会全量扫描 `~/.config/` 之外的未跟踪文件，所以未跟踪的 `~/Library`
本来就不会进入 Fresh；这些规则仍明确跨平台策略边界，并供 `check-exclude` 和配置缺失回退使用。
若仓库显式跟踪 `Library/...` 配置，普通策略排除不会阻止它进入 Fresh；只有安装基础设施保护不可覆盖。

30 项规则覆盖以下类别：

- Linux 标准用户目录：`~/Downloads/`、`~/Desktop/`、`~/Documents/`、`~/Videos/`、`~/Music/`、`~/Pictures/`
- Linux 缓存和运行时状态：`~/.cache/`、`~/.local/share/Trash/`、`~/.thumbnails/`、`~/.npm/`、`~/.cargo/`
- Shell 历史文件：`~/.bash_history`、`~/.zsh_history`、`~/.lesshst`、`~/.viminfo`
- 浏览器状态目录：`~/.config/microsoft-edge/`、`~/.config/nvm/`、`~/.config/chromium/`、`~/.config/google-chrome-for-testing/`
- macOS 系统目录：`~/Applications/`、`~/Library/`、`~/Movies/`、`~/Public/`、`~/Sites/`、`~/.Trash/`
- macOS 元数据：`*.DS_Store`
- 日志和临时文件：`*.log`、`*.tmp`、`*.swp`、`core.*`

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
| `.config-backup.bak/*` | 用户急救备份，迁移和 Fresh 扫描均不得触碰 |
| `.cfg-checkout-state` | checkout 状态记录文件 |
| `.local/bin/dotcfg` | 统一命令入口 |
| `.local/share/test/*` | 测试目录 |

浏览器、NVM、Linux/macOS 用户数据目录、缓存、历史记录和临时文件等策略性规则不再硬编码在
运行逻辑中，统一位于 `exclude.conf` 的兼容区段；配置缺失时由内置回退提供同样的保护。

#### 状态检测

`cfg_detect_state()` 先检查 `.cfg`，不存在时返回 `fresh`。仓库存在且节点元数据有效时，读取 HEAD
节点的 `type`。只有当前 category 版本显式声明 `CATEGORY_ALIASES` 时才规范化名称；缺少该元数据时
原样返回节点 type。因此历史 `desktop/server` 节点仍显示原值，但这些名称不会自动成为可切换目标。

没有节点元数据时，优先读取当前 category 版本的 `STATE_INDICATORS` 和 `STATE_DEFAULT`；旧配置
缺少这些字段时回退到 `.xinitrc`、`.xprofile` 或 `.config/x11/xinitrc` 存在即为 `full`，否则为
`min`。空的 `.config/x11/` 目录不构成指标。独立调用未加载 category 库的 `cfg-validate.sh` 时
仍使用同一组兼容指标。

#### dotcfg list 的 TYPE 来源

`dotcfg list` 输出的 TYPE 列来自节点创建时记录的 `type` 字段（存储在 `index.json`）。正式新节点
通常使用正式配置中的 `full`、`min` 或 `macos`，根节点固定为 `fresh`。迁移旧会话时保留原始
`desktop/server` type；这只是历史数据，不赋予同名 category 特殊地位。新节点记录用户实际选择的
普通 category 名称。

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

status 取值：`tracked_at_install`（安装或重建时由混合选择器加入）、`tracked_by_user`（用户
`dotcfg track` 添加）、`legacy_backup`（旧备份原件）或 `untracked_config_at_adoption`（采纳时的
未跟踪配置）。
普通节点和 Fresh 节点都将符号链接视为独立配置对象：复制、备份、摘要、diff 和恢复均使用链接
文本，不跟随链接目标；失败回滚、undeploy、uninstall 和 autoclean 的文件枚举也包含符号链接。
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

- 重复执行 `dotcfg switch <category> --reinstall` 创建新节点
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

### 场景 1：全量安装
```bash
dotcfg switch full --dry-run  # 预览
dotcfg switch full            # 安装（创建节点）
exec zsh                      # 重启 shell
```

### 场景 2：命令行或 macOS 部署
```bash
dotcfg switch min --dry-run
dotcfg switch min             # Linux 命令行配置

dotcfg switch macos --dry-run
dotcfg switch macos           # 跨平台核心配置
```

### 场景 3：category 切换
```bash
dotcfg switch min             # full → min，退出文件先按需备份再移除
dotcfg switch full            # min → full，补齐全量文件
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

**最后更新**: 2026-08-11
**版本**: 5.5 — 跨 Linux/macOS Fresh 排除 + 单一保留 full category + min 精简
