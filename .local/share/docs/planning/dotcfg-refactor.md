# dotcfg 内部重构计划

## 计划状态

- 状态：阶段 0 已完成，阶段 1 执行中
- 确认日期：2026-08-10
- 基线提交：`0d3209a fix: align dotcfg command output documentation`
- 基线测试：181/181 个受管 Bats 测试通过
- 当前检查点：243 个受管 Bats 测试，包含原本未纳管的 category、配置版本和生命周期测试
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

## 阶段计划

### 阶段 0：回归基线（已完成）

- 增加关键只读命令的精确输出和返回码测试
- 增加 bootstrap、旧入口、配置缺失和配置回退的行为测试
- 固化当前测试数量、性能数据和 ShellCheck 统计
- 验收：181/181 通过，工作树无非预期改动

### 阶段 1：按需加载与进程内缓存（执行中）

- 增加 `core/env.sh`、`core/loader.sh` 和配置缓存边界
- 保留 `common.sh` 作为兼容聚合入口
- help/version 在已安装状态下不加载业务库；bootstrap 路径保持原样
- 为节点索引增加 `code -> index` 关联数组和进程内缓存
- 为 category 版本解析增加按版本缓存和显式失效函数
- 不首先引入磁盘缓存，避免 stale cache、并发和恢复复杂度
- 验收：所有测试通过，status 不超过基线，categories list 明显改善

### 阶段 2：外部化配置性硬编码

- 将 23 项策略性排除规则迁移到 `.local/lib/dotfiles/exclude.conf`
- 7 项安装基础设施保护继续硬编码并始终生效
- 保留缺失配置文件时的默认回退
- 保持既有 `check-exclude` 输出中的 `hardcoded rule` 兼容标签
- 在 category 文件头部增加可选的状态指标、状态类别、TAG 值和旧别名元数据
- 旧配置缺少元数据时使用现有默认值
- 验收：绝对路径、排除规则、配置回退和安全边界测试全部通过

### 阶段 3：动态 category 与状态检测

- switch 目标校验从当前 category 配置读取
- 状态检测优先使用节点元数据，其次使用 category 元数据，最后使用现有三个指标回退
- 保留 `full`、`bootstrap`、`desktop/server` 的特殊和兼容语义
- 当前正式 category 下的输出顺序和文字不改变
- 验收：新增 category、缺失元数据、旧配置和旧节点测试通过

### 阶段 4：入口和命令拆分

- 将入口内嵌的 status/list/history/categories 实现拆为薄命令模块
- dotcfg 只保留 bootstrap、参数分发和兼容转换
- 现有命令路径先保留兼容包装，验证一个模块后再迁移下一个
- 不删除 `switch-desktop.sh`、`switch-server.sh` 和 `bootstrap-lib.sh`
- 验收：全命令矩阵、旧会话迁移、bootstrap 和完整生命周期测试通过

### 阶段 5：可读性和静态检查

- 为公共 `cfg_*`、`fresh_*` 函数补充参数、返回值和副作用说明
- 修复高置信度 ShellCheck 问题，动态 source 和跨文件全局变量使用有理由的注释
- 新增代码统一四空格、双引号和局部变量风格
- 统一错误辅助函数只用于新代码，既有错误文字不批量改写
- 验收：ShellCheck 无新增 warning，Bash 语法、diff 检查和全量测试通过

### 阶段 6：文档和最终复查

- 更新 `installation-system.md` 的内部架构、加载关系和配置元数据说明
- 更新 architecture、testing 和依赖文档中受影响的内容
- 执行全库文档一致性检查：术语、链接、目录结构、逻辑关系和平台事实
- 记录完成项到 `history.md`，未完成项保留在 `todo.md` 或 `suspended.md`
- 只有全部验收通过后才进行阶段性提交

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
