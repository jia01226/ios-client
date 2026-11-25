import SwiftUI

// App 入口。
// 名字就叫「柯」——她 2026-08-14 13:22 自己定的。

@main
struct KeApp: App {

    @StateObject private var theme = Theme.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            appRoot
                // 123 她：日期选择是英文的。整个 App 的日期、系统按钮都按中文来
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .environmentObject(theme)
                .tint(theme.effectiveAccent)
        }
    }

    private var appRoot: some View {
        RootTabView()
    }
}

// MARK: - AppDelegate（APNs 注册与前台通知）

import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// 11-25 手表回柯：服务器给柯的聊天通知带上这个类别（APNS_CHAT_CATEGORY），通知上就多一个「回复」
    static let replyCategory = "KE_REPLY"
    static let replyAction = "KE_REPLY_ACTION"

    private func registerReplyCategory() {
        let reply = UNTextInputNotificationAction(
            identifier: Self.replyAction,
            title: "回复",
            options: [],
            textInputButtonTitle: "发送",
            textInputPlaceholder: "跟柯说…"
        )
        let category = UNNotificationCategory(
            identifier: Self.replyCategory, actions: [reply], intentIdentifiers: [], options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// 通知里带的 url 形如 /?session_id=12&message_id=…；拿不到就给 0，服务器会落到当前那扇窗
    private static func sessionID(from userInfo: [AnyHashable: Any]) -> Int {
        guard let raw = userInfo["url"] as? String,
              let items = URLComponents(string: raw)?.queryItems,
              let value = items.first(where: { $0.name == "session_id" })?.value,
              let sid = Int(value) else { return 0 }
        return sid
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-test-reduce-motion") {
            // System keyboard/glass animations can prevent XCUITest from reaching idle.
            // Only this explicit accessibility fixture disables UIKit animations.
            UIView.setAnimationsEnabled(false)
        }
#endif
        UNUserNotificationCenter.current().delegate = self
        registerReplyCategory()
        PushRegistrationCoordinator.shared.prepareAtLaunch()
        LocationContextReporter.shared.prepareAtLaunch()
        _ = HomeReminderCoordinator.shared
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushRegistrationCoordinator.shared.receivedDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[push] 注册失败：\(error)")
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if response.actionIdentifier == Self.replyAction,
           let input = response as? UNTextInputNotificationResponse {
            let text = input.userText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let sid = Self.sessionID(from: response.notification.request.content.userInfo)
            do {
                try await APIClient.shared.sendFromNotification(text: text, sessionID: sid)
            } catch {
                print("[push] 通知里回的没发出去：\(error)")
                // 没发出去要让她知道，不然她在手表上等一个永远不来的回复
                let note = UNMutableNotificationContent()
                note.title = "柯"
                note.body = "刚才那句没发出去：「\(text.prefix(30))」。打开 App 再发一次吧"
                note.sound = .default
                try? await UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: "ke.reply-failed.\(UUID().uuidString)", content: note, trigger: nil)
                )
            }
            return
        }
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        // 1116：她自己记的日程提醒（看医生的号，见 CalendarEventStore）只是打开 App，不跳去聊天
        if response.notification.request.identifier.hasPrefix("ke.appt.") { return }
        await MainActor.run { ChatNotificationCoordinator.shared.openChat() }
    }

    /// App 在前台时也要显示推送 —— 不然她开着 App 就收不到柯的提醒。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // 137：她正开着 App，聊天页顺手拉一次记录，这句直接出现在聊天里
        await MainActor.run { ChatNotificationCoordinator.shared.noteIncoming() }
        return [.banner, .sound, .badge]
    }
}
