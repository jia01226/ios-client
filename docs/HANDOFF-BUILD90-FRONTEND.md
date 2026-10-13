# 2026-10-13 · 山茶花园前端交给 Claude

## 分工与当前状态

佳佳已确认五场景、九种山茶和半透明精灵蝶的方向。Codex 负责前端素材、场景和交互动效；Claude 负责接入真实记忆和完成业务验收。保留确认过的画风，不需要重画环境或重新搭版。

代码基于 `codex/memory-garden-build89` 的 `5d97680806922d64dc9677a8d5c80954f3b0beb6`，交付分支为 `codex/memory-garden-build90`。佳佳已授权将本批前端代码、素材、截图和交接说明提交到 GitHub；不制作安装包、不触发打包工作流、不合并、不上线。工程版本号仍为 89，不是已生成的 Build 90 IPA；由 Claude 接完真实记忆后在云端指定 Build 90。Thinking、服务器与真实数据均未修改。

`MemoryGardenExperience` 已从匿名预览中拆出，参与 Debug 和 Release 编译，但没有替换普通启动时的 `MemoryGardenView`。只有显式 Debug 预览入口使用它。匿名夹具、素材板和飞行定格参数均在 `#if DEBUG` 内。

## 前端接入入口

文件 `KeApp/Features/Memories/MemoryExpeditionPreview.swift`，入口 `MemoryGardenExperience`。文件名保留，但主体已不只在 Debug 下编译。

```swift
MemoryGardenExperience(
    flowers: snapshot,                 // [MemoryFlower]，由调用方过滤来源并传入
    categories: categoryNames,         // [String]，不要丢掉服务器额外分类
    initialCategory: "约定",
    night: true,                      // 初始化昼夜，组件内有本地切换按钮
    isPreview: false,
    isBusy: saving,
    interactionError: saveError,
    onOpenMemory: { id in /* 点花抵达或列表点选后的真实 ID */ },
    onLoveMemory: { id, loved in /* 保存目标值，成功后回传新快照 */ },
    onRequestCorrection: { id in /* 宿主负责填写纠错、确认、调用接口 */ }
)
```

- 组件不创建 APIClient，不发请求，不使用 Cookie，不做数据库或偏好写入。数据源与操作均由调用方持有。
- `onLoveMemory` 不会先在组件里伪造成功；图标和花心读取输入的 `loved`。未提供回调时按钮禁用，`isBusy` 防止保存期间重复点选；失败文案由 `interactionError` 传入。
- `onRequestCorrection` 未传时不显示「记错了」。组件不替调用方确认、不调用删除接口、不声称已保存。
- `onOpenMemory` 只报告打开事件，不写 `recall_count`。普通点花在蝶抵达后浮现输入记录，减少动态效果时直接显示。卡片展示正文、最多三句原话和两种时间。
- `MemoryExpeditionRoute.pages` 提供当前探索分片方案，按回想时间／次数／ID 排序，每片最多九条，去重且不漏可绘制 ID。这是浏览规则，不是服务端记忆归档规则。
- `ExpeditionBush.layout` 与 `flowerPoint` 是枝叶和种植点入口。`MemoryExpeditionRoute.sprite` 与 `angle` 决定固定花型和朝向；不要再用整片 sourceAtop 填色覆盖花瓣。
- `SpiritButterflyFlight` / `SpiritFlightMotion` 控制独立蝶翼、有限拖尾、减速落定。没有永久循环或常驻粒子，切换分区、离开页面会取消待浮现的记忆。

## Claude 继续的业务工作

1. 将既有 `MemoryGardenStore` 的真实快照连接进组件，默认过滤 `author=other`，保留开启历史来源的开关。现有真实接口及旧页留在仓库，不需重建协议。
2. 补齐业务状态的视觉映射：other 淡化、valence 的轻微调色、fallen 在地面、wither 成功后的枯落与找回。新组件目前未完整接入这些语义；旧 `MemoryGardenCanvas` 的实现仅可参考业务含义，不能把旧贴图视觉换回来。
3. 接好纠错确认、喜欢保存、回收与撤销。保存成功后才更新快照，失败保留原花。图上的一朵花必须始终对应一个真实 ID，不能复制装饰花凑数。
4. 将前端嵌入正式「花园 / 语录」导航，接现有加载、空态、错误、刷新和花朵列表；额外分类要能横向浏览。当前预览导航主要按五个确认场景排版，尚不是完整业务导航。
5. 分片里更少回想的记录在深处。当前不是连续无边界游戏地图；回想时间或输入集合变化可能改变片区／槽位。上线前明确稳定位置规则与列表跳回花朵的行为。
6. 完成真实登录接口、600 多条真机体验、系统减少动态效果、快速连续点花、动态大字与跨页恢复验证。当前本机匿名截图不能充当真实记忆或真机性能验收。

## 素材、截图与运行

- 新资源全部位于 `KeApp/Assets.xcassets/Expedition*.imageset`。提示词保存在 `Design/Build90/Expedition*.prompt.txt`，由内置 image_gen 生成并保留 alpha。
- 确认过的画面与素材核对截图在 `Design/Build90/Spirit/`；素材板不是产品页面，飞行中段图是诊断定格，不是视频。
- 本机预览启动参数：`-ui-test-companion -ui-test-memory -preview-memory -preview-expedition -ui-test-scroll-control`。
- 素材板另加 `-preview-flower-study`；飞行定格另加 `-preview-spirit-frame`。正式运行不得带匿名夹具参数。
- `KeAppTests/MemoryExpeditionTests.swift` 和 `KeAppUITests/MemoryExpeditionUITests.swift` 提供前端定向回归。旧记忆、语录、便利贴测试继续保留。

## 跨电脑取文件

本轮最终验证：`/tmp/loveapp-build90-frontend-final.xcresult` 中 8 项定向测试全部通过，0 失败、0 跳过；无签名 Release 模拟器编译通过，日志 `/tmp/loveapp-build90-frontend-release.log`。这只是源码编译验证，不是签名打包或真机验证。

请通过 GitHub 获取，不再依赖另一台电脑的 `/Users/Admin/...` 路径或本机文件包：

- [交付分支](https://github.com/jia01226/ios-client/tree/codex/memory-garden-build90)
- [本交接说明](https://github.com/jia01226/ios-client/blob/codex/memory-garden-build90/docs/HANDOFF-BUILD90-FRONTEND.md)
- [精灵版模拟器截图](https://github.com/jia01226/ios-client/tree/codex/memory-garden-build90/Design/Build90/Spirit)
- [素材提示词与前端评审](https://github.com/jia01226/ios-client/tree/codex/memory-garden-build90/Design/Build90)

拉取前先保留 Claude 所在工作树的现有改动；若已经有业务接入工作，逐项合并，不覆盖。上述测试日志为本机验证证据路径，不在仓库中；源码、测试、素材、截图均随交付分支提供。
