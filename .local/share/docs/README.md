# 文档中心索引

本配置库的文档体系按读者类型和主题组织。根目录 `README.md` 提供安装入口，本文档提供完整导航。
根 README 与 `user/` 构成面向最终用户的交付层；其余文档构成面向开发、验证和维护的开发文档层。
两层各自保持自洽并独立维护，通过本索引互相导航，不要求任一类读者先理解另一层，也不把用户指南
迁入上游 LARBS 保留区。

## 快速开始

只想快速安装和使用？阅读根目录 [README](../../../README.md)。

## 用户指南（面向最终用户）

日常使用、快捷键、个性化设置：

- [桌面使用指南](user/desktop-guide-zh.md) — 安装、启动、使用和故障处理
- [快捷键摘要](user/keybindings-zh.md) — DWM/st 键位和桌面级按键；Vim、Emacs、Herdr、Tmux 的完整分类速查可用 `getkeys <program>`

## 维护者/Codex 文档（面向 AI 助手和开发者）

项目架构、依赖、设计决策和维护边界：

- [架构与设计](project/architecture.md) — 目录结构、运行关系、所有权和维护边界
- [架构域归属表](project/domain-map.md) — 跟踪路径到唯一主域和可选关联域的权威登记
- [依赖清单](project/dependencies.md) — 十个用户能力域到通用命令、库和服务的映射
- [维护策略](project/maintenance-policy.md) — 项目约束、工作流规则、已接受决定和明确不采用项
- [文档质量规范](project/docs-standard.md) — 文件级写作标准、完整性自检、Agent 维护规范
- [显示管理设计](project/display-management.md) — X11 显示引擎的状态模型、显示布局策略和验证矩阵
- [显示设备适配器指引](project/display-device-adapter.md) — 非标准硬件扩展接口规范
- [显示管理测试](project/display-testing.md) — 状态、显示布局、配置和适配器的测试方案与验收步骤
- [协作规约](project/collaboration.md) — 用户 × dsh × qoder × codex 四角色协作流程、两级审查标准与提交纪律；轮次档案保存在本机私有目录 `.local/share/collab/`

### 约束速查

本表只提供约束入口和适用边界；具体规则、例外和变更记录以所链接的权威正文为准。

