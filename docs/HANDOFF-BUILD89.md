# Build 89：记忆山茶花园、语录与便利贴同步

2026-10-12。供 Claude 核对代码、接口与候选安装包；不表示已经上架或装上手机。

## 交付位置

- 仓库 [jia01226/ios-client](https://github.com/jia01226/ios-client)
- 分支 `codex/memory-garden-build89`
- 基线 `codex/lockscreen-glass-build88`，提交 `5b9f27df166bc7a72b24b448ffccb636fd340e49`
- Build 以根目录 `project.yml` 的 `CURRENT_PROJECT_VERSION` 为准，本次为 89。
- 本次按用户授权提交、推送，并使用已有 `Build iOS` 工作流手动打包，输入 `build_number=89`。打包结果见下方「云端安装包」。不合并、不 SSH、不部署、不重启、不上架、不覆盖手机安装。Thinking 未改。

在任意已克隆本仓库的电脑上获取，不依赖原开发电脑用户名：

```sh
git fetch origin
git worktree add ../ios-build89-review origin/codex/memory-garden-build89
cd ../ios-build89-review
```

## 云端安装包

工作流为 `.github/workflows/ios-build.yml`（Build iOS），产物名 `KeApp-ipa`，保留 14 天。

- [Build 89 打包运行](https://github.com/jia01226/ios-client/actions/runs/38240991153)
- 打包源码提交 `536fe098e7005f1c19e57b99112c7988c3cc84ba`；本提交之后若仅补交付结果和文档，不改变 IPA 源码。
- 运行已完成，结果 **success**，Ad Hoc 签名安装包已生成：[下载 KeApp-ipa](https://github.com/jia01226/ios-client/actions/runs/38240991153/artifacts/11742709297)（通常需要登录 GitHub）。
- 下载并解包核验：`柯.ipa`，版本 `0.1.0 (89)`，Bundle ID `love.jiagude.ke`，Team ID `527CR3MRV2`；`codesign --verify --deep --strict` 通过，`aps-environment=production`、`get-task-allow=false`。这些是静态包核验，未执行真机安装。
- IPA 文件 SHA-256：`d2defc0cd77a7a7d8558bf6807e1f41f7b4fd3f95c8551db85d230e96e3b46bb`。这是解压 GitHub artifact 后的 IPA 校验值，不是 artifact ZIP 的校验值。

Claude 可在自己的电脑上通过已登录的 GitHub CLI 下载，无需原开发电脑路径：

```sh
gh run download 38240991153 --repo jia01226/ios-client \
  --name KeApp-ipa --dir ./build89-artifact
shasum -a 256 ./build89-artifact/柯.ipa
```

## 一朵山茶就是一条记忆

背景只有环境与枝叶，实际记忆花单独绘制。服务端 ID 是唯一身份；去重后每个可绘制 ID 只产生一个节点。空花园不会补装饰花。测试样例只存在 DEBUG 专用路径，不会写到真实记忆接口。

| 要调整的内容 | 代码入口（相对仓库根目录） |
| --- | --- |
| 真实接口、Cookie 与路径 | `KeApp/Core/APIClient.swift` 的 `memoryGarden`、`changeMemoryFlower` |
| 一朵花的数据、去重、显示条件、服务端状态 | `KeApp/Features/Memories/MemoryGardenModels.swift` 的 `MemoryFlower`、`MemoryGardenStore` |
| 分类对应场景、场景名字 | 同文件的 `MemoryScene.forCategory` / `title` |
| 花长在哪、大小、密度、地上花瓣 | `KeApp/Features/Memories/MemoryGardenCanvas.swift` 的 `MemoryFlowerLayout` / `plantingRegions` |
| 花颜色、花苞、花瓣、喜欢心光、旧记忆透明度 | 同文件 `GardenDrawingView.drawFlower`，普通与聚合共用 |
| 拖动、缩放、点选与远景聚合 | 同文件 `GardenScrollView` / `GardenDrawingView.draw` |
| 顶部花园/语录、详情、记错、找回 | `KeApp/Features/Memories/MemoryGardenView.swift` |
| 底部 tab 及语录跳回聊天 | `KeApp/RootTabView.swift` 的 `.memory` 与 `quoteOpenRequest` |

花的中心位置由 ID 与场景固定决定，新记忆加入不重排旧花。大小随 importance 与当前密度变化。远景显示真实节点的代表花丛和准确条数；放大恢复单朵，不把代表花的数量当总记忆数。大量重叠记忆可用「花朵列表」精确选择。

五个主要分区：约定 → 月下山茶；关系 → 水边山茶；生活 → 山茶城堡；身体 → 山茶庭院；喜好 → 玻璃花房。服务端额外分类保留，恋爱使用水边、医疗使用庭院，未知分类暂用庭院，不把数据改名。

`bloom/bud/fallen/withered` 以服务端状态为准，不由客户端擅自随时间变更。默认只显示 `author=ke`，开关打开才显示更淡的历史整理。操作等待服务器成功；失败明确提示并保留内容。详情展示服务端正文、最多三句原话、发生时间与写下时间。

## 语录与便利贴入口

- `AppQuotesStore.swift` 维护语录与书签共享状态，`AppQuotesView.swift` 提供备注、纸条、日常/床上分组及删除确认。只有床上默认折叠。
- `ChatMessageViews.swift`、`ChatCollectionTimeline.swift`、`ChatView.swift` 增加长按收藏/取消与书签。仅柯已发送完成且有真实服务器消息 ID 的消息可以收藏。
- `ChatViewModel.revealQuotedMessage` 使用原有 `around_id` 拉取定位。当前会话内未加载的消息可定位；跨历史会话、已删除消息或服务端找不到时明确提示失败，不创建假消息、不切换服务器会话。**跨历史会话跳转尚未完整验收**，若工单要求任意历史会话都能跳转，需要核对服务端的 message → session 定位合同。
- `StickyNotesStore.swift` 处理 `acked/acked_at`、ack/unack 与 83 版旧本机收起状态迁移；`MoonStickyNotesView.swift` 在收起/放回时等待服务器确认。
- 旧收起 ID 逐条确认成功后清掉，失败保留以便重试。服务端当前列表找不到的旧 ID 不擅自丢弃。用户旧草稿不上传、不删除。

## 修改范围

除以上文件，还修改 `KeApp/Core/CompanionPreviewTransport.swift`（DEBUG 验收路由）、`project.yml`、`KeAppTests/CompanionAPITests.swift`、`KeAppTests/StickyNotesStoreTests.swift`、`KeAppUITests/RootTabBarTests.swift`。

新增 `KeApp/Core/MemoryPreviewData.swift`、`KeAppTests/MemoryGardenTests.swift`、`KeAppUITests/MemoryGardenUITests.swift`、八组 `Memory*.imageset`（Moon / Water / Castle / Courtyard / Glasshouse / Bloom / Bud / Petals），以及 [Design/Build89](../Design/Build89) 中的截图、生成提示词与确认图。设计约束见根目录 `PRODUCT.md` 与 `DESIGN.md`。

## 本机复现

在交付工作树运行：

```sh
xcodegen generate
xcrun simctl list devices available
# 将 SIMULATOR_ID 替换为上一条命令列出的可用设备 ID。
xcodebuild -project KeApp.xcodeproj -scheme KeApp \
  -destination 'platform=iOS Simulator,id=SIMULATOR_ID' \
  -derivedDataPath /tmp/loveapp-build89-derived \
  -only-testing:KeAppTests \
  -only-testing:KeAppUITests/MemoryGardenUITests \
  -only-testing:KeAppUITests/RootTabBarTests \
  CODE_SIGNING_ALLOWED=NO test
```

本机验证环境为 Xcode 27 / iOS 26.5 模拟器。换机器时替换 destination。工程由 XcodeGen 生成，源码与资源随分支获取，无需原开发电脑上的 `.xcodeproj`。

## 验证记录

最终回归通过 **133 项单元/接口测试、7 条模拟器 UI 流程**。测试采用匿名本机接口响应，未读写用户真实记忆、语录或便利贴。

- 原开发电脑的结果包为 `/tmp/loveapp-build89-round2.xcresult`，日志 `/tmp/loveapp-build89-round2.log`；这些是本机测试记录位置，不是另一台电脑的下载入口。仓库内有下面的截图，可按上述命令复跑测试。
- UI 覆盖五场景、喜欢/取消、记错/找回、默认过滤及空态/失败态区分、647 条夜间缩放拖动、大字列表、语录收藏/书签/跳转/删除确认、便利贴收起放回、五 tab 回归。
- 数据检查覆盖重复 ID、647 个唯一节点、ID 位置稳定、稀疏可读尺寸与种植区域、聚合总数与边界避让、失败不伪造成功、接口 Cookie/路径/请求体、便利贴部分迁移失败重试与新本机状态恢复。
- Release 配置的**无签名模拟器编译**成功，日志 `/tmp/loveapp-build89-release.log`。这不是正式 IPA，也不是设备签名验证。
- [Design/Build89](../Design/Build89) 下的 `89-*.png` 是最后一轮模拟器截图；其 `Approved/` 是用户确认的设计参考，二者不要混淆。截图中的「匿名记忆」不是真实个人记录。
- `git diff --check` 通过；八个新增图像资源的 prompt 元数据扫描为 `8 rasters, 0 missing`。
- 独立界面复核结论为 **ship**，仅针对其列出的 F1–F4 修正清单：花朵可辨识尺寸、顶部构图与控件对比、聚合保留数据语义、场景种植区域及聚合避让均 resolved。这不表示全 App、真实服务器或真机性能已认证。

Claude 仍需核对：

1. 真实登录 Cookie 下的 GET 解码，以及经用户允许的喜欢、记错、恢复、收藏/删除、ack/unack；重新进入与重新安装后的服务端恢复。
2. 跨历史会话的语录跳转合同与体验。
3. 真机 600 多条的帧率、内存、触控命中、VoiceOver、大字号与昼夜观感。模拟器手势流程及布局耗时不能证明真机不卡。
4. 核对云端签名安装包及真机安装体验；设备安装和上架不在本轮执行范围。

## 图像资源来源

五个环境与三种花朵状态素材使用内置 image_gen 生成，并复制到工程 `KeApp/Assets.xcassets/` 对应 imageset，工程不依赖 Codex 私有目录。完整最终 prompt 集保存在 `Design/Build89/` 的八个 `Memory*.prompt.txt`，也嵌入了 PNG 元数据；扫描结果为八张资源均有 prompt。素材是独立环境层与透明花朵层，不含硬编码的真实记忆文本。
