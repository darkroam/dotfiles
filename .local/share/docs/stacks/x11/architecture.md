# X11 架构摘录

> 服务域：U02；U06 的 X11 段

公共架构仍在 `.local/share/docs/project/architecture.md`。本文只收 U02 全文，以及 U06 的显示布局和锁屏桥接。

## U02 · X11 桌面与输入

负责会话启动、输入法选择、键盘重映射、合成器、Xresources 和 X11 辅助工具。`xprofile` 是
唯一输入法决策点，必须从选定引擎导出完整环境。它可以启动会话应用，但不得取得由平台服务
管理器负责的音频服务所有权。

`~/src/` 的 DWM、DWMBlocks、dmenu 和 st 是独立源码仓库；`slock` 是系统程序。DWM `Mod+F1`
使用 Groff 将安装的 `larbs.mom` 动态生成 PDF 并交给 Zathura，命令/快捷键标签必须使用实际
嵌入字体。四仓库的获取与构建入口位于根 README，编译能力由依赖清单定义，发行版开发包映射
只写平台档案。源码、安装副本、字体和代表页面的检查遵循维护策略。

Clash Verge 自己拥有运行时生成的
`~/.local/share/applications/clash-verge-handler.desktop`：Tauri deep-link 插件根据当前实际
可执行文件生成该入口，并注册 `clash:` 与 `clash-verge:`。配置库只跟踪
`.config/mimeapps.list` 中指向 `clash-verge-handler.desktop` 的默认关联，并显式忽略生成文件；
不得重新加入包含固定安装路径的 handler。Clash Verge 源码属于独立仓库，本配置库只维护双方的
文件所有权边界和桌面关联结果。

st 自己拥有终端选区状态机：左键完成选区时写入 X11 `PRIMARY`；右键释放时若当前屏幕存在
已完成选区，就将其复制到 `CLIPBOARD` 并清除终端高亮，否则请求并粘贴 `CLIPBOARD`；中键继续
请求 `PRIMARY`。该路径使用 st 已有的 X selection 所有权和转换逻辑，不依赖外部 `xclip`。
应用启用鼠标上报时，事件上报先于本地鼠标快捷动作；普通右键留给应用，`Shift` 通过统一的
强制本地修饰键恢复 st 的左键选区与右键动作。此行为属于 st 源码边界，不应移入 DWM 或 xprofile。

## U06 · 显示布局与锁屏桥接

`xprofile` 通过按登录会话和规范化 X server 划分的 `flock` 运行锁，单实例启动
`xss-lock --ignore-xss -- slock`：它在 login1 睡眠准备阶段启动真实 locker，
但不改变 XScreenSaver 空闲策略。标准 `slock` 不实现
`XSS_SLEEP_LOCK_FD` 握手，因此不使用 `--transfer-sleep-lock`；若未来要求严格的 locker-ready
确认，必须另行实现可验证的 FD 关闭协议，不得只加该选项。

显示状态模型、锁、显示布局、设备适配器边界、验证矩阵和 framebuffer 诊断统一由
[X11 显示管理设计](display-management.md)定义；本节不复制算法或平台实测。

`xdisplay apply`（默认）、`xdisplay watch` 和 `xdisplay status` 分别负责立即对齐、持续监测和只读
诊断；`xdisplay.sh` 仅转发旧参数。`displayselect` 是交互选屏和自定义显示布局管理入口，两者必须
共用显示布局锁。共享实现不得新增硬编码设备输出、模式或服务；非标准差异只通过默认关闭的设备
适配器接入。
