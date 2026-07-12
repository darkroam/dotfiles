# 依赖与文档审计记录

审计范围：当前 Debian 系统。其他发行版分支仅做语法检查。

状态：第一阶段进行中。发现缺失依赖时，仅暂停对应项目；不得以未验证的替代项
自动改写配置。

## 第一批：根目录兼容入口与 FbTerm 配置

| 来源文件 | 依赖 | 要求级别 | 安装状态 | dependencies layout | `progs.csv` 状态 | 处理结果 |
| --- | --- | --- | --- | --- | --- | --- |
| `.profile`、`.zprofile`、`.xinitrc`、`.xprofile`、`.asoundrc`、`.gtkrc-2.0` | 无；均为指向规范配置的兼容链接 | 不适用 | 不适用 | 不适用 | 不适用 | 通过；目标文件将在所属批次审计 |
| `.gitignore` | 无 | 不适用 | 不适用 | 不适用 | 不适用 | 通过 |
| `.bashrc` | `bash`、`stty`、`tput`、`git`、Bash/Git completion、`fzf`、`groff` | 必需或条件可选 | 已安装；补全文件可读；`~/.fzf.bash` 缺失但已有条件加载 | Shell、源代码管理与开发 | 待核对 | 已验证，`bash -n` 通过 |
| `.gitconfig` | `git`、`vim`、`less` | 必需 | 已安装；`git`、`less` 由 Debian 软件包提供，`vim` 可执行 | Shell、源代码管理与开发 | 待核对 | 已验证，待 `progs.csv` 全量迁移时核对说明 |
| `.npmrc` | `npm` | 必需（使用 npm 时） | 已安装；当前由 NVM 提供，非 APT 软件包 | Shell、源代码管理与开发 | 待核对 | 已验证，待 `progs.csv` 全量迁移时核对说明 |
| `.config/shell/profile` | `find`、`nvim`、`st`、`microsoft-edge`、`zathura`、`lfub`、`dwm`、`dwmblocks`、`highlight`、`shortcuts`、`dmenupass`、Qt GTK 平台主题 | 必需或已启用默认功能 | 已安装；Qt5/Qt6 GTK 平台主题由 `qt5-gtk-platformtheme`、`qt6-gtk-platformtheme` 提供 | Shell、源代码管理与开发；X11 桌面与输入；文件、文档与桌面处理 | 待核对 | 已验证，`sh -n` 通过 |
| `.config/shell/aliasrc` | `bc` | 已启用计算器及显示选择功能 | 已安装，Debian 软件包 `bc` | 显示、网络、挂载与系统控制 | 待核对 | 已验证 |
| `.config/shell/aliasrc` | `transmission-remote` | 可选种子控制别名 | 已安装，Debian 软件包 `transmission-cli` | 下载、种子与文本浏览 | 待核对 | 已验证；守护进程与 `tremc` 将在种子脚本批次审计 |
| `.config/shell/aliasrc`、`.config/newsboat/config` | `youtube-viewer` | 最低优先级可选视频别名及 Newsboat 宏 | 不检查安装状态 | 状态栏、RSS、邮件、天气与任务队列 | 待核对 | 代码完备性已验证：仅由可选 Newsboat 视频宏和别名调用；常规流程已有浏览器、`mpv`、`yt-dlp` 与 `linkhandler`，本轮不安装或运行验证 |
| `.config/shell/aliasrc` | `calcurse` | 可选日历别名和状态栏操作 | 已安装，Debian 软件包 `calcurse` | 状态栏、RSS、邮件、天气与任务队列 | 待核对 | 已验证 |
| 图像查看链路（`.config/shell/aliasrc`、LF、桌面条目与处理脚本） | `nsxiv` | 已批准整体替换当前 `sxiv` 图像查看链路 | 已安装，Debian 软件包 `nsxiv` | 文件、文档与桌面处理 | `sxiv` 行待第二阶段迁移 | 已迁移配置目录、调用点、桌面条目、帮助文本和项目文档；待 X11 图形流程复查 |
| `.config/shell/aliasrc` | `lazygit` | 可选 Git TUI 别名 | 已安装，Debian 软件包 `lazygit` | Shell、源代码管理与开发 | 不存在 | 已验证；后续需补入 `dependencies.md` |
| `.config/shell/aliasrc` | 本地 `cc-switch` 包装 | 可选自定义别名 | 已安装于 `~/.local/bin/cc-switch` | Shell、源代码管理与开发 | 不存在 | 已验证；非外部软件包 |
| `.config/shell/aliasrc` | APT 分支 | 当前 Debian 包管理 | 已安装 | Shell、源代码管理与开发 | 待核对 | 已验证，`sh -n` 通过；pacman、XBPS、Portage 分支留作语法检查 |
| `.fbtermrc` | `fbterm` | 必需（使用 FbTerm 时） | 已安装，Debian 软件包 `fbterm` | 外观、字体与壁纸 | 不存在 | 已验证 |
| `.fbtermrc` | Hack、Fira Code、JetBrains Mono、Noto Sans Mono CJK SC、Sarasa Mono SC、Noto Sans CJK SC | 回退字体链 | 已安装并可被 Fontconfig 解析；Noto Sans Mono CJK SC 由 Debian `fonts-noto-cjk` 提供 | 外观、字体与壁纸 | 待核对 | 已验证；以仓库既有等宽中文字体替换缺失的 Maple Mono CN |
| `.tmux.conf`、`.tmux.conf.local` | `tmux` | 必需（使用 Tmux 时） | 已安装，Debian 软件包 `tmux` | Shell、源代码管理与开发 | 待核对 | 命令已验证；当前沙箱禁止 Tmux Unix 套接字操作，运行加载需在正常用户会话复查 |
| `.tmux.conf` | `urlview` | 可选 URL 选择绑定 | 已安装，Debian 软件包 `urlview` | 下载、种子与文本浏览 | 待核对 | 已验证 |
| `.tmux.conf` | Facebook PathPicker `fpp` | 最低优先级可选路径选择绑定 | 不检查安装状态 | 下载、种子与文本浏览 | 待核对 | 代码完备性已验证：绑定调用 `_fpp`，helper 对 `fpp` 使用 `|| true`；本轮不安装或运行验证 |
| `.tmux.conf` | `xclip`、`xsel` | X11 剪贴板绑定 | `xclip` 已安装；`xsel` 缺失，但配置会在无 `xsel` 时回退到 `xclip` | Shell、源代码管理与开发 | 待核对 | 已验证；不要求安装 `xsel` |
