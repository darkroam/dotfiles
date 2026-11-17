# X11 桌面指南

公共使用说明仍在 `.local/share/docs/user/desktop-guide-zh.md`。本文只收 X11 桌面和 xdisplay。

## X11 桌面与输入

进入 X11 后，DWM 管理窗口，dmenu 用于启动程序，st 提供终端，Dunst 显示通知。常用操作
包括 `Mod+Enter` 打开终端、`Mod+d` 打开 dmenu、`Mod+数字` 切换工作区、
`Mod+Shift+数字` 移动窗口。

在 st 中用左键拖选文本；存在已完成选区时，右键把选区复制到 `CLIPBOARD` 并清除高亮，
没有选区时右键把 `CLIPBOARD` 粘贴到终端当前光标位置。右键点击不会把 shell 光标移动到
鼠标所在列。中键仍粘贴 `PRIMARY`。Nvim、Tmux 等程序启用鼠标上报后，普通鼠标操作由程序
处理；使用 `Shift+左键拖动`建立 st 本地选区，使用 `Shift+右键`强制执行 st 的本地复制或粘贴。

Herdr 当前启用 `mouse_capture`，因此工作区窗格的普通鼠标操作和滚轮由 Herdr 处理；st 的
选区、`PRIMARY`/`CLIPBOARD` 语义仍以 st 源码和上面的强制本地修饰键规则为准。

`Mod+F1` 会用 Groff 动态生成英文快捷键指南并在 Zathura 中打开。若指南无法生成或命令标签
显示异常，确认已安装 `groff`、可嵌入的 Nimbus Sans Type 1 字体、`zathura` 和 PDF 后端，
再从 `~/src/dwm` 重新安装帮助文件；发行版包名见平台档案。

输入法优先使用 fcitx5。无法输入中文时，先确认输入法程序已安装，再完整退出并重新进入
X11。Caps、菜单键或外接键盘行为不符合预期时，使用 `Mod+F12` 重新应用键盘映射；若仍有
问题，检查当前硬件是否支持该映射。

## 显示布局

`Mod+F3` 打开显示选择器；多屏、镜像和手动显示布局按当前显示器连接状态选择。

登录 X11 时，`xdisplay watch` 会同时监测笔记本盖子和已连接显示器：合盖且有外接显示器时关闭内屏并
将外屏设为主屏；切换时会先准备外屏再关闭内屏。开盖时恢复内屏为主屏，并按显示布局配置排列所有
外屏。启动时若暂时只发现一个输出，会直接将其启用为主屏；
之后检测到新输出会再次收敛显示布局。无法识别内屏的多屏情况会尝试镜像，失败后 watcher 会继续重试，
但 XRandR 不保证自动回滚已经部分应用的显示布局。

`xdisplay` 失败时会输出错误，并在 `notify-send` 可用时通知；`displayselect` 的所有失败路径
不保证通知。需要立即修正显示布局时执行 `xdisplay apply`；旧 `xdisplay.sh --apply` 只作为兼容入口保留。

只排查、不修改显示布局时执行 `xdisplay status`，它会显示 lid、各输出的连接与 geometry、
current/preferred/target 模式及刷新率、模式数量和能力签名、stale/pending、当前策略、锁路径、
watcher generation、manual marker、配置摘要和命中的自定义显示布局。标准内屏名称无需设置。

非标准硬件可以使用已经实现但默认关闭的本地
[设备适配器](display-device-adapter.md)；适配器失败会回到标准探测和平台已登记的 legacy
兼容路径，不把新设备参数写进通用配置。
事件后 watcher 会短时提高探测频率以等待迟到模式；手动显示选择期间
自动显示布局等待共享锁。缺少基础命令时脚本会明确提示，缺少 Arandr 只影响可选手动界面。

调整好显示布局后可执行 `displayselect save [名称]` 保存；`displayselect list` 列出快照，
`displayselect delete 名称` 删除。保存的显示布局在输出集合和 lid 匹配时优先于默认扩展方向；损坏或
不再可用的快照会自动回退默认策略。

切换不正常时，先保存 `xdisplay status` 和 `xrandr --current`，检查 stale/pending、primary、
geometry、target 模式和 framebuffer，再执行一次 `xdisplay apply`。不要手工套用另一台设备
或另一 connector 的分辨率。显示布局已经正确但物理出图仍慢时，按
[显示管理设计](display-management.md#framebuffer-边界)区分软件收敛与驱动/链路延迟；
设备已知现象和已验证恢复路径只从[平台档案索引](../../platforms/index.md)查看。

## 锁屏桥接

X11 启动时 `xss-lock`
以 `--ignore-xss` 启动：它不新增空闲超时锁屏，但会在 login manager 准备睡眠时启动
`slock`。确认 `pgrep -x xss-lock` 有输出后再验证挂起；命令缺失或未启动时，硬件睡眠仍由
login manager 执行，但不保证恢复前已有 `slock`。
