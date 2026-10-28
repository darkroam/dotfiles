# 访问子系统

本机的网络访问控制。`axs` 用来启停 mihomo、刷新订阅、测节点、管理域名规则。其它工具保持原来的用法。

代码在 dotfiles 的 `.local/lib/access/`。`full` 检出；`min` 不含会拉起网络守护进程的入口。

## 依赖

python3 是全部命令的硬依赖。没有它，`axs` 不能启动。还需要本机已有的 mihomo，以及 Python 的 PyYAML。

## 安装

PATH 上的 `axs` 是相对链接 `.local/bin/axs` → `bin/axs`。用户服务模板在 `units/`，复制到用户级 systemd 后再 enable。`dotcfg switch` 不 enable 服务，也不创建 `run/`。

## 常用命令

命令和别名以 `axs help` 为准。不带参数时打印用法。

- `axs s`：状态
- `axs service ensure`：保证服务在跑
- `axs su r`：拉取订阅
- `axs node show --all`：全部叶子端点
- `axs g m <组>`：一个组的成员
- `axs p u on`：打印当前 shell 的代理变量，需要 eval 才会生效
- `axs h` 或 `axs ?`：帮助

## 测试

在本目录执行：

```
sh tests/run.sh
```

这是离线套件。真内核另跑 `sh tests/lab/run.sh check`。

## 契约

行为见 [design.md](design.md)。术语与规则见 [design.md](design.md#模型与术语)。约束见 [constraints.md](constraints.md)。文件怎么摆见 [architecture.md](architecture.md)。还没授权的事见 [roadmap.md](roadmap.md)。健康检查的口径见 [design.md](design.md#健康)。
