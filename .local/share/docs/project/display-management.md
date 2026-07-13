# 本机 X11 显示管理分析

本文记录 2026-07-14 对本机显示切换链路的分析结果。它面向维护者，说明实际运行关系、
系统级参与者和遗留边界；日常操作见 `../user/desktop-guide-zh.md`，通用设计约束见
`architecture.md`。

本文只描述当前已运行的实现。尚未生效的目标状态、隔离清单、验证矩阵和分阶段回退见
[`../planning/display-management-redesign.md`](../planning/display-management-redesign.md)；
计划采用的单设备扩展接口见
[`display-device-adapter.md`](display-device-adapter.md)。在计划进入对应阶段前，不能把目标接口
当作当前配置使用。

## 结论

当前受支持的自动显示管理由 X11 会话中的 `xdisplay.sh --watch` 完成，不依赖 udev
直接执行 `xrandr`。本机已在热插入和拔出外接显示器时验证用户可见的切换行为。
`displayselect` 是唯一的交互式入口，两者通过同一把锁串行修改 RandR 布局。

复查同时发现，拔出后 innogpu 可能把 HDMI 报为 `disconnected`，却继续保留其几何和扩展后的
framebuffer；当前脚本尚未清理这种残留状态。因此物理热切换已可用，但 RandR 状态不能称为
完全收敛。旧 udev 规则、它调用的 hybrid 脚本和不参与加载的 Xorg 历史备份已移入临时隔离
目录，不再留在活动路径。旧的 `.local/share/doc/xdisplay.md` 说明已被本报告取代。

## 本机硬件与内核层

| 层级 | 本机事实 | 与显示切换的关系 |
| --- | --- | --- |
| GPU | Fantasy II-M，PCI `02:00.0` | 提供全部 DRM 输出 |
| 内核驱动 | `inno-drv`，模块 `innogpu` | 创建 DRM connector、DRI/fbdev 设备节点 |
| 盖子状态 | `/proc/acpi/button/lid/LID0/state` | watcher 每 0.5 秒读取开合状态 |
| 外接电源 | `/sys/class/power_supply/ADP1/online` | 审计时为 `1`；与 logind 的接电合盖策略共同决定是否挂起 |
| DRM connector | `card0-DP-1`、`card0-HDMI-A-1`、`card0-HDMI-A-2` | watcher 每 0.5 秒汇总其 `status`，名称和连接状态均是运行时事实 |
| RandR | Xorg 通过 `xrandr` 暴露输出、模式、几何和主屏 | 唯一的布局修改接口 |

本机的 DRM `DP-1`、`HDMI-A-1`、`HDMI-A-2` 分别由 Xorg 暴露为 `eDP-1`、`HDMI-1`、
`HDMI-2`。共享脚本不得硬编码外接输出名；本机只通过
`XDISPLAY_INTERNAL_OUTPUTS="eDP-1 DP-1"` 补充非标准内屏候选。

Xorg 日志确认当前会话加载以下系统级配置；它们不在配置仓库中，却直接影响 RandR 行为：

| 系统文件 | 当前作用 |
| --- | --- |
| `/etc/X11/xorg.conf` | 选择 PCI `02:00.0` 的 innogpu，声明 `DRI=3`、TearFree，并禁用 Xorg blank/standby/suspend/off 计时；当前驱动日志将 DRI 选项标为未使用，实际 GL provider 为 DRI2 |
| `/etc/X11/xorg.conf.d/10-innogpu.conf` | 为 innogpu OutputClass 设置 GLX vendor 与 `FBCompression=2` |
| `/etc/X11/xorg.conf.d/20-innogpu-display.conf` | 再次禁用 blanking，并声明为 `eDP-1`、`DP-1` Monitor section 禁用 DPMS；当前只采用 `eDP-1` section，Xorg 日志仍报告全局 DPMS enabled |

其中 `DP-1` 是曾出现过的内屏别名，当前 Xorg 实际输出是 `eDP-1`。这些系统文件记录驱动和
省电意图；未被驱动采用的选项不能视为已经生效，布局所有权仍在用户会话的 watcher。

## 有效运行链路

```text
innogpu 内核模块
  -> innogpu-repair-dri-nodes.service（系统启动时修复设备节点）
  -> Xorg + /etc/X11/xorg.conf{,.d/*} -> RandR
  -> startx: .xinitrc -> .config/x11/xprofile
       -> 导出内屏候选和可选恢复钩子
       -> xdisplay.sh --watch
            -> /proc 的盖子状态 + /sys/class/drm 的 connector 状态
            -> xrandr --current / --query
            -> RandR 布局
                 -> DWM 的 ConfigureNotify + Xinerama 几何更新

Mod+F3 -> displayselect -> 同一 RandR 布局锁 -> RandR 布局

systemd-logind -> Xorg 会话/DRM fd 授权 + 合盖挂起策略
```

