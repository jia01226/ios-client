import Foundation
import WatchConnectivity

/// 手机把「柯在哪条线上」和登录状态（cookie）递过来，手表照着去连，不用在手表上再输一遍口令。
/// 手机那头见 KeApp/Core/WatchBridge.swift。
@MainActor
final class WatchLink: NSObject, ObservableObject {
    static let shared = WatchLink()

    @Published private(set) var baseURL: URL?
    @Published private(set) var paired = false

    private let defaults = UserDefaults.standard
    private let baseKey = "ke.watch.baseURL"
    private let cookieKey = "ke.watch.cookies"

    override init() {
        super.init()
        if let raw = defaults.string(forKey: baseKey), let url = URL(string: raw) {
            baseURL = url
            restoreCookies()
            paired = true
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// 让手机马上再递一次（她在手机上重新登录过、或者手表这边说没登录时）
    func askPhone() {
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["want": "login"], replyHandler: nil, errorHandler: nil)
    }

    fileprivate func accept(_ context: [String: Any]) {
        guard let raw = context["baseURL"] as? String, let url = URL(string: raw) else { return }
        let cookies = context["cookies"] as? [[String: Any]] ?? []
        defaults.set(raw, forKey: baseKey)
        defaults.set(cookies, forKey: cookieKey)
        baseURL = url
        restoreCookies()
        paired = true
    }

    private func restoreCookies() {
        let saved = defaults.array(forKey: cookieKey) as? [[String: Any]] ?? []
        for item in saved {
            var props: [HTTPCookiePropertyKey: Any] = [:]
            for (key, value) in item {
                if key == "expires", let seconds = value as? Double {
                    props[.expires] = Date(timeIntervalSince1970: seconds)
                } else {
                    props[HTTPCookiePropertyKey(key)] = value
                }
            }
            if let cookie = HTTPCookie(properties: props) {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in
            if !context.isEmpty { self.accept(context) } else { self.askPhone() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.accept(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.accept(message) }
    }
}
