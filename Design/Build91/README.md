# Build 91 · 灰紫塔罗半圆选牌

佳佳确认的灰紫稿见 `approved-purple.png`。从 `codex/memory-garden-build89` 的 `5d97680806922d64dc9677a8d5c80954f3b0beb6` 接出 `codex/tarot-semicircle-build91`；当时远端无 Build 90，佳佳回复「你做你的」后继续。

## 已定交互

- 灰紫织纹桌面、月蝶牌背、香槟细边。保留其他牌背入口，首次默认灰紫月蝶。
- 点击洗牌：服务器一次锁定 78 张牌，视觉上交错洗牌后完整铺成半圆，两端留出余量。
- 点一下仅抬起预览；再点同一张，才滑到牌阵中。左右拨动可逐张预览，手指松开不会自动确认。
- 未提交前可把任意已选牌拖回牌扇，剩余牌按选择顺序补位。VoiceOver 也提供「放回牌扇」操作。
- 放满后才可翻牌。发送按选牌先后排列的序号；翻牌请求一旦发出就冻结选择，网络失败重试同一 deal、同一顺序。
- 逐张翻转，逆位牌面倒置。支持原来的大图检查与缩放。点击「交给柯」沿用 `[塔罗#id]` 聊天交接。
- 支持一张、三张、凯尔特十字；十字牌阵下方列出完整位置与牌名。大号辅助字体时把牌名移到列表，避免挤压牌扇。
- 尊重系统减弱动态效果设置；不使用循环发光或弹跳动画。

## 代码位置

- `KeApp/Features/Play/TarotView.swift`：原生 SwiftUI 牌桌、动作、选牌命中、翻面和网络阶段。
- `KeApp/Features/Play/TarotSelection.swift`：独立选牌规则、冻结重试和 deal 编解码。
- `KeApp/Features/Play/PlayView.swift`：移出旧的自动抽牌页面，原有入口和其他功能保留。
- `KeApp/Core/APIClient.swift`：新增 shuffle、pick；保持当前会话 Cookie 和 ChatLine 地址前缀。
- `KeApp/Theme/Theme.swift`：灰紫塔罗视觉参数。
- `KeApp/Assets.xcassets/Tarot*`：桌布与月蝶牌背；生成来源保存在 `asset-prompts.json`。
- `KeApp/Core/TarotPreviewData.swift` 和 `CompanionPreviewTransport.swift`：匿名本地接口夹具。
- `KeAppTests/TarotSelectionTests.swift`、`CompanionAPITests.swift`：状态、边界及网络契约测试。
- `KeAppUITests/TarotSemicircleInteractionTests.swift`、`TarotInteractionChecks.swift`、`CompanionInteractionTests.swift`：交互和截图。

## 交付范围

只改塔罗入口内部，不重做聊天、花园和其他 tab。版本号为 91。仅打包交核对，不 SSH、不改服务器、不部署、不上架、不打 `app-v` 标签。

完整 Xcode 编译、单测和 UI 测试由现有 GitHub Actions 的 Xcode 27 模拟器工作流完成。本机只有 Command Line Tools。最终运行编号、签名包校验及真机待验项目记录在交付说明。
