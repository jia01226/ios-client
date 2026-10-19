import Foundation
import UIKit

/// 121：输入框的动静——只报「在打字、打到几个字」和三种犹豫，**从不带她写的字**。
/// 要不要叫醒柯由服务器决定（/api/ke/typing、/api/ke/hesitate）；这里只管看、只管报。
///
/// 同一份草稿里最多到过几个字记作 peak；不到 4 个字服务器不看，这边也就不发。
/// - 删光 cleared：写到过 ≥4 个字，又删到空，空着 3 秒没再打字；
/// - 卡住 stuck：框里有字，90 秒没动也没发；同一份草稿只报一次；
/// - 切走 left：框里有字、没发，App 退到后台。
/// 发出去就算这份草稿结束：计时全停、清零，什么都不报。
@MainActor
final class ComposerPresenceReporter: ObservableObject {
    enum Hesitation: String, Sendable {
        case cleared, stuck, left
    }

    enum Event: Equatable, Sendable {
        case typing(length: Int)
        case hesitate(Hesitation, peak: Int)
    }

    struct Timing: Sendable {
        /// 打字最多 1.5 秒报一次
        var typingInterval: TimeInterval = 1.5
        var clearedDelay: TimeInterval = 3
        var stuckDelay: TimeInterval = 90
        var minimumPeak = 4
    }

    /// 计时用的睡；测试里换成手拨的钟。被取消时要抛错。
    typealias Sleep = @MainActor @Sendable (TimeInterval) async throws -> Void

    private let timing: Timing
    private let now: @MainActor () -> Date
    private let sleep: Sleep
    private let emit: @MainActor (Event) -> Void

    /// 框里现在几个字（只记数，字本身不留）
    private var length = 0
    private var peak = 0
    private var stuckReported = false
    private var leftReported = false
    private var isForeground = true
    /// 恢复上次没发的草稿：紧跟着的那次变化是恢复本身，不算她在打字
    private var restoredLength: Int?

    private var lastTypingAt: Date?
    /// 上次报给服务器的字数；空着又报空就不发了
    private var lastSentLength = 0
    private var typingTask: Task<Void, Never>?
    private var clearedTask: Task<Void, Never>?
    private var stuckTask: Task<Void, Never>?

    init(
        timing: Timing = Timing(),
        now: @escaping @MainActor () -> Date = { Date() },
        sleep: @escaping Sleep = { try await Task.sleep(nanoseconds: UInt64(max(0, $0) * 1_000_000_000)) },
        emit: @escaping @MainActor (Event) -> Void
    ) {
        self.timing = timing
        self.now = now
        self.sleep = sleep
        self.emit = emit
    }

    deinit {
        typingTask?.cancel(); clearedTask?.cancel(); stuckTask?.cancel()
    }

    // MARK: 她那边的动静

    /// 输入框的字变了：打字、删字、粘贴、听写都走这里。只看字数。
    func textChanged(_ text: String) {
        let count = text.count
        if let restored = restoredLength {
            restoredLength = nil
            if restored == count { return }
        }
        guard count > 0 || length > 0 else { return }
        length = count
        peak = max(peak, count)
        leftReported = false
        reportTyping()
        if count == 0 {
            stuckTask?.cancel(); stuckTask = nil
            armCleared()
        } else {
            clearedTask?.cancel(); clearedTask = nil
            armStuck()
        }
    }

    /// 打开时恢复上次没发的草稿：只记个底，不算打字、不算 peak，也不开卡住的表。
    func adoptRestoredDraft(_ text: String) {
        cancelTimers()
        length = text.count
        peak = 0
        stuckReported = false
        leftReported = false
        restoredLength = text.count
    }

    /// 发出去了：这份草稿结束，什么都不报。
    func didSend() {
        cancelTimers()
        length = 0
        peak = 0
        lastSentLength = 0
        stuckReported = false
        leftReported = false
        restoredLength = nil
    }

