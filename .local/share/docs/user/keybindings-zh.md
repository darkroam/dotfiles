# 快捷键摘要

以下以当前 `~/src/dwm/config.h` 为准。`Mod` 是 Super/Windows 键；大写字母表示
同时按 Shift。依赖缺失时，快捷键会启动失败而不会自动安装程序。

## 窗口、布局与标签

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
| `Mod+f` / `Mod+Shift+f` | 切换全屏 / 浮动布局 |
| `Mod+t` / `Mod+Shift+t` | 平铺 / 底部栈布局 |
| `Mod+y` / `Mod+Shift+y` | 螺旋 / 递减布局 |
| `Mod+u` / `Mod+Shift+u` | Deck / Monocle 布局 |
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

## 状态栏鼠标操作

| 操作 | 动作 |
| --- | --- |
| 左键、中键、右键或滚轮 | 把对应点击信号交给当前状态模块；具体动作由模块定义 |
| `Shift+左键` | 把第六种点击信号交给当前状态模块 |
| `Shift+右键` | 在 Nvim 中打开 `~/src/dwmblocks/config.h` |

## 启动器与常用程序

| 快捷键 | 动作 |
| --- | --- |
| `Mod+d` / `Mod+Shift+d` | dmenu / 已跟踪的 `passmenu` 密码库菜单；后者默认复制所选密码 |
| `Mod+\`` | Unicode/Emoji 菜单 |
| `Mod+w` / `Mod+Shift+w` | 浏览器（Microsoft Edge）/ Nmtui |
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
| `Print` / `Shift+Print` | 全屏截图 / 选区截图 |
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
| 睡眠键 | 执行 `sudo -A zzz`；这是需由目标平台提供或替换的旧绑定 |
| 屏保键 | 锁屏、关闭 DPMS、暂停 MPD/MPV |
| 邮件键 | 打开 Neomutt |
| 我的电脑键 | 用 LF 打开根目录 |
| 亮度键 | `xbacklight` 增减 15；需安装且硬件支持 |
| 触摸板键 | 使用 `synclient` 切换；仅适用于支持它的 X11 触摸板 |
