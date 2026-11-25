import Foundation
import UIKit
import WatchConnectivity

/// 11-25 手表上的柯：把「柯在哪条线上」和登录状态（cookie）递给手表，她不用在手表上再输口令。
/// App 启动、回到前台、手表来要的时候各递一次。手表那头见 KeWatch/WatchLink.swift。
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.push() }
    }

    private func context() -> [String: Any] {
        let base = ChatLine.test1.apiBaseURL
        let cookies = (HTTPCookieStorage.shared.cookies(for: base) ?? []).map { cookie -> [String: Any] in
            var item: [String: Any] = [:]
            for (key, value) in cookie.properties ?? [:] {
                if key == .expires, let date = value as? Date {
                    item["expires"] = date.timeIntervalSince1970
                } else if value is String || value is NSNumber {
                    item[key.rawValue] = value
                }
            }
            return item
        }
        return ["baseURL": base.absoluteString, "cookies": cookies, "at": Date().timeIntervalSince1970]
    }

    func push() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        do {
            try session.updateApplicationContext(context())
        } catch {
            print("[watch] 没递过去：\(error)")
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated { push() }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // 手表说没登录 / 刚装好：当场递，手表在线就直接发过去
        guard message["want"] as? String == "login" else { return }
        if session.isReachable {
            session.sendMessage(context(), replyHandler: nil, errorHandler: nil)
        }
        push()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
