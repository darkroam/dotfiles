# 分支与任务登记

本文是分支治理的权威登记，权威副本在 master。公共文档 blob 必须与 master 一致，
不得在主线上单独改。栈文档不进入 master：`stacks/x11/` 只在 x11，`stacks/wayland/` 只在 wayland。
机器本地的 `collab/R44-.../BRANCHES.md` 只是副本，不参与审计。

| R | 类型 | target | task branch | base | head | 状态 | 审查结论 | 合并目标 | 合并 SHA | 已删除 | 备注 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| - | 冻结锚点 | - | master | - | 2172961 | 代码冻结 | - | - | - | 否 | `split-base^{commit}`；文档可写 |
| - | 主线 | x11 | x11 | - | 4d870f7 | 已同步 | - | - | - | 否 | retired docs + latest-date checker；待 push |
| - | 主线 | wayland | wayland | - | 651ca27 | 已同步 | - | - | - | 否 | retired docs + latest-date checker；待 push |
| R40 | 任务 | x11 | task/R40-x11-offline-branch | ae4822a | 32f0e04 | 已合并 | dsh 合并入主线 | x11 | 559efba | 是 | 离线包 target；合并后删除 |
| R40 | 任务 | wayland | task/R40-wayland-offline-branch | b9d5ba2 | 24ac5ed | 已合并 | dsh 合并入主线 | wayland | b23e006 | 是 | 与 x11 任务树一致后合并；合并后删除 |
| R42 | 任务 | wayland | task/R42-wayland-migration | 2172961 | 1f68229 | 开发中 | - | wayland | - | 否 | 无提交；暂停；已同步 wayland |
| R43 | 任务 | wayland | task/R43-wayland-desktop | 2172961 | f7c2d3f | 开发中 | Ghostty 配置初审通过 | wayland | - | 否 | 暂停；部分完成，未合入；仅配置；docs 不随任务；Ghostty 正文在 stacks/wayland/wayland-desktop-alternatives.md |
| R44 | 任务 | x11 | task/R44-x11-docs-whitelist | f9af676 | 469b00e | 已合并 | qoder 复审通过 | x11 | 68f10cf | 是 | docs 白名单；合并后删除 |
| R44 | 任务 | wayland | task/R44-wayland-docs-whitelist | 70f95b4 | 99e8373 | 已合并 | qoder 复审通过 | wayland | f9ead5d | 是 | docs 白名单；合并后删除 |
| R44 | 任务 | x11 | task/R44-x11-doc-counts | cd1d342 | d6711f4 | 已合并 | dsh 终审通过 | x11 | c8108a6 | 是 | 数字断言；合并后删除 |
| R44 | 任务 | wayland | task/R44-wayland-doc-counts | 7b85bd3 | 4fce0da | 已合并 | dsh 终审通过 | wayland | dd35ade | 是 | 数字断言；合并后删除 |
| R44 | 任务 | x11 | task/R44-x11-retired-docs | 7dec330 | 2097eb3 | 已合并 | qoder 复审通过 | x11 | 4d870f7 | 是 | 旧 docs 清理；同批合并 |
| R44 | 任务 | wayland | task/R44-wayland-retired-docs | 9dc86e6 | 6d1a0e2 | 已合并 | qoder 复审通过 | wayland | 651ca27 | 是 | 旧 docs 清理；同批合并 |
| R44 | 任务 | x11 | task/R44-x11-doc-count-date | 7dec330 | b093e5a | 已合并 | qoder 复审通过 | x11 | 4d870f7 | 是 | 最新日期记录；同批合并 |
| R44 | 任务 | wayland | task/R44-wayland-doc-count-date | 9dc86e6 | e20b1e8 | 已合并 | qoder 复审通过 | wayland | 651ca27 | 是 | 最新日期记录；同批合并 |
| R44 | 治理 | master | master | - | 2172961 | 通过 | qoder 复审通过 | master | 2172961 | 否 | v0.9 规约；代码冻结点 |
| R44 | 文档主干 | master | master | 2172961 | 532846a | 通过 | qoder 回读/收尾 | master | 532846a | 否 | v1.0；head 为上次审计值 |
| R44 | 任务 | x11 | task/R44-x11-test-record | 2172961 | 3729850 | 已合并 | qoder 复审通过 | x11 | c75f00a | 是 | 测试标签 + 规约 |
| R44 | 任务 | wayland | task/R44-wayland-test-record | 2172961 | fa7b248 | 已合并 | qoder 复审通过 | wayland | 1a2687f | 是 | 测试标签 + 规约；cherry-pick 自 1fee43b |
| R44 | 同步 | x11 | x11 | 559efba | 47dacaf | 已同步 | qoder 回读通过 | x11 | 47dacaf | 否 | 第一轮文档 sync |
| R44 | 同步 | wayland | wayland | b23e006 | a0744ac | 已同步 | qoder 回读通过 | wayland | a0744ac | 否 | 第一轮文档 sync |
| R44 | 同步 | x11 | x11 | 47dacaf | 4a44aab | 已同步 | 二轮 registry 修正 | x11 | 4a44aab | 否 | 第二轮 sync |
| R44 | 同步 | wayland | wayland | a0744ac | 1f68229 | 已同步 | 二轮 registry 修正 | wayland | 1f68229 | 否 | 第二轮 sync |
| R44 | 任务 | wayland | task/R44-wayland-stack-docs | 139e73e | 670b64a | 已合并 | 待审查 | wayland | 813250f | 否 | 只新增 stacks/wayland |
| R44 | 任务 | x11 | task/R44-x11-stack-docs | 91eaec0 | 49ad472 | 已合并 | 待审查 | x11 | 4e4eb49 | 否 | 只新增 stacks/x11 |


