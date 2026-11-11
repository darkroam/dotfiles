# 分支与任务登记

本文是分支治理的权威登记，必须在 `x11` 与 `wayland` 两条主线保持 blob 一致。
机器本地的 `collab/R44-.../BRANCHES.md` 只是副本，不参与审计。

| R | 类型 | target | task branch | base | head | 状态 | 审查结论 | 合并目标 | 合并 SHA | 已删除 | 备注 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| - | 冻结锚点 | - | master | - | 2172961 | 已冻结 | - | - | - | 否 | `split-base^{commit}` |
| - | 主线 | x11 | x11 | - | 2172961 | 已建立 | - | - | - | 否 | 未 push |
| - | 主线 | wayland | wayland | - | 2172961 | 已建立 | - | - | - | 否 | 未 push |
| R42 | 任务 | wayland | task/R42-wayland-migration | 2172961 | 2172961 | 挂起 | - | wayland | - | 否 | 无提交 |

`head` 列是最近一次已审 head；审计以现场 `git rev-parse` 为准，允许任务分支比登记晚一笔。
| R43 | 任务 | wayland | task/R43-wayland-desktop | 2172961 | 1f5420d | 开发中（部分完成，未合入） | Ghostty 配置初审通过 | wayland | - | 否 | 含 ea8a2b6、1f5420d；无 picom |
| R44 | 治理 | master | master | - | 2172961 | 通过 | qoder 复审通过，收尾项已修 | master | 2172961 | 否 | v0.9 规约 |
| R44 | 任务 | x11 | task/R44-x11-test-record | 2172961 | 3729850 | 已合并 | qoder 复审通过 | x11 | c75f00a | 是 | 测试标签 + 规约；合并后删除 |
| R44 | 任务 | wayland | task/R44-wayland-test-record | 2172961 | fa7b248 | 已合并 | qoder 复审通过 | wayland | 1a2687f | 是 | 测试标签 + 规约；cherry-pick 自 1fee43b；合并后删除 |

## 当前工作树

不静态记录；每次审计用 `git symbolic-ref HEAD` 读取，并核对它属于
声明的 target。日常 `$HOME` 应常驻 `x11`；Wayland 验证使用独立 worktree
或显式切换，并记录当前 HEAD。

## 审计

任务 base 必须属于目标主线；both 任务以结果 blob 比对；合并后由 dsh 删除并登记。
