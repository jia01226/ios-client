import UIKit

/// 一小段后台时间：发完或系统到点都还回去，只还一次。
/// 125：从输入框那边（ComposerPresenceReporter）搬出来共用——柯回话的那一轮也攥着它，
/// 她发完就切走、锁屏时流不在挂起那一下被掐断（见 ChatViewModel.runReplyTask）。
@MainActor
final class BackgroundGrant {
    typealias Begin = @MainActor (_ name: String, _ expiration: @escaping @MainActor @Sendable () -> Void) -> UIBackgroundTaskIdentifier
    typealias End = @MainActor (UIBackgroundTaskIdentifier) -> Void

    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private let onExpire: (@MainActor () -> Void)?
    private let endTask: End

    /// onExpire：系统到点要收回（App 随后就会被挂起）时叫一次。系统没给（.invalid）也当到点，当场叫。
    /// begin/end 只给测试换掉，平时就是 UIApplication 那两个。
    init(name: String, onExpire: (@MainActor () -> Void)? = nil,
         begin: Begin = { name, expiration in
             UIApplication.shared.beginBackgroundTask(withName: name) { MainActor.assumeIsolated { expiration() } }
         },
         end: @escaping End = { UIApplication.shared.endBackgroundTask($0) }) {
        self.onExpire = onExpire
        endTask = end
        // 125 修：到点时先还、再叫回调，而且这里强引用自己。以前是 [weak self] 先叫回调再还：
        // 回话那一轮的回调会放掉攥着这份时间的最后一个引用（ChatViewModel.releaseReplyKeepAlive），
        // 这一份当场被释放，后面那句 end() 落空，endBackgroundTask 从来没叫——系统到点没收到还，直接杀掉 App，
        // 她点推送就成了冷启动，等得更久。系统在 endBackgroundTask 以后才放掉这个闭包，不会留着不放。
        identifier = begin(name) { [self] in
            let callback = self.onExpire
            self.end()
            callback?()
        }
        if identifier == .invalid { onExpire?() }
    }

    func end() {
        guard identifier != .invalid else { return }
        let ending = identifier
        identifier = .invalid
        endTask(ending)
    }
}
