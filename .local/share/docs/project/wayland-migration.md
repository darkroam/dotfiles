# Wayland 迁移研究

本文面向维护者和 Agent，记录 R42 的迁移边界、已证硬件能力和未决问题。
状态：**挂起**（2026-11-06 用户决定）；尚未改变任何运行配置，也未选定替代桌面。

## 目标

把 dotfiles 的桌面会话从 X11 迁到 Wayland，包括：

- 窗口管理 / 合成器；
- 状态栏、启动器、终端；
- 显示布局、输入法、截图、剪贴板、锁屏、idle、壁纸；
- 启动链、systemd user units、dotfiles categories；
- XWayland 过渡与回滚。

X11 不是立即删除：先证明 Wayland 可用，再逐项替换，最后决定是否移除 Xorg。

## 分支与冻结基线

| 项目 | 值 |
| --- | --- |
| 最后 X11 基线 | `00fd8f5` |
| 附注标签 | `x11-final`（标签对象 `1f7d1ab`，指向 `00fd8f5`） |
| 长期分支 | `x11`、`wayland`，均从 `00fd8f5` 起 |
| 主线 | `master`，当前仍是 X11 |
| 分支远端 | `x11`、`wayland` 尚未 push |

合并 wayland 到主线前保留 `x11-final`；之后 X11 维护走 `x11` 分支。
R40 离线包只打 `origin/master`，不会自动包含 `wayland` 分支；恢复 R42 前要先决定
分支同步或离线包 ref 策略。

## 硬件与驱动实测

环境：Gentoo，内核 `6.12.115-gentoo`，fh2m 驱动 `2.19.50278583`
（DDK 23.3，模块 srcversion `227E896A`），PCI `1ec8:9810`。

| 能力 | 结论 | 证据 |
| --- | --- | --- |
| Wayland 合成器（EGL/GBM/KMS） | 可用 | `weston --backend=drm` 实际启动并渲染 |
| Wayland 客户端 GL/GLES | 可用 | `eglinfo -p wayland` 正常，Fantasy II-M，OpenGL 4.3 / GLES 3.2 |
| 双输出 | 可用 | eDP-1 2560x1600、DP-1 1920x1080 |
| 缓冲协商 | 可用 | `wl_drm` v2、`zwp_linux_dmabuf_v1` v5，LINEAR 与非线性 modifier |
| 退出恢复 | 正常 | 回原 X 会话，无 Oops，模块身份不变 |
| Vulkan Wayland 表面 | 不支持 | 运行时无 `VK_KHR_wayland_surface`；WSI 库有字符串但 ICD 未暴露 |

结论：原生 Wayland 合成器和 GL 客户端路线有实际基础；Vulkan 程序不能创建原生
Wayland 表面，需要 XWayland/X11 表面或接受限制。

注意：weston 成功只证明 DRM/EGL/GBM 链路，不等于 dwl/sway 等 wlroots 合成器、
输入法、XWayland、截图/剪贴板已完成验收。

## 已确认的环境前提

- 厂商 `libgbm` 通过 `/etc/ld.so.conf.d/0-fantgpu-hwgl.conf` 排在 Mesa 之前；
  “使用厂商 GBM”是默认，不是可选项。
- glvnd 链：`00_fh2m.json → libEGL_fh2m.so.1 → libEGL_fh2m_l.so → libft_mesa_wsi.so`；
  不能把前两级当成直接加载 `_l`。
- X 会话持有 `card0`；非夺 master 的 render-node 探测可作为低风险预检。
- sysfs 驱动名是 `fant-drv`，脚本不能按 `fantgpu` 匹配。
- `#Option "Atomic" "false"` 和 `#Option "TearFree" "False"` 都是注释；
  PageFlip 关闭是 TearFree 的 X 侧连带，不代表内核没有 page flip。
- Vulkan 限制是当前驱动事实，不应在应用层假装支持。

## 输入法

- 本机有 fcitx5 `5.1.21`，`.xprofile` 已优先启动 fcitx5；
- 当前没有开 `wayland` USE，`fcitx5-diagnose` 只有 DBus/Fcitx4/IBus/XIM 前端；
- `/usr/lib64/fcitx5` 未见 Wayland 前端模块；
- 因此输入法仍是阻塞项：需要核对 ebuild IUSE、按包开 `wayland` USE、
  重建前端，再在真实 Wayland 会话验证。

不要先全局开 `wayland` USE；应使用包级 `package.use`。

## Vulkan 限制

- 原生 Wayland Vulkan 应用无法创建 surface；
- 可通过 XWayland/X11 表面运行的程序不受同一限制；
- 恢复 R42 后需要列出受影响应用，并决定 XWayland 保留范围；
- 不把“XWayland 能跑”写成“X11 已移除”。

## 候选工具（未定）

以下只是调研范围，不是决定：

- 合成器：dwl、sway、labwc、river、wayfire、hyprland、niri；
- 状态栏：waybar、somebar/someblocks、sfwbar、ags/quickshell；
- 启动器：fuzzel、wofi、rofi-wayland、bemenu、tofi；
- 终端：foot、alacritty、kitty、wezterm、ghostty；
- 其他：grim/slurp、wl-clipboard、swaylock、swayidle、kanshi、mako。

初步树核对：dwl/sway/labwc/waybar/bemenu/foot/kitty/alacritty/grim/slurp/
wl-clipboard/swaylock/swayidle/kanshi/mako/xwayland 可用；somebar/fuzzel/tofi/
hyprland/niri/river、keyd 不在当前 Portage 树。

选择标准：与 suckless 风格匹配、资源占用、wlroots 兼容、Gentoo 可用性、
输入法/XWayland/双输出支持、维护活跃度；GPU 和输入法未过之前不做最终推荐。

## 迁移阶段（研究稿）

1. **可行性**：完成 GPU 能力、输入法前端、compositor 冷启动；
2. **并行验证**：在 `wayland` 分支上验证双输出、XWayland、输入法、截图、剪贴板；
3. **工具替换**：逐项选择并验证，保留 X11 回退；
4. **dotfiles 迭代**：categories、启动链、systemd user units、安装测试；
5. **切换**：Wayland 成为默认会话，XWayland 过渡；
6. **收口**：合并前确认 `x11-final`、`x11` 分支、离线包和回滚路径。

## 未决问题

- fcitx5 的 `wayland` USE 前端是否足够，是否需要额外插件；
- 哪个 wlroots 合成器在 FH2M 上稳定，实际 ATOMIC/page flip 表现；
- XWayland 下 Vulkan/输入法/截图是否满足日常；
- `x11`/`wayland` 分支如何同步与打包；
- X11 专属工具（xdisplay、picom、xrandr、xinput、xresources、xinit、
  xprofile、xcape、xdotool、xclip、maim/slop、xss-lock 等）的逐项替代；
- 是否最终移除 Xorg，还是长期保留 XWayland/X11 回退。

## 相关文档

- [显示管理设计](display-management.md)
- [显示设备适配器指引](display-device-adapter.md)
- [依赖清单](dependencies.md)
- [安装系统](installation-system.md)
- [KaiTian X7h G1e + Gentoo 平台档案](../platforms/kaitian-x7h-g1e-gentoo.md)
- [Wayland 桌面替代选型](wayland-desktop-alternatives.md)
