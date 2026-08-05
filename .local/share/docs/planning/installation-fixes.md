# 安装系统修复记录

本文面向 Agent 和维护者。

相关文档：[安装系统设计](../project/installation-system.md)、[安装测试](../project/installation-testing.md)、[当前待办](todo.md)

**状态**: 全部已修复
**创建日期**: 2026-08-04
**最终修复**: 2026-08-05

本文档记录安装系统代码审查中发现的问题，按严重程度排序。全部 8 项已修复。

> **注**：B1 和 B2 在 2026-08-05 的备份系统重设计中被根本性解决——备份目录结构改为嵌套
> `.config-backup/{from}-to-{to}-{ts}/`，MANIFEST 格式改为 tab 分隔的 `relative_path\tmd5\tstatus`，
> uninstall.sh 完全重写为备份链扫描模式。原始修复方案记录在此但已被更彻底的重设计取代。

---

## B1（高）：uninstall.sh 备份匹配模式错误

**文件**: `.local/bin/uninstall.sh:17`

**问题**: 备份匹配模式为 `.config-backup-pre-install-*`（Gen 1 命名），但 Gen 2 脚本生成的备份目录命名为 `.config-backup-{from}-to-{to}-{timestamp}`。模式永远不匹配，导致 uninstall.sh 无法发现 Gen 2 备份目录。

**当前代码**:
```bash
backup_pattern="$HOME/.config-backup-pre-install-*"
```

**影响**: 卸载时无法检测和提供 Gen 2 备份恢复选项。

**修复方案**: 改为 `backup_pattern="$HOME/.config-backup-*"` 以匹配所有代际的备份目录。

---

## B2（高）：uninstall.sh MANIFEST 解析捕获状态后缀

**文件**: `.local/bin/uninstall.sh:141`

**问题**: MANIFEST.txt 格式为 `original -> backup (status)`，正则 `^(.+) -> (.+)$` 将 `(modified)` 或 `(untracked)` 后缀捕获为 backup_file 路径的一部分。

**当前代码**:
```bash
if [[ "$line" =~ ^(.+)\ -\>\ (.+)$ ]]; then
    backup_file="${BASH_REMATCH[2]}"
    # backup_file = "/path/to/backup/.bashrc (modified)"  ← 错误
```

**影响**: 从备份恢复文件时路径不存在，恢复失败。

**修复方案**: 修改正则剥离状态后缀：
```bash
if [[ "$line" =~ ^(.+)\ -\>\ (.+)\ \((modified|untracked)\)$ ]]; then
```
或在捕获后去除 ` (*)` 后缀。

---

## B3（高）：install-2.sh --force 无备份删除有效仓库

**文件**: `.local/bin/install-2.sh`（`--force` 路径）

**问题**: 当 `cfg_validate` 返回 `valid` 且 `--force` 启用时，脚本直接 `rm -rf` 删除现有仓库，不创建任何备份。

**影响**: 用户数据丢失风险。在测试环境中，这导致真实 `~/.cfg` 被删除。

**修复方案**:
1. 在 `--force` 路径中添加安全检查，拒绝在非测试环境中删除有效仓库
2. 或至少提示用户确认并说明数据将丢失

---

## B4（中）：install-server.sh 与 restore-server.sh 白名单不一致

**文件**: `.local/bin/install-server.sh:295-325`, `.local/bin/restore-server.sh:284-295`

**问题**: install-server.sh 白名单包含 22 个文件，restore-server.sh 只包含 11 个文件。

**install-server.sh 独有文件**（restore-server.sh 缺失）:
- `.config/shell/tmux.conf.local`
- `.config/git/ignore`
- `.gitignore`
- `.config/lf/scope`
- `.config/lf/cleaner`
- `.config/lf/icons`
- `.config/lf/shortcutrc`
- `.local/share/docs/user/desktop-guide-zh.md`

