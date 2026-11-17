# Wayland 下替代 dwm 的桌面选型

本文面向维护者和 Agent，记录 R43 对 Wayland 平铺桌面方案的比较与替换清单。
状态：**开发中（部分完成，未合入）**。暂停说明：2026-11-10 用户决定；X11 主线继续使用 dwm，不替换。

## 结论

| 排序 | 方案 | 定位 |
| --- | --- | --- |
| 1 | **sway** | Wayland 日常主力，替换件最完整、风险最低 |
| 2 | **dwl** | 最接近 dwm 的 Wayland 直系替代，但需要自己补生态 |
| 3 | **niri** | 滚动式平铺，笔记本体验最好，但属于换工作流 |
| 4 | **Hyprland** | 功能/动画最强，但不适合极简首选 |

如果只做一个试点：**sway + waybar + fuzzel + foot + swaylock/swayidle**。
如果要保留 dwm 的窗口模型：**dwl**。
如果要现代滚动式体验：**niri**。

## 候选对比

| 维度 | sway | niri | dwl | Hyprland |
| --- | --- | --- | --- | --- |
| 布局 | i3 式树形/手动 | 滚动式横向列 | dwm 式动态 master-stack | dwindle/master 动态 |
| 配置 | 纯文本 | KDL | C 重编译 | 纯文本 |
| 成熟度 | 高 | 中 | 中低 | 高但变化快 |
| 内置栏 | swaybar，可不用 | 无 | 无 | 无 |
| XWayland | 内置 | `xwayland-satellite` | 可选启动 | 内置 |
| 多输出 | 强 | 强 | 基础 | 强 |
| 输入法 | fcitx5 Wayland | 同左 | 同左 | 同左 |
| 最像 dwm | 中 | 低 | **最高** | 低 |
| 学习成本 | 低 | 中高 | 中 | 中高 |
| 主要风险 | 不是 dwm 动态布局 | 工作流差异、较年轻 | DIY、生态弱 | 复杂、偏重 |

## 完整替换表

| 当前 X11 组件 | 作用 | sway | niri | dwl | Hyprland |
| --- | --- | --- | --- | --- | --- |
| `dwm` | 窗口管理 | `sway` | `niri` | `dwl` | `Hyprland` |
| `dwmblocks` + `sb-*` | 状态栏 | `waybar` 自定义模块 | `waybar` | `someblocks`/`somebar` 或 `waybar` | `waybar` |
| `dmenu` | 启动器 | `fuzzel`/`wofi` | `fuzzel` | `fuzzel`/`bemenu` | `fuzzel` |
| `st` | 终端 | `foot` | `foot` | `foot` | `foot` |
| `slock` + `xss-lock` | 锁屏/空闲 | `swaylock` + `swayidle` | `swaylock` + `swayidle`（需实测 ext-session-lock） | `swaylock` + `swayidle` | `hyprlock` + `hypridle` |
| `xinit`/`.xinitrc`/`startx` | 会话启动 | `uwsm`/`greetd`/`exec sway` | `niri-session`/`uwsm` | `exec dwl` | `Hyprland`/`uwsm` |
| `.xprofile` | 环境/自启 | `environment.d` + compositor autostart + systemd user | 同左 | 同左 | 同左 |
| `xdisplay`/`xrandr` | 显示布局 | `kanshi` + `wlr-randr` | niri `output` 配置 | `wlr-randr` | `monitor` 配置 |
| `picom` | 合成/阴影/动画 | 合成器内置 | 内置 | 内置 | 内置 |
| `setbg`/`feh`/`xwallpaper` | 壁纸 | `swaybg` | `swaybg`/`swww` | `swaybg` | `hyprpaper` |
| `maim`/`slop` | 截图 | `grim` + `slurp` + `satty` | 同左 | 同左 | 同左/`hyprshot` |
| `xclip`/`xsel` | 剪贴板 | `wl-clipboard` + `cliphist` | 同左 | 同左 | 同左 |
| `dunst` | 通知 | `mako` | `mako` | `mako` | `mako` |
| `fcitx5` | 输入法 | fcitx5 开 `wayland` USE | 同左 | 同左 | 同左 |
| `remaps`/`xcape` | 键位重映射 | compositor 绑定；Caps/Esc 用 `keyd` | 同左 | 同左 | 同左 |
| `xdotool` | 模拟按键/窗口操作 | `ydotool`/`wtype` + compositor IPC | 同左 | 同左 | 同左 |
| `xresources`/`xrdb` | X 资源/配色 | 原生 Wayland 不再使用；改 GTK/Qt/foot 配置 | 同左 | 同左 | 同左 |
| `unclutter` | 隐藏鼠标 | compositor 自带 | 同左 | 同左 | 同左 |
| `Synergy` | 跨机键鼠 | 需单独验证；可能用 Waynergy/Input Leap | 同左 | 同左 | 同左 |
| X11 专用程序 | 兼容 | XWayland | `xwayland-satellite` | XWayland | XWayland |