`~/.xinitrc` 是 `.config/x11/xinitrc` 的兼容链接。它先加载 `.config/x11/xprofile`，再以
`ssh-agent dwm` 启动窗口管理器。显示管理并非 systemd user service：`xprofile` 以后台
进程启动 watcher，因此它继承当前 X11 的 `DISPLAY`、`XAUTHORITY` 和用户 D-Bus 环境。

## 自动布局行为

`xdisplay.sh` 的锁前缀包含 UID 和规范化后的 X server `DISPLAY`：`:0` 与 `:0.0` 共用，
不同 X server 相互独立。`apply.lock` 保证每次布局串行，`watch.lock` 保证每个 X server
只有一个 watcher。`displayselect` 取得同一个 `apply.lock`，所以手动选择期间 watcher 不会
并发布局。

| 事件 | watcher 的处理 |
| --- | --- |
| X11 会话启动 | 读取完整 RandR 状态，按当前连接输出收敛布局 |
| 热插入或拔出 | DRM 状态变化触发快速检查窗口；模式就绪后自动扩展输出 |
| 合盖且有外屏 | 首次使用缓存 RandR 状态，先确保外屏可用并位于 `0x0`、设为主屏，再关闭内屏 |
| 开盖 | 主动探测内屏模式，恢复内屏为主屏，并将外屏依次置于右侧 |
| 只有一个可用输出 | 将其启用为主屏并定位到 `0x0`；合盖且只剩内屏时不强制 modeset |
| 无法识别内屏的多屏 | 尝试镜像；失败时不记录成功并继续重试。`xrandr` 不提供事务回滚，可能已经部分应用布局 |
| 手动布局 | `Mod+F3` 启动 `displayselect`，可选单屏、扩展、镜像或 Arandr；脚本自动完成的前三种路径会刷新壁纸和键盘映射并重启 Dunst，Arandr 分支退出时只释放锁 |

稳定期 watcher 每 1 秒读取 `xrandr --current`；事件后的快速窗口以 0.5 秒间隔检查。
`xrandr --query` 只用于 DRM 变化、开盖、失败恢复、待就绪输出和 60 秒兜底，避免持续 EDID
探测拖慢 innogpu/外接显示器。布局成功后脚本验证主屏、坐标、激活状态和扩展关系，避免
对已经正确的输出重复执行 `--auto`。

每份 RandR 原始文本只解析一次，并保留输出连接、primary、geometry、正负坐标、可用模式、
active、stale 和 pending。`xdisplay.sh --status` 不执行恢复或布局命令，可显示解析结果、当前
策略、基础 health、物理拓扑签名、锁路径、watcher generation、manual marker 状态和当前旧式
设备注入。连续 6 次快照失败后 watcher 退出；新的同 X server watcher 最多等待 8 秒接管锁。
manual marker 目前只预留路径，尚不保护手动布局的换代竞争，该功能仍在阶段 4。

DWM 的 `configurenotify()` 在根窗口尺寸改变时调用 `updategeom()`；其 Xinerama 路径重新读取
所有屏幕几何、更新状态栏并重新排列窗口。因此 RandR 完成布局后，DWM 不需要单独重启。

`displayselect` 的基础依赖是 `xrandr`、`flock` 和 `dmenu`；镜像缩放使用 `bc`，手动布局
使用可选 `arandr`。脚本自动完成单屏、扩展或镜像布局后调用本地 `setbg`、`remaps`，并通过
`killall`/`setsid` 重启 `dunst`；Arandr 分支没有这些后处理。这些副作用只属于手动入口，
watcher 不执行它们。

## 系统服务与规则

| 项目 | 状态/位置 | 作用与边界 |
| --- | --- | --- |
| `innogpu-repair-dri-nodes.service` | `/etc/systemd/system/`，`enabled` 且 `active (exited)`，结果为 success | `oneshot` 服务，在 innogpu 已加载后、显示管理器前修复缺失的 DRI/fbdev 设备节点；它是本机 Xorg 设备节点的启动修复，不负责布局 |
| `systemd-logind` | `active`；`/etc/systemd/logind.conf` 设置 `HandleLidSwitchExternalPower=ignore` | 为 Xorg 持有会话和 DRM fd，并处理合盖睡眠策略。接电时忽略合盖；docked 默认忽略；普通非 docked 且未接电源时回退默认 suspend |
| systemd user services | `.config/systemd/user/` | 没有 `xdisplay`、`xrandr` 或显示监控服务；PipeWire 等用户服务与显示布局无直接所有权关系 |
| `95-display-hotplug.rules` | 已从 `/etc/udev/rules.d/` 移入临时隔离目录并 reload rules | 遗留规则使用不存在的 `ATTR{connector_status}` 且硬编码会话；当前活动规则路径已不存在 |

