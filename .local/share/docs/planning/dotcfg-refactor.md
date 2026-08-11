# dotcfg 内部重构计划

## 计划状态

- 状态：阶段 0、阶段 1、阶段 2、阶段 3、阶段 4、阶段 5、阶段 6 已完成
- 确认日期：2026-08-10
- 基线提交：`0d3209a fix: align dotcfg command output documentation`
- 基线测试：181/181 个受管 Bats 测试通过
- 当前检查点：251 个受管 Bats 测试，包含原本未纳管的 category、配置版本和生命周期测试
- 适用平台：本轮只在[平台档案索引](../platforms/index.md)所列当前 Debian 平台执行真实性验证；
  其他发行版只做 Shell 语法和兼容性判断

## 不可变约束

重构不得改变现有用户接口：

- `dotcfg` 命令名称、参数、返回码保持不变
- 正常配置下的终端输出、颜色、表格和图形符号保持不变
- `categories-*.conf`、`exclude.conf` 既有语法和语义保持兼容
- `desktop/server`、`full/min/macos`、`fresh` 和 `bootstrap` 兼容语义保留
- bootstrap 必须继续由入口脚本独立完成，不能依赖尚未安装的库
- 旧会话迁移、旧入口包装脚本和 Fresh 恢复逻辑必须继续可用

发现需要改变用户可见行为时，暂停当前阶段，先说明差异并等待确认。

## 当前基线

在本设备 Debian 环境中，使用 `hyperfine --warmup 3 --runs 20` 测得：

| 命令 | 平均耗时 |
|------|---------:|
| `dotcfg help` | 14.1 ms |
| `dotcfg status` | 66.5 ms |
| `dotcfg list` | 31.7 ms |
| `dotcfg categories list` | 377.5 ms |

ShellCheck 当前记录 102 条提示，其中动态 `source` 的 SC1091 有 44 条；后续验收要求不新增
warning，并逐步修复高置信度问题。

### 阶段 1 节点缓存检查点

2026-08-10 使用同一快照、预热 3 次并运行 20 次的 A/B 结果：

| 命令 | 重构前 | 节点缓存后 |
|------|-------:|-----------:|
| `dotcfg help` | 15.3 ms | 13.5 ms |
| `dotcfg status` | 70.5 ms | 60.8 ms |
| `dotcfg list` | 34.7 ms | 31.9 ms |
| `dotcfg history` | 86.0 ms | 47.2 ms |
| `dotcfg categories list` | 未单独对比 | 339.8 ms |

节点读取命令无回退，`history` 提升约 45%。category 解析仍是下一项优化对象。

### 阶段 1 category 缓存检查点

2026-08-11 使用同一快照、预热 3 次并运行 20 次，`dotcfg categories list` 从 301.9 ms 降至
84.8 ms，提升约 72%。实现只使用进程内的版本发现、显示前缀和元数据缓存；配置文件变化后通过
`cfg_config_versions_invalidate` 与 `cfg_categories_invalidate` 显式失效，不创建磁盘缓存。

### 阶段 1 按需加载检查点

2026-08-11 使用同一快照、预热 3 次并运行 30 次：`dotcfg help` 从 13.6 ms 降至 7.5 ms，
`dotcfg version` 为 7.8 ms。`help`、`version` 以及带 `--help` 的命令不会加载 nodes、categories、
exclude 或 fresh 业务库；bootstrap 路径保持原有自举逻辑。

## 阶段计划

### 阶段 0：回归基线（已完成）

- 增加关键只读命令的精确输出和返回码测试
- 增加 bootstrap、旧入口、配置缺失和配置回退的行为测试
- 固化当前测试数量、性能数据和 ShellCheck 统计
- 验收：181/181 通过，工作树无非预期改动

### 阶段 1：按需加载与进程内缓存（已完成）

- 在现有入口和 `utils/` 文件内增加加载边界，不新增 `core/` 目录
- 保留 `common.sh` 作为兼容聚合入口
- help/version 在已安装状态下不加载业务库；bootstrap 路径保持原样
- 为节点索引增加 `code -> index` 关联数组和进程内缓存
- 为 category 版本解析增加按版本缓存和显式失效函数
- 不首先引入磁盘缓存，避免 stale cache、并发和恢复复杂度
- 验收：246/246 测试通过，status 不超过基线，categories list 明显改善；已提交
  `2ff737f`、`676703b`、`ac13370`

### 阶段 2：外部化配置性硬编码（已完成）

- 将 23 项策略性排除规则迁移到 `.local/lib/dotfiles/exclude.conf`
- 7 项安装基础设施保护继续硬编码并始终生效
- 保留缺失配置文件时的默认回退
- 保持既有 `check-exclude` 输出中的 `hardcoded rule` 兼容标签
- 在 category 文件头部增加可选的 `VALID_TAGS`、`CATEGORY_ALIASES`、`STATE_DEFAULT` 和
  `STATE_INDICATORS` 元数据
