# X11 依赖

> 服务域：U02；U06 的 X11 行

公共依赖仍在 `.local/share/docs/project/dependencies.md`。本文只收 U02 整节和 U06 的 X11 行。

## U02 · X11 桌面与输入

| 软件或命令 | 用途 |
| --- | --- |
| Xorg/Xinit, `dbus-launch`, `dbus-update-activation-environment` | X11 会话启动 |
| `dwm`, `dwmblocks`, `st`, `dmenu` | 窗口管理器、状态栏、终端和启动器；从 `~/src/` 单独构建 |
| C99 编译器、`make`、`pkg-config` | 构建四个独立桌面源码仓库 |
| `suckless-rebuild` | 仓库命令。比较产物 SHA 后按需 `sudo make install`。不自动安装发行版包 |
| X11、Xft、Xrender、Xinerama、Fontconfig、FreeType、HarfBuzz 开发头文件和库 | DWM、DWMBlocks、dmenu 与 st 的编译、字体和渲染能力 |
| X11-XCB、XCB、XCB Res 开发头文件和库 | 当前 DWM 补丁使用的进程/窗口资源能力 |
| `tic` | 安装 st 的 terminfo 条目 |
| kbd（`loadkeys`） | 按需手动加载已跟踪的 TTY 键盘映射；登录 Shell 不执行提权命令 |
| `fbterm` | 使用已跟踪 `.fbtermrc` 时的可选 framebuffer 终端；平台需要的 redraw 兼容二进制由对应驱动项目维护，系统包可作为回退 |
| `slock` | 系统安装的 X11 锁屏程序；不属于仓库约定的四个 `~/src/` 源码目录 |
| `dunst`, `picom`, `unclutter`, `xwallpaper` | 通知、合成器、鼠标隐藏和壁纸 |
| `xrdb`, `xrandr`, `xset`, `xdotool`, `xdpyinfo`, `xclip`, `xprop`, `setxkbmap` | Xresources、显示、输入、剪贴板和辅助脚本 |
| `xkblayout-state` | 可选键盘布局状态命令；上游来源：<https://github.com/nonpop/xkblayout-state>。缺失时 `sb-kbselect` 回退到 `setxkbmap`。 |
| `notify-send` (libnotify) | 桌面通知 |
| `fcitx5` | 首选已配置输入法；`fcitx` 或 `ibus` 为回退；GTK4 程序（如 Ghostty）需要 `app-i18n/fcitx-gtk` 的 `gtk4` USE |
| `xcape` | 启用时将 Caps 作为 Escape/修饰键重映射 |
| `microsoft-edge` | 当前 `BROWSER` 的值 |

## U06 · 显示与锁屏

| 软件或命令 | 用途 |
| --- | --- |
| `xrandr`, `flock` | `xdisplay` 与 `displayselect` 的基础显示布局和互斥；`xdisplay.sh` 是兼容包装；缺少任一命令时拒绝运行 |
| `dmenu`, `bc` | `displayselect` 的选择界面和双屏镜像缩放计算 |
| `arandr` | `displayselect` 的可选手动显示布局界面；选中该路径但缺少命令时提示安装 |
| `dunst`, `xwallpaper` | 手动显示布局后的可选通知与壁纸刷新；不属于自动 watcher 的基础依赖 |
| `cvt` | 仅在非标准面板确需自定义 modeline 时使用的可选设备适配开发工具 |
| `flock`、`xss-lock`、`slock` | 按登录会话和 X server 保证单实例；`xss-lock` 在 login1 睡眠准备阶段启动 `slock`，不接管 XScreenSaver 空闲超时 |
| `xinput` | DWM 触控板开关（`Mod+Ctrl+t` 和触摸板硬件键）。按设备名查找后设置 `libinput Send Events Mode Enabled`。不再使用 `synclient` 或 Synaptics 驱动 |
| `screenkey` | 为单独构建 DWM 绑定保留的可选按键覆盖层；无已跟踪 dotfiles 运行调用 |
