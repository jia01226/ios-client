import SwiftUI
import UIKit
import UserNotifications

/// Retains a notification-open intent even when the root view has not mounted yet.
@MainActor
final class ChatNotificationCoordinator: ObservableObject {
    static let shared = ChatNotificationCoordinator()
    @Published private(set) var openRequest: UUID?

    func openChat() { openRequest = UUID() }

    func clearBadgeIfActive() async {
        guard UIApplication.shared.applicationState == .active else { return }
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
        // Do not remove medication or other delivered notifications indiscriminately.
    }
}