`head` 列是最近一次已审 head；主线 head 的滞后只代表同步历史，不代表任务未审。
审计以现场 `git rev-parse` 为准。


## 文档分层窗口

2026-11-17 打开。整份搬迁在窗口期内旧路径和新路径同时存在。切分文件的旧路径保留公共残段，不删除。已推送历史只 revert，不 reset。关闭条件：归属线新 blob 已登记，且公共文档不再用 Markdown 链接指向旧路径。

### 整份搬迁

| 旧路径 | 新路径 | 归属 | 旧 blob | 新 blob | 状态 |
| --- | --- | --- | --- | --- | --- |
| `.local/share/docs/project/display-management.md` | `.local/share/docs/stacks/x11/display-management.md` | x11 | 2ed361864329 | 9d210b424622 | 已关闭 |
| `.local/share/docs/project/display-device-adapter.md` | `.local/share/docs/stacks/x11/display-device-adapter.md` | x11 | 05754c4f19ee | 63ed8ebff3f2 | 已关闭 |
| `.local/share/docs/project/display-testing.md` | `.local/share/docs/stacks/x11/display-testing.md` | x11 | 4f0b38b4d87f | 4f0b38b4d87f | 已关闭 |
| `.local/share/docs/user/keybindings-zh.md` | `.local/share/docs/stacks/x11/keybindings-zh.md` | x11 | d73e306d9537 | c668ac498af7 | 已关闭 |
| `.local/share/docs/project/wayland-migration.md` | `.local/share/docs/stacks/wayland/wayland-migration.md` | wayland | 65830c83cb8c | 519a52127743 | 已关闭 |
| `.local/share/docs/project/wayland-desktop-alternatives.md` | `.local/share/docs/stacks/wayland/wayland-desktop-alternatives.md` | wayland | d93dfab43814 | d93dfab43814 | 已关闭 |

### 切分

旧路径保留。状态不随窗口关闭而删除。

| 旧路径 | 新路径 | 归属 | 新 blob | 说明 |
| --- | --- | --- | --- | --- |
| `.local/share/docs/project/dependencies.md` | `.local/share/docs/stacks/x11/dependencies.md` | x11 | 0559c2eb60e1 | U02 与 U06 的 X11 行 |
| `.local/share/docs/project/architecture.md` | `.local/share/docs/stacks/x11/architecture.md` | x11 | cc653e3d28f4 | U02 与 U06 的 X11 段 |
| `.local/share/docs/user/desktop-guide-zh.md` | `.local/share/docs/stacks/x11/desktop-guide-zh.md` | x11 | 3c8f79fc8965 | X11 桌面节与 xdisplay 段 |

本窗口已由删除上述六条旧路径的 master 提交关闭。

## 当前工作树

不静态记录；每次审计用 `git symbolic-ref HEAD` 读取，并核对它属于
声明的 target。日常 `$HOME` 应常驻 `x11`；Wayland 验证使用独立 worktree
或显式切换，并记录当前 HEAD。

## 审计

任务 base 必须属于目标主线；both 任务以结果 blob 比对；合并后由 dsh 删除并登记。
公共文档权威在 master，栈文档权威在归属主线。非文档 diff 用 `split-base^{commit}..master` 排除
`.local/share/docs/**` 与 `README.md` 后必须为空。
