# 分支与任务登记

本文是分支治理的权威登记，权威副本在 master。x11 与 wayland 只保留同步快照，
blob 必须与 master 一致，不得在主线上单独改。机器本地的 `collab/R44-.../BRANCHES.md`
只是副本，不参与审计。

| R | 类型 | target | task branch | base | head | 状态 | 审查结论 | 合并目标 | 合并 SHA | 已删除 | 备注 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| - | 冻结锚点 | - | master | - | 2172961 | 代码冻结 | - | - | - | 否 | `split-base^{commit}`；文档可写 |
| - | 主线 | x11 | x11 | - | 559efba | 已建立 | - | - | - | 否 | 与 origin/x11 一致；文档快照待本轮同步 |
| - | 主线 | wayland | wayland | - | b23e006 | 已建立 | - | - | - | 否 | 与 origin/wayland 一致；文档快照待本轮同步 |
| R40 | 任务 | x11 | task/R40-x11-offline-branch | ae4822a | 32f0e04 | 已合并 | dsh 合并入主线 | x11 | 559efba | 是 | 离线包 target；合并后删除 |
| R40 | 任务 | wayland | task/R40-wayland-offline-branch | b9d5ba2 | 24ac5ed | 已合并 | dsh 合并入主线 | wayland | b23e006 | 是 | 与 x11 任务树一致后合并；合并后删除 |
| R42 | 任务 | wayland | task/R42-wayland-migration | 2172961 | 2172961 | 开发中 | - | wayland | - | 否 | 无提交。暂停说明：2026-11-06 用户决定；状态与 INDEX 统一为开发中 |
| R43 | 任务 | wayland | task/R43-wayland-desktop | 2172961 | 1f5420d | 开发中（部分完成，未合入） | Ghostty 配置初审通过 | wayland | - | 否 | 含 ea8a2b6、1f5420d；无 picom。暂停说明不作为状态行 |
| R44 | 治理 | master | master | - | 2172961 | 通过 | qoder 复审通过，收尾项已修 | master | 2172961 | 否 | v0.9 规约；代码冻结点 |
| R44 | 文档主干 | master | master | 2172961 | 2172961 | 开发中 | 待初审 | master | - | 否 | v1.0；本提交写入文档主干，head 以现场 rev-parse 为准 |
| R44 | 任务 | x11 | task/R44-x11-test-record | 2172961 | 3729850 | 已合并 | qoder 复审通过 | x11 | c75f00a | 是 | 测试标签 + 规约；合并后删除 |
| R44 | 任务 | wayland | task/R44-wayland-test-record | 2172961 | fa7b248 | 已合并 | qoder 复审通过 | wayland | 1a2687f | 是 | 测试标签 + 规约；cherry-pick 自 1fee43b；合并后删除 |

`head` 列是最近一次已审 head。审计以现场 `git rev-parse` 为准，允许比登记晚一笔。
文档同步 merge 发生在本登记之后，主线 head 会因此再前进一笔。

## 当前工作树

不静态记录；每次审计用 `git symbolic-ref HEAD` 读取，并核对它属于
声明的 target。日常 `$HOME` 应常驻 `x11`；Wayland 验证使用独立 worktree
或显式切换，并记录当前 HEAD。

## 审计

任务 base 必须属于目标主线；both 任务以结果 blob 比对；合并后由 dsh 删除并登记。
文档权威在 master。非文档 diff 用 `split-base^{commit}..master` 排除
`.local/share/docs/**` 与 `README.md` 后必须为空。
