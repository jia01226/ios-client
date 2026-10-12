# Build 88：锁屏照片玻璃候选包（第一批）

## 版本与交付

- 仓库：jia01226/ios-client。
- 分支：`codex/lockscreen-glass-build88`。
- 基线：`claude/glass-build84` 最新提交 `265e1b189080717b98d0d62cefd8857d06a33821`（Build 87）。
- Release 源码提交：`0efe865`；后续提交仅补测试、DEBUG 测试环境与本说明，Release 业务逻辑不变。
- Build：88；最低 iOS 17。最终 IPA 为 `KeApp-Build88-final.ipa`，请使用最终 ZIP 中的这一份，替换早先分享的候选 IPA。
- [Ad Hoc 打包运行](https://github.com/jia01226/ios-client/actions/runs/38203698866) 已成功。
- IPA：`KeApp-Build88-final.ipa`（下载原名 `柯.ipa`）。
- SHA256：`b3b681228e8d933c459e81551f4e93467727ab23b957e3bf3ee4d0fd21f3c60c`。
- 包内版本、Bundle ID、最低系统版本均已检查；Ad Hoc 描述文件含 1 台设备，生产 APNs，get-task-allow=false。
- 未修改安装网页、未部署、未 SSH 服务器。供 Claude 核对后上架。

## 本批完成

聊天设置 → 界面与气泡 → 聊天背景：纯色/照片；从系统相册选择，拖动、双指缩放后点“使用照片”。支持重新调整取景。

照片原图缩小后与裁剪结果保存在本机 Application Support。照片不进入附件上传流程。纯色切换保留已选照片，照片文件丢失/损坏时回到原背景。设置返回手势限定在屏幕左边缘，避免拖动滑杆触发返回。更换照片成功后才切换文件清单，旧图不会因读取或写入失败被覆盖。

背景模糊范围 0–20、默认 0；背景压暗 0–40%、默认 10%。滑杆在原有下半截设置面板里，修改后聊天背景立即更新并持久保存。

“锁屏玻璃”可独立开关。从纯色切到照片或首次保存照片时默认打开；关闭后恢复 Build 87 的气泡染色、输入栏和按钮样式，照片仍可保留。未选照片时也可打开，用原有光晕作背景。

锁屏模式气泡、输入栏、顶栏按钮使用原生 `glassEffect(.clear)`，无 tint；两边气泡同样透明，圆角继续由已有滑杆控制。正文白色，时间与 Thinking 等次要文字为白色 70%，文字阴影为黑色 25%、radius 2、y 1。旧系统用 `.ultraThinMaterial` 配合深色材质保证白字层级。发送按钮保留原有回弹反馈和主色底，箭头在锁屏模式下变白。

顶栏的动态字体上限设为 xxxLarge，避免无障碍大字号把状态文字与按钮挤在一起；聊天正文仍随系统大字体放大。

设置页与 Thinking 弹出页保持普通主题的可读配色。Thinking 原地展开与记忆 tab 属于下一批，本包未更改其交互。

## 改动文件

- `KeApp/Features/Chat/ChatWallpaperStore.swift`：本机照片与背景设置、照片解码降采样、替换失败保护。
- `KeApp/Features/Chat/ChatWallpaperSettings.swift`：相册选择、取景器、背景滑杆、锁屏开关。
- `KeApp/Features/Chat/ChatView.swift`：照片背景与设置入口、顶栏和输入栏白字/透明玻璃。
- `KeApp/Features/Chat/ChatMessageViews.swift`：无染色气泡与聊天正文、时间、Thinking、日期的白字层级。
- `KeApp/Features/Chat/ChatStatusViews.swift`：聊天状态和失败提示的玻璃及白字。
- `KeApp/Theme/CrystalSurface.swift`：仅为显式启用的聊天玻璃增加无染色与旧系统材质路径。
- `KeApp/Theme/Theme.swift`：聊天锁屏开关、颜色/阴影/取景器视觉令牌。
- `project.yml`：Build 88。
- `KeAppTests/ChatWallpaperTests.swift`：保存、重载、损坏回退、裁剪与组件截图。
- `KeAppUITests/ChatWallpaperInteractionTests.swift`：滑杆持久化、取景、输入、夜间大字体检查。
- `KeAppUITests/CompanionInteractionTests.swift`：复用现有 CI 入口执行照片用例；保留可独立运行的旧回归，无工作流权限变更。

## 验证边界

Release archive 与 IPA 导出已通过。[最终模拟器核验 38203697096](https://github.com/jia01226/ios-client/actions/runs/38203697096) 已成功：118 项单测全部通过，聊天照片整页流程通过，包括滑杆不退出面板、重启保持设置、缩放拖动取景与保存、键盘输入、夜间大字体及顶栏不与按钮重叠的位置断言。运行设备为 iPhone 18 Pro / iOS 27。

此前 [完整回归 38202343930](https://github.com/jia01226/ios-client/actions/runs/38202343930) 已成功：118 项单测 + 1 套组合 UI 流程，涵盖聊天照片设置、取景与保存、重启、键盘输入、夜间大字体，以及原有朋友圈、前台恢复和月光界面回归。本轮补上顶栏字体上限与位置断言后，仅重复相关聊天流程；旧回归仍可单独运行 `CompanionInteractionTests/testBuild83Regression`。

DEBUG 界面测试样例使用静止光晕，排除自动化空闲等待，正式包保留 84–87 的漂移动画。

需要 Claude/佳佳真机核对：iOS 26 原生玻璃折射、真实照片的相册选择与 iCloud 下载、亮/暗照片的白字观感、键盘出现时取景稳定、拖动背景滑杆时上半截预览、夜间和动态大字体。模拟器使用匿名色块测试图，真实相册/iCloud 选择仍需真机核对。当前云端环境只有 iOS 27 模拟器，iOS 17 材质分支尚未运行验证。
