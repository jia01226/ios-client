import UIKit

/// 一小段后台时间：发完或系统到点都还回去，只还一次。
/// 125：从输入框那边（ComposerPresenceReporter）搬出来共用——柯回话的那一轮也攥着它，
/// 她发完就切走、锁屏时流不在挂起那一下被掐断（见 ChatViewModel.runReplyTask）。
@MainActor
final class BackgroundGrant {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private let onExpire: (@MainActor () -> Void)?

    /// onExpire：系统到点要收回（App 随后就会被挂起）时叫一次。系统没给（.invalid）也当到点，当场叫。
    init(name: String, onExpire: (@MainActor () -> Void)? = nil) {
        self.onExpire = onExpire
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated {
                self?.onExpire?()
                self?.end()
            }
        }
        if identifier == .invalid { onExpire?() }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
