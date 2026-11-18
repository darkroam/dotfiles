# 共用路径表

人工归属表。分叉时查本表，不写检查脚本，也不做长期自动巡检。

三种分叉都查两侧，不只查 wayland：

1. 内容分叉：同一路径 blob 不同。
2. 存在性分叉：路径只在一侧。实例是 Ghostty 两路径。
3. 假定分叉：blob 仍相同，但写死 `dmenu`、`xclip`、`dwm`、`st` 或 `dwmblocks`。

2026-11-18：x11 与 wayland 的非文档 diff 为 0。下表已跟踪路径两侧 blob 相同，内容分叉为 0。假定分叉因此仍在两侧。Ghostty 只归 wayland。

| 路径 | 归属 | 依据 | 分叉处理 |
| --- | --- | --- | --- |
| `.gitconfig` | common | 无显示栈命令 | 只在内容分叉时改这一份 |
| `.config/mpd/mpd.conf` | common | 播放守护，不引用显示栈 | 同上 |
| `.config/ncmpcpp/bindings`、`config` | common | 客户端配置，无 X 工具 | 同上 |
| `.config/shell/aliasrc`、`inputrc`、`bm-dirs`、`bm-files` | common | 别名、readline、书签 | 同上 |
| `.config/shell/profile` | 适配 | `LARBSWM=dwm`、`TERMINAL=st`、`STATUSBAR` 推出 dwmblocks、`dmenupass` | 假定分叉；两侧仍同 blob，触发时改默认，不拆文件 |
| `.config/shell/zprofile` | 适配 | tty1 执行 `startx`，并可写 xorg 配置；其余是登录环境 | 触发时只拆 startx 段；当前两侧都有 |
| `.config/tmux/tmux.conf.local` | common | 复制注释同时接受 xclip 与 wl-copy | 内容分叉才动 |
| `.config/lf/cleaner`、`icons`、`scope` | common | 预览与清理，不绑剪贴板 | 同上 |
| `.config/newsboat/urls` | common | 订阅列表 | 同上 |
| `.local/bin/getkeys` | 适配 | 查表引擎通用；写死 `dwm`、`st`、`dmenu` | 假定分叉在同一文件；通用表仍按 common |
| `.local/share/larbs/getkeys/` 的 btmenu、calcurse、emacs、herdr、music、neomutt、newsboat、nsxiv、tmux、vim、zathura | common | 没有 dwm/st 键表文件 | 单表内容分叉再改 |
| `.local/bin/statusbar/` 的 sb-clock、sb-cpu、sb-disk、sb-iplocate、sb-mailbox、sb-music、sb-nettraf、sb-news、sb-tasks、sb-torrent、sb-volume、sb-battery、sb-cpubars、sb-memory、sb-moonphase、sb-pacpackages、sb-price | common | 采集，无 dmenu/xclip/dwm/xrandr | 两侧同 blob |
| `sb-forecast2`、`sb-mpdup`、`sb-popupgrade` | 适配 | 刷新默认 `${STATUSBAR:-dwmblocks}` | 假定分叉 |
| `sb-internet` | 适配 | 点击后写死 `pkill dwmblocks` | 假定分叉 |
| `sb-doppler` | 适配 | 雷达选择调用 `dmenu` | 假定分叉 |
| `.config/tmux/tmux.conf` | 适配 | 复制绑定 `xclip` | 假定分叉 |
| `.config/lf/lfrc` | 适配 | 复制绑定 `xclip` | 假定分叉 |
| `.config/zsh/.zshrc` | 适配 | `xclip -o`；注释写明 st 小键盘序列 | 假定分叉 |
| `.config/newsboat/config` | 适配 | 宏调用 dmenuhandler 与 `xclip` | 假定分叉 |
| `sb-kbselect` | 适配 | `setxkbmap`、`dmenu`、默认 dwmblocks | 假定分叉 |
| `sb-brightness` | 适配 | 亮度键走 `xbacklight`，注释绑定 dwm | 假定分叉 |
| `sb-bluetooth` | 适配 | `btmenu` 后刷新默认 dwmblocks | 假定分叉 |
| `sb-help-icon` | 适配 | `pidof dwm` 才读 dwm 帮助并重载 | 假定分叉 |
| `.config/x11/` | x11 | xinitrc、xprofile、xresources、picom、显示布局 | 存在性分叉，只留 x11 |
| `.xinitrc`、`.xprofile` | x11 | 指向 `.config/x11/xinitrc` 与 `xprofile` | 存在性分叉 |
| `.local/bin/xdisplay`、`xdisplay.sh` | x11 | 要求 `xrandr` | 存在性分叉 |
| `.local/bin/displayselect` | x11 | `dmenu` 加 `xrandr` | 存在性；命令也是假定分叉 |
| getkeys 的 dwm/st 名单 | x11 | 引擎写死这两个名字；对应键表文件不存在 | 假定分叉；不要在 wayland 补空表 |
| `.config/ghostty/config.ghostty` | wayland | R43 的 Ghostty 配置 | 存在性分叉，不进 x11 |
| `.config/wal/templates/ghostty` | wayland | wal 的 Ghostty 颜色模板 | 存在性分叉，不进 x11 |

触发时人工对上表。common 只在内容真的分叉后才决定是否拆开。适配项先改写死的命令，不因为两侧还相同就当成已经安全。
