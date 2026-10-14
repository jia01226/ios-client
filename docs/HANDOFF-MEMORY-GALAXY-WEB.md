# 记忆星河网页交接 · 2026-10-14

## 给 Claude 的入口

- 分支：`codex/memory-galaxy-web-preview`。
- 基线：`claude/starmap-94`，`98ed0ff752f5b886ee26c62eb9ed52a4698aa8fb`。
- 网页：[Design/MemoryGalaxyPreview](../Design/MemoryGalaxyPreview/README.md)。
- 主效果截图：[font15-applied.png](../Design/MemoryGalaxyPreview/review/font15-applied.png)。
- 字体选择截图：[fonts-slanted.png](../Design/MemoryGalaxyPreview/review/fonts-slanted.png)，用户明确选择 **15 号**。

本次只交网页源码、字体素材、许可证和截图。没有修改原生 App、版本号、MemoryGardenStore、Thinking 或服务器；没有合并、触发打包或部署网站。GitHub 可以查看代码与截图；动态效果需要在能运行网页的环境启动静态服务。

## 用户已明确的方向

- 近黑、微冷的天空，自然白色星光，粉紫只在局部低饱和星云里；拒绝整屏粉紫与霓虹旋臂。
- 银河中心最亮，星星有轻呼吸和偶尔轻闪。流星从右上到左下，时不时划过。
- 星图要有厚度、前后层次，不能像整块贴图。当前候选增加粒子 Z 厚度、透视、远近大小和亮度差、拖动视差及可变化的倾角。用户认可之前的大致外观，但纵深版本仍需她确认，不能把本次上传当作全面验收。
- 英文标题采用 **15 号**：Pinyon Script Regular，加 `skewX(-16deg) scaleX(.9)`。不要改回 Herr、Allura 或未选中的其他花体。参数与响应式字号见 `dist/style.css` 的 `.script`。
- 用户明确说记忆接入由 Claude 做，Codex 只做星图。这里没有真实记忆，也没有导入入口。

## 原生对接注意

保留 Build 94 的 MemoryGardenStore 与原有业务。每个可点星应绑定一条记忆 ID；真实数据、分类、作者过滤、喜欢、纠错、恢复与服务端同步由 Claude 继续处理。网页的星尘是环境粒子，不代表新增记忆；匿名示例不得回填服务器。

网页用 WebGL + Canvas + HTML，是效果参考，不是已经移植完成的 iOS 组件。投影在 `model.mjs/project` 与 `app.mjs/initGL` 顶点着色器中双份实现；改变一边必须同步另一边，避免星点与触点错位。内存里的示例按 `id` 绑定卡片，`position` 为三维坐标。

参考过基线 `MemoryStarMapView.swift` 的分层视差与固定 ID 布星思路，没有替换该原生文件。原生迁移时应沿用已有真实记忆映射，不按示例数组序号给旧记忆重新排位置。

## 本次检查与限制

- `node test.mjs` 通过：示例 ID 唯一、中心星、固定种子 52000 粒子、投影、初始目标间距、近大远小/视差、粒子厚度、流星方向与间隔、呼吸数值范围。
- `node --check` 检查主逻辑和模型语法。
- 本机窄屏浏览器观察字体加载与倾斜矩阵、无横向溢出；分类筛选、点星和卡片打开验证过。截图保留最终选定字体。
- 未验证 iPhone 14 Pro Max 真机、3× 截图、持续帧率/耗电、600 条真实记忆同时显示、完整 VoiceOver、双指真机手势。数据容量不能从 52000 环境粒子数量推断。
- 本次没有录制新的视频，也没有重新进行完整独立视觉审查；不要套用前几轮候选的通过结论。

下一步先让用户确认网页星图，记忆适配与原生整合由 Claude 处理；发版另行确认。