    /// scenePhase 到 .background
    func didEnterBackground() {
        isForeground = false
        typingTask?.cancel(); typingTask = nil
        stuckTask?.cancel(); stuckTask = nil
        if length > 0 {
            guard !leftReported else { return }
            leftReported = true
            hesitate(.left)
        } else if clearedTask != nil {
            // 删光还没满 3 秒就切走：人走了不会再打字，直接按删光报，免得挂起后迟到
            clearedTask?.cancel(); clearedTask = nil
            finishCleared()
        }
    }

    /// scenePhase 回到 .active。从后台回来框里还有字，卡住的表重新从 0 数。
    func didBecomeActive() {
        guard !isForeground else { return }
        isForeground = true
        if length > 0 { armStuck() }
    }

    // MARK: 计时

    private func reportTyping() {
        // 已经约好了下一次：到点带最新字数
        guard typingTask == nil else { return }
        let wait = lastTypingAt.map { timing.typingInterval - now().timeIntervalSince($0) } ?? 0
        if wait <= 0 {
            flushTyping()
        } else {
            typingTask = after(wait) { $0.typingTask = nil; $0.flushTyping() }
        }
    }

    private func flushTyping() {
        guard length > 0 || lastSentLength > 0 else { return }
        lastTypingAt = now()
        lastSentLength = length
        emit(.typing(length: length))
    }

    private func armCleared() {
        clearedTask?.cancel()
        clearedTask = after(timing.clearedDelay) { $0.clearedTask = nil; $0.finishCleared() }
    }

    private func finishCleared() {
        guard length == 0 else { return }
        hesitate(.cleared)
        // 这份草稿到此为止，下一份从头算
        peak = 0
        stuckReported = false
        leftReported = false
    }

    private func armStuck() {
        stuckTask?.cancel(); stuckTask = nil
        guard isForeground, !stuckReported else { return }
        stuckTask = after(timing.stuckDelay) { reporter in
            reporter.stuckTask = nil
            guard reporter.length > 0, !reporter.stuckReported else { return }
            reporter.stuckReported = reporter.hesitate(.stuck)
        }
    }

    @discardableResult
    private func hesitate(_ kind: Hesitation) -> Bool {
        guard peak >= timing.minimumPeak else { return false }
        emit(.hesitate(kind, peak: peak))
        return true
    }

    private func cancelTimers() {
        typingTask?.cancel(); typingTask = nil
        clearedTask?.cancel(); clearedTask = nil
        stuckTask?.cancel(); stuckTask = nil
    }

    private func after(_ delay: TimeInterval, _ fire: @escaping @MainActor (ComposerPresenceReporter) -> Void) -> Task<Void, Never> {
        Task { [weak self, sleep] in
            do { try await sleep(delay) } catch { return }
            // 睡醒到轮上主线程之间可能已经被取消（她又打了一个字）
            guard !Task.isCancelled, let self else { return }
            fire(self)
        }
    }
}

extension ComposerPresenceReporter {
    /// 真用的那个：打这条线自己的服务器（line.apiBaseURL），发了就不管，失败不吭声。
    static func live(api: APIClient) -> ComposerPresenceReporter {
#if DEBUG
        // UI 测试的假数据、预览模式一律不碰网络
        let process = ProcessInfo.processInfo
        if process.arguments.contains(where: { $0.hasPrefix("-ui-test") || $0.hasPrefix("-preview") })
            || process.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return ComposerPresenceReporter { _ in }
        }
#endif
        return ComposerPresenceReporter { event in
            switch event {
            case let .typing(length):
                Task { try? await api.reportComposerTyping(length: length) }
            case let .hesitate(kind, peak):
                // 切走那一下 App 马上要被挂起：向系统多要一小会儿，让这一下发完
                let grant = BackgroundGrant(name: "composer-hesitate")
                Task {
                    _ = try? await api.reportComposerHesitation(kind: kind.rawValue, peak: peak)
                    grant.end()
                }
            }
        }
    }
}
