# 文档中心索引

本配置库的文档体系按读者类型和主题组织。根目录 `README.md` 提供安装入口，本文档提供完整导航。

## 快速开始

只想快速安装和使用？阅读根目录 [README](../../../README.md)。

## 用户指南（面向最终用户）

日常使用、快捷键、个性化设置：

- [桌面使用指南](user/desktop-guide-zh.md) — 安装、启动、使用和故障处理
- [快捷键摘要](user/keybindings-zh.md) — DWM 键位和媒体键速查

## 维护者/Codex 文档（面向 AI 助手和开发者）

项目架构、依赖、设计决策和维护边界：

- [架构与设计](project/architecture.md) — 目录结构、运行关系、所有权和维护边界
- [依赖清单](project/dependencies.md) — 完整命令和能力清单，按布局（layout）组织
- [维护策略](project/maintenance-policy.md) — 项目约束、工作流规则、已接受决定和明确不采用项
- [文档质量规范](project/docs-standard.md) — 文件级写作标准、完整性自检、Agent 维护规范
- [显示管理设计](project/display-management.md) — X11 显示引擎的状态模型、布局策略和验证矩阵
- [显示设备适配器指引](project/display-device-adapter.md) — 非标准硬件扩展接口规范

## 平台部署（面向运维）

发行版映射、设备事实、验证和恢复：

- [平台档案索引](platforms/index.md) — 所有平台的入口，包含包映射、系统事实和平台工作

## 安装系统

安装脚本、状态机和已知问题：

- [安装系统设计](project/installation-system.md) — 节点幂等安装系统架构、统一 CLI 和共享验证库
- [安装测试](project/installation-testing.md) — 节点系统测试框架、181 个受管测试用例验证
- [安装修复记录](planning/installation-fixes.md) — B1-B8 已修复缺陷、设计变更和验证记录

## 项目跟踪

活动待办、挂起项目和历史变更：

- [当前待办](planning/todo.md) — 进行中的工作
- [挂起项目](planning/suspended.md) — 暂缓的工作和恢复条件
- [变更历史](planning/history.md) — 已完成的工作记录
- [跨发行版审计流程](planning/dependency-audit.md) — 可复用的审计流程和基线
- [dotcfg 内部重构计划](planning/dotcfg-refactor.md) — 已确认的分阶段重构方案、基线和验收门槛
- [全量审查问题清单](audits/2026-07-31-full-review.md) — 2026-07-31 审计发现的 112 项问题（已全部修复）
- [配置全量审计修改](audits/2026-08-04-full-review.md) — 2026-08-04 审计修改计划 64 项（已全部完成）

## 文档体系说明

### 读者定位

- **根 README.md**：只想快速使用的用户，保留最简要的安装说明、启动逻辑、感谢和版权
- **用户指南**：需要了解如何安装、启动、使用和个性化的最终用户，不需要理解实现细节
- **维护者/Codex 文档**：AI 助手和维护者，需要理解项目全貌、结构、所有权、运行关系和决策

### 术语规则

除根 `README.md` 外，所有 `.local/share/docs/` 下文档使用中文标题和内容。命令名、路径、代码标识、字面输出、许可证和必要上游引用保持原样。

### 内容重叠说明

`architecture.md` 与 `desktop-guide-zh.md` 因读者不同必然存在内容重叠（如快捷键、启动流程），这是设计意图而非缺陷。两者各自独立完整，不要求读者交叉引用。

## 文档关系

```
根 README.md (英文，安装入口)
    ↓
docs/README.md (中文，文档索引)
    ├── 用户指南 (desktop-guide-zh.md, keybindings-zh.md)
    ├── 维护者文档 (architecture.md, dependencies.md, maintenance-policy.md, docs-standard.md)
    ├── 显示管理 (display-management.md, display-device-adapter.md)
    ├── 安装系统 (project/installation-system.md, project/installation-testing.md)
    ├── 平台部署 (platforms/index.md → 各平台档案)
    ├── 审计记录 (audits/ — 按日期归档的审计发现和执行记录)
    └── 项目跟踪 (todo.md, suspended.md, history.md, dependency-audit.md, installation-fixes.md)
```

修改任何文档后，必须执行维护策略规定的全库一致性检查：术语统一、内部链接有效、文档关系成立、无平台泄漏。