- 旧配置缺少元数据时使用现有默认值
- 兼容区段规则仍显示为 `hardcoded rule`，普通用户规则显示为 `exclude.conf`
- 验收：249/249 测试通过；阶段 2 已提交 `6fbb369`

### 阶段 3：动态 category 与状态检测

- switch 目标校验从当前 category 配置读取
- 状态检测优先使用节点元数据，其次使用 category 元数据，最后使用现有三个指标回退
- 保留 `full`、`bootstrap`、`desktop/server` 的特殊和兼容语义
- 当前正式 category 下的输出顺序和文字不改变
- 自定义 category 可通过 `dotcfg switch <category>` 使用；未知目标继续保持原错误文本
- 验收：251/251 测试通过，状态元数据和自定义 category 回归通过；阶段 3 已提交 `01504c8`

### 阶段 4：入口和命令拆分（已完成）

- 将入口内嵌的 status/list/history/categories 实现拆为薄命令模块：
  `.local/lib/dotfiles/commands/status.sh`、`list.sh`、`history.sh`、`categories.sh`
- dotcfg 保留 bootstrap、按需加载、参数分发、switch 兼容转换和 help/validate 入口
- 现有命令路径先保留兼容包装，验证一个模块后再迁移下一个
- 不删除 `switch-desktop.sh`、`switch-server.sh` 和 `bootstrap-lib.sh`
- 验收：全命令矩阵、旧会话迁移、bootstrap 和完整生命周期测试 `251/251` 通过；
  `status`、`list`、`history`、`categories` 与重构前输出逐字一致；阶段 4 已提交
  `8352c95`、`a34dea8`、`cc86f93`

### 阶段 5：可读性和静态检查

（已完成）

- 为公共 `cfg_*`、`fresh_*` 函数补充参数、返回值和副作用说明
- 修复高置信度 ShellCheck 问题，动态 source 和跨文件全局变量使用有理由的注释
- 新增代码统一四空格、双引号和局部变量风格
- 统一错误辅助函数只用于新代码，既有错误文字不批量改写
- 验收：公共函数参数、返回值和副作用说明已补充；ShellCheck 严重级别
  `warning/error` 为 0（保留 59 条动态 source 信息和 12 条 style 提示）；Bash 语法、
  diff 检查和全量测试 `251/251` 通过。阶段 5 已提交 `91ac775`、`c7e0a50`

### 阶段 6：文档和最终复查

（已完成）

- 更新 `installation-system.md` 的内部架构、加载关系和配置元数据说明
- 更新 architecture、testing 和依赖文档中受影响的内容
- 执行全库文档一致性检查：术语、链接、目录结构、逻辑关系和平台事实
- 记录完成项到 `history.md`，未完成项保留在 `todo.md` 或 `suspended.md`
- 最终复查：文档链接、目录/代码路径、术语与平台边界检查通过；未发现凭据、主机名、序列号、
  UUID、MAC/IP 或私钥内容。已知 `.gitconfig` 中仍有用户明确要求暂时保留的 Git 身份邮箱，
  是否重写公开历史继续由 `todo.md` 单独跟踪；完整 Bats `251/251`、Bash 语法、
  `git diff --check` 和 ShellCheck 严重级别检查通过。

### 阶段 6 性能检查点

2026-08-11 在同一 Debian 会话中使用 `hyperfine --warmup 5 --runs 30` 测得：

| 命令 | 平均耗时 |
|------|---------:|
| `dotcfg help >/dev/null` | 7.0 ms |
| `dotcfg status >/dev/null` | 103.9 ms |
| `dotcfg list >/dev/null` | 35.8 ms |
| `dotcfg categories list >/dev/null` | 98.4 ms |

四个查询命令均低于既定 `help <= 0.2s`、`status <= 0.5s` 目标；状态和类别耗时受当前
节点数量、网络验证和会话负载影响，后续性能比较必须复用同一快照和测量参数。

## 允许保留的硬编码

- `full` 的全部跟踪文件语义
- `bootstrap` 特殊版本标识
- 安装基础设施保护路径
- 配置文件缺失时保证系统可用的默认回退
- 旧会话和旧入口兼容别名

## 性能验收

每阶段使用同一设备、同一环境执行：

```bash
hyperfine --warmup 5 --runs 30 \
  'dotcfg help >/dev/null' \
  'dotcfg status >/dev/null' \
  'dotcfg list >/dev/null' \
  'dotcfg categories list >/dev/null'
```

`switch` 使用隔离 HOME 和 `--dry-run` 测试；任何复杂命令不得比对应基线慢超过 5%。

## 交付规则

每个阶段单独提交，提交前必须报告：修改文件、测试结果、输出差异、性能变化和剩余风险。
任何阶段发现用户可见行为变化，立即停止该阶段，不自行扩大范围。
