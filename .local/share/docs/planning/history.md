# 待办历史

## 最近记录的变更

- [x] 将 `architecture.md` 重写为 Codex/开发者设计文档，将 `desktop-guide-zh.md` 重写为
  自洽的用户操作指南。两者均使用十个依赖布局（layout）；维护策略固定了不同读者和内容边界。
  全库文档检查通过术语、链接、路径、布局（layout）覆盖和文档关系验证。

- [x] 静态凭据扫描未在当前树或可达历史中发现私钥或高置信度 token 模式；已跟踪 Git 身份和
  既有历史作者元数据有意保留。

- [x] `11b758e`：通过 `BROWSER` 选择 Microsoft Edge，并移除剩余 Firefox 专用 DWM 规则。
- [x] `66846b6`：将 LF 图标移动至 `.config/lf/icons`。
- [x] `ac3e17b`：加入感知缓存的 `weath` 辅助命令。
- [x] `ddd0693`：使 `samedir` 能处理活动终端/LF 进程树。
- [x] `f228040`、`f7c5cfd`、`a84bd30`：将亮度、图形和 TeX 提案记录为延期，而不是改变
  未测试行为。
- [x] `f99558e`：为更多图像/文档格式加入 LF 预览。
- [x] `342b643`：通过 `rssget` 加入 RSS feed 发现并加固 `rssadd`。
- [x] `c1181c1`：将 PipeWire 感知静音整合进锁屏处理。
- [x] `508d029`：使 PATH 初始化在 shell 与 X11 启动中幂等。
- [x] `89d9aa8`：加固 shell 命令配置，包括 bare Git 命令补全路径。
- [x] `7deada6`：完成并记录第一轮配置审查。

## 第一轮配置审查

- [x] 验证 bare 仓库操作、根符号链接、shell 启动和 `c` 补全。
- [x] 检查 X11 启动、输入法选择、壁纸/pywal 回退、PipeWire 所有权、字体、GTK 和 Xresources。
- [x] 检查状态模块语法和当前环境问题。没有暴露 CPU 热传感器时 CPU 温度保持为空；NVMe 温度
  有意不视为 CPU 温度。
- [x] 检查 cron 文档、MIME 图像关联和包管理器可移植性。
- [x] 审查显示、挂载和亮度辅助命令。Android MTP 重试仅限首次授权失败；`xlight` 可容忍
  没有已保存状态。
- [x] 完成通用辅助命令的静态和语义审查：文件/MIME、下载/种子、媒体、文档、系统辅助和模板。
- [x] 修正录制控制、幻灯片/有声书时间码解析、PeerTube/RSS、文档编译和辅助命令错误报告边界情况。
- [x] 加固可选辅助命令对缺失依赖和失败队列的处理。

## 已采用的 Voidrice 启发工作

- [x] 加入 `sysact` 锁屏集成：锁定时静音 PipeWire 默认输出并暂停 MPD/MPV，只恢复原先未静音的
  输出；不自动恢复播放，音量刷新 DWMBlocks。
- [x] 加入 `rssget`：接收 URL 或剪贴板 URL，发现 feed，提供选择，并使用有限请求和唯一临时文件调用 `rssadd`。
- [x] 为 AVIF、DjVu、SVG、XCF 和 NDJSON 回退加入 LF 预览。
- [x] 将 LF 图标移动至 `.config/lf/icons`，使所有 LF 启动路径一致。
- [x] 通过活动窗口进程树查询加固 `samedir`，同时保留 shell/LF 回退。
- [x] 使用共享 XDG 缓存以 `weath` 替代过时天气别名。

## 其他已完成决定

- [x] 在 APT、pacman、XBPS 和 Portage 中统一 `p`、`pu`、`pi`、`pr`、`pse`、`pp`、`pl`、`pc` 包别名。
- [x] 将状态栏音量动作切换至 `wpctl`，同时保留 ALSA 回退配置和 `pulsemixer` 界面。
- [x] 使壁纸/pywal 行为可选，同时保留静态默认值。
- [x] 保持 PipeWire 用户服务所有权，并移除重复 X 会话启动。
- [x] 通过 `setbg` 统一 URL 壁纸选择；成功下载刷新可选 wal 颜色，失败下载保留桌面状态。
