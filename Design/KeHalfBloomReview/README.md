# 柯的 · 半朵山茶六入口交接包

2026-10-31。供 Claude 核对设计并在现有 iOS App 中实现。

**本包是交互设计原型和素材，不是 IPA，也不是已接入真实数据的 SwiftUI 页面。** 本次只新增这个目录，没有修改原生 App、版本号、服务器或发布配置。

## 先看什么

1. 下载并解压 `ke-half-bloom-six-review.zip`，用浏览器打开 [preview-standalone.html](preview-standalone.html)。GitHub 文件页本身不执行 HTML。
2. 阅读 [CLAUDE_REVIEW.md](CLAUDE_REVIEW.md)，按六个入口逐项核对现有功能。
3. [spec/interaction.json](spec/interaction.json) 是入口 ID、顺序、旋转参数和原生接入位置清单。
4. [screenshots/](screenshots/) 为本包实际运行截图；[verification.json](verification.json) 记录验证范围。

## 本次设计

- 右侧是一朵放大的粉色水彩山茶，中心位于容器右边缘，裁去右半边。左侧是功能区。
- 使用新生成的正面山茶，花心靠近图片几何中心。旧图的侧向花蕊和倾斜花杯会造成旋转时“歪”的感觉，不采用旧图。
- 六个入口按用户最新要求排列：**日记 → 梦 → 朋友圈 → 记忆 → 抽屉 → 塔罗**。
- 每档旋转 **60°**。旧五入口原型中的 72°、模 5 运算不能直接照搬。
- 拖动花朵会同步切换左侧选中项；松手就近吸附。点击左侧名称走最短角度；点击花朵前进一档；方向键也可切换。
- 切换只改变选择，不自动进入功能；点击下方动作文字才进入。返回后保留选择。
- 默认奶白底，保留浅粉预览。背景切换按钮属于设计审核工具，不要求成为 App 的产品控件。
- 英文使用 Baskerville / Georgia 斜体，中文使用系统宋体类回退。没有附带或分发字体文件。

## 文件

- `preview-standalone.html`：离线单文件预览，包含样式、脚本、图片和独立运行容器。
- `source-fragment.html`：可编辑的内联原型源码，包含同一份 JavaScript。
- `app.js`：从原型分出的交互逻辑，便于 Claude 阅读；修改后须同步到内联原型和导出文件。
- `assets/camellia-master.png`：1254 × 1254 透明母版，供原生接入。保持完整方形透明画布，不要自动裁边。
- `assets/camellia-preview.png`：620 × 620 透明预览图，与内联图片字节一致。
- `spec/asset-provenance.json`：素材提示词、来源及生成方式。
- `tools/check-preview.cjs`：Playwright 检查脚本，需本地已有 Node、Playwright 和 Chrome。
- `manifest.sha256`：压缩包之外所有交付文件的 SHA-256。

## 范围与真实数据

本轮只实现「柯的」入口页和六功能的路由示意。子页仅列出需保留的现有能力，**不是六个业务页面的新设计或已完成实现**。本包没有联网请求，不发送聊天、不抽真实牌、不改已读状态，也不写业务数据。原型只保存主题和选中的稳定入口 ID。

底栏的「柯」「我们」在本包中不可操作；原 App 的聊天、完整月历和其他功能由现有实现继续承担。源码保留了一些历史 CSS 选择器，不代表新增功能。本次「塔罗」入口以这份六入口清单为准，Claude 对接现有 TarotView，不另造一套抽牌逻辑。

当前仓库检查基点：`ffb71d8544e09f5d6d92d305b8d57a387b053f8b`（`codex/us-watercolor-review-20261029`）。此 SHA 只说明本次核对代码的来源；Claude 开始实施时应确认自己的最新工作分支，不用这份设计包覆盖更新的 App 代码。

这次交接分支：`codex/ke-half-bloom-review-20261031`。未合并、未触发 iOS 构建或发布，未部署为网站。
