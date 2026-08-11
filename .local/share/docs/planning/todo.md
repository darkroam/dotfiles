# 当前待办

本文面向 Agent 和维护者。

这里只保留活动工作。修改已跟踪文件前，先检查其运行依赖并保持可选依赖行为。

- [ ] 检查审计未覆盖的文件是否包含过时设置或发行版专属假设（安装脚本、补丁文件、DWM 源码
  配置等），但不删除可信个人设置。全量 H/M/L 审计（112 项）已于 2026-08-04 完成。
- [ ] 按[平台档案索引](../platforms/index.md)完成各平台仍需真实会话、硬件、账户或网络的验证；
  公共 TODO 不重复记录某台设备的安装状态。
- [ ] 在持续 PipeWire-only 测试后，决定是否可以移除保留的 ALSA 兼容入口。
- [ ] 启用无人值守包检查前，复查 cron 调度和 sudo 策略。
- [ ] 决定是否重写已发布 Git 历史，以移除历史作者/提交者邮箱元数据和旧跟踪
  `.gitconfig` 身份。此操作需要协调 force-push，不能轻率执行。
- [ ] 已跟踪功能或所需命令变化时，更新 `dependencies.md`。
- [ ] 逐项审查 `exclude.conf` 兼容区段的 30 项 Fresh 策略排除；缓存、浏览器可变状态、macOS
  标准用户目录和 `.config-backup.bak` 的排除原则已经确认，但完整模式清单尚未逐项确认。
- [ ] 审查无节点元数据时的状态兼容默认：`STATE_DEFAULT=min`，以及 `.xinitrc`、`.xprofile`、
  `.config/x11/xinitrc` 存在时判断为 `full`；这些值来自历史检测逻辑，尚未逐项确认。
- [ ] 本机 k10temp 设备识别与驱动补丁工作已移至[平台档案的活动待办](../platforms/kaitian-x7h-g1e-debian-13.md#平台活动待办)，
  通用 planning 文档不再保存设备型号、PCI ID 或发行版专属事实。
- [x] 测试脚本环境隔离加固：已从 Gen 1 shell 脚本迁移到 Bats 框架，测试目录迁移到
  `.local/share/test/installation/`。所有测试在 `/tmp/dotfiles-test-*` 隔离环境中运行，
  `teardown` 有双重安全检查（拒绝删除 `$REAL_HOME`，只删除 `/tmp/` 下路径）。72 个测试全部通过。

有意挂起的工作见[挂起项](suspended.md)，已完成项目记录在[待办历史](history.md)。
