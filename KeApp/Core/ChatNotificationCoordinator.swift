import SwiftUI
import UIKit
import UserNotifications

/// Retains a notification-open intent even when the root view has not mounted yet.
@MainActor
final class ChatNotificationCoordinator: ObservableObject {
    static let shared = ChatNotificationCoordinator()
    @Published private(set) var openRequest: UUID?

    func openChat() { openRequest = UUID() }

    /// 137：App 开着时来了推送（柯主动来信、分享小红书、被叫醒说的话……）。
    /// 聊天页看到它变了就去拉一次记录，不用点横幅、也不用切出去再回来。
    @Published private(set) var incoming = 0
    func noteIncoming() { incoming &+= 1 }

    func clearBadgeIfActive() async {
        guard UIApplication.shared.applicationState == .active else { return }
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
        // Do not remove medication or other delivered notifications indiscriminately.
    }
}
