import SwiftUI

// App 入口。
// 名字就叫「柯」——她 2026-08-14 13:22 自己定的。

@main
struct KeApp: App {

    @StateObject private var theme = Theme.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(theme)
                .preferredColorScheme(theme.skin == .night ? .dark : .light)
                .tint(theme.effectiveAccent)
        }
    }
}

// MARK: - AppDelegate（APNs 注册与前台通知）

import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        PushRegistrationCoordinator.shared.prepareAtLaunch()
        LocationContextReporter.shared.prepareAtLaunch()
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

    /// App 在前台时也要显示推送 —— 不然她开着 App 就收不到柯的提醒。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
