import SwiftUI

// 手表上的柯。她 2026-11-25：「我想手表上面有柯 app 安装，然后点击可以聊天，像手机那样」。
// 手表上只放聊天：看最近的话、说一句发给他。图片、日记、收藏、设置还在手机上。

@main
struct KeWatchApp: App {
    @StateObject private var link = WatchLink.shared

    var body: some Scene {
        WindowGroup {
            WatchChatView()
                .environmentObject(link)
                .environment(\.locale, Locale(identifier: "zh_CN"))
        }
    }
}
