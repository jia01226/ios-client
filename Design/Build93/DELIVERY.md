# Build 93 · 塔罗输入、牌阵切换与自动发送

## 版本

- 基线：`claude/build92`，`e9980dc535c62b0584702392cfd02cf0c9e9e324`。
- 分支：`codex/tarot-fixes-build93`，Build 93。
- 保留 92 的花园、灰紫牌桌、完整 78 张牌扇及洗牌／抬起／放牌／翻牌动画。
- 仅通过 GitHub Actions 编译测试、导出 Ad Hoc IPA。没有 SSH、重启、部署或发布操作。

## 修复

1. 问题框：移除洗牌后的禁用；点击输入框空白和边框内区域也能聚焦，装饰边框不拦截触摸。输入时有“完成”收键盘。翻牌前可补写／改写问题，发给柯采用最后写的文字。改问题不重新洗牌；服务器 deal 仍保留洗牌时的问题，最新问题明确随聊天消息发送。
2. 牌阵切换：旧版 `deal != nil` 会同时禁用一张、三张、凯尔特十字。现在洗牌动画结束后可随时换牌阵，换阵收回旧牌、保留问题，再点洗牌开始新的一轮。牌扇和单张牌的手势在定位前绑定到自身边界，防止大容器抢走触摸；竖向滑动可以滚动十张牌的长桌面。
3. 交给柯：切到聊天页并自动提交包含问题和 `[塔罗#id]` 的消息。根页面保留待发送请求，聊天会话准备好再接收；相同请求只接收一次。使用原有发送、回执、失败与恢复流程，不占用聊天框草稿或待发附件。柯正在回复时也可提交。

## 文件

- `KeApp/Features/Play/TarotView.swift`：输入、切换、触摸、一次交接。
- `KeApp/Features/Play/PlayView.swift`：用最新问题组合解牌消息。
- `KeApp/RootTabView.swift`、`KeApp/Features/Chat/ChatView.swift`、`KeApp/Features/Chat/ChatViewModel.swift`：待发送请求及自动发送。
- `KeApp/Core/TarotPreviewData.swift`、`TarotHandoffPreviewTransport.swift`：仅 DEBUG 的匿名牌面与发送回执夹具。
- `KeAppTests/TarotSelectionTests.swift`、`ChatForegroundRecoveryTests.swift`：问题文本、发送等待、去重、附件保留及回复中发送回归。
- `KeAppUITests/TarotBuild93InteractionTests.swift`、`CompanionInteractionTests.swift`：一／三／十张完整流程。
- `project.yml`：Build 93。
- `KeApp/KeApp.swift`：仅 DEBUG 的减弱动态验收入口；正式包无此逻辑。

## 验证记录

- IPA 与验收源码提交：`c51789967daae6e449f61dc611b618f6c265e5df`。后续交付说明提交不改应用代码。
- [模拟器完整验收通过](https://github.com/jia01226/ios-client/actions/runs/38356847236)：148 项单测零失败；一组 UI 全流程零失败，覆盖一张／三张／十张，耗时 226.53 秒。
- 环境：Xcode 27，iPhone 18 Pro / iOS 27.0。未运行 iOS 17 模拟器；IPA 最低系统版本保持 17.0。
- 验收实际执行了：洗过三张后切到一张和十张；点问题框呼出键盘并输入；洗牌后再次补写；逐张第一次抬起、第二次确认，十张选满；三张拖回重选及逆位大图；翻开后直接跳聊天并自动发送，核对最新问题全文、编号和发送回执／回复路径。
- [Ad Hoc 打包成功](https://github.com/jia01226/ios-client/actions/runs/38356849778)；`CFBundleVersion = 93`，标识 `love.jiagude.ke`，`codesign --verify --deep --strict` 通过。
- IPA：`柯-Build93.ipa`，98,400,561 字节。
- SHA256：`247525e322ed0cf99a090628778a67503acf09d46bf129da54b16cc10e3dbb47`。
- 附 15 张原始模拟器截图。自动发送截图的回复为 DEBUG 匿名夹具；顶部“语录暂时没有同步成功”来自该夹具未提供语录响应，不作为现网语录结论。正式包已核对不含测试动画开关和匿名解牌文本。

一张牌走正常动画；三张、十张使用显式 DEBUG 减弱动态验收配置，避免模拟器系统键盘／玻璃动画让 XCTest 每次操作等待空闲 60 秒。正式版动画未关闭；真机仍需核对完整动画手感。

## 真机交接

本机没有完整 Xcode，也未连接可操作的 iPhone；不能把云端模拟器结果写成真机验收。自动测试的服务器与柯回复使用匿名夹具，并未向她的真实聊天发送测试消息。

请 Claude 安装包后，在真机上各走一遍一张、三张、十张：点问题框输入中文；洗牌后再补写；从三张切到一张／十张并重新洗牌；逐张点一下抬起、再点确认，选满翻开；点“交给柯”后检查聊天里问题与编号已发送，并核对真实柯回复提到本次牌面与正逆位。保留灰紫风格和动画要求。