审计时本机为接电、盖子关闭状态。当前已验证的合盖结论适用于这一路径；未接电且未被 logind
判定为 docked 时，系统可能先挂起，不能把接电测试结果直接外推到该场景。

## 未跟踪的本机专用与遗留代码

| 路径 | 现状 | 结论 |
| --- | --- | --- |
| `.local/bin/innogpu-restore-dp1-mode-x11` | 由 `XDISPLAY_RESTORE_COMMAND` 可选调用，写死 `DP-1`/`eDP-1` 和 `1920x1200R` modeline | 本机内屏无可用模式时的有界恢复钩子；硬件专用，不跟踪 |
| `.local/share/xdisplay-transition-20260714/home/.local/bin/xdisplay-hybrid.sh` | 旧 udev helper 的隔离副本；原 `.local/bin/` 路径已不存在 | 硬编码 `eDP-1`、无共享锁并直接调用 `xrandr`，只为回退保留，不能重新启用 |
| `.local/share/xdisplay-transition-20260714/system/etc/udev/rules.d/95-display-hotplug.rules` | 旧规则的隔离副本；原 `/etc/udev/rules.d/` 路径已不存在 | 硬编码会话并使用不存在的属性，只为回退保留，不属于跨设备配置 |

发现未跟踪代码时仍遵循维护策略：只有具备明确运行必要性、跨设备复用价值、足够效率和可维护
结构时才考虑跟踪。恢复钩子仍保留为显式可选注入；旧 udev/hybrid 链路只存在于被 Git 忽略的
临时隔离目录，不再扩展。

## 阶段 1 隔离结果

`~/.local/share/xdisplay-transition-20260714/` 保存恢复说明、原路径/UID/GID/mode/链接目标、
sha256 清单和活动配置快照。它由 `.gitignore` 明确排除，不属于仓库部署内容。已经隔离：

- 四字节且无引用的 `.config/x11/xinit`；
- 旧 `.local/bin/xdisplay-hybrid.sh` 与对应 udev 规则；
- `/etc/X11/` 下 12 份不参与加载的 `*.before-*` 历史备份。

活动 Xorg 三份配置、logind 配置、innogpu service 及启用链接、modprobe、modules-load、ld.so
配置和本机内屏恢复 helper 均只备份、不移动。隔离后确认 logind active，innogpu service 仍为
enabled、active (exited)、success，Xorg/DWM 和唯一的 `xdisplay.sh --watch` 正常运行。

## 阶段 2 观测重构结果

阶段 2 没有改变单屏、扩展、镜像、开合盖或 stale 清理策略。保存快照覆盖单屏、扩展、镜像、
负坐标、pending 和真实 disconnected geometry；11 组状态/锁测试与 4 组 watcher 生命周期测试
全部通过。真实会话中 `--status` 正确报告 `HDMI-2` 为 disconnected、active、stale；受控 watcher
交接前后 RandR 保持 `4608x1600`，新 generation 与唯一 watcher 一致，错误日志为空。

真实 apply lock 测试中，锁被占用时 `xdisplay.sh --apply` 返回 `75`，`displayselect` 等待同一锁，
释放后可立即重新取得。阶段 2 提交后仍需一次真实退出 X11/重新登录，验证旧 watcher 自动退出和
新会话取得 watch lock；完成前不进入设备适配器迁移。

## 验证结果与维护约束

- 已完成：本机 X11 会话中的外接显示器热插入、拔出和用户可见布局切换。
- 已完成：内屏候选识别、开合盖布局、手动 `displayselect` 与 watcher 的共享锁行为。
- 已发现：拔出后可能残留带几何的 disconnected 输出和扩展 framebuffer；清理逻辑单独列入 TODO。
- 已确认：旧 udev 规则不会匹配本机 DRM 属性；现已从活动路径隔离并 reload rules。
- 已完成：统一 RandR 状态解析、`--status`、按 X server 加锁、watcher generation、失败退出和
  当前会话受控交接；仍待真实 X11 重登验证。
- 新设备只应配置必要的 `XDISPLAY_INTERNAL_OUTPUTS` 候选；外接输出保持动态识别。
- 目标方案将把本机候选和恢复逻辑迁入单一未跟踪适配器；迁移完成前，上述环境变量仍是当前接口。
- 不要把 watcher 改为 systemd user service，除非同时明确传递图形会话环境并重新验证登录、D-Bus
  和 X 授权边界。
- 修改本链路时，同时更新 `architecture.md`、用户指南、依赖清单和本报告，并在真实 X11
  会话中复查开盖、合盖、插拔和手动布局。
