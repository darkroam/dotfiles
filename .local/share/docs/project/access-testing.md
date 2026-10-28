# 访问测试

离线套件和真机 lab。脚本自己定位测试根和实现根，不依赖当前目录，也不读旧的独立 git 目录。

从仓库根执行：

```
sh .local/share/test/access/run.sh
```

这是离线套件。真内核另跑 `sh .local/share/test/access/lab/run.sh check`。

术语与规则见 [access-design.md](access-design.md#模型与术语)。