## Ghostty 试点（R43，2026-11-17 更新）

- 已安装 Ghostty 1.3.1（GTK4），作为 `st` 的 Wayland 替代；
- 配置只在 `task/R43-wayland-desktop` 的
  `~/.config/ghostty/config.ghostty`，不部署到 x11；
- 视觉对齐：
  - 字体 monospace，10.5pt（Xft.dpi 96 下约 14px）；
  - 80x24、2px padding、无窗口装饰；
  - 背景透明度 0.8，`alpha-blending = native`，不依赖 picom；
  - block 光标、Gruvbox/st 光标色。
- 颜色由 wal 生成，不写死在 Ghostty 配置：
  - 模板 `.config/wal/templates/ghostty`；
  - 生成 `~/.cache/wal/ghostty`；
  - Ghostty 用 `config-file = ?../../.cache/wal/ghostty` 引入；
  - 换壁纸后运行 `wal -i <wallpaper>`。
- 鼠标：
  - 左键选择即复制，`copy-on-select = clipboard`（primary + system）；
  - 右键 `right-click-action = paste`，不弹菜单；
  - `Alt+C`/`Alt+V` 保留，普通 `Ctrl+C` 仍是 SIGINT。
- 滚屏：
  - `Alt+L` 上翻一页；
  - `Alt+Shift+L` 下翻一页；
  - zsh 的 vi-mode 也可能把 Alt+L 的 ESC 序列当成命令模式，当前接受这个副作用。
- 输入法：
  - Ghostty 是 GTK4，需要 `app-i18n/fcitx-gtk` 的 `gtk4` USE；
  - 当前只有 gtk3 immodule，所以 Ghostty 无法接 fcitx；
  - 这只是 X11 GTK4 前端问题，不是 Ghostty 没编 Wayland；
  - Wayland 会话仍需 fcitx5 的 `wayland` USE 前端，另行处理。
- `tab-width` 在 1.3.1 不是可配置项，只能实测。

## 关键说明

### `dwmblocks` 不能保留

它写 X11 root window 的 `WM_NAME`，Wayland 下没有对应语义。必须换：

- 通用：`waybar`；
- dwl 极简：`someblocks` + `somebar`；
- 现有 `sb-*` 脚本可包装成 custom module。

### `dmenu` 与 `st`

- 推荐 `fuzzel` + `foot`；
- `dmenu`/`st` 可以继续在 XWayland 下运行，但不是原生；
- 过渡期可保留，最终建议换原生。

### 锁屏与 idle

- sway/dwl/niri：`swaylock` + `swayidle`；
- Hyprland：`hyprlock` + `hypridle`；
- `xss-lock` 不再需要；
- niri 的 ext-session-lock 兼容性必须实测。

### 启动链

当前：

```
.zprofile → startx → .xinitrc → xprofile → dwm
```

Wayland：

```
tty/greetd → uwsm 或 compositor session
  → systemd user units
  → compositor
  → waybar/mako/fcitx5/kanshi/swayidle
```

`.xinitrc`、`.xprofile` 的 X11 部分拆成：

- `~/.config/environment.d/`：环境变量；
- compositor 配置：键位、输出、自启；
- `systemd --user`：输入法、通知、状态栏等。

### 显示布局

`xdisplay` 不能直接复用：

- sway/dwl：`kanshi` + `wlr-randr`；
- niri：`output` 配置；
- Hyprland：`monitor` 配置；
- 内外屏自动切换逻辑需要重写成 Wayland output watcher。

## 硬件与前置条件

- FH2M 的 EGL/GBM/KMS 已用 `weston --backend=drm` 验证；
- Vulkan 原生 Wayland 表面不支持，Vulkan 程序需 XWayland/X11 表面；
- fcitx5 5.1.21 已有，但未开 `wayland` USE，Wayland 前端仍缺失；
- `st`、`dmenu` 是 X11 程序，过渡期依赖 XWayland；
- niri 的 XWayland 需要 `xwayland-satellite`，不是内置。

## 推荐试点顺序

1. `sway` + waybar + fuzzel + foot；
2. 补 swaylock/swayidle、grim/slurp、wl-clipboard、mako；
3. 用 kanshi 接替 xdisplay 的基本布局；
4. 再试 `dwl`（dwm 原教旨）或 `niri`（滚动式）；
5. 最后才考虑 Hyprland。

## 关系

- X11 主线继续用 dwm，不换；
- Wayland 迁移实施归 R42；本文只做选型；
- 当前任务挂起，恢复前不改配置、不装包、不切换会话。
