# 快捷键摘要

本文面向本配置的使用者。

相关文档：[桌面使用指南](desktop-guide-zh.md)、[架构与设计](../project/architecture.md)

本页集中记录 DWM、st 和桌面级按键。需要查看当前 Vim/Neovim、Emacs、Herdr 或 Tmux 的
完整分类速查时，使用 `getkeys <program>`：

```sh
getkeys vim       # Vim/Neovim（当前配置以 Neovim 为准）
getkeys emacs     # Emacs、Evil 和 Hydra
getkeys herdr     # Herdr 工作区、窗格和标签
getkeys tmux      # Tmux 前缀、窗格和 copy-mode
```

这些资料位于 `~/.local/share/larbs/getkeys/`，同时整理当前配置和程序默认键；配置专属内容
以当前仓库文件为准，插件或版本相关按键可能随启用条件变化。

DWM 部分以当前 `~/src/dwm/config.h` 为准，st 鼠标操作以当前 `~/src/st/config.h` 为准。
`Mod` 是 Super/Windows 键；大写字母表示同时按 Shift。依赖缺失时，快捷键会启动失败而不会
自动安装程序。

## 窗口、窗口布局与标签

| 快捷键 | 动作 |
| --- | --- |
| `Mod+Enter` / `Mod+Shift+Enter` | 打开 `st` / 切换 `spterm` 下拉终端 |
| `Mod+q` | 关闭当前窗口 |
| `Mod+j/k` | 在窗口栈中切换 |
| `Mod+Shift+j/k` | 在窗口栈中向后/向前移动当前窗口 |
| `Mod+v` / `Mod+Shift+v` | 聚焦主窗口 / 将当前窗口推入主位置 |
| `Mod+Space` | 当前窗口提升为主窗口 |
| `Mod+Shift+Space` | 切换当前窗口浮动 |
| `Mod+h/l` | 缩小/放大主区域 |
| `Mod+z/x` | 增加/减少间隙 |
| `Mod+a` / `Mod+Shift+a` | 切换间隙 / 恢复默认间隙 |
| `Mod+s` | 切换窗口粘滞 |
| `Mod+b` | 显示/隐藏状态栏 |
| `Mod+f` / `Mod+Shift+f` | 切换全屏 / 浮动窗口布局 |
| `Mod+t` / `Mod+Shift+t` | 平铺 / 底部栈窗口布局 |
| `Mod+y` / `Mod+Shift+y` | 螺旋 / 递减窗口布局 |
| `Mod+u` / `Mod+Shift+u` | Deck / Monocle 窗口布局 |
| `Mod+i` / `Mod+Shift+i` | 居中主窗口 / 居中浮动主窗口布局 |
| `Mod+o` / `Mod+Shift+o` | 增加 / 减少主窗口数 |
| `Mod+g` / `Mod+;` | 前后切换标签 |
| `Mod+Shift+g` / `Mod+Shift+;` | 将窗口移到前后标签 |
| `Mod+数字` / `Mod+Shift+数字` | 查看标签 / 将窗口移到标签 |
| `Mod+Ctrl+数字` / `Mod+Ctrl+Shift+数字` | 追加查看标签 / 追加将窗口标记到标签 |
| `Mod+0` / `Mod+Shift+0` | 查看全部标签 / 将窗口标记到全部标签 |
| `Mod+Tab` 或 `Mod+\\` | 切换回前一标签视图 |
| `Mod+Left/Right` | 切换显示器焦点 |
| `Mod+Shift+Left/Right` | 将窗口移到另一显示器 |

自动归类：Microsoft Edge 的类名进标签 9。WPS 12 的文字、表格和演示窗口类名都是 `wpsoffice`，共进标签 6，不能再按应用拆开。

## st 鼠标操作

| 操作 | 动作 |
| --- | --- |
| 左键拖动 | 建立文本选区并更新 `PRIMARY` |
| 有选区时右键 | 复制到 `CLIPBOARD` 并清除选区高亮 |
| 无选区时右键 | 在终端当前光标位置粘贴 `CLIPBOARD` |
| 中键 | 粘贴 `PRIMARY` |
| `Shift+左键拖动` / `Shift+右键` | 程序启用鼠标上报时，强制执行 st 本地选区 / 复制粘贴 |

## 状态栏鼠标操作

| 操作 | 动作 |
| --- | --- |
| 左键、中键、右键或滚轮 | 把对应点击信号交给当前状态模块；具体动作由模块定义 |
| `Shift+左键` | 把第六种点击信号交给当前状态模块 |
| `Shift+右键` | 在 Nvim 中打开 `~/src/dwmblocks/config.h` |

蓝牙块 `sb-bluetooth`（信号 2，每 10 秒刷新）只使用前三种点击。`Shift+右键` 仍由 DWM 全局打开上面的 `config.h`，该块不绑定第六种点击。

