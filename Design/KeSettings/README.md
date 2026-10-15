# 月隐 · 统一设置抽屉

这是独立网页设计预览，开关仅影响当前页面，不连接 App 或服务器。

在本目录运行 `python3 -m http.server 8774 --bind 127.0.0.1`，打开 <http://127.0.0.1:8774/>。默认展开目录；加 `?open=0` 从收起状态开始。资源、字体与示例数据全部随目录提供。由于使用 fetch 读取 JSON，请通过本地 HTTP 服务打开，不要双击 HTML。

- 右上小月牙、右边缘向左划都能打开；点左侧露出的底页、关闭按钮或向右划会收起。
- 八个入口各有一页设置。目录可上下滚动，窄屏不会压小触控范围。
- 底色里的四款纸色同步改变抽屉和三个示例底页；刷新后重置。
- 支持键盘 Tab、Escape，系统“减少动态效果”时取消空间动画。

Claude 接入前请读 [交接文档](../../docs/HANDOFF-KE-SETTINGS.md)。素材尺寸、来源与生成描述在 [asset-provenance.json](spec/asset-provenance.json)，位置和动效分别在 [layout.json](spec/layout.json)、[motion.json](spec/motion.json)。

测试：`node --test tests/preview.test.cjs`。

当前源码提取的设计记录见 [DESIGN.md](DESIGN.md)；设计面板记录见 [.impeccable/design.json](.impeccable/design.json)。视觉仍待继续确认。
