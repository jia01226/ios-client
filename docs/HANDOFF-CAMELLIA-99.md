# Build 99 · 山茶四款配色核对

## 基线与范围

从 `claude/camellia-98` 的 `8aa2dea391658274fbed1d42daa201d50634b1fe` 创建 `codex/camellia-palettes-build99`。
用户要求：App 内可选浅雾蓝、冷白、暖白、浅米色，去掉原蓝；保留上一轮减淡的花枝、轻透蝴蝶与落瓣，并打包交由 Claude 核对。

仅改「柯的」页外观和该页的底栏衔接，不修改服务器、APIClient、内容 Store、入口映射或聊天主题。未合并、发布或安装到用户真机。

## 代码入口

- `KeApp/Theme/CamelliaPalette.swift`：四款配色、背景去色与雾层强度、花枝减淡 modifier。`defaultPalette` 为暖白；未知保存值也回退暖白。没有原蓝选项。
- `KeApp/Features/Play/KeCamelliaView.swift`：标题下的「山茶配色」原生菜单，使用 `@AppStorage(CamelliaPalette.storageKey)` 保存。退出/重开保留，不跨设备同步。花枝和花朵先合成再减淡，挂签、文字和点击范围不受滤镜影响；蝴蝶翅膀/身体统一轻透；卡片小图使用相同花枝处理。
- `KeApp/RootTabView.swift`：仅选中「柯的」时，底栏与底部安全区跟随山茶配色；离开后恢复既有主题。山茶页面本身始终为用户选定的浅色，不随聊天的昼夜设置变黑。
- `KeApp/KeApp.swift`：原有根层昼夜偏好移到 `RootTabView` 决定，让浅色山茶页使用可读的深色状态栏；打开原有业务页面时恢复原来的昼夜偏好。
- `project.yml`：候选 Build 99，版本名不变。
- `KeAppTests/CamelliaPaletteTests.swift`、`KeAppUITests/CamelliaPaletteUITests.swift`：颜色枚举、无效值回退、本机保存、四种选择、重启恢复、六个入口往返及夜间皮肤/大字号检查。

## 沿用 Claude 98 的连接

`KeCamelliaStore.load()` 仍通过 `fetchDiaries`、`fetchMoments`、`memoryGarden` 取数据，蝴蝶与底部卡片的事件选择不变；`destination(_:)` 的六个入口不变。
`petals(w:h:now:)` 保留 98 的原生落瓣，不把网页示例数据搬进 App。

`-ui-test-reduce-motion` 只在 DEBUG 下让本页遵循测试的减少动态效果选项，Release 仍读取系统无障碍设置。测试数据走既有 `CompanionPreviewTransport`，不向真实日记或朋友圈写入内容。

挂签属于固定尺寸画中标识，字形跟画布缩放、不再随系统大字号溢出；独立按钮仍有完整无障碍名称和至少 44pt 的命中范围。卡片在固定画布内将动态字号上限设为 xxxLarge，标题和配色菜单仍支持动态字号。这是局部适配，不是全 App 的无障碍验收。

## Claude 核对重点

1. 在「柯的」标题下切换四种颜色，重开 App，核对颜色保留和底栏衔接；切回聊天时原聊天配色不变。
2. 真机查看减淡程度、蝴蝶透明感和持续动画流畅度。网页滤镜与原生渲染不是逐像素相同，不能用代码参数相同代替真机视觉验收。
3. 用既有登录数据核对日记、梦、抽屉、朋友圈、塔罗、记忆入口，以及真实新内容对应的蝴蝶/卡片。模拟器匿名测试不能证明线上接口或真实数据正确。
4. 本次没有修订 98 的数据选择/刷新策略，也没有合并其他分支。

## 验证与安装包

- iPhone 14 Pro Max / iOS 26.5 模拟器，Xcode 27：4 项单元测试 + 3 条 UI 流程共 7 项通过，失败 0。UI 流程包括四款切色/重启恢复、六入口打开关闭、夜间皮肤与无障碍大字号。
- 实际模拟器截图及机器结果在 `Design/KeCamellia/Build99/`，不是网页截图或真机截图。`test-summary.json` 是测试工具直接导出的结果。
- 打开塔罗时测试记录了一条 `Invalid frame dimension (negative or non-finite)` 运行时警告；入口和返回断言通过，塔罗源码未修改。尚未定位警告来源，交给 Claude 核对，不宣称全 App 无警告。
- 未验证真实账号联网、真机持续动效性能或手机安装；没有生成真实内容。

安装包已通过仓库原有 `Build iOS` 工作流生成，供核对，没有执行 OTA 发布或真机安装。

- 打包源码提交：`9db507cb02d181c5644e983dcb50cc276933eb16`。后续交付记录提交只更新文档，不改变此安装包的源码。
- [签名打包工作流（成功）](https://github.com/jia01226/ios-client/actions/runs/38559437833)。
- [下载 KeApp-ipa](https://github.com/jia01226/ios-client/actions/runs/38559437833/artifacts/11891687590)，需要仓库访问权限；保留至 2026-10-28 19:52（台北时间）。
- 下载后本机静态核验：版本 `0.1.0 (99)`，Bundle ID `love.jiagude.ke`，严格签名校验通过；推送 entitlement 为 production，get-task-allow 为 false。此核验不代表已在手机安装或验证线上接口。
- IPA SHA-256：`f2806386ee9253d705da0fecc8ee1fe7b7b02b3a1261a1c17032fb5fdced9d65`。