无适配器时该块不输出。适配器关闭显示 `⛔`，可用但无连接显示 `🔵`。已连接时按设备类型显示图标和总数，例如 `🎧📱 2`；同一类型只保留一个，最多四个，多出的类型写成 `+N`。没有已知类型时仍显示 `🔵N`。

主菜单的「动态扫描（fzf）」用 `st -e btmenu --dynamic` 打开终端，最多扫描 30 秒，并通过本地 Unix socket 每秒刷新 fzf。回车后才配对；只有已配对且已连接才算成功，失败写在终端和通知里。原「扫描并配对」仍是 8 秒。

| 点击 | `BLOCK_BUTTON` | 动作 |
| --- | --- | --- |
| 左键 | 1 | `btmenu` 主菜单 |
| 中键 | 2 | 已连接设备列表 |
| 右键 | 3 | `notify-send` 模块说明 |

用法详情见 `getkeys btmenu`。


## 启动器与常用程序

| 快捷键 | 动作 |
| --- | --- |
| `Mod+d` / `Mod+Shift+d` | dmenu / 已跟踪的 `passmenu` 密码库菜单；后者默认复制所选密码 |
| `Mod+\`` | Unicode/Emoji 菜单 |
| `Mod+w` / `Mod+Shift+w` | 浏览器（Microsoft Edge）/ `nmtui` |
| `Mod+e` / `Mod+Shift+e` | Neomutt / Abook 通讯录 |
| `Mod+c` | Profanity XMPP 客户端 |
| `Mod+r` / `Mod+Shift+r` | LF / Htop |
| `Mod+n` / `Mod+Shift+n` | Vimwiki / Newsboat |
| `Mod+m` | Ncmpcpp |
| `Mod+Shift+m` | 切换默认输出静音并刷新状态栏 |
| `Mod+'` / `Mod+Shift+'` | 切换 `spcalc` 计算器 / 切换智能间隙 |
| `Mod+F1` | DWM 安装的英文指南 |
| `Mod+F2` | 教程视频菜单 |
| `Mod+F3` | 显示器选择器 |
| `Mod+F4` | Pulsemixer |
| `Mod+F5` | 重载 Xresources |
| `Mod+F6/F7` | Transmission / Transmission 开关 |
| `Mod+F8` | 邮件同步 |
| `Mod+F9/F10` | 挂载 / 卸载普通块设备 |
| `Mod+F11` | 摄像头预览 |
| `Mod+F12` | 重新执行键盘映射 |
| `Mod+Backspace`、`Mod+Shift+q` | `sysact` 系统操作菜单 |
| `Mod+Insert` | 从 LARBS snippets 菜单输入文本 |

## 音乐、截图与录制

| 快捷键 | 动作 |
| --- | --- |
| `Mod+,` / `Mod+.` | MPD 上一首 / 下一首 |
| `Mod+Shift+,` | MPD 回到开头 |
| `Mod+Shift+.` | 切换 MPD 循环 |
| `Mod+p` / `Mod+Shift+p` | 播放/暂停 MPD / 暂停 MPD 和 shell 启动的 MPV |
| `Mod+[` / `Mod+]` | MPD 后退/前进 10 秒 |
| `Mod+Shift+[` / `Mod+Shift+]` | MPD 后退/前进 60 秒 |
| `Mod+-` / `Mod+=` | 默认输出音量减/加 5% |
| `Mod+Shift+-` / `Mod+Shift+=` | 默认输出音量减/加 15% |
| `Print` / `Shift+Print` | 保存全屏截图到 maimpick 目录 / 打开选区、窗口、全屏的保存或复制菜单 |
| `Mod+Print` | 录制菜单 |
| `Mod+Shift+Print`、`Mod+Delete` | 停止录制 |
| `Mod+ScrollLock` | 切换 screenkey 显示按键 |
| 音量键 | 使用 `wpctl` 静音或调节默认输出 |
| 媒体键 | 通过 `mpc` 控制 MPD，媒体键打开 Ncmpcpp |
| 麦克风静音键 | 通过 `wpctl` 切换默认输入静音 |

## 其他硬件键

| 按键 | 动作 |
| --- | --- |
| 浏览器键 | 打开 `$BROWSER`，当前为 Microsoft Edge |
| 计算器键 | 在终端打开 `bc -l` |
| 睡眠键 | 由 systemd-logind 或 elogind 唯一处理；`xss-lock` 在睡眠准备阶段启动 `slock` |
| 屏保键 | 锁屏、关闭 DPMS、暂停 MPD/MPV |
| 邮件键 | 打开 Neomutt |
| 我的电脑键 | 用 LF 打开根目录 |
| 亮度键 | `xbacklight` 增减 15。`xlight` 只是记住上次值的包装。没有标准背光设备时两者都无效 |
| `Mod+Ctrl+t` | 切换触控板。`xinput` 按设备名查找，翻转 `libinput Send Events Mode Enabled`。不用 `synclient`。`Mod+t` 仍是平铺布局 |
| 触摸板切换键、关闭键、开启键 | 与上一行相同的 `xinput` 动作。部分机器没有这三颗硬件键 |
