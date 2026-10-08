# 便利贴抽屉、塔罗查看与卷轴核对 · Build 81

本分支 `codex/notes-tray-tarot-build81` 接在已交付的 Build 80 上，保留 79 的修复、80 的全屏日记、三层柜和单聊天。佳佳确认第一层纸条必须在抽屉内部；新包仍由 Claude 核对后走网页安装，GPT 不上架。

## 本次变更

- 用户从六版图标中选择 01：月牙托着山茶。单独生成正式图标，导出为 1024×1024、不透明、无预制圆角的 AppIcon，随本包安装。

- 第一层和第二层拉开后均进入完全打开的正俯视抽屉内部。佳佳、柯的真实便利贴轻微旋转、前后错落搭放在内底，纸色区分作者；两张一组，左右翻取更多纸条。卷轴也摆在第二层的抽屉内部，可在内底滚动查阅。空抽屉不生成示例便利贴。
- 点纸条进入全屏纸张：佳佳的可编辑，柯的只读；放回去回到原来的抽屉。新增保存继续用既有 StickyNotesStore、接口和缓存，“我们”页保持同一份内容。
- 补齐已选月光山茶设计的单张牌背。牌堆、洗牌、发牌背面、主题选择都用同一素材；一次性迁移旧选择到月光山茶，之后可以再自行换回。
- 具体塔罗牌面继续读取服务器抽到的原图，不把装饰牌背冒充 78 张牌面。点牌面全屏查看，双指缩放至 4 倍、拖动、双击还原／放大，上一张／下一张浏览已有牌；保留正逆位，不重新抽牌，不向柯发送消息。牌面载入失败可重试。
- 预览传输修正 URLSession httpBodyStream 的读取，隔离便利贴的成功回包能被验证；没有改生产服务器或正式接口。

## 卷轴：仓库链路存在，线上轻装柯待 Claude 确认

只读核对 goodlove 提交 `eb93c820d1ce3bdcc54cdee430de6b7b270f5db6`：

1. `platform/chat_ai.py:353` 的 DRAWER_ACTION_RULE 教柯 save / tease / release，并在 build_system_prompt 中加入；`_drawer_block()` 为模型提供私藏。
2. `platform/routes/chat.py:54` 从 ke_note 提取 drawer_action，`_apply_drawer_actions` 保存或公开；聊天流 `_process_private_note` 调用它并移除隐藏动作。
3. `platform/db.py:4012` 有 add_drawer_item、tease_drawer_item、release_drawer_item。`public_drawer_view` 只返回 released 正文和 teaser 外壳，private 不返回。
4. `GET /api/drawer` 由客户端读取。App 只将已公开的条目画成卷轴，没有另一个需要柯调用的“卷轴接口”。

在本机一次性 SQLite 上运行仓库已有的两项测试，均通过：`test_private_drawer_content_never_enters_public_view`、`test_drawer_can_leave_a_teaser_then_release_without_browser_write_api`。这只验证仓库数据库逻辑，不代表线上写入已验收。

请 Claude 核对当前轻装柯运行进程是否真的使用上述提示与动作处理，数据库是否和 `/ke-test1/api/drawer` 一致；精简开窗须知指向 KONGKONG_DIR 下的文件，本次未读取运行环境，不能确认实际内容。验收应覆盖柯发起保存、返回真实 ID、公开后 GET 返回同条正文、App 刷新出现并可读；口头说“放好了”不算成功。若线上缺连接或有不同协议，由 Claude 修复并安排部署，GPT 未改任何服务器文件或重启服务。

## 双弈「下一局」：客户端失败处理已补，真实登录后棋盘待核对

2026-10-08 无登录 Cookie 的只读 GET `https://jiagude.love/duel/` 返回 nginx 404 / text/html。进一步只读查看 ke-backup 提交 `122473db6920d4469f14388393eface93dbcc0d4` 的 `routes/duel.py` 与 `house_key.py`，确认这个地址经 Nginx auth_request 检查 `ke_home`，无钥匙也会隐藏成失败响应。因此 **公开 GET 404 不能证明游戏未部署或地址已失效**，此前推断已纠正。

App 仍使用仓库规定的 `/duel/`，只将这个 URL 范围内已有 Cookie 复制到 WKWebView，完成后才载入；没有跨路径扩大 Cookie、伪造钥匙或尝试解除服务端保护。此前 UI 测试用“牌桌已经摆好”的占位文字跳过 WebView，不能证明棋盘可用；本次移除，增加真实 WKWebView 导航响应、网络失败、进程终止处理及重试／关闭。