**影响**: desktop → server（restore-server.sh）→ desktop（restore-desktop.sh）往返后，上述 8 个文件不会被 checkout，用户丢失这些配置。

**修复方案**: 统一两个脚本的白名单。建议将白名单提取为共享常量文件或函数。

---

## B5（中）：restore-desktop.sh --auto-stash 未实现

**文件**: `.local/bin/restore-desktop.sh:14,180-182`

**问题**: `--auto-stash` 参数被解析并设置 `AUTO_STASH=true`，但代码中只用于改变提示文本（"To skip backup and overwrite directly, use --auto-stash flag"），实际备份行为不受影响。

**当前行为**: 无论是否传 `--auto-stash`，文件都会被备份。

**影响**: 用户期望 `--auto-stash` 会跳过备份直接覆盖，但实际行为与不加参数相同。文档和 server-mode.md 中错误地描述了此功能。

**修复方案**:
1. 实现 `--auto-stash` 功能（使用 `git stash` 或直接跳过备份）
2. 或移除 `--auto-stash` 参数，避免误导

---

## B6（中）：Gen 2 脚本 checkout 失败时无回滚

**文件**: `install-2.sh`, `install-server.sh`, `restore-desktop.sh`, `restore-server.sh`

**问题**: 如果 `git checkout HEAD -- ...` 在部分文件后失败，已完成的 checkout 不会被回滚，备份也不会被恢复。系统处于半安装状态。

**对比**: 只有 Gen 1 的 `install.sh` 有回滚机制（checkout 失败时恢复备份）。

**影响**: 安装中断后用户需要手动清理。

**修复方案**: 在 checkout 循环中添加 trap 或错误处理，失败时自动恢复备份。

---

## B7（低）：helpers.sh 存在但未被加载

**文件**: `scripts/test/helpers.sh`（已移除，迁移到 `.local/share/test/installation/helpers.bash`）

**问题**: 该文件定义了 `check_backup_structure()`、`verify_manifest()` 等辅助函数，但 `state-machine-tester.sh` 和 `cfg-validate-test.sh` 都没有 source 它。测试脚本内嵌了所有验证逻辑。

**影响**: 代码冗余，helpers.sh 的修改不影响测试行为。

**修复方案**:
1. 在测试脚本中 source helpers.sh 并移除内嵌重复代码
2. 或将 helpers.sh 的有用函数合并到测试脚本中并删除该文件

---

## 优先级

| 编号 | 严重度 | 说明 |
| --- | --- | --- |
| B1 | 高 | uninstall.sh 无法发现 Gen 2 备份 |
| B2 | 高 | MANIFEST 解析导致恢复失败 |
| B3 | 高 | --force 无备份删除仓库 |
| B4 | 中 | 白名单不一致导致文件丢失 |
| B5 | 中 | --auto-stash 未实现 |
| B6 | 中 | checkout 失败无回滚 |
| B7 | 低 | helpers.sh 死代码 |

---

## B8（高）：uninstall.sh 恢复逻辑跳过已存在文件

**文件**: `.local/bin/uninstall.sh:145-149, 174-177`

**问题**: 恢复备份时，如果目标路径已存在文件（安装 checkout 的仓库版本），uninstall.sh 会跳过恢复而不是替换。导致卸载后用户原始文件未被恢复。

**当前代码**:
```bash
if [ -e "$original" ] || [ -L "$original" ]; then
    printf 'Skipped (exists): %s\n' "$(basename "$original")"
    ((skipped++)) || true
    continue
fi
```

**影响**: 卸载无法恢复到安装前状态，用户原始配置丢失。

**修复方案**: 恢复前先删除当前文件（它是仓库 checkout 的版本）：
```bash
if [ -e "$original" ] || [ -L "$original" ]; then
    rm -f -- "$original"
fi
```

---

**状态**: 全部 8 项已修复并验证（72 个 Bats 测试通过，2026-08-05）。
