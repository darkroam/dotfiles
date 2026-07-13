# 当前待办

这里只保留活动工作。修改已跟踪文件前，先检查其运行依赖并保持可选依赖行为。

- [ ] 检查其余配置文件是否包含过时设置或发行版专属假设，但不删除可信个人设置。
- [ ] 在真实多显示器 X11 会话中复查新版 `xdisplay.sh --watch` 的合盖、开盖、插拔、启动时慢速外屏接入、
  未知内屏多屏镜像回退、动态轮询和单实例锁；已验证 `displayselect` 精确过滤输出名称并设置
  `xrandr --primary`。
- [ ] 在安装依赖后测试交互式 X11 路径：`nmtui`、`nsxiv`、日历、亮度、截图、OTP、
  MTP/CIFS 挂载、种子、录制选择和 RSS 下载队列。
- [ ] 安装后复查依赖：`mpc`、NetworkManager、图像和预览工具、task-spooler、
  Transmission、媒体元数据工具和需要的编译工具链。
- [ ] 在持续 PipeWire-only 测试后，决定是否可以移除保留的 ALSA 回退文件。
- [ ] 启用无人值守包检查前，复查 cron 调度和 sudo 策略。
- [ ] 决定是否重写已发布 Git 历史，以移除历史作者/提交者邮箱元数据和旧跟踪
  `.gitconfig` 身份。此操作需要协调 force-push，不能轻率执行。
- [ ] 已跟踪功能或所需命令变化时，更新 `dependencies.md`。

有意挂起的工作见[挂起项](suspended.md)，已完成项目记录在[待办历史](history.md)。
