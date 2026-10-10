# KaiTian X7h G1e + Gentoo 平台档案

本文面向 Agent 和维护者。

状态：新建档案（2026-10-11）。同一台 KaiTian X7h G1e 从 Debian 13 换成 Gentoo 后单独建档。
Debian 的实测、包映射和待办仍只在 [Debian 13 档案](kaitian-x7h-g1e-debian-13.md)，不是本平台事实。

## 设备基本信息

| 项目 | 平台事实 |
| --- | --- |
| 档案身份 | KaiTian X7h G1e 笔记本 + Gentoo |
| 厂商与型号 | KaiTian X7h G1e。主板、处理器、内存、显卡与驱动未在本系统复核，待填 |
| 发行版 | Gentoo。Profile、stage 与 `@world` 待填 |
| 包管理 | Portage（`emerge`）。不是 APT，不沿用 Debian 的 APT 结论 |
| 配置仓库 | bare 仓库 `$HOME/.cfg`，work-tree `$HOME` |
| 内核 | 待填 |
| init 与服务管理 | 待填 |
| 图形会话与桌面启动链 | 待填 |
| 使用人 | 本机日常账户。公开档案不记录用户名 |

## 适用范围与隐私边界

本档案只记录“KaiTian X7h G1e + Gentoo”。它不代表其他 Gentoo 机器，也不取代
Debian 13 档案。没有在本系统重新核对的项目保持待填，不用 Debian 档案里的安装状态、
服务所有权或实测结果填空。

不得记录主机名、用户名、序列号、UUID、MAC/IP、账户、凭据或原始 EDID。以后写入的内核、
软件版本和测试结果必须带日期，且不能当作长期身份。

## 通用规则入口

- 稳定命令与能力：[依赖清单](../project/dependencies.md)
- 跨发行版验证步骤：[依赖与文档审计流程](../planning/dependency-audit.md)
- 共享结构与职责：[架构与设计](../project/architecture.md)
- 显示状态模型与验证：[X11 显示管理设计](../project/display-management.md)
- 非标准显示硬件扩展：[显示设备适配器指引](../project/display-device-adapter.md)
- 文档与平台边界：[维护策略](../project/maintenance-policy.md)

## Gentoo 依赖审计

状态：未开始（2026-10-11）。没有 Gentoo 安装快照，也没有审计表。

## Gentoo 关键映射

只记通用依赖在本平台的映射。未验证的命令不算已安装。

| 通用能力 | Gentoo 映射或本平台结论 |
| --- | --- |
| 包管理 | Portage / `emerge`。`checkup` 只跑 `apt update` 和 `apt list --upgradable`，不能在本平台启用。`.config/shell/aliasrc` 里的 `pmu` 有 emerge 分支（`emerge-webrsync` 后 `emerge --ask -uDN @world`），但探测顺序是 `apt`、`pacman`、`xbps-install`、`emerge`；PATH 上还有 `apt` 时仍走 APT。该分支未在本机验证 |
| 状态栏可更新包计数 | `sb-pacpackages` 找到 `emerge` 时把更新列表留空，并把 `updates_supported` 设为 false。状态栏不显示 Portage 更新数。这是空实现，不是已核对的“没有更新” |

## 系统与会话差异

Debian 档案里的 init、包管理、网络、显示钩子和会话所有权都还没有在 Gentoo 上复核。
下列项不能从 Debian 搬过来：

- 显示，包括外接屏幕
- 输入法
- 电池
- 内核、init、桌面启动链
- Portage profile 与 `@world`
- 已验证的状态栏模块

Debian 时期为 APT 加过 `checkup` 定时任务。这里不记录它是否还在 crontab 里，也不把它当作 Gentoo 配置。

2026-10-11 核对了 Edge，不是从 Debian 档案搬来的：

- Mod+w 没有反应：`/usr/local/bin/dwm` 把浏览器编成 `librewolf`，本机没有这个命令。`microsoft-edge` 这个名字也不存在，包装脚本是 `/usr/bin/microsoft-edge-stable`。dwm 用 `posix_spawnp` 直接执行参数，argv0 必须是绝对路径，否则包装脚本里的 `readlink -f "$0"` 会指错目录。`~/src/dwm/config.h` 的 `BROWSER` 已改为该绝对路径，新二进制在 `~/.local/bin/dwm`。当前会话如果还是旧 dwm，要退出图形会话再进一次，Mod+w 才换新的。`~/.local/bin/microsoft-edge` 指向 stable，给环境变量 `BROWSER=microsoft-edge` 用。
- 不进 9 号标签：原来的规则没有 Edge。已加类名 `Microsoft-edge`，标签掩码 `1 << 8`（和 Gimp 一样）。类名还没用 `xprop` 对过实际窗口，新 dwm 生效后要核一次。
- Edge 不能开输入法，st 可以：fcitx5 的 XIM（`libxim`）在，st 走 XIM。Edge 154.0.4258.48 走 GTK；本机没有 gtk4，GTK3 的 immodules 里也没有 `im-fcitx5.so`。`xprofile` 设置的 `GTK_IM_MODULE=fcitx` 因此加载失败。要装 `app-i18n/fcitx-gtk`（gtk3）。这一项还没装。


## 显示硬件与本机钩子

待填。没有 Gentoo 上的输出名、驱动、钩子或 modeline 记录。

## 显示验证与已知行为

待填。没有 Gentoo 上的显示验证记录。

## 临时隔离与恢复

待填。没有已验证的本机恢复步骤。

## 平台工作

### 平台活动待办

- 填写内核、init 和桌面启动链。
- 填写 Portage profile 与 `@world`。
- 在本系统重新核对显示、电池和外屏。
- 安装 `app-i18n/fcitx-gtk`（gtk3）后再看 Edge 输入法。装好前不要改 `GTK_IM_MODULE`。
- 重新进入图形会话后确认 Mod+w 打开 Edge，并且窗口落在 9 号标签。
- 列出已在 Gentoo 上验证通过的状态栏模块；没跑过的保持待填。
- `checkup` 有经本平台验证的 Portage 路径之前，不要启用 APT 版 `checkup`。

### 平台挂起项目

当前没有挂起项。
