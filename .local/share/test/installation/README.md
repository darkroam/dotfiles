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
│   ├── backup-logic.bats  ← TC-04..10  备份逻辑
│   ├── bootstrap.bats     ← 自举安装
│   ├── categories.bats    ← category 解析、继承和排除
│   ├── commands-lifecycle.bats ← 生命周期命令
│   ├── config-versions.bats ← category 版本管理
│   ├── deploy-undeploy.bats ← 节点部署与撤销
│   ├── detect-state.bats  ← 状态检测
│   ├── doctor-repair.bats ← 完整性诊断与修复
│   ├── dotcfg.bats        ← 统一 CLI
│   ├── e2e-state-machine.bats ← 端到端生命周期
│   ├── exclude-rules.bats ← Fresh 排除规则
│   ├── fresh-node.bats    ← Fresh 根节点
│   ├── history-graph.bats ← 节点清单和历史图
│   ├── install-desktop.bats ← full 兼容入口安装
│   ├── install-server.bats  ← min 兼容入口安装
│   ├── migration.bats     ← 旧会话迁移
│   ├── nodes.bats         ← 节点索引
│   ├── nodes-lifecycle.bats ← 节点生命周期
│   ├── refactor-contract.bats ← 重构接口契约
│   ├── restore-desktop.bats ← full 兼容入口恢复
│   ├── restore-server.bats  ← min 兼容入口恢复
│   ├── uninstall.bats     ← 卸载与恢复
│   ├── validate.bats      ← 仓库验证
│   └── generate-conflicts.sh ← 冲突文件生成器
```

## 测试隔离

所有测试在隔离的 `/tmp/dotfiles-test-*` 目录中运行。真实 `$HOME` 永远不被修改。

## 环境变量

- `DOTFILES_REPOSITORY` — 覆盖源仓库 URL（测试自动设置）
- `DOTFILES_LIB_DIR` — 共享验证库路径
