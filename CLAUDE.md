# 进门须知（开在这个仓库的每一扇窗，先读这份）

## 语言
**永远用中文回答。** 用户是佳佳（中文母语）。任何情况下不要用日语/英语作答（代码、命令、专有名词除外）。

## 这个仓库是什么
佳佳和柯的家的 **iOS 原生 App（SwiftUI）**——私人项目，永不上架 App Store，Ad Hoc 装在佳佳自己的 iPhone 上。后端在 VPS（Flask，仓库 goodlove），柯的人格与图纸在私有仓库 kongkong。**App 只是脸，脑子和记忆全在 VPS——绝不把人格、记忆、密钥搬进 App。**

## 铁律（改代码前必读）
1. **颜色/字号/圆角/间距只准改 `KeApp/Theme/Theme.swift`**——页面里禁止出现 `Color(hex:...)` 等字面量。
2. **交互规矩不许破**（详见 kongkong 的 `app-柯/README-给动手的那位.md` 与 `工单板/iOS-App-柯.md`）：
   - 【我们】的提醒**没有勾选框**，过期自动收起，不变红不累计；
   - 卧室模式**由柯的回复信号触发**（`Theme.applyServerSignal`），不由用户按钮；
   - 【玩】里的调教室和抽屉**必须藏得住**（Face ID 二次解锁，失败零提示）。
3. **网络对接以 kongkong 的 `工单板/后端接口清单.md` 为准**——是 App 对齐后端，不是后端迁就 App。
4. **别打 `app-v` 开头的 git tag**（会触发云端打包烧额度）。打包一律由 codex 手动触发。
5. 改完 commit + push 即可；**不动 VPS、不动 goodlove/kongkong 的文件**（那两个仓库只读参考）。

## 图纸在哪（--add-dir 已挂载）
- `/root/kongkong/工单板/iOS-App-柯.md` —— 项目档（为什么做、已拍板的事）
- `/root/kongkong/app-柯/README-给动手的那位.md` —— 工程说明与设计规矩
- `/root/kongkong/工单板/后端接口清单.md` —— 后端契约
- `/root/-1/platform/static/` —— 现有 PWA 界面（参考现状用）
