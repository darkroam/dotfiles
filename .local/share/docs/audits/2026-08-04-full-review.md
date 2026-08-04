# 配置全量审计修改计划

- **日期：** 2026-08-04
- **范围：** 全库逐文件审查（140 个跟踪文件）
- **方法：** 按修复类型（安全/功能/质量）分批，每项含影响分析
- **状态：** 已完成（64/64）

## 工作流程

遵循[维护策略规定的工作流规则](../project/maintenance-policy.md#工作流)。

每一项编号（S01、F01、Q01 等）为一个独立任务，必须单独走完整流程：
提出方案 → 用户确认 → 执行 → review → 用户确认 → 下一项。
不得将多个任务合并处理。会话因上下文压缩恢复后，必须先阅读
[维护策略](../project/maintenance-policy.md)确认约束和工作流，再对照本文件的
执行进度表确认当前状态。

---

## 第一批：安全漏洞 + 语法/运行时错误（18 项）

### S01 — `rssget:117` 缺少 `]`，语法错误
- **文件：** `.local/bin/rssget`
- **现状：** `if [ "$(printf '%s\n' "$candidates" | wc -l)" -eq 1; then` 缺少闭合 `]`
- **影响：** 脚本在找到候选 feed 时永远失败
- **修复：** 补 `]`：`-eq 1 ]; then`
- **状态：** [x] 已修复

### S02 — `rssadd:34` URL 正则缺量词
- **文件：** `.local/bin/rssadd`
- **现状：** `grep -o "https?://[^\" ]"` 只匹配 1 个字符，URL 被截断
- **影响：** feed 自动发现功能完全失效
- **修复：** 改为 `grep -oE 'https?://[^" ]*'`（ERE 标准语法，跨平台通用）
- **状态：** [x] 已修复

### S03 — `dmenuunicode:16` printf 格式串漏洞
- **文件：** `.local/bin/dmenuunicode`
- **现状：** `printf "$chosen" | xclip`，`$chosen` 含 `%` 时被解释为格式符
- **影响：** 选到含 `%` 的 Unicode 字符时剪贴板内容错误
- **修复：** 改为 `printf '%s' "$chosen" | xclip`
- **状态：** [x] 已修复

### S04 — `getkeys:3` 路径遍历
- **文件：** `.local/bin/getkeys`
- **现状：** `cat .../getkeys/"$1"` 未校验 `$1`，`../../../etc/passwd` 可读取任意文件
- **影响：** 任意文件读取
- **修复：** 在 cat 之前添加 case 语句，拒绝含 `/`、`..` 或以 `.` 开头的参数
- **状态：** [x] 已修复

### S05 — `shortcuts:23,35` eval 注入
- **文件：** `.local/bin/shortcuts`
- **现状：** `eval "echo \"$(cat "$bmdirs")\""` 执行书签文件内容
- **影响：** 书签文件含 `$(cmd)` 或反引号时执行任意命令
- **修复：** 保持现状，在脚本中添加注释记录 eval 注入风险及接受理由
- **状态：** [x] 已处理（接受风险 + 文档记录）

### S06 — `booksplit:27-46` eval 注入
- **文件：** `.local/bin/booksplit`
- **现状：** ffmpeg 命令拼成字符串后 `eval "$cmd"` 执行，用户输入含特殊字符时注入
- **影响：** 输入书名含 `$(cmd)` 时执行任意命令
- **修复：** 使用位置参数（set -- 和 "$@"）替代字符串拼接和 eval，消除命令注入风险
- **状态：** [x] 已修复

### S07 — `compiler:156` R 代码注入
- **文件：** `.local/bin/compiler`
- **现状：** `Rscript -e "rmarkdown::render('$file', quiet=TRUE)"`，文件名含 `'` 时注入
- **影响：** 文件名含单引号可执行任意 R 代码
- **修复：** 改为 `Rscript -e 'args <- commandArgs(trailingOnly=TRUE); rmarkdown::render(args[1], quiet=TRUE)' -- "$file"`
- **状态：** [x] 已修复

### S08 — `compiler:162` shebang 处理器逻辑错误
- **文件：** `.local/bin/compiler`
- **现状：** `sed ... | xargs -r -I % "$file"` 将 `$file` 当作解释器执行，而非用解释器运行 `$file`
- **影响：** shebang 检测分支永远直接执行文件，忽略解释器
- **修复：** 改为 `xargs -r -I % % "$file"`
- **状态：** [x] 已修复

### S09 — `slider:12,70` 未声明选项 + 未初始化变量
- **文件：** `.local/bin/slider`
- **现状：** getopts 字符串缺 `s:`，`-s` 选项不可达；`$seconds` 在使用前未赋值
- **影响：** `-s` 永远触发 usage；endtime 计算不含起始偏移
- **修复：** getopts 加 `s:`；在循环前初始化 `seconds=0`
- **状态：** [x] 已修复

### S10 — `aliasrc:233` pacman 空参数
- **文件：** `.config/shell/aliasrc`
- **现状：** `pc='sudo pacman -Rns $(pacman -Qtdq)'`，无孤儿包时 `pacman -Qtdq` 为空
- **影响：** `pacman -Rns` 无目标报错
- **修复：** 改为 `pc='pacman -Qtdq | xargs -r sudo pacman -Rns'`，`xargs -r` 在输入为空时不执行命令
- **状态：** [x] 已修复

### S11 — `sb-price:50` printf 格式串注入
- **文件：** `.local/bin/statusbar/sb-price`
- **现状：** `printf "$3$symb%0.2f$after"` 将变量注入格式串
- **影响：** `$3` 含 `%` 时 printf 行为未定义
- **修复：** 改为 `printf '%s%s%0.2f\n' "$3" "$symb" "$(cat "$pricefile")"`
- **状态：** [x] 已修复

### S12 — `sb-help-icon:6-9` 条件逻辑损坏
- **文件：** `.local/bin/statusbar/sb-help-icon`
- **现状：** `pidof dwm && READMEFILE=... restartwm() {...} || restartwm() {...}` 逻辑链错误
- **影响：** i3 回退分支永远不执行（已清理 i3 后此问题影响降低）
- **修复：** 改为 `if pidof dwm; then ... else ... fi` 结构
- **状态：** [x] 已修复

### S13 — `sb-doppler:270` 文件不存在时算术错误
- **文件：** `.local/bin/statusbar/sb-doppler`
- **现状：** `[ $(($(date '+%s') - $(stat -c %Y "$doppler"))) -gt "$secs" ]`，文件不存在时 stat 失败
- **影响：** 首次点击时脚本崩溃
- **修复：** 加 `[ -f "$doppler" ]` 前置检查
- **状态：** [x] 已修复

### S14 — `lf/lfrc:77,88` eval 注入
- **文件：** `.config/lf/lfrc`
- **现状：** `eval mv/cp` 处理含特殊字符的文件名
- **影响：** 文件名含 `;`、`|`、`$()` 时执行任意命令
- **修复：** 移除 eval，直接使用 `mv -iv "$x" "$dest"` 和 `cp -ivr "$x" "$dest"`
- **状态：** [x] 已修复

### S15 — `picom.conf:8,12` 废弃选项
- **文件：** `.config/x11/picom.conf`
- **现状：** `dbe = false` 已从 picom v10+ 移除；`glx-copy-from-front` 已废弃
- **影响：** picom 启动报错或警告
- **修复：** 删除这两行
- **状态：** [x] 已修复

### S16 — `.gitconfig:51` 危险别名
- **文件：** `.gitconfig`
- **现状：** `rm-remotes-but-master` 强制推送删除远程分支，正则 `/\/[^mH]/` 可误匹配
- **影响：** 单次误操作可销毁远程历史
- **修复：** 删除该别名
- **状态：** [x] 已修复

### S17 — `user-dirs.dirs:8` 桌面指向主目录
- **文件：** `.config/user-dirs.dirs`
- **现状：** `XDG_DESKTOP_DIR="$HOME/"`
- **影响：** 桌面即主目录，文件散落各处
- **说明：** 与 voidrice（Luke Smith 的配置）一致，确认为有意设置。Luke Smith 的设计哲学是不使用独立的桌面目录，保持文件管理简化。保持现状。
- **状态：** [x] 已确认（有意设置，与 voidrice 一致）

### S18 — GOPATH 跨 shell 不一致
- **文件：** `.config/shell/profile:62` vs `.config/zsh/.zshrc:15`
- **现状：** profile 设 `~/.local/share/go`，zshrc 覆盖为 `~/Project/go`
- **影响：** bash 和 zsh 下 Go 工具使用不同目录
- **修复：** 删除 zshrc 中的覆盖，统一使用 profile 的 XDG 规范设置
- **状态：** [x] 已修复

---

## 第二批：功能修复（26 项）

### F01 — `pdf.desktop` 缺少 MimeType
- **文件：** `.local/share/applications/pdf.desktop`
- **现状：** 无 MimeType
- **影响：** PDF 文件无法通过桌面关联打开
- **修复：** 添加 `MimeType=application/pdf;`
- **状态：** [x] 已修复

### F02 — `mail.desktop` 缺少 MimeType
- **文件：** `.local/share/applications/mail.desktop`
- **现状：** 无 MimeType
- **影响：** 邮件链接（mailto:）无法通过桌面关联打开
- **修复：** 添加 `MimeType=x-scheme-handler/mailto;`
- **状态：** [x] 已修复

### F03 — `rss.desktop` 缺少 MimeType
- **文件：** `.local/share/applications/rss.desktop`
- **现状：** 无 MimeType
- **影响：** RSS/Atom feed 链接无法通过桌面关联打开
- **修复：** 添加 `MimeType=application/rss+xml;application/atom+xml;x-scheme-handler/feed;`
- **状态：** [x] 已修复

### F04 — `text.desktop` 缺少 MimeType
- **文件：** `.local/share/applications/text.desktop`
- **现状：** 无 MimeType
- **影响：** 文本文件无法通过桌面关联打开
- **修复：** 添加 `MimeType=text/plain;text/x-c;text/x-python;text/x-shellscript;text/html;text/css;application/json;`
- **状态：** [x] 已修复

### F05 — `torrent.desktop` 缺少 MimeType
- **文件：** `.local/share/applications/torrent.desktop`
- **现状：** 无 MimeType
- **影响：** 种子文件和磁力链接无法通过桌面关联打开
- **修复：** 添加 `MimeType=application/x-bittorrent;x-scheme-handler/magnet;`
- **状态：** [x] 已修复

### F06 — `file.desktop` 缺少 MimeType
- **文件：** `.local/share/applications/file.desktop`
- **现状：** 无 MimeType
- **影响：** 文件管理器无法通过桌面关联打开目录
- **修复：** 添加 `MimeType=inode/directory;`
- **状态：** [x] 已修复

### F07 — `video.desktop` MimeType 不完整
- **文件：** `.local/share/applications/video.desktop`
- **现状：** 仅 `video/x-matroska;`
- **影响：** 大部分视频和音频文件无法通过桌面关联打开
- **修复：** 补充 `video/mp4;video/webm;video/x-flv;video/x-msvideo;audio/mpeg;audio/flac;audio/ogg;audio/mp4;`
- **状态：** [x] 已修复

### F08 — `img.desktop` 用 `%f` 限制单文件
- **文件：** `.local/share/applications/img.desktop`
- **现状：** `Exec=/usr/bin/nsxiv -a %f`，`%f` 限制单文件
- **影响：** 图片查看器只能打开单个文件，无法批量查看
- **修复：** 改为 `%F` 支持多文件
- **状态：** [x] 已修复

### F09 — ncmpcpp `l` 键绑定 4 次
- **文件：** `.config/ncmpcpp/bindings`
- **现状：** `l` 键绑定 next_column、enter_directory、run_action、play_item，最后一个生效
- **影响：** vim 右导航（next_column）丢失
- **说明：** 与 voidrice 一致，最后一个绑定（play_item）生效。保持现状，与 voidrice 保持一致。
- **状态：** [x] 已确认（与 voidrice 一致，保持现状）

### F10 — ncmpcpp `g`/`G` 与 vim 惯例
- **文件：** `.config/ncmpcpp/bindings`
- **现状：** `g` = move_home, `G` = move_end
- **影响：** 与 vim 惯例（gg = 开头, G = 末尾）不同
- **说明：** 与 voidrice 一致，保持现状。
- **状态：** [x] 已确认（与 voidrice 一致，保持现状）

### F11 — ncmpcpp 无退出快捷键
- **文件：** `.config/ncmpcpp/bindings`
- **现状：** `q = quit` 被注释
- **影响：** 无法用 `q` 退出
- **说明：** 与 voidrice 一致，保持现状。
- **状态：** [x] 已确认（与 voidrice 一致，保持现状）

### F12 — ncmpcpp `h`/`s`/`f`/`m` 重复绑定
- **文件：** `.config/ncmpcpp/bindings`
- **现状：** 每个键绑定 2 次，最后一个生效
- **影响：** 部分功能不可达
- **说明：** 与 voidrice 一致，保持现状。
- **状态：** [x] 已确认（与 voidrice 一致，保持现状）

### F13 — ncmpcpp 注释与实际按键不匹配
- **文件：** `.config/ncmpcpp/bindings`
- **现状：** 注释 "not used but bound" 不准确
- **影响：** 文档误导
- **说明：** 与 voidrice 一致，保持现状。
- **状态：** [x] 已确认（与 voidrice 一致，保持现状）

### F14 — `lf/lfrc` MIME 分支死代码
- **文件：** `.config/lf/lfrc`
- **现状：** `application/pdf` 在第 32 行已匹配，第 45 行不可达；`application/vnd*` 使 localc 分支不可达
- **影响：** 死代码增加维护负担，MIME 匹配逻辑不可预测
- **修复：** 合并或重排 MIME 分支
- **状态：** [x] 已修复（根据 voidrice 配置全面更新 lfrc）

### F15 — `lf/lfrc:99` `map gh` 无动作
- **文件：** `.config/lf/lfrc`
- **现状：** `map gh` 绑定为空
- **影响：** 快捷键绑定无效，用户预期行为不可达
- **修复：** 补为 `map gh cd ~` 或删除
- **状态：** [x] 已修复（根据 voidrice 配置改为 `map H cd ~`）

### F16 — `lf/lfrc:59,68` `$ans` 未加引号
- **文件：** `.config/lf/lfrc`
- **现状：** `[ $ans = "y" ]`，空输入时语法错误
- **影响：** 空输入时 `[ $ans = "y" ]` 展开为 `[ = "y" ]`，语法错误
- **修复：** 改为 `[ "$ans" = "y" ]`
- **状态：** [x] 已修复

### F17 — 补丁文件格式错误
- **影响：** 补丁无法应用或应用后破坏功能

| 编号 | 文件 | 问题 |
|------|------|------|
| F17a | `my-dwm-fonts.patch` | 第二个 hunk 无变更行，补丁无法应用 |
| F17b | `my-fzf-keybindings-zsh.patch` | 替换目标为空字符串，破坏 Alt+C 绑定 |

- **修复：** 删除两个补丁文件
- **状态：** [x] 已修复（删除补丁文件）

### F18 — `crontog:6` 数据丢失风险
- **文件：** `.local/bin/cron/crontog`
- **现状：** 单行 `&&`/`||` 组合，中断时可永久删除 crontab
- **影响：** 中断时 crontab 永久丢失，无法恢复
- **修复：** 重写为显式 if/else，每步检查返回值
- **状态：** [x] 已修复（重写为 if/else，添加失败提示）

### F19 — `sb-kbselect:16` dmenu 取消后空参数
- **文件：** `.local/bin/statusbar/sb-kbselect`
- **现状：** dmenu 取消后 `$kb` 为空，`setxkbmap ""` 执行
- **影响：** 按 Escape 取消时键盘布局被重置
- **修复：** 加 `[ -n "$kb_choice" ] || exit 0`
- **状态：** [x] 已修复

### F20 — `cron/newsup:8` xdotool 空窗口 ID
- **文件：** `.local/bin/cron/newsup`
- **现状：** `xdotool search --name "^newsboat$"` 无匹配时返回空，后续 `key --window ""` 出错
- **影响：** 无 newsboat 窗口时 xdotool 报错
- **修复：** 加空值检查
- **状态：** [x] 已修复

### F21-F23 — lf/lfrc 问题
- **影响：** tr 转义错误导致 mkdir 失败；~ 替换可能误改路径；拼写错误影响专业性

| 编号 | 问题 | 状态 |
|------|------|------|
| F21 | `mkdir` tr 转义错误 | [x] 已修复（voidrice 用 `"$@"`） |
| F22 | `sed 's\|~\|$HOME\|'` 替换所有 ~ | [x] 已确认（bm-dirs 无中间 ~ 情况，保持现状） |
| F23 | "copies" 拼写错误 | [x] 已修复（voidrice 用 "copied"） |

### F24-F26 — 其他功能问题
- **影响：** 非标准 MIME 类型不被桌面识别；HTTP 传输不安全；已弃用命令将在未来失效

| 编号 | 文件 | 问题 | 状态 |
|------|------|------|------|
| F24 | `mimeapps.list:16-18` | `application/xls`、`application/csv` 非注册 MIME | [x] 已修复（删除，标准类型已存在） |
| F25 | `newsboat/urls:10` | 使用 HTTP 而非 HTTPS | [x] 已修复 |
| F26 | `nsxiv/key-handler:17-19` | 使用已弃用的 `convert` | [x] 已修复（改为 `magick`） |

---

## 第三批：质量改进（约 30 项重点）

### Q01 — 统一信号号
- **文件：** `sb-mpdup` 等
- **现状：** `kill -45` 不跨平台
- **影响：** 信号号因系统而异，脚本在其他机器上可能无效
- **修复：** 统一为 `pkill -RTMIN+N`
- **状态：** [x] 已修复（改为 `pkill -RTMIN+11`）

### Q02 — D-Bus 启动加条件守卫
- **文件：** `.config/x11/xprofile:21`
- **现状：** 无条件调用 `dbus-launch`
- **影响：** 已有 D-Bus 会话时重复启动，浪费资源并可能产生僵尸进程
- **修复：** 加 `[ -z "$DBUS_SESSION_BUS_ADDRESS" ]` 检查
- **状态：** [x] 已修复

### Q03 — 临时文件清理
- **文件：** `linkhandler`、`dmenuhandler`
- **现状：** 下载后临时文件不清理
- **影响：** 临时文件积累占用磁盘，可能泄漏敏感下载内容
- **修复：** 加 trap 清理
- **状态：** [x] 已修复

### Q04 — 依赖检查补全
- **文件：** 多个状态栏脚本
- **现状：** `sensors`、`mpc`、`newsboat`、`wpctl`、`groff` 无存在性检查
- **影响：** 缺少依赖时脚本报错而非优雅降级，状态栏显示错误信息
- **修复：** 加 `command -v` 检查
- **状态：** [x] 已修复（sb-cpu, sb-help-icon, sb-mpdup, sb-music, sb-news, sb-volume）

### Q05 — echo → printf
- **文件：** `tag`、`qndl`、`dmenuhandler`、`install-ohmyz.sh`
- **现状：** 用 `echo` 处理用户数据
- **影响：** echo 解释用户数据中的 -n、-e 等选项，输出错误
- **修复：** 改为 `printf '%s\n'`
- **状态：** [x] 已修复

### Q06 — 废弃选项清理
- **影响：** 已弃用选项在未来版本中可能不被识别，导致配置加载失败或警告
- **文件：** `dunstrc`（transparency）、`zathurarc`（旧选项名）、`tmux.conf`（utf8）、`gtkrc-2.0`/`settings.ini`（toolbar-style）
- **修复：** 删除或更新为当前语法
- **状态：** [x] 已修复（dunstrc transparency、tmux.conf utf8 已删除；gtk-toolbar-style 保留）

### Q07 — lf 未引用变量
- **文件：** `.config/lf/lfrc`
- **现状：** `$f`、`$fx` 多处未加引号
- **影响：** 含空格的文件名导致命令断裂，行为不可预测
- **修复：** 加引号
- **状态：** [x] 已修复

### Q08 — wal postrun 安全
- **文件：** `.config/wal/postrun`
- **现状：** 写入所有 PTY；`pkill dunst` 影响所有用户
- **影响：** 向其他用户的 PTY 写入数据是安全隐患；pkill 影响其他用户的 dunst
- **修复：** 限制为当前用户 PTY；`pkill -u "$USER" dunst`
- **状态：** [x] 已修复

### Q09 — `.bashrc` GIT_DIR 泄漏
- **文件：** `.bashrc:16-34`
- **现状：** 补全函数导出 GIT_DIR/GIT_WORK_TREE 到环境
- **影响：** 子 shell 继承 GIT_DIR 后 git 操作指向错误仓库
- **修复：** 函数末尾 unset 或改用 local
- **状态：** [x] 已修复

### Q10 — `.gitignore` 过宽模式
- **文件：** `.gitignore:14`
- **现状：** `.z*` 匹配所有 `.z` 开头文件
- **影响：** `.z*` 匹配 `.zshrc`、`.zshenv` 等，意外忽略重要配置文件
- **修复：** 改为具体模式
- **状态：** [x] 已修复

### Q11 — `.gitconfig` 未引用参数
- **文件：** `.gitconfig:66-68`
- **现状：** `fs`/`fm` 别名 `$1` 未加引号
- **影响：** 含空格的参数断裂，git 别名行为不可预测
- **修复：** 加引号
- **状态：** [x] 已修复

### Q12 — `.gitconfig:49` dm 别名空输入
- **文件：** `.gitconfig`
- **现状：** `xargs` 无 `--no-run-if-empty`
- **影响：** 空输入时 xargs 仍执行命令，可能打开空窗口或报错
- **修复：** 加 `-r` 标志
- **状态：** [x] 已修复

### Q13 — `samedir:30` $TERMINAL 未检查
- **文件：** `.local/bin/samedir`
- **现状：** `$TERMINAL` 为空时 `exec ""` 失败
- **影响：** $TERMINAL 为空时 exec "" 失败，脚本崩溃
- **修复：** 加非空检查
- **状态：** [x] 已修复

### Q14 — `sb-tasks:18` 编辑器阻塞状态栏
- **文件：** `.local/bin/statusbar/sb-tasks`
- **现状：** 中键直接运行 `$EDITOR`，无 `setsid -f`
- **影响：** 编辑器阻塞状态栏脚本，dwm 状态更新停滞直到编辑器关闭
- **修复：** 改为 `setsid -f "$TERMINAL" -e "$EDITOR" "$0"`
- **状态：** [x] 已修复

### Q15 — `sb-cpubars:20` 未引用变量
- **文件：** `.local/bin/statusbar/sb-cpubars`
- **现状：** `[ ! -f $cache ]`
- **影响：** 含空格的路径导致测试条件断裂
- **修复：** 加引号
- **状态：** [x] 已修复

### Q16 — `noisereduce` ffmpeg 无错误检查
- **文件：** `.local/bin/noisereduce`
- **现状：** ffmpeg 失败后继续处理
- **影响：** ffmpeg 失败后继续处理损坏或空的输出文件
- **修复：** 每步加错误检查
- **状态：** [x] 已修复

### Q17 — `lf/scope:67` GPG 预览可能挂起
- **文件：** `.config/lf/scope`
- **现状：** `gpg -d` 在预览中可能等待密码输入
- **影响：** GPG 等待密码输入时 lf 预览卡死
- **修复：** 加 `--batch --pinentry-mode error`
- **状态：** [x] 已修复

### Q18 — `xprofile` GO 变量仅 X 会话
- **文件：** `.config/x11/xprofile:49`
- **现状：** `GO111MODULE`/`GOPROXY` 仅在 X 会话生效
- **影响：** 非 X 会话（SSH、tty）中 Go 工具使用错误的模块设置
- **修复：** 移到 shell profile
- **状态：** [x] 已修复

### Q19 — `picom.conf` animations 需 v13+
- **文件：** `.config/x11/picom.conf:71-81`
- **现状：** animations 块仅 picom v13+ 支持
- **影响：** 旧版 picom 启动时因无法识别的选项报错
- **修复：** 加注释说明版本要求，或移除
- **状态：** [x] 已有注释说明，无需修改

### Q20 — `.gitignore:25` 拼写错误
- **文件：** `.gitignore`
- **现状：** `.CFUserTextEnncoding` 多一个 n
- **影响：** gitignore 模式不匹配目标文件，意外跟踪用户文本编码配置
- **修复：** 改为 `.CFUserTextEncoding`
- **状态：** [x] 已修复

---

## 已记录在 installation-fixes.md 的缺陷（不重复）

B1-B7 安装系统缺陷已记录在 [installation-fixes.md](../planning/installation-fixes.md)，不在本文档重复。

---

## 执行进度

第一批 18 项：18/18 完成
第二批 26 项：26/26 完成
第三批 20 项：20/20 完成

总计 64 项，全部完成。
