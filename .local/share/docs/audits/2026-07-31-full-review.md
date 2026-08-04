# 全量审查问题清单

- **日期：** 2026-07-31
- **范围：** 全库逐文件审查（140 个跟踪文件）
- **方法：** 按严重度（高/中/低）分类，逐项确认后修复
- **状态：** 已完成（112/112）

## 工作流程

遵循[维护策略规定的工作流规则](../project/maintenance-policy.md#工作流)。

每一项编号（H01、M01、L01 等）为一个独立任务，必须单独走完整流程：
提出方案 → 用户确认 → 执行 → review → 用户确认 → 下一项。
不得将多个任务合并处理。会话因上下文压缩恢复后，必须先阅读
[维护策略](../project/maintenance-policy.md)确认约束和工作流，再对照本文件的
执行进度表确认当前状态。

---

## 高严重度（22 项）

### H01 — `...` 别名解析为 `cd ....`（永远失败）
- **文件：** `.config/shell/aliasrc:55`
- **现状：** `...='cd ..\..'`，单引号内 `\.` 被 shell 解析为字面 `.`，结果为 `cd ....`
- **影响：** `...` 命令永远失败，无法跳转到上两级目录
- **修复：** 改为 `...='cd ../..'`

### H02 — `pss` 别名末尾悬空 `-e`（grep 报错）
- **文件：** `.config/shell/aliasrc:37,46`
- **现状：** `pss='ps aux | grep -v grep | grep -i -e VSZ -e'`，末尾 `-e` 缺参数，grep 退出码 2
- **影响：** `pss` 命令每次执行都报错，无法查看进程
- **修复：** 改为函数 `pss() { ps aux | grep -v grep | grep -i -e VSZ -e "${1:-.}"; }`

### H03 — Zsh `c` 命令补全双重改写
- **文件：** `.config/zsh/.zshrc:235`
- **现状：** `compdef _c_git c=git` 自动将 words 中 `c` 替换为 `git`，但 `_c_git` 函数内又手动替换一次，导致 `words` 变成 `(git git args...)`
- **影响：** `c` 补全参数重复，补全结果错误
- **修复：** 保留 `compdef _c_git c=git`，去掉函数内的手动 words 改写，让 zsh 自动处理翻译

### H04 — `sb-doppler` 结构错误：`pickloc()` 缺少 `{`
- **文件：** `.local/bin/statusbar/sb-doppler:9,251`
- **状态：** 误报。第 251 行 `;}` 正确闭合函数，后续函数和 main case 在顶层。
- **影响：** 无（误报）
- **关联修复：** L30（stat 文件不存在检查）已修复。

### H05 — `sb-kbselect` 取错 awk 字段
- **文件：** `.local/bin/statusbar/sb-kbselect:15`
- **状态：** 误报。当前 base.lst 所有布局描述为单词，`$3` 正确取到布局代码。
- **影响：** 无（误报）

### H06 — `sb-price` 用 atime 代替 mtime，价格不刷新
- **文件：** `.local/bin/statusbar/sb-price:25,33`
- **状态：** 误报。`relatime` 下 atime 超过 24 小时未访问时会在读取时更新，日更新逻辑正确。
- **影响：** 无（误报）

### H07 — `booksplit` eval 命令注入
- **文件：** `.local/bin/booksplit:34,46`
- **现状：** 用户输入的 `$author`、`$title` 等直接拼入命令字符串后 `eval` 执行，含引号或 `$()` 时注入
- **影响：** 输入含特殊字符时执行任意命令
- **修复：** 去掉 eval，改为循环内直接调用 ffmpeg 并使用正确引号

### H08 — `compiler` RMarkdown 处理注入
- **文件：** `.local/bin/compiler:156`
- **现状：** `Rscript -e "rmarkdown::render('$file', quiet=TRUE)"`，`$file` 含单引号时 R 表达式断裂
- **影响：** 文件名含单引号时可执行任意 R 代码
- **修复：** 改为 `Rscript -e 'args <- commandArgs(trailingOnly=TRUE); rmarkdown::render(args[1], quiet=TRUE)' -- "$file"`

### H09 — `prompt` 未加引号的 `$2` 执行
- **文件：** `.local/bin/prompt:8`
- **状态：** 误报。脚本设计就是执行传入的命令字符串，调用者控制输入。
- **影响：** 无（误报）

### H10 — `shortcuts` eval 执行书签文件内容
- **文件：** `.local/bin/shortcuts:23,35`
- **状态：** 误报。个人工具，书签文件由用户自己维护，输入可控。
- **影响：** 无（误报）

### H11 — `tutorialvids` 用户输入注入 grep 正则
- **文件：** `.local/bin/tutorialvids:26`
- **现状：** dmenu 选择直接插入 `grep -P` 正则，特殊字符导致匹配失败；`grep -P` 非 POSIX
- **影响：** 特殊字符导致匹配失败，功能不可用
- **修复：** 改用 `grep -F`（固定字符串）匹配标题，用 `grep -E` + `[[:space:]]` 替代 `\s`

### H12 — `displayselect` 三屏 tertiary 与 secondary 重叠
- **文件：** `.local/bin/displayselect:167`
- **状态：** 误报。tertiary 使用 `grep -v "$direction"` 取反方向，自动放在 primary 另一侧，不会重叠。
- **影响：** 无（误报）

### H13 — `displayselect` dmenu 取消后空变量传入 xrandr
- **文件：** `.local/bin/displayselect:133-158`
- **现状：** 用户在 dmenu 按 Escape 后变量为空，xrandr 收到 `--output ""` 报错
- **影响：** xrandr 收到空参数报错，显示配置失败
- **修复：** 每个 dmenu 调用后加 `|| return 1` 和 `[ -n "$var" ] || return 1`

### H14 — `picom.conf` 使用已移除选项
- **文件：** `.config/x11/picom.conf:8,12`
- **现状：** `dbe = false` 和 `glx-copy-from-front = false` 在 picom v12+ 已移除，可能导致启动失败
- **影响：** picom 可能启动失败
- **修复：** 删除这两行

### H15 — `cron/checkup` sudo 在 cron 中挂起
- **文件：** `.local/bin/cron/checkup:7`
- **现状：** `sudo apt update` 在 cron 无 TTY 环境下挂起等待密码输入
- **影响：** cron 任务永久挂起，等待密码输入
- **修复：** 增加 TTY 检测，无 TTY 时跳过或使用 `sudo -n`（non-interactive）

### H16 — `cron/crontog` 写入失败后仍删除 crontab
- **文件：** `.local/bin/cron/crontog:6`
- **现状：** 单行 `(... && crontab -l > save && crontab -r) || ...`，写入失败后 `crontab -r` 仍执行
- **影响：** 写入失败时 crontab 被永久删除
- **修复：** 改为显式 if/else，每步检查返回值

### H17 — `slider` 变量未初始化
- **文件：** `.local/bin/slider:70`
- **现状：** `$seconds` 在使用前未赋值，`endtime` 计算错误
- **影响：** endtime 计算错误，计时器不准
- **修复：** 正确解析 ffmpeg 时长为算术值，或在循环后计算

### H18 — `rssadd` URL 正则捕获尾部引号
- **文件：** `.local/bin/rssadd:34`
- **现状：** `grep -o 'https?://[^\" ]'` 只匹配一个尾部字符，URL 被截断且可能带 `"`
- **影响：** URL 被截断，feed 地址不完整
- **修复：** 改为 `grep -o 'https://[^" ]*'`

### H19 — `dmenuunicode` printf 格式串漏洞
- **文件：** `.local/bin/dmenuunicode:16`
- **现状：** `printf "$chosen"` 中 `$chosen` 含 `%` 时被解释为格式符
- **影响：** 含 `%` 的字符被解释为格式符，输出错误
- **修复：** 改为 `printf '%s' "$chosen"`

### H20 — `newsboat/config` 正则多余括号
- **文件：** `.config/newsboat/config:45`
- **现状：** `highlight feedlist ".*(0/0))" black` 多一个 `)`
- **影响：** 正则匹配错误，高亮失效
- **修复：** 改为 `highlight feedlist ".*(0/0)" black`

### H21 — `lf/lfrc` setbg 命令将文件路径当命令执行
- **文件：** `.config/lf/lfrc:93,120`
- **现状：** `cmd setbg "$1"` 直接执行参数，`map b $setbg $f` 将图片路径当命令
- **影响：** 图片路径被当命令执行，可能执行任意程序
- **修复：** 改为 `cmd setbg $HOME/.local/bin/setbg "$1"` 或调用实际壁纸设置命令

### H22 — Bash `c` 补全 COMP_POINT 偏移错误
- **文件：** `.bashrc:26`
- **现状：** `COMP_POINT=$(( saved_point + 2 ))`，`c`（1 字符）替换为 `git`（3 字符）应偏移 +2 仅在光标紧贴 `c` 后正确，行尾时差 1
- **影响：** 无（误报）
- **修复：** 改为 `COMP_POINT=$(( saved_point + ${#git} - 1 ))`

---

## 中严重度（38 项）

### M01 — XDG 变量在定义前使用
- **文件：** `.config/shell/profile:38-43`
- **现状：** `profile.local` 在第 38 行使用 `XDG_CONFIG_HOME`，但该变量在第 43 行才定义
- **影响：** XDG 变量使用默认值而非预期路径
- **修复：** 将 XDG 定义块移到第 38 行之前

### M02 — GOPATH 两处不一致
- **文件：** `.config/shell/profile:62` vs `.config/zsh/.zshrc:15`
- **现状：** profile 设为 `~/.local/share/go`，zshrc 设为 `~/Project/go`
- **影响：** bash 和 zsh 下 Go 工具使用不同目录
- **修复：** 统一为一处定义

### M03 — gitconfig 别名 `$1` 未加引号
- **文件：** `.gitconfig:21,49,66,68,81,82`
- **现状：** 多个 git 别名传参未引号保护，含空格参数断裂；`dm` 缺 `xargs -r`
- **影响：** 含空格参数断裂，`dm` 空输入时报错
- **修复：** 逐个加引号保护，`dm` 加 `-r`

### M04 — `remaps` killall+xcape 竞争
- **文件：** `.local/bin/remaps:9`
- **现状：** `killall xcape` 后立即启动新实例，旧进程未完全退出时新实例可能失败
- **影响：** 新实例可能在旧进程退出前启动失败
- **修复：** killall 后加短暂等待

### M05 — `xprofile`/`remaps` xset r rate 重复
- **文件：** `.config/x11/xprofile:62` + `.local/bin/remaps:5`
- **现状：** 两处都执行 `xset r rate 300 50`，xprofile 的还后台化
- **影响：** xset r rate 执行两次，无功能影响但冗余
- **修复：** 删除 xprofile 中的重复行，保留 remaps 中的

### M06 — `xprofile` DPI 被 xdisplay.sh 覆盖
- **文件：** `.config/x11/xprofile:52,74`
- **现状：** `xrandr --dpi 96` 在 `xdisplay.sh --watch` 之前执行，后续 xrandr 操作可能重置 DPI
- **影响：** DPI 设置被后续 xrandr 操作覆盖
- **修复：** 改用 Xresources 中的 `Xft.dpi: 96` 设置

### M07 — `lf/lfrc` application/pdf 死代码
- **文件：** `.config/lf/lfrc:32,45`
- **现状：** `application/pdf` 在第 32 行已匹配，第 45 行永远不会匹配到
- **影响：** 第二个 MIME 分支永远不可达
- **修复：** 从第 32 行移除或合并两个分支

### M08 — `lf/lfrc` map gh 无动作
- **文件：** `.config/lf/lfrc:99`
- **现状：** `map gh` 无目标，绑定不完整
- **影响：** `gh` 绑定无效果，按键无响应
- **修复：** 补充为 `map gh ~` 或删除

### M09 — `lf/lfrc` 通知拼写错误
- **文件：** `.config/lf/lfrc:90`
- **现状：** `"File(s) copies to $dest."` 应为 `"copied"`
- **影响：** 通知文本语法错误
- **修复：** 改为 `copied`

### M10 — `mimeapps.list` 缺少尾部分号
- **文件：** `.config/mimeapps.list:12-14`
- **现状：** `application/rss+xml`、`video/x-matroska`、`inode/directory` 缺少尾部 `;`
- **影响：** MIME 类型注册不完整，部分文件关联失败
- **修复：** 补充分号

### M11 — `mimeapps.list` 无效 MIME 类型
- **文件：** `.config/mimeapps.list:16`
- **现状：** `application/xls` 不是注册 MIME 类型，永远不会匹配
- **影响：** 无效 MIME 类型永远不匹配
- **修复：** 删除或改为 `application/vnd.ms-excel`

### M12 — `nsxiv/key-handler` 使用已弃用的 convert
- **文件：** `.config/nsxiv/exec/key-handler:17-21`
- **现状：** ImageMagick 7+ 中 `convert` 已弃用
- **影响：** ImageMagick 7+ 中 `convert` 已弃用
- **修复：** 改为 `magick`

### M13 — `dmenuhandler` 临时文件未清理
- **文件：** `.local/bin/dmenuhandler:23-25`
- **现状：** download() 创建的临时文件在使用后未删除
- **影响：** 临时文件累积占用磁盘
- **修复：** 使用后 `rm -f "$temp"`

### M14 — `linkhandler` 临时文件未清理
- **文件：** `.local/bin/linkhandler:27,29`
- **现状：** 同 M13
- **影响：** 同 M13
- **修复：** 使用后 `rm -f "$temp"`

### M15 — `linkhandler` 运算符优先级错误
- **文件：** `.local/bin/linkhandler:33`
- **现状：** `[ -f "$url" ] && setsid ... || setsid ...`，文件存在但 setsid 失败时错误回退到浏览器
- **影响：** 文件存在但打开失败时错误回退到浏览器
- **修复：** 改为显式 if/else

### M16 — `lfub` 残留 FIFO 阻塞运行
- **文件：** `.local/bin/lfub:19`
- **现状：** 崩溃后 `mkfifo` 失败，`set -e` 退出
- **影响：** 崩溃后残留 FIFO 阻止再次运行
- **修复：** mkfifo 前 `rm -f "$FIFO_UEBERZUG"`

### M17 — `noisereduce` ffmpeg 无错误检查
- **文件：** `.local/bin/noisereduce:71-76`
- **现状：** ffmpeg 失败后继续处理空文件
- **影响：** ffmpeg 失败后继续处理空文件
- **修复：** 每个 ffmpeg 调用后加 `|| { echo "ffmpeg failed" >&2; exit 1; }`

### M18 — `maimpick` mv -n 静默跳过
- **文件：** `.local/bin/maimpick:139`
- **现状：** `mv -n` 目标存在时静默成功但不移动，错误信息误导
- **影响：** 目标已存在时静默跳过，错误信息误导
- **修复：** 先检查目标是否存在

### M19 — `setbg` find 在换行文件名时失败
- **文件：** `.local/bin/setbg:44`
- **现状：** `find | shuf -n 1` 按换行分割，文件名含换行时路径断裂
- **影响：** 换行文件名导致路径断裂
- **修复：** 改用 `-print0 | shuf -n 1 -z | tr -d '\0'`

### M20 — `sysact` emoji case 跨 locale 不匹配
- **文件：** `.local/bin/sysact:111-121`
- **现状：** dmenu 显示 emoji 文本，case 按 emoji 匹配，locale 变化时可能不匹配
- **影响：** locale 变化时 emoji 匹配失败
- **修复：** 改用 ASCII 标签匹配，emoji 仅作显示

### M21 — `xlight` 缓存值无校验
- **文件：** `.local/bin/xlight:5`
- **现状：** 从配置文件读取的值直接传给 `xbacklight -set`，非数字时失败
- **影响：** 非数字值导致 xbacklight 报错
- **修复：** 增加数字校验

### M22 — `sb-battery` 无电池设备报错
- **文件：** `.local/bin/statusbar/sb-battery:20`
- **现状：** 桌面机无 BAT* 时 glob 不展开，cat 报错
- **影响：** 桌面机无电池时 cat 报错
- **修复：** 加 `[ -e "$battery" ] || exit 0`

### M23 — `sb-forecast` curl 缺少 https://
- **文件：** `.local/bin/statusbar/sb-forecast:10`
- **现状：** `curl -sf "wttr.in/$LOCATION"` 缺少 scheme
- **影响：** 缺少 scheme 可能导致 curl 失败
- **修复：** 改为 `https://wttr.in/$LOCATION`

### M24 — `sb-help-icon` 条件结构脆弱
- **文件：** `.local/bin/statusbar/sb-help-icon:6-9`
- **现状：** `pidof dwm && READMEFILE=... \n restartwm() ...` 跨行逻辑脆弱
- **影响：** 条件逻辑脆弱，跨行解析易出错
- **修复：** 改为显式 if/else

### M25 — `sb-mailbox` 错误重定向位置错误
- **文件：** `.local/bin/statusbar/sb-mailbox:16`
- **现状：** `find ... | wc -l 2>/dev/null`，2>/dev/null 在 wc 上而非 find
- **影响：** 错误抑制在 wc 而非 find 上
- **修复：** 移到 find 上

### M26 — `sb-tasks` 编辑器阻塞状态栏
- **文件：** `.local/bin/statusbar/sb-tasks:18`
- **现状：** 中键直接运行 `$EDITOR`，缺少 `setsid -f`
- **影响：** 中键点击阻塞状态栏
- **修复：** 改为 `setsid -f "$TERMINAL" -e "$EDITOR" "$0"`

### M27 — `cron/newsup` pgrep 模式不匹配带参数的 newsboat
- **文件：** `.local/bin/cron/newsup:8`
- **现状：** `pgrep -f newsboat$` 不匹配 `newsboat -r`
- **影响：** 带参数的 newsboat 进程不被匹配
- **修复：** 改为 `pgrep -x newsboat`

### M28 — `slider` -s 选项不可达
- **文件：** `.local/bin/slider:12`
- **现状：** getopts 字符串缺 `s:`，`-s` 选项永远触发 usage
- **影响：** `-s` 选项永远触发 usage
- **修复：** 加入 `s:`

### M29 — `tag` 空标签写入 OGG/FLAC
- **文件：** `.local/bin/tag:41-48`
- **现状：** 未提供的标签以空值写入文件
- **影响：** 空标签值写入文件
- **修复：** 仅写入非空标签

### M30 — `qndl` $cmd 未受控展开
- **文件：** `.local/bin/qndl:16`
- **现状：** `$cmd` 来自 `$2`，含 glob 字符时意外展开
- **影响：** glob 字符意外展开
- **修复：** 验证或限制 `$2` 内容

### M31-M38 — 多个 .desktop 文件缺少 MimeType
- **文件：** `file.desktop`、`mail.desktop`、`pdf.desktop`、`text.desktop`、`video.desktop` 等
- **现状：** 缺少 `MimeType=` 声明，文件管理器"打开方式"不显示
- **影响：** "打开方式"菜单不显示对应应用
- **修复：** 补充对应 MIME 类型

### M39 — `displayselect` postrun 缺 command -v 保护
- **文件：** `.local/bin/displayselect:187-188`
- **现状：** `setbg` 和 `remaps` 直接调用无存在性检查
- **影响：** 命令不存在时报错
- **修复：** 加 `command -v ... &&`

### M40 — `sb-price` 未定义变量 $after
- **文件：** `.local/bin/statusbar/sb-price:50`
- **现状：** `$after` 从未定义，静默展开为空
- **影响：** $after 展开为空，输出格式不完整
- **修复：** 删除或定义

### M41 — `peertubetorrent` hash 长度可能错误
- **文件：** `.local/bin/peertubetorrent:24`
- **现状：** `.\{37\}` 匹配 37 字符，标准 BitTorrent hash 为 40
- **影响：** hash 长度不匹配标准 BitTorrent 格式
- **修复：** 验证实际格式后调整

### M42 — `rssadd` 反斜杠检查匹配双反斜杠
- **文件：** `.local/bin/rssadd:50`
- **现状：** case 模式 `*'\\'*` 在单引号内是两个字面反斜杠，不匹配单个
- **影响：** case 模式匹配两个字面反斜杠，不匹配单个
- **修复：** 用变量传递单个反斜杠

---

## 低严重度（52 项）

### L01 — `.gitignore` 拼写错误
- **文件：** `.gitignore:25`
- **现状：** `.CFUserTextEnncoding` 多一个 n
- **影响：** 拼写错误导致 gitignore 规则不生效
- **修复：** 改为 `.CFUserTextEncoding`

### L02 — `booksplit` 音轨从 00 开始
- **文件：** `.local/bin/booksplit:32`
- **现状：** `track` 未初始化，第一条为 00
- **影响：** 第一首音轨编号为 00
- **修复：** 初始化 `track=1`

### L03 — `booksplit` GNU sed 扩展
- **文件：** `.local/bin/booksplit:18,37`
- **现状：** `\+` 和 `\|` 非 POSIX
- **影响：** 非 POSIX 语法在其他系统可能失败
- **修复：** 改为 `sed 's/--*/-/g;s/^-//;s/-$//'`

### L04 — `booksplit` echo 用户输入
- **文件：** `.local/bin/booksplit:18,37`
- **现状：** `echo "$booktitle"` 可能解释反斜杠
- **影响：** 反斜杠可能被解释
- **修复：** 改为 `printf '%s\n'`

### L05 — `compiler` 多余分号
- **文件：** `.local/bin/compiler:145`
- **现状：** `fi ; ;;` 多余 `;`
- **影响：** 多余分号，无功能影响但语法不规范
- **修复：** 删除多余分号

### L06 — `dmenuhandler` $TERMINAL/$BROWSER 引号问题
- **文件：** `.local/bin/dmenuhandler:19,38`
- **现状：** 引号包裹使多词值被当作单命令名
- **影响：** 多词变量值被当作单命令名
- **修复：** 按意图决定是否拆分

### L07 — `dmenumount` glob 展开风险
- **文件：** `.local/bin/dmenumount:22`
- **现状：** awk 生成的 find 参数含 glob 模式
- **影响：** glob 模式展开风险
- **修复：** 已有 shellcheck disable，记录为已知限制

### L08 — `getkeys` 无目录检查
- **文件：** `.local/bin/getkeys:3,5`
- **现状：** 目录不存在时静默失败
- **影响：** 目录不存在时静默失败
- **修复：** 加存在性检查

### L09 — `noisereduce` 变量未加引号
- **文件：** `.local/bin/noisereduce:70,79`
- **现状：** `[ $isVideo -eq "1" ]` 未加引号
- **影响：** 变量为空时语法错误
- **修复：** 改为 `[ "$isVideo" -eq 1 ]`

### L10 — `rotdir` 用法提示重定向在引号内
- **文件：** `.local/bin/rotdir:10`
- **现状：** `echo "usage: rotdir regex 2>&1"` 中 `2>&1` 是字面文本
- **影响：** usage 信息中 2>&1 是字面文本
- **修复：** 改为 `echo "usage: rotdir regex" >&2`

### L11 — `rotdir` ls + awk -v 特殊文件名脆弱
- **文件：** `.local/bin/rotdir:12`
- **现状：** `ls` 不可靠，awk -v 解释反斜杠
- **影响：** ls 不可靠，特殊文件名导致 awk 错误
- **修复：** 改用 `printf '%s\n' *` 和 ENVIRON

### L12 — `samedir` 无 $TERMINAL 检查
- **文件：** `.local/bin/samedir:30`
- **现状：** `$TERMINAL` 未设置时 `exec ""` 失败
- **影响：** $TERMINAL 为空时 exec 失败
- **修复：** 加非空检查

### L13 — `showclip` 无 xclip 检查
- **文件：** `.local/bin/showclip:6-7`
- **现状：** xclip 不存在时报错
- **影响：** xclip 不存在时报错
- **修复：** 加 `command -v` 检查

### L14 — `slider` GNU grep `\+`
- **文件：** `.local/bin/slider:24`
- **现状：** BRE `\+` 非 POSIX
- **影响：** BRE \+ 非 POSIX，其他系统可能失败
- **修复：** 改用 `grep -Eq`

### L15 — `slider` 内部 $(...) 未加引号
- **文件：** `.local/bin/slider:69`
- **现状：** 时长字符串被词分割
- **影响：** 时长字符串被词分割
- **修复：** 加引号

### L16 — `tag` 无依赖检查
- **文件：** `.local/bin/tag`
- **现状：** 不检查 vorbiscomment/opustags/eyeD3/metaflac
- **影响：** 缺少依赖时运行报错
- **修复：** 按文件类型检查

### L17 — `tag` eyeD3 空参数
- **文件：** `.local/bin/tag:57`
- **现状：** MP3 路径不提示缺失值，eyeD3 收到空字符串
- **影响：** eyeD3 收到空字符串参数
- **修复：** 条件性包含非空参数

### L18 — `tutorialvids` grep -P 非 POSIX
- **文件：** `.local/bin/tutorialvids:26`
- **现状：** `grep -P` 是 GNU 扩展
- **影响：** grep -P 非 POSIX
- **修复：** 改用 `grep -E` + `[[:space:]]`

### L19 — `weath` 无 curl 检查
- **文件：** `.local/bin/weath`
- **现状：** 不检查 curl 是否存在
- **影响：** curl 不存在时报错
- **修复：** 加 `command -v` 检查

### L20 — `weath` ANSI 转义剥离不完整
- **文件：** `.local/bin/weath:32`
- **现状：** 仅剥离 SGR 序列
- **影响：** ANSI 转义剥离不完整
- **修复：** 改用 `col -b`

### L21 — `aliasrc` expr substr 非 POSIX
- **文件：** `.config/shell/aliasrc:38`
- **现状：** `expr substr` 是 GNU 扩展
- **影响：** expr substr 非 POSIX
- **修复：** 改用 `uname -s | cut -c1-5`

### L22 — `aliasrc` source 非 POSIX
- **文件：** `.config/shell/aliasrc:271`
- **现状：** `source` 是 bash/zsh 扩展
- **影响：** source 非 POSIX
- **修复：** 改为 `.`

### L23 — `profile` find -mindepth 非 POSIX
- **文件：** `.config/shell/profile:14`
- **现状：** `find -mindepth` 是 GNU 扩展
- **影响：** find -mindepth 非 POSIX
- **修复：** 记录为已知 Linux-only 假设

### L24 — `aliasrc` date %N 非 POSIX
- **文件：** `.config/shell/aliasrc:261`
- **现状：** `%N`（纳秒）GNU only
- **影响：** date %N 非 POSIX
- **修复：** 记录为已知 Linux-only 假设

### L25 — `gtk-3.0/settings.ini` 缺 cursor theme
- **文件：** `.config/gtk-3.0/settings.ini`
- **现状：** GTK2 设了 `gtk-cursor-theme-name=Adwaita`，GTK3 未设
- **影响：** GTK3 cursor theme 未设置
- **修复：** 补充 `gtk-cursor-theme-name=Adwaita`

### L26 — `user-dirs.dirs` Desktop 指向 $HOME
- **文件：** `.config/user-dirs.dirs:8`
- **现状：** `XDG_DESKTOP_DIR="$HOME/"` 使整个 home 成为桌面
- **影响：** 整个 home 成为桌面
- **修复：** 确认是否为有意设置

### L27 — `ncmpcpp/bindings` 重复绑定
- **文件：** `.config/ncmpcpp/bindings:429-475`
- **现状：** `l`、`h`、`m`、`s`、`f` 等键有多重绑定，动作叠加
- **影响：** 多重绑定导致部分功能不可达
- **修复：** 确认是否为 LARBS 上游有意设计

### L28 — `sb-cpu` 硬编码 Core 0
- **文件：** `.local/bin/statusbar/sb-cpu:12`
- **现状：** 只读 Core 0 温度，AMD 等不同标签无输出
- **影响：** 不同 CPU 标签可能无输出
- **修复：** 改用更灵活的模式

### L29 — `sb-cpubars` 变量未加引号
- **文件：** `.local/bin/statusbar/sb-cpubars:20`
- **现状：** `[ ! -f $cache ]`
- **影响：** 变量未加引号
- **修复：** 加引号

### L30 — `sb-doppler` stat 可能文件不存在
- **文件：** `.local/bin/statusbar/sb-doppler:270`
- **现状：** `$doppler` 不存在时 stat 报错
- **影响：** 文件不存在时 stat 报错
- **修复：** 加 `[ -f "$doppler" ]`

### L31 — `sb-forecast` 空管道输出误导
- **文件：** `.local/bin/statusbar/sb-forecast:17`
- **现状：** 无温度数据时仍输出 `🥶° 🌞°`
- **影响：** 无数据时仍输出误导文本
- **修复：** 加空值检查

### L32 — `sb-internet` 信号质量除数硬编码
- **文件：** `.local/bin/statusbar/sb-internet:21`
- **现状：** `int($3 * 100 / 70)` 对不同适配器不准确
- **影响：** 不同适配器信号质量计算不准确
- **修复：** 记录为已知限制

### L33 — `sb-moonphase` 点击处理在输出之后
- **文件：** `.local/bin/statusbar/sb-moonphase:24-37`
- **现状：** echo 先于 case 执行
- **影响：** 输出顺序不一致
- **修复：** 调换顺序

### L34 — `sb-mpdup` 信号号可能不匹配
- **文件：** `.local/bin/statusbar/sb-mpdup:7`
- **现状：** `kill -45` 的 SIGRTMIN 映射因系统而异
- **影响：** SIGRTMIN 映射因系统而异
- **修复：** 验证与 dwmblocks config.h 一致

### L35 — `sb-music` 注释全部错误
- **文件：** `.local/bin/statusbar/sb-music:8-14`
- **现状：** 注释说 "right click" 但实际是左键/中键/右键/滚轮
- **影响：** 注释与实际行为不匹配
- **修复：** 更正注释

### L36 — `sb-nettraf` 未加引号
- **文件：** `.local/bin/statusbar/sb-nettraf:29`
- **现状：** `$(numfmt ...)` 未加引号
- **影响：** 变量未加引号
- **修复：** 分别调用或正确引号

### L37 — `sb-news` 多余嵌套
- **文件：** `.local/bin/statusbar/sb-news:17`
- **现状：** `echo "$(cmd)"` 多余
- **影响：** 多余嵌套，无功能影响
- **修复：** 直接输出

### L38 — `sb-popupgrade` sh -c 模式
- **文件：** `.local/bin/statusbar/sb-popupgrade:20`
- **现状：** `sh -c "$upgrade"` 反模式，当前安全但脆弱
- **影响：** sh -c 反模式，当前安全但脆弱
- **修复：** 改为直接执行

### L39 — `sb-torrent` 输出顺序不一致
- **文件：** `.local/bin/statusbar/sb-torrent:5-29`
- **现状：** 数据输出在点击处理之前
- **影响：** 输出顺序不一致
- **修复：** 调换顺序

### L40 — `clash-verge-handler.desktop` Exec 路径加引号
- **文件：** `.local/share/applications/clash-verge-handler.desktop:10`
- **现状：** `Exec="/usr/bin/clash-verge" %u` 不符合 freedesktop 规范
- **影响：** Exec 引号不符合 freedesktop 规范
- **修复：** 去掉引号（注：此项属于未提交变更，需先确认是否提交）

### L41-L52 — 其他可移植性和风格问题
- **影响：** 低。风格问题和轻微可移植性差异，不影响功能正确性；部分条目（sb-iplocate 等）
  审查后确认无严重问题。
- `qndl:18` echo 应改 printf
- `podentr:5` 风格问题
- `shortcuts:10` $vim_shortcuts 死代码
- `dmenuunicode:6` 未保护 glob
- `dmenuunicode:17` notify-send 格式串
- `sb-clock:22` cal --color GNU only
- `sb-disk:23` awk 模式边缘情况
- `sb-iplocate` 无严重问题
- `sb-memory` 无严重问题
- `sb-pacpackages` 无严重问题
- `sb-volume` 无严重问题
- `zathurarc` 无问题

---

## 执行进度

每项确认后标记完成并记录到 history.md。

| 编号 | 状态 |
|------|------|
| H01 | [x] |
| H02 | [x] |
| H03 | [x] |
| H04 | [x] 误报 |
| H05 | [x] 误报 |
| H06 | [x] 误报 |
| H07 | [x] |
| H08 | [x] |
| H09 | [x] 误报 |
| H10 | [x] 误报 |
| H11 | [x] |
| H12 | [x] 误报 |
| H13 | [x] |
| H14 | [x] |
| H15 | [x] |
| H16 | [x] |
| H17 | [x] |
| H18 | [x] |
| H19 | [x] |
| H20 | [x] |
| H21 | [x] |
| H22 | [x] 误报 |
| M01 | [x] |
| M02 | [x] |
| M03 | [x] |
| M04 | [x] |
| M05 | [x] |
| M06 | [x] |
| M07 | [x] |
| M08 | [x] |
| M09 | [x] |
| M10 | [x] |
| M11 | [x] |
| M12 | [x] |
| M13 | [x] |
| M14 | [x] |
| M15 | [x] |
| M16 | [x] |
| M17 | [x] |
| M18 | [x] |
| M19 | [x] |
| M20 | [x] 不修改，用户故意用 emoji |
| M21 | [x] |
| M22 | [x] |
| M23 | [x] |
| M24 | [x] |
| M25 | [x] |
| M26 | [x] |
| M27 | [x] |
| M28 | [x] |
| M29 | [x] |
| M30 | [x] |
| M31 | [x] |
| M32 | [x] |
| M33 | [x] |
| M34 | [x] |
| M35 | [x] |
| M36 | [x] |
| M37 | [x] |
| M38 | [x] |
| M39-M42 | [x] |
| L01-L22 | [x] |
| L23 | [x] |
| L24 | [x] |
| L25-L28 | [x] L25-L27 误报，L28 已修改 |
| L29-L36 | [x] |
| L37 | [x] 已修复 |
| L38 | [x] 已修复 |
| L39 | [x] 已修复 |
| L40 | [x] 误报 |
| L41-L43 | [x] 保持现状 |
| L44-L46 | [x] |
| L47 | [x] 误报 |
| L48-L52 | [x] 误报（无严重问题） |