隔离 UI 测试通过 WKURLSchemeHandler 发出 cannotConnectToHost，让真实 WKNavigationDelegate 处理失败并验证重试和返回；不是线上对局验收。自定义 scheme 的 HTTPURLResponse 在 WebKit 中丢失 HTTP 状态，首轮 404 模拟方式无效，已改用真实导航错误。生产 HTTPS 的非 2xx 状态仍由导航响应处理。

**下棋尚未验收通过**。请 Claude 先在已登录的 iPhone 查看 `/duel/` 是否带有有效 `ke_home`，再分别核对家门鉴权、Nginx 转发、棋盘服务和当前柯会话绑定，避免只凭公开 404 重启服务。若网页能开，再核对实际落子、柯响应与重开一局。GPT 没有读取设备 Cookie 值、没有修改服务器或重启，也没有用离线电脑对手冒充柯。

## 审核安装包（尚未上架）

只使用 [Build iOS 37859282090](https://github.com/jia01226/ios-client/actions/runs/37859282090) 的 `KeApp-ipa` artifact 中的 `柯.ipa`。本轮早些时候同号的中间包均不要用。

- 源码：`af3a07d760921298eea93c840b37338641511433`；版本 `0.1.0 (81)`；Bundle ID `love.jiagude.ke`。
- 大小：`66346168` bytes；SHA-256：`ca57e759c5a60e5039e9ff4dd6052d0957c36793e8999e154d4f2f43d41d1e36`。
- 本机解包核对 Info.plist；`codesign --verify --deep --strict` 通过，签名 Team `527CR3MRV2`、生产 APNs、`get-task-allow=false`。
- 亲眼查看 IPA 内编译图标（仅将 iOS 优化 PNG 解码用于查看）：确认为选定的粉色月牙山茶。没有改签名包。
- 安装页和服务器均未修改；Claude 核对后再安排网页安装。

## 验收记录

[模拟器核验 37859119077](https://github.com/jia01226/ios-client/actions/runs/37859119077) 通过：87 项单元测试零失败；1 条完整 UI 场景（150.072 秒）零失败，覆盖四格切换、全屏日记翻页／选日、白天与深夜抽屉、便利贴阅读／新增／跨页面共享、塔罗牌背／全屏／缩放／换牌，以及双弈故障重试／关闭。

环境是 **iPhone 18 Pro 模拟器 / iOS 27.0**，不是佳佳的 iPhone 14 Pro Max。使用隔离数据，测试没有向生产聊天、便利贴或棋局写入。应用源码和正式 IPA 对应同一提交 `af3a07d`；之后提交只追加交付文档及截图。

| 亲眼验过 | 没验过／交 Claude 核对 |
| --- | --- |
| CI 原始截图：纸条在正俯视抽屉内部，两张略微倾斜重叠；白天和深夜仍是粉色实物质感；纸条放大可读，新建后在抽屉与我们显示同一内容。 | 14 Pro Max 真机触感、性能、字体缩放；真实便利贴服务的在线写入与跨设备同步。 |
| 珍珠柜关合画面、卷轴位于抽屉内部、封蜡提示、展开信纸及落款；测试断言私密正文和 teaser 正文不进入 UI。第二层内容在抽屉内滚动，截图只显示顶部一段。 | 柯在线自主保存／公开卷轴；实际轻装进程提示和数据库连接。 |
| 月光山茶牌背、逆位原始牌面全屏、双指放大画面；测试验证换牌和还原后仍为同次结果。 | 78 张服务端牌面不是这次重新画的；原图分辨率仍限制放大清晰度。 |
| 全屏日记正文、选日期界面；UI 测试确认翻页后日期变化、阅读时底部 tabs 不可点击。 | 实际服务器分页、长日记、缺页场景的真机体验。 |
| 双弈真实 WKWebView 导航失败后出现重试／关闭；测试再次失败也能退出回到玩。 | **棋盘能否在登录后打开、真实落子及柯的回应仍未验收，不称为已修好。** |
| 安装包 0.1.0 (81)、有效签名、正式新图标与生产 APNs。79、80 的提交均是本分支祖先。 | 网页上架与安装；本次未上架。 |

聊天保留单个“柯”，Thinking 相关实现未改。`01-chat.png` 原始截图被既有运动权限弹窗遮住，**不作为完整聊天外观验收**；保留原图并如实标注，未修图去除系统弹窗。其后 UI 流程正常继续。当前到家提醒入口已撤下，请 Claude 后续确认旧提醒协调器是否仍需首次启动即申请运动权限。

共 26 张原始附件及来源记录见 [截图目录](screenshots/notes-tarot-build81/README.md)。

素材与完整生成提示见 [notes-tray-tarot-assets.md](notes-tray-tarot-assets.md)。
