# 珍珠抽屉与全屏日记 · Build 80 审核交付

基线为安装页第 79 版，分支 `ke/app-1008-141329`，提交 `8f40b281d7aaa166c5a999c1d4efac95b67e4395`。本分支 `codex/moonlight-keepsake-build80`，PR：https://github.com/jia01226/ios-client/pull/4 。交付前再次读取 goodlove 工单，安装基线仍为 79。

## 最终行为

- 粉色正面三层柜，绢面水波纹、贝母细边、五颗珍珠拉手；无拉手飘带，页面只留英文 keepsakes。
- 第一层放佳佳和柯的既有便利贴，点击拉手或文字入口后放大抽屉，纸条使用原生阅读／编辑界面。复用现有 StickyNotesStore、账户缓存与接口；“我们”页入口保留，两处共享。没有数据就留空，不生成示例内容。
- 第二层放柯公开的卷轴，能点开、拖开和收回。已公开卷轴点击后向下展开，原生正文可选取，落款柯和上海日期；关闭先卷回。
- 最下层一直锁住，没有私密内容入口。teaser 只有提示、不开封；private 与未知可见性字段不进入展示模型。保留要求的辅助功能标识。
- “柯的”仍默认日记，保留日记／抽屉切换。点封面或翻开入口后全屏阅读，遮住底部标签栏；有封面展开／合上、UIKit 纸页翻动和日期选择。全屏日期入口有独立标识，阅读时封面层从辅助功能树隐藏。
- 聊天只保留一个“柯”，沿用 test1 路由与缓存；Thinking 未修改。79 版纪念日、经期、日记数据修复保留。
- 素材随 App 入包，运行时色值统一在 Theme；夜间乘色保留粉色。支持减少动态效果。

最新的三层顺序、便利贴放大、去掉中文标题、全屏日记来自佳佳在本会话的后续确认，优先于工单中旧的两层描述。

## 请 Claude 只取这一包

- Build iOS 成功：https://github.com/jia01226/ios-client/actions/runs/37769557837
- Artifact：`KeApp-ipa`；其中 `柯.ipa` 对应代码 `4e1eedfa1d6a1a0910ad002c8334b2e1556ce502`。
- `0.1.0 (80)`，Bundle ID `love.jiagude.ke`，最低 iOS 17，63,944,140 字节。
- SHA-256：`ad884d4aa16254b5b6a77eaa9184bd4504a66fbb04046b76b79d880f447aa0e5`。
- 原生 ditto 解包后 `codesign --verify --deep --strict` 通过。应用签名标识 `527CR3MRV2.love.jiagude.ke`；推送 `production`；`get-task-allow=false`。
- 同号中间构建 `37765015691`、`37767026612` 均未上架，**不要使用**。上面的最新包包含最终顺序和日期入口修正。

```sh
gh run download 37769557837 --repo jia01226/ios-client --name KeApp-ipa --dir ke-build80-review
```

## 亲眼验过 / 没验过

| 亲眼验过 | 没验过 |
| --- | --- |
| 最终原生截图：日记封面、全屏书页、日期选择；日夜柜体关闭／拉开、卷轴列表、展开读信、便利贴放大。字体和正文未遮挡，柜体保持粉色。 | 佳佳的 iPhone 14 Pro Max 真机；当前截图设备是 iPhone 18 Pro / iOS 27，1206×2622。 |
| 日志核对：87 项单元测试和 1 条完整日夜 UI 流程通过，包含全屏翻页、底栏不可点、日期选择、合上、珍珠拉手拖动、蜡封不能打开、私密字段不显示、便利贴两处可见与收回。 | 生产服务器成功写入便利贴、柯端读到新便利贴、真实聊天／通知联调。UI 测试完全使用隔离数据。 |
| IPA 版本、SHA-256、完整签名、应用标识及推送签名权限。 | 网页安装到手机；尚未上架，由 Claude 审核后处理。 |

最终测试工作流**成功**：https://github.com/jia01226/ios-client/actions/runs/37770163489 。87 项单元测试无失败，日夜 UI 流程 112.7 秒通过，截图导出／上传均成功。[完整原生截图](screenshots/keepsake-build80/README.md)。PNG 原样拷贝，没有修图、重绘或改色；`provenance.json` 可对应 Actions 原始文件名、设备和时间。

便利贴新增截图中的“本机·待同步”来自隔离 UI 测试：现有预览传输只读取 httpBody，URLSession 的流式请求体未被该夹具读取，因此本次验证覆盖的是本地保存、两处共享和重启保留，**不能把它说成服务器同步成功**。正式保存接口与请求体构造沿用 79 版，没有修改；请 Claude 用真实账户再核对成功同步。

测试提交 `89e8822328ad72e6b9caee448b64e24fe8e80434` 与 IPA 提交之间只增加测试计划配置，App 源码、素材及签名设置相同。本地 Swift 语法、素材透明通道及 diff 检查通过。

测试计划保持原有两个测试目标，把 `diagnosticCollectionPolicy` 设为 `Never`，避免云端在测试结束后卡在 600 秒的系统诊断收集；断言、截图及测试结果全部保留。XcodeGen 2.46 本地生成并核对了目标 ID 和测试计划引用。[Apple 对诊断收集设置的说明](https://developer.apple.com/forums/thread/698054)。

## 交付边界

包交 Claude 核对后由 Claude 上架网页安装。本次没有 SSH、服务器修改、服务重启或安装页发布；没有发送真实聊天或写入佳佳的数据。截图里的文字来自测试数据，不是她的真实日记／便利贴。

素材出处与生成提示词：`docs/moonlight-keepsake-assets.md`。机器可读包验证：`docs/moonlight-keepsake-build80-verification.json`。
