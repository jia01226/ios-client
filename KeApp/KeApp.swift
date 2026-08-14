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

// MARK: - AppDelegate（推送要用）
//
// ⚠️ 第一版先留桩。等 Apple 开发者账号激活、拿到 .p8 密钥之后再接。
// 接之前先读：https://github.com/Cheiineeey/ios-app-where-it-breaks
// 那份文档里"推送"一节记的坑，比苹果官方文档实在。

import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// 申请推送权限。
    /// ⚠️ 别在 App 一启动就弹 —— 被拒一次就很难再要回来。
    /// 正确时机：她第一次发出消息、或者第一次进「我们」那一页之后。
    func requestPushAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return }
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            print("[push] 申请权限失败：\(error)")
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[push] device token = \(token)")
        // TODO: 接口清单到位后，把 token 上报给 VPS
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
