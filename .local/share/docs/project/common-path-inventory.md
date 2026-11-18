# 共用路径表

人工查表。未列出的路径或目录一律停，禁止 fail-open。不写检查脚本，不做长期自动巡检。

基线：master `aff82ac`、x11 `a6c4849`、wayland `2c92b78`。复现非文档差异：

```
git diff --name-only a6c4849 2c92b78 -- . ':(exclude).local/share/docs/**' ':(exclude)README.md'
```

这条命令只列出 `.config/ghostty/config.ghostty` 与 `.config/wal/templates/ghostty`。它们是唯一存在性分叉，只归 wayland。`categories` 与 `exclude` 命中为 0，待 categories 条目；只在 git 里不算已部署。

目录：`.local/lib/display/` 归 x11。`.local/lib/installation/` 归 common。`.local/bin/statusbar/` 和 `.local/bin/` 里没点名的脚本先补表，不默认 common。

三种分叉都查两侧。内容分叉是同路径 blob 不同。存在性分叉是只在一侧。假定分叉是 blob 仍相同，但写死 `dmenu`、`xclip`、`dwm`、`st` 或 `dwmblocks`。

| 路径 | 归属 | 依据 | 分叉处理 |
| --- | --- | --- | --- |
| `.gitconfig`；mpd；ncmpcpp；shell 的 aliasrc、inputrc、bm-dirs、bm-files；`tmux.conf.local`；lf 的 cleaner、icons、scope；`newsboat/urls` | common | 无显示栈命令。tmux 本地配置同时接受 xclip 与 wl-copy | 内容分叉才拆 |
| `.config/shell/profile` | 适配 | `LARBSWM=dwm`、`TERMINAL=st`、`STATUSBAR` 推出 dwmblocks、`dmenupass` | 假定分叉，不拆文件 |
| `.config/shell/zprofile` | 适配 | tty1 执行 `startx`；其余是登录环境 | 只拆 startx 段 |
| `.local/bin/getkeys`；通用键表 btmenu、calcurse、emacs、herdr、music、neomutt、newsboat、nsxiv、tmux、vim、zathura | 适配 | 引擎写死 `dwm`、`st`、`dmenu`。键表没有 dwm/st 文件 | 假定分叉在引擎；单表仍按 common |
| `sb-iplocate` | common | 采集，无 notify-send，无 X 命令 | 内容分叉才动 |
| sb-battery、sb-clock、sb-cpu、sb-cpubars、sb-disk、sb-mailbox、sb-memory、sb-moonphase、sb-music、sb-nettraf、sb-news、sb-pacpackages、sb-price、sb-tasks、sb-torrent、sb-volume | 适配 | 这 16 个调用 `notify-send`。dunst 换 mako 时行为会分叉 | 不能标 common |
| sb-bluetooth、sb-brightness、sb-doppler、sb-forecast2、sb-help-icon、sb-internet、sb-kbselect、sb-mpdup、sb-popupgrade | 适配 | 前 8 个也调用 notify-send，并有 dmenu、xbacklight、setxkbmap 或默认 dwmblocks。popupgrade 只默认 dwmblocks | 假定分叉 |
| `tmux.conf`、`lfrc`、`.zshrc`、`newsboat/config` | 适配 | `xclip`；newsboat 还有 dmenuhandler；zshrc 注释 st 小键盘 | 假定分叉 |
| passmenu、prompt、dmenumount、dmenumountcifs、dmenuumount、dmenuunicode、sysact、td-toggle、tutorialvids、suckless-rebuild、otp、rssget | x11 | 入口是 dmenu；部分还有 xclip、xdotool、dwm | 两侧仍同 blob；归属 x11 |
| `maimpick`、`setbg`、`samedir` | x11 | maim/xclip、xdotool/dwm、xprop | 同上 |
| `remaps`、`xlight` | x11 | setxkbmap、xset、xdotool；xbacklight | 同上 |
| `.local/bin/cron/newsup` | x11 | notify-send、xdotool、dwm | 同上 |
| `innogpu-restore-dp1-mode-x11` | x11 | 未跟踪；用 xrandr 恢复 eDP/DP | 不在 git，也没有 categories 条目 |
| `.config/x11/`、`.xinitrc`、`.xprofile`、`xdisplay`、`xdisplay.sh`、`displayselect` | x11 | X 启动、picom、xrandr、dmenu | 存在性应只留 x11 |
| `.config/ghostty/config.ghostty`、`.config/wal/templates/ghostty` | wayland | 唯一存在性分叉 | 待 categories 条目；不进 x11 |
