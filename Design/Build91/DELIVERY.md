# Build 91 · 灰紫塔罗半圆选牌交付

给 Claude 核对后再上架。安装包是 `柯-Build91.ipa`，本次没有 SSH、服务器变更、部署或上架，也没有创建 app-v 标签。

## 分支与安装包

- 仓库：jia01226/ios-client
- 分支：`codex/tarot-semicircle-build91`
- 安装包源码提交：`406054898b546b6271851f6da72e9ab5e598398f`。后续提交仅补本交付说明，不改 App 源码。
- 基线：`codex/memory-garden-build89` / `5d97680806922d64dc9677a8d5c80954f3b0beb6`。当时没有远端 Build 90，佳佳回复「你做你的」后从最新花园 89 接出 91。
- Build：91；Bundle ID：love.jiagude.ke；最低系统：iOS 17.0。
- Ad Hoc 签名已核验：`codesign --verify --deep --strict` 返回 valid on disk / satisfies its Designated Requirement。
- 安装包 SHA-256：`833a50e648db6c023d8e6aacaff8dc8ef08114bb5e5617f5b071af4adea7ee72`
- 安装包大小：82,838,226 字节。
- [签名打包成功记录](https://github.com/jia01226/ios-client/actions/runs/38343636645)
- [单测与界面验收成功记录](https://github.com/jia01226/ios-client/actions/runs/38343635214)

## 这版做了什么

灰紫织纹桌面、月蝶牌背与香槟细边，按佳佳确认的紫色图落地。78 张牌完整铺成半圆，两端留有余量。

先洗牌锁定一副牌；点一下只抬起预览，再点同一张才滑到牌阵。点另一张会更换预览，左右划动可扫过牌扇；松手不自动确认。未提交前，可以把已放到桌上的牌拖回牌扇重选。余下牌保持抽取先后顺序。

放满后点击翻牌，按顺序逐张翻开。逆位牌面旋转 180°。保留点牌看大图和缩放功能；「交给柯」沿用原有消息格式和 `[塔罗#id]`，回到聊天页。

一张、三张、凯尔特十字均已接入。十字牌阵的位置说明在下方列表；辅助功能大字号时，牌名与位置也放入列表，避免挤在牌面上。动画包括交错洗牌、展开半圆、抬起、移动和逐张翻转，系统减弱动态效果开启时跳过这些动画。

接口使用 `POST /api/tarot/shuffle` 与 `POST /api/tarot/pick`，沿用当前线路地址和 Cookie。第一次提交翻牌后冻结 deal 和 picks，网络错误重试保持同一请求，不自动重新抽牌。超过一小时的失效错误会提示重新洗牌。

## 核验与真机待验

最终源码提交已通过 141 项单测、1 个完整 UI 自动验收入口（内含三种牌阵、夜间、大字号场景），并保留 11 张实际截图。环境为 Xcode 27.0、iOS 27.0、iPhone 18 Pro 模拟器。

自动验收检查了：第一次点击只预览、第二次确认、拖回重选、三张牌翻开、逆位大图、聊天消息包含 `[塔罗#7]`、一张及十张牌阵翻开、大字号牌扇显示。接口测试覆盖顺序、重复/越界选牌、Cookie/线路前缀、超时原请求重试与失效错误。单张牌和十字编号的截图已另做视觉核对。

shuffle/pick 使用匿名本地夹具；聊天交接截图确认文字进入聊天，但夹具不提供真实 SSE 回复，因此截图里的「没发稳」不是一次现网发送结果。牌面图片沿用测试静态资源。本次未对真实会话抽牌、发消息或验证柯的实际解读。

请 Claude 真机核对：完整三张流程的触控与动画手感、减弱动态效果、实际服务器的选牌及解读，以及 iOS 17 / iOS 26 的运行表现。以上系统和真机未在本次运行验证。

## 改动文件

- `Design/Build91/README.md`
- `Design/Build91/approved-purple.png`
- `Design/Build91/asset-prompts.json`
- `KeApp/Assets.xcassets/TarotLavenderCloth.imageset/Contents.json`
- `KeApp/Assets.xcassets/TarotLavenderCloth.imageset/artwork.png`
- `KeApp/Assets.xcassets/TarotMoonButterflyBack.imageset/Contents.json`
- `KeApp/Assets.xcassets/TarotMoonButterflyBack.imageset/artwork.png`
- `KeApp/Core/APIClient.swift`
- `KeApp/Core/CompanionPreviewTransport.swift`
- `KeApp/Core/TarotPreviewData.swift`
- `KeApp/Features/Play/PlayView.swift`
- `KeApp/Features/Play/TarotSelection.swift`
- `KeApp/Features/Play/TarotView.swift`
- `KeApp/Theme/Theme.swift`
- `KeAppTests/CompanionAPITests.swift`
- `KeAppTests/TarotSelectionTests.swift`
- `KeAppUITests/CompanionInteractionTests.swift`
- `KeAppUITests/TarotInteractionChecks.swift`
- `KeAppUITests/TarotSemicircleInteractionTests.swift`
- `project.yml`

截图目录按 01–11 排序：完整半圆、抬起预览、三张背面、翻牌后、逆位大图、聊天交接、夜间单张、十字选牌、十字翻牌、大字号顶部、大字号牌扇。确认稿与素材提示词保存在仓库 `Design/Build91`。
