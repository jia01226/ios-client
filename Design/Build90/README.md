# 记忆花园探索样例

2026-10-13。已确认视觉方向的前端交互预览；交付状态与真实记忆接入分工见 [前端交接](../../docs/HANDOFF-BUILD90-FRONTEND.md)。未签名打包、未上线。

## 打开

在 Debug 模拟器构建中使用 `-ui-test-companion -ui-test-memory -preview-memory -preview-expedition -ui-test-scroll-control` 启动参数。`MemoryTabView` 仅在 DEBUG 且显式传入 `-preview-expedition` 时进入样例；普通启动继续使用已有记忆页。

样例有 647 条明确标注的匿名虚构记忆，探索视图不发起真实记忆请求、不读写真实记忆。喜欢仅保存在当前预览状态，关闭样例后不保留。

## 代码入口

- `KeApp/Features/Memories/MemoryExpeditionPreview.swift`：`MemoryExpeditionRoute` 将记忆按回想时间、回想次数、ID 排序，每片最多九朵，去重且不漏 ID；`sprite` 与 `angle` 用 ID 固定花型与旋转。
- `ExpeditionBush.layout`：五场景各自的独立花丛布局；`flowerPoint` 是花在枝叶上的锚点。所有背景、花丛和单朵花独立分层。
- `MemoryGardenExperience.visit`：取消前次点选，从飞行中的位置转向对应花朵，抵达后浮现该条记忆；切换分区或离开会取消延迟任务。减少动态效果时直接显示，不扇翅或拖尾。
- `SpiritButterflyFlight` 与 `SpiritFlightMotion`：左右蝶翼独立绕身体转动，身体保持不变形；短拖尾由有限段曲线绘制，落定后清零，不使用常驻计时器或无限粒子。时长和曲线以这两个代码入口为准。
- `move`：往深处／回程；读完不改变当前片区与镜头位置。列表可直接找到任意记忆并进入所属片区。
- `KeAppTests/MemoryExpeditionTests.swift` 与 `KeAppUITests/MemoryExpeditionUITests.swift`：样例的数据和原生交互验证。

## 当前范围

这是分景探索原型：可以轻拖、缩放、沿小路进入下一片花丛。深处以更少回想的记录为主；尚未实现连续无边界地图、角色行走、动态光照或生产数据接入。归档与纠错继续由原记忆页提供，本样例不提供模拟成功的服务器操作。

画面每片只绘制九朵数据花与三丛独立植物，不同时创建 647 个花朵视图。固定输入下位置、花型、角度保持一致；回想时间改变后排序可能移动片区，此规则仍待产品确认。模拟器测试不代表真机帧率验收。

## 素材

使用内置 image_gen 生成，未引入第三方仓库代码或图片。环境、独立花丛、三叶枝、花型与蝴蝶均为独立资源，位于 `KeApp/Assets.xcassets/Expedition*.imageset`；使用中的花型由 `MemoryExpeditionRoute.sprite` 定义，精灵蝶为 `ExpeditionButterflySpirit`。完整提示词为本目录 `Expedition*.prompt.txt`。环境的微小闭合绿芽为植物纹理，没有可点击身份；可点击的山茶均一朵对应一条样例记忆。

花朵与蝴蝶按最长边 512 像素、花丛 1024 像素缩小供原生渲染，透明通道保留；原有 Build 89 素材没有覆盖。原图由内置工具保留在本机生成目录。

## 本机验证与截图

分支 `codex/memory-garden-build90`，基于 Build 89 的 `5d97680`。当前只是本机开发样例，工程版本号仍为 89，未制作 Build 90 发布包。

2026-10-12 基线证据为 `/tmp/loveapp-build90-preview-confirm.xcresult`。2026-10-13 的精灵蝶与花型验证见本目录 `REVIEW-2026-10-13.md`。

本目录以下 PNG 均为这次运行的真实模拟器截图，内容为虚构样例：

- `90-01-moon-entrance.png`：月下入口。
- `90-02-memory-emerges.png`：点花后蝴蝶抵达、记忆卡片浮现。
- `90-03-deeper-garden.png`：更少回想的下一片花丛。
- `90-day-water.png`、`90-day-castle.png`、`90-day-courtyard.png`、`90-day-glasshouse.png`：四个白天环境。

视觉仍待用户确认。白天开关目前仅切换探索场景，外围状态区及底部导航保持测试启动时的夜间主题；本轮没有修改其他 Tab。静态截图无法展示蝴蝶飞行过程。

诊断入口仅供本机素材核对：在原启动参数后追加 `-preview-flower-study` 显示花型素材板；追加 `-preview-spirit-frame` 后点花会停在飞行中段，不打开记忆卡片。诊断截图须标注定格，不作为动画播放证据。正常体验不传这两个参数。

## 交给 Claude

用户已确认视觉并将真实记忆接入交给 Claude。可复用的前端主体为 `MemoryGardenExperience`，匿名数据由 Debug 包装层提供；普通启动仍是原记忆页。输入、回调、业务待接项与跨电脑文件说明统一见 [前端交接](../../docs/HANDOFF-BUILD90-FRONTEND.md)。