| 约束类别 | 权威文档 | 不可越过的边界摘要 |
| --- | --- | --- |
| 架构所有权与域归属 | [架构与设计](project/architecture.md) · [架构域归属表](project/domain-map.md) | 先确定唯一主域；路径归属只在域表登记。 |
| 项目维护与平台事实 | [维护策略](project/maintenance-policy.md) | 共享行为与设备事实分开维护；行为变更先审查再执行。 |
| 文档质量与术语 | [文档质量规范](project/docs-standard.md) | 文档必须面向单一读者，并与实现、链接和权威术语同步。 |
| 多 Agent 协作与提交 | [协作规约](project/collaboration.md) | 用户决策、dsh 终审、qoder 初审与建议、codex 实现的职责和文件边界不得越权。 |
| 安装系统外部契约 | [安装系统](project/installation-system.md#核心开发契约与不可变规则) | 用户接口、数据保护、幂等性和配置驱动契约不可由内部重构改变。 |
| 验证基线 | [安装测试](project/installation-testing.md) · [显示测试](project/display-testing.md) · [协作规约](project/collaboration.md) | 行为变更必须同步相应测试基线，失败不得绕过。 |

## 按能力域导航

架构域定义见[架构与设计](project/architecture.md#架构域模型)，路径归属只查
[架构域归属表](project/domain-map.md)。下表用于从用户能力进入命令、配置和权威文档，不复制依赖或
设计结论。

| 域 | 主要命令/配置位置 | 文档入口 |
| --- | --- | --- |
| U01 Shell、源代码管理与开发 | `.config/{shell,zsh,tmux,powershell}/`、Shell/开发辅助命令 | [架构](project/architecture.md) · [依赖](project/dependencies.md) |
| U02 X11 桌面与输入 | `.config/x11/`、`.fbtermrc`、会话/输入命令 | [架构](project/architecture.md) · [快捷键](user/keybindings-zh.md) |
| U03 外观、字体与壁纸 | `.config/{fontconfig,gtk-2.0,gtk-3.0,dunst,wal}/`、`setbg` | [架构](project/architecture.md) · [桌面指南](user/desktop-guide-zh.md) |
| U04 音频、音乐、录制与视频 | `.config/{alsa,mpd,mpv,ncmpcpp}/`、媒体辅助命令 | [架构](project/architecture.md) · [依赖](project/dependencies.md) |
| U05 文件、文档、密码与桌面处理 | `.config/{lf,nsxiv,zathura}/`、MIME/密码命令、桌面入口 | [架构](project/architecture.md) · [桌面指南](user/desktop-guide-zh.md) |
| U06 显示、网络、挂载与系统控制 | `xdisplay`、`displayselect`、`.local/lib/xdisplay/`、系统辅助命令 | [架构](project/architecture.md) · [显示设计](project/display-management.md) |
| U07 状态栏、通信与网络服务 | `.local/bin/statusbar/`、`weath` | [架构](project/architecture.md) · [依赖](project/dependencies.md) |
| U08 下载、种子与文本浏览 | `.config/newsboat/`、下载/RSS/种子辅助命令 | [架构](project/architecture.md) · [依赖](project/dependencies.md) |
| U09 编译、排版与数据辅助 | `compiler`、`getbib`、`texroot`、`opout`、`texclear` | [架构](project/architecture.md) · [依赖](project/dependencies.md) |
| U10 系统模板与计划任务 | `.local/share/sys-etc/`、`.local/bin/cron/` | [架构](project/architecture.md) · [依赖](project/dependencies.md) |

### 项目支撑域导航

| 域 | 主要位置 | 文档入口 |
| --- | --- | --- |
| S01 安装与交付 | `.local/bin/{dotcfg,install.sh}`、`.local/lib/dotfiles/` | [安装系统](project/installation-system.md) |
| S02 验证 | `.local/share/test/` | [安装测试](project/installation-testing.md) · [显示测试](project/display-testing.md) · [协作规约](project/collaboration.md) |
| S03 文档与治理 | `README.md`、`.local/share/docs/` | [文档质量规范](project/docs-standard.md) · [维护策略](project/maintenance-policy.md) |
| S04 内部工程工具 | `.local/lib/project-tools/` | [协作规约](project/collaboration.md) |
| S05 元数据与来源 | `.gitignore`、LARBS 许可证/迁移来源 | [架构域归属表](project/domain-map.md) · [维护策略](project/maintenance-policy.md) |

## 平台部署（面向运维）

发行版映射、设备事实、验证和恢复：

- [平台档案索引](platforms/index.md) — 所有平台的入口，包含包映射、系统事实和平台工作

## 安装系统

安装脚本、状态机和已知问题：

- [安装系统设计](project/installation-system.md) — 节点幂等安装系统架构、统一 CLI 和共享验证库
- [安装测试](project/installation-testing.md) — 节点系统测试框架、272 个受管测试用例验证
- [安装修复记录](planning/installation-fixes.md) — B1-B8 已修复缺陷、设计变更和验证记录

## 项目跟踪

活动待办、挂起项目和历史变更：

- [当前待办](planning/todo.md) — 进行中的工作
- [挂起项目](planning/suspended.md) — 暂缓的工作和恢复条件
- [变更历史](planning/history.md) — 已完成的工作记录
- [问题与排查记录](planning/problems.md) — 跨设备复用的脱敏问题、证据、排查结论和权威来源索引
- [跨发行版审计流程](planning/dependency-audit.md) — 可复用的审计流程和基线
- [dotcfg 内部重构计划](planning/dotcfg-refactor.md) — 已确认的分阶段重构方案、基线和验收门槛
- [全量审查问题清单](audits/2026-07-31-full-review.md) — 2026-07-31 的 112 项审计发现（均已裁决/关闭）
- [配置全量审计修改](audits/2026-08-04-full-review.md) — 2026-08-04 审计修改计划 64 项（已全部完成）

## 文档体系说明

### 读者定位

- **根 README.md**：只想快速使用的用户，保留最简要的安装说明、启动逻辑、感谢和版权
- **用户指南**：需要了解如何安装、启动、使用和个性化的最终用户，不需要理解实现细节
- **维护者/Codex 文档**：AI 助手和维护者，需要理解项目全貌、结构、所有权、运行关系和决策

### 术语规则

除根 `README.md` 外，所有 `.local/share/docs/` 下文档使用中文标题和内容。命令名、路径、代码标识、字面输出、许可证和必要上游引用保持原样。
架构分类使用“用户能力域/项目支撑域”；显示、键盘和 GLSL 语境分别使用“显示布局”“键盘布局”
和“GLSL `layout` 限定符”。完整规则见[文档质量规范](project/docs-standard.md#术语写作规则)。

### 内容重叠说明

`architecture.md` 与 `desktop-guide-zh.md` 因读者不同必然存在内容重叠（如快捷键、启动流程），这是设计意图而非缺陷。两者各自独立完整，不要求读者交叉引用。

## 文档关系

```
根 README.md (英文，安装入口)
    ↓
docs/README.md (中文，文档索引)
    ├── 用户指南 (desktop-guide-zh.md, keybindings-zh.md)
    ├── 维护者文档 (architecture.md, domain-map.md, dependencies.md, maintenance-policy.md, docs-standard.md, collaboration.md)
    ├── 显示管理 (display-management.md, display-device-adapter.md, display-testing.md)
    ├── 安装系统 (project/installation-system.md, project/installation-testing.md)
    ├── 平台部署 (platforms/index.md → 各平台档案)
    ├── 审计记录 (audits/ — 按日期归档的审计发现和执行记录)
    └── 项目跟踪 (todo.md, suspended.md, history.md, problems.md, dependency-audit.md, installation-fixes.md, dotcfg-refactor.md)
```

轮次协作档案（要求/汇报/审查）不在 docs 树内，保存在本机私有目录 `.local/share/collab/`（不入库），
结构见[协作规约](project/collaboration.md) §五。

修改任何文档后，必须执行维护策略规定的全库一致性检查：术语统一、内部链接有效、文档关系成立、无平台泄漏。
