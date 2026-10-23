# 访问子系统

本机的网络访问控制。`axs` 用来启停 mihomo、刷新订阅、测节点、管理域名规则。其它工具保持原来的用法。

主仓库不跟踪本目录。本目录有本地 git，无远端。

## 依赖

python3 是全部命令的硬依赖。没有它，`axs` 不能启动。还需要本机已有的 mihomo，以及 Python 的 PyYAML。

## 安装

本目录就是安装位置。把 `bin/axs` 放到 `PATH` 上，或直接调用它。用户服务模板在 `units/`，复制到用户级 systemd 后再 enable。

## 常用命令

命令和别名以 `axs help` 为准。不带参数时打印用法。

- `axs s`：状态
- `axs e`：保证服务在跑
- `axs su r`：拉取订阅
- `axs n l`：节点列表
- `axs p u on`：打印当前 shell 的代理变量，需要 eval 才会生效
- `axs h` 或 `axs ?`：帮助

## 测试

在本目录执行：

```
sh tests/run.sh
```

这是离线套件。真内核另跑 `sh tests/lab/run.sh check`。

## 契约

行为见 [design.md](design.md)。约束见 [constraints.md](constraints.md)。文件怎么摆见 [architecture.md](architecture.md)。还没授权的事见 [roadmap.md](roadmap.md)。健康检查的口径见 [design.md](design.md#健康)。
