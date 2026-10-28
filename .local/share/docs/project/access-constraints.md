# 访问子系统 · 约束

行为、开关和 health 的口径见 [access-design.md](access-design.md)。术语与规则见 [access-design.md](access-design.md#模型与术语)。本文只写边界。

## 隐私

- 订阅地址、机场名、凭据、密钥、节点名、端口、控制器、内网段：不进主仓库，不进跟踪文档，不进轮次档案。
- 地址与密钥只存在 `run/` 的 0600 文件。命令与日志不打印。文档写「运行时读取」。
- 操作者自己的终端可以显示组名和延迟。这些输出不写入档案。
- 回环与私网的具体写法由代码在运行时生成，不写进文档。

## 仓库边界

- 代码在 `.local/lib/access/`。测试在 `.local/share/test/access/`。六份文档在 `.local/share/docs/project/`（`access-system.md`、`access-design.md`、`access-architecture.md`、`access-constraints.md`、`access-roadmap.md`、`access-testing.md`）。
- `run/` 不入库。根 `.gitignore` 忽略 `.local/lib/access/run/`、`.local/share/test/access/lab/var/` 和 `.local/share/test/access/**/__pycache__/`。实现目录的 `.gitignore` 再忽略 `run/`、`__pycache__/` 和 `*.pyc`。
- 订阅地址和密钥仍只在 `run/`。禁止把该目录加进提交。
- 撤回并入用 `git revert -m 1 <subtree merge>`，不要用不带 `-m` 的 revert。
- 只读归档是 `~/src/access-2026-10-28.git`。

## 回滚

系统里一旦装过，按这个顺序撤：

1. `systemctl --user disable --now` 停掉服务和刷新定时器。还没安装就跳过。
2. 删除 `run/`。地址、密钥、配置、备份和开关都在这里。开关删除后，登录脚本不再导出代理变量或桌面标识。
3. 不改 shell 里现有的 `setproxy`。
4. 代码撤回用 `git revert -m 1 <subtree merge>`。不要删掉还在用的工作树。

## 明确不做

- 不改其它工具的命令，不用包装器占名。
- 不读其它代理程序的配置或数据目录。
- 不做 TUN、登录前代理、跨机器部署。未启用 TUN 之前，不得写成对其它工具已经无感。
- 透明性、三层开关和 health 的细节不在这里复述。
