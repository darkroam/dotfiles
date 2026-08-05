# 测试框架

Bats (Bash Automated Testing System) 测试套件，按专题组织在子目录中。

## 前置条件

- [bats](https://github.com/bats-core/bats-core) >= 1.11.0
- git

## 快速开始

```bash
# 运行全部测试（递归扫描子目录）
bats -r .local/share/test/

# 运行某个专题
bats .local/share/test/installation/

# 运行单个文件
bats .local/share/test/installation/install-desktop.bats

# 过滤运行
bats --filter "TC-11" .local/share/test/installation/

# TAP 输出（CI 适用）
bats -r .local/share/test/ --tap
```

## 目录结构

```
.local/share/test/
├── installation/          ← 安装系统测试（状态机、备份、卸载、CLI）
│   ├── helpers.bash       ← 共享辅助函数
│   ├── detect-state.bats  ← TC-01..03  状态检测
│   ├── backup-logic.bats  ← TC-04..10  备份逻辑
│   ├── install-desktop.bats ← TC-11..16  桌面安装
│   ├── install-server.bats  ← TC-17..21  服务器安装
│   ├── restore-desktop.bats ← TC-22..25  恢复桌面
│   ├── restore-server.bats  ← TC-26..29  恢复服务器
│   ├── uninstall.bats       ← TC-30..43  卸载与恢复
│   ├── validate.bats        ← TC-34..35  仓库验证
│   ├── e2e-state-machine.bats ← TC-36..37  端到端生命周期
│   ├── dotcfg.bats          ← TC-44..58  统一 CLI
│   └── generate-conflicts.sh ← 冲突文件生成器
```

## 测试隔离

所有测试在隔离的 `/tmp/dotfiles-test-*` 目录中运行。真实 `$HOME` 永远不被修改。

## 环境变量

- `DOTFILES_REPOSITORY` — 覆盖源仓库 URL（测试自动设置）
- `DOTFILES_LIB_DIR` — 共享验证库路径
