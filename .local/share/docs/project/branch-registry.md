# 分支与任务登记

本文是分支治理的权威登记，权威副本在 master。x11 与 wayland 只保留同步快照，
blob 必须与 master 一致，不得在主线上单独改。机器本地的 `collab/R44-.../BRANCHES.md`
只是副本，不参与审计。

| R | 类型 | target | task branch | base | head | 状态 | 审查结论 | 合并目标 | 合并 SHA | 已删除 | 备注 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| - | 冻结锚点 | - | master | - | 2172961 | 代码冻结 | - | - | - | 否 | `split-base^{commit}`；文档可写 |
| - | 主线 | x11 | x11 | - | 4a44aab | 已同步 | - | - | - | 否 | 最新文档同步后 head；未 push |
| - | 主线 | wayland | wayland | - | 1f68229 | 已同步 | - | - | - | 否 | 最新文档同步后 head；未 push |
| R40 | 任务 | x11 | task/R40-x11-offline-branch | ae4822a | 32f0e04 | 已合并 | dsh 合并入主线 | x11 | 559efba | 是 | 离线包 target；合并后删除 |
| R40 | 任务 | wayland | task/R40-wayland-offline-branch | b9d5ba2 | 24ac5ed | 已合并 | dsh 合并入主线 | wayland | b23e006 | 是 | 与 x11 任务树一致后合并；合并后删除 |
| R42 | 任务 | wayland | task/R42-wayland-migration | 2172961 | 1f68229 | 开发中 | - | wayland | - | 否 | 无提交；暂停；已同步 wayland |
| R43 | 任务 | wayland | task/R43-wayland-desktop | 2172961 | f7c2d3f | 开发中 | Ghostty 配置初审通过 | wayland | - | 否 | 暂停；部分完成，未合入；仅配置；docs 不随任务 |
| R44 | 治理 | master | master | - | 2172961 | 通过 | qoder 复审通过 | master | 2172961 | 否 | v0.9 规约；代码冻结点 |
| R44 | 文档主干 | master | master | 2172961 | 6c894e8 | 通过 | qoder 回读通过 | master | 6c894e8 | 否 | v1.0；head 为上次审计值 |
| R44 | 任务 | x11 | task/R44-x11-test-record | 2172961 | 3729850 | 已合并 | qoder 复审通过 | x11 | c75f00a | 是 | 测试标签 + 规约 |
| R44 | 任务 | wayland | task/R44-wayland-test-record | 2172961 | fa7b248 | 已合并 | qoder 复审通过 | wayland | 1a2687f | 是 | 测试标签 + 规约；cherry-pick 自 1fee43b |
| R44 | 同步 | x11 | x11 | 559efba | 47dacaf | 已同步 | qoder 回读通过 | x11 | 47dacaf | 否 | 第一轮文档 sync |
| R44 | 同步 | wayland | wayland | b23e006 | a0744ac | 已同步 | qoder 回读通过 | wayland | a0744ac | 否 | 第一轮文档 sync |
| R44 | 同步 | x11 | x11 | 47dacaf | 4a44aab | 已同步 | 二轮 registry 修正 | x11 | 4a44aab | 否 | 第二轮 sync |
| R44 | 同步 | wayland | wayland | a0744ac | 1f68229 | 已同步 | 二轮 registry 修正 | wayland | 1f68229 | 否 | 第二轮 sync |

`head` 列是最近一次已审 head；主线 head 的滞后只代表同步历史，不代表任务未审。
审计以现场 `git rev-parse` 为准。

## 当前工作树

不静态记录；每次审计用 `git symbolic-ref HEAD` 读取，并核对它属于
声明的 target。日常 `$HOME` 应常驻 `x11`；Wayland 验证使用独立 worktree
或显式切换，并记录当前 HEAD。

## 审计

任务 base 必须属于目标主线；both 任务以结果 blob 比对；合并后由 dsh 删除并登记。
文档权威在 master。非文档 diff 用 `split-base^{commit}..master` 排除
`.local/share/docs/**` 与 `README.md` 后必须为空。
