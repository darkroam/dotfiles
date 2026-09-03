# 架构域归属表

> 服务域：U01-U10 用户能力域；S01-S05 项目支撑域（全库归属登记）

本文是仓库路径到主域/关联域的唯一登记表。域定义和关系由[架构与设计](architecture.md#架构域模型)
维护；通用外部依赖由[依赖清单](dependencies.md)维护。其他文档中的“服务域”只用于导航，不改变
本文登记的产物所有权。

## 判定规则

所有路径均相对仓库工作树根目录：

1. 精确文件例外优先于目录规则；目录规则按路径长度从具体到一般匹配；同一层级按表中顺序首项命中。
2. 行为一致的目录使用递归规则 `/**`；`.local/bin/` 等行为异构目录不设兜底规则，必须按文件行为
   显式登记。
3. 每个产物只有一个主域；关联域可为空或有多个。调用某域的命令不自动改变主域，编排入口归入口
   所有者，测试归 S02，公开文档归 S03，根兼容链接继承规范目标。
4. 新跟踪路径若没有命中任何规则，检查失败；不得用“最接近的目录”静默归类。

表中的 `{a,b}` 表示列出的精确名称集合，不是 Shell glob；`/**` 表示目录内任意深度的文件。

## 域标识

| ID | 层级 | 规范名称 |
| --- | --- | --- |
| U01 | 用户能力域 | Shell、源代码管理与开发 |
| U02 | 用户能力域 | X11 桌面与输入 |
| U03 | 用户能力域 | 外观、字体与壁纸 |
| U04 | 用户能力域 | 音频、音乐、录制与视频 |
| U05 | 用户能力域 | 文件、文档、密码与桌面处理 |
| U06 | 用户能力域 | 显示、网络、挂载与系统控制 |
| U07 | 用户能力域 | 状态栏、通信与网络服务 |
| U08 | 用户能力域 | 下载、种子与文本浏览 |
| U09 | 用户能力域 | 编译、排版与数据辅助 |
| U10 | 用户能力域 | 系统模板与计划任务 |
| S01 | 项目支撑域 | 安装与交付 |
| S02 | 项目支撑域 | 验证 |
| S03 | 项目支撑域 | 文档与治理 |
| S04 | 项目支撑域 | 内部工程工具 |
| S05 | 项目支撑域 | 元数据与来源 |

## 精确例外

本表先于后续目录规则匹配。

| 路径 | 主域 | 关联域 | 理由 |
| --- | --- | --- | --- |
| `.config/x11/display-engine.conf.example` | U06 | U02 | 显示引擎策略文件位于 X11 配置树，但由显示能力所有。 |
| `.local/bin/dotcfg` | S01 | U01 | 安装系统唯一入口，不是普通用户辅助命令。 |
| `.local/bin/install.sh` | S01 | U01 | 旧初始安装入口；D9 已裁定迁出 U01 主域。 |
| `.local/bin/getbib` | U09 | U05 | 生成排版引用数据，同时消费 PDF/DOI 文档。 |
| `.fbtermrc` | U02 | U03 | TTY/FbTerm 输入显示配置，字体外观是关联能力。 |
| `.local/share/docs/planning/problems.md` | S03 | - | 跨设备复用的脱敏问题排查摘要与权威来源索引。 |

## 目录规则

| 路径规则 | 主域 | 关联域 | 行为边界 |
| --- | --- | --- | --- |
| `.config/x11/display-layouts/**` | U06 | U02 | 默认和自定义显示布局配置。 |
| `.config/x11/**` | U02 | U03、U06 | X11 会话、输入、资源和合成器；显示引擎例外见上表。 |
| `.config/{herdr,powershell,shell,tmux,wget,zsh}/**` | U01 | - | Shell、终端工作区及开发环境。 |
| `.config/{dunst,fontconfig,gtk-2.0,gtk-3.0,wal}/**` | U03 | U02 | 桌面外观、字体、通知和可选配色。 |
| `.config/{alsa,mpd,mpv,ncmpcpp}/**` | U04 | - | 音频、音乐和媒体配置。 |
| `.config/{lf,nsxiv,zathura}/**` | U05 | U03、U04 | 文件、图像和文档处理。 |
| `.config/newsboat/**` | U08 | U07 | RSS 阅读/动作，关联通信状态。 |
| `.local/lib/dotfiles/**` | S01 | S02 | dotcfg 安装实现；测试归 S02，不改变实现主域。 |
| `.local/lib/project-tools/**` | S04 | S02、S03 | 仓库开发过程内部工具。 |
| `.local/lib/xdisplay/**` | U06 | U02、S02 | 共享显示实现；测试仍单独归 S02。 |
| `.local/share/test/collab/**` | S02 | S03、S04 | 协作子系统 fixture。 |
| `.local/share/test/display/**` | S02 | U06 | 显示子系统 fixture。 |
| `.local/share/test/installation/**` | S02 | S01 | 安装子系统 Bats 与辅助文件。 |
| `.local/share/docs/**` | S03 | - | 公开设计、用户、平台、planning 和审计文档。 |
| `.local/share/applications/**` | U05 | U03、U04、U07、U08 | MIME/桌面入口由桌面处理能力所有。 |
| `.local/share/sys-etc/**` | U10 | U06、S01 | 未激活的系统模板。 |
| `.local/share/larbs/getkeys/**` | U01 | U02、U04、U05、U07、U08 | `getkeys` 运行数据，内容服务多个应用域。 |
| `.local/share/larbs/chars/**` | U02 | U03 | 字符选择和图标数据。 |
| `.local/patch/**` | U02 | U03 | 独立桌面源码的补丁来源。 |

## 声明式配置与根文件

| 路径或集合 | 主域 | 关联域 |
| --- | --- | --- |
| `.config/mimeapps.list` | U05 | U03、U04、U07、U08 |
| `.config/user-dirs.dirs` | U05 | U01 |
| `.asoundrc` | U04 | - |
| `.bashrc`、`.gitconfig`、`.npmrc`、`.profile`、`.zprofile` | U01 | U02 |
| `.custom.el` | U01 | U09 |
| `.gtkrc-2.0` | U03 | U02 |
| `.xinitrc`、`.xprofile` | U02 | U03、U04、U06 |
| `.gitignore` | S05 | S03 |
| `README.md` | S03 | S01 |
| `.local/share/larbs/LICENSE`、`.local/share/larbs/progs.csv` | S05 | - |
| `.local/share/larbs/ttymaps.kmap` | U02 | - |

## 用户命令

`.local/bin/` 不设目录默认值；以下集合与精确例外合起来必须覆盖该目录全部跟踪文件。

| 文件名（均位于 `.local/bin/`） | 主域 | 关联域 |
| --- | --- | --- |
| `fzf_preview`、`ifinstalled`、`install-ohmyz.sh`、`shortcuts`、`unix` | U01 | - |
| `getkeys` | U01 | U02、U04、U05、U07、U08 |
| `samedir`、`showclip` | U01 | U02、U05 |
| `dmenupass`、`dmenuunicode`、`prompt`、`remaps`、`td-toggle` | U02 | U05、U06、U08 |
| `setbg` | U03 | U02 |
| `booksplit`、`noisereduce`、`pauseallmpv`、`rotdir`、`slider`、`tag` | U04 | - |
| `dmenurecord`、`maimpick` | U04 | U02 |
| `lfub`、`otp`、`passmenu` | U05 | U02 |
| `displayselect`、`dmenumount`、`dmenumountcifs`、`dmenuumount`、`sysact`、`xdisplay`、`xdisplay.sh`、`xlight` | U06 | U02、U04 |
| `statusbar/{sb-kbselect}` | U07 | U02 |
| `statusbar/{sb-mpdup,sb-music,sb-volume}` | U07 | U04 |
| `statusbar/{sb-torrent}` | U07 | U08 |
| `statusbar/{sb-battery,sb-clock,sb-cpu,sb-cpubars,sb-disk,sb-doppler,sb-forecast,sb-help-icon,sb-internet,sb-iplocate,sb-mailbox,sb-memory,sb-moonphase,sb-nettraf,sb-news,sb-pacpackages,sb-popupgrade,sb-price,sb-tasks}`、`weath` | U07 | - |
| `dmenuhandler`、`linkhandler`、`podentr`、`qndl`、`torrent`、`transadd` | U08 | - |
| `peertubetorrent`、`rssadd`、`rssget` | U08 | U07 |
| `queueandnotify`、`tutorialvids` | U08 | U04 |
| `compiler`、`opout`、`texclear`、`texroot` | U09 | U01 |
| `cron/{README.md,checkup,crontog}` | U10 | U01、U06 |
| `cron/newsup` | U10 | U07、U08 |

## 覆盖基线

| 口径 | U01 | U02 | U03 | U04 | U05 | U06 | U07 | U08 | U09 | U10 | 用户能力域 | 项目支撑域 | 总计 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| R05 迁移前 HEAD | 39 | 16 | 9 | 14 | 20 | 35 | 25 | 13 | 4 | 7 | 182 | 95 | 277 |
| D9 落地后的 HEAD 路径 | 38 | 16 | 9 | 14 | 19 | 35 | 25 | 13 | 5 | 7 | 181 | 96 | 277 |
| 加入本文后的提交预期 | 38 | 16 | 9 | 14 | 19 | 35 | 25 | 13 | 5 | 7 | 181 | 97 | 278 |
| R08 加入 `problems.md` 后预期 | 38 | 16 | 9 | 14 | 19 | 35 | 25 | 13 | 5 | 7 | 181 | 98 | 279 |

D9 后的 96 个支撑文件分布为 S01 40、S02 28、S03 24、S04 1、S05 3；本文由
`.local/share/docs/**` 规则归 S03，提交预期因此变为 S03 25、支撑合计 97。阶段二禁止 Git 写操作，
所以提交前应对“277 个 HEAD 路径 + 本文”复算 278，不能声称当前 `git ls-files` 已包含本文。

R08 基线已包含上述 278 个路径；新增 `planning/problems.md` 后由精确例外归 S03，使 S03 变为 26、
项目支撑域变为 98、提交预期总计 279。该行在文件进入提交后才是实际跟踪基线。

## 维护流程

新增、移动或删除跟踪路径时：

1. 先按行为确定唯一主域和必要关联域；不能仅按所在目录猜测。
2. 优先复用现有规则；只有行为确实不同才增加精确例外。新增规则不得与更高优先级规则产生意外重叠。
3. 更新本文，并检查 `git ls-files` 全集及本轮拟新增文件全部恰好命中一个主域。
4. 若能力或外部要求变化，再更新 `dependencies.md`；若形成独立实现/接口/测试边界，再更新对应
   子系统文档。发行版提供者和实机结果只更新平台档案。
5. 提交前执行[文档质量规范](docs-standard.md)规定的术语、链接、平台泄漏和隐私检查。
