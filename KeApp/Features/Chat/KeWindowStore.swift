import Foundation

/// 112：设置抽屉里「来信」「换窗」和聊天里小图钉共用的一份状态。
/// 窗口、钉住、设置都以服务器为准；App 只是读、改、等后台的活做完。
@MainActor
final class KeWindowStore: ObservableObject {
    /// 洗澡 / 换窗各自的进度，页面据此显示「正在…」「好了」「没成」。
    enum JobPhase: Equatable {
        case idle
        case running
        case done(String?)
        case failed(String)
    }

    @Published private(set) var window: KeWindowState?
    @Published private(set) var windowError: String?
    @Published private(set) var isLoadingWindow = false

    @Published private(set) var settings: KeProactiveSettings?
    @Published private(set) var settingsError: String?
    @Published private(set) var isSavingSettings = false

    @Published private(set) var washPhase: JobPhase = .idle
    @Published private(set) var rotatePhase: JobPhase = .idle
    @Published private(set) var pinError: String?
    @Published private(set) var pinningIDs: Set<Int> = []

    private let api: APIClient
    private var pollTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var pendingPatch: [String: Any] = [:]
    /// 后端的 job 不一定写 kind，就记住最后一次是谁发起的。
    private var startedKind: String?

    init(api: APIClient = .shared) {
        self.api = api
    }

    var pinnedMessageIDs: Set<Int> { window?.pinnedMessageIDs ?? [] }
    var pinnedStartIDs: Set<Int> { Set(window?.pins.items.map(\.startID) ?? []) }
    var isJobRunning: Bool { window?.job?.isRunning ?? false }

    // MARK: 窗口

    func loadWindow() async {
        isLoadingWindow = window == nil
        defer { isLoadingWindow = false }
        do {
            apply(try await api.fetchKeWindow())
            windowError = nil
        } catch is CancellationError {
            return
        } catch {
            windowError = Self.message(for: error)
        }
    }

    private func apply(_ next: KeWindowState) {
        let previous = window?.job
        window = next
        route(job: next.job, previous: previous)
        if next.job?.isRunning == true { startPolling() }
    }

    /// 把 job 分给洗澡或换窗。跑着的活结束了（变 done/failed 或者干脆没了）就记下结果。
    private func route(job: KeWindowJob?, previous: KeWindowJob?) {
        let kind = Self.kind(of: job ?? previous, fallback: startedKind)
        func set(_ phase: JobPhase) {
            if kind == "rotate" { rotatePhase = phase } else { washPhase = phase }
        }
        guard let job else {
            if previous?.isRunning == true || startedKind != nil { set(.done(nil)) }
            startedKind = nil
            return
        }
        if job.isRunning {
            set(.running)
        } else if job.isFailed {
            // 只报这次 App 里看着跑完的；打开时就躺在那里的旧结果不再弹。
            if previous?.isRunning == true || startedKind != nil {
                set(.failed(job.error ?? "这次没成，稍后再试一次。"))
            }
        } else if job.isDone, previous?.isRunning == true || startedKind != nil {
            set(.done(job.resultText))
        }
        if !job.isRunning { startedKind = nil }
    }

    private static func kind(of job: KeWindowJob?, fallback: String?) -> String {
        let raw = (job?.kind ?? fallback ?? "").lowercased()
        return raw.contains("rotate") || (raw.contains("window") && !raw.contains("wash")) ? "rotate" : "wash"
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.loadWindow()
                if !self.isJobRunning { break }
            }
            self?.pollTask = nil
        }
    }

    func wash() async {
        guard !isJobRunning else { return }
        startedKind = "wash"
        washPhase = .running
        do {
            let job = try await api.washKeWindow()
            window?.job = job ?? KeWindowJob(kind: "wash", state: "running")
            startPolling()
        } catch {
            startedKind = nil
            washPhase = .failed(Self.message(for: error))
        }
    }

    func rotate(picks: [Int]) async {
        guard !isJobRunning else { return }
        startedKind = "rotate"
        rotatePhase = .running
        do {
            let job = try await api.rotateKeWindow(picks: picks)
            window?.job = job ?? KeWindowJob(kind: "rotate", state: "running")
            startPolling()
        } catch {
            startedKind = nil
            rotatePhase = .failed(Self.message(for: error))
        }
    }

    /// 挑选带走：一页一页往前翻。
    func fetchRounds(before: Int?) async throws -> KeRoundPage {
        try await api.fetchKeRounds(limit: 30, beforeID: before)
    }

    func resetWashPhase() { if washPhase != .running { washPhase = .idle } }
    func resetRotatePhase() { if rotatePhase != .running { rotatePhase = .idle } }

    // MARK: 钉住

    func isPinned(messageID: Int?) -> Bool {
        guard let messageID else { return false }
        return pinnedMessageIDs.contains(messageID)
    }

    func setPin(messageID: Int, pinned: Bool) async {
        guard !pinningIDs.contains(messageID) else { return }
        pinningIDs.insert(messageID)
        pinError = nil
        defer { pinningIDs.remove(messageID) }
        do {
            try await api.setKePin(messageID: messageID, pinned: pinned)
            await loadWindow()
        } catch {
            pinError = Self.message(for: error)
        }
    }

    func clearPinError() { pinError = nil }

    // MARK: 来信设置

    func loadSettings() async {
        do {
            settings = try await api.fetchKeSettings()
            settingsError = nil
        } catch is CancellationError {
            return
        } catch {
            settingsError = Self.message(for: error)
        }
    }

    /// 改一项就先在页面上变过去，停手半秒再一起存；存不上就退回服务器的值并说明原因。
    func change<Value>(_ keyPath: WritableKeyPath<KeProactiveSettings, Value>, to value: Value, key: String, wire: Any) {
        guard var next = settings else { return }
        next[keyPath: keyPath] = value
        settings = next
        pendingPatch[key] = wire
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.flushSettings()
        }
    }

    private func flushSettings() async {
        let patch = pendingPatch
        guard !patch.isEmpty else { return }
        pendingPatch = [:]
        isSavingSettings = true
        defer { isSavingSettings = false }
        do {
            let saved = try await api.updateKeSettings(patch)
            // 存的路上她又改了别的，就别用旧回执盖掉页面上的新值。
            if pendingPatch.isEmpty { settings = saved }
            settingsError = nil
        } catch {
            settingsError = Self.message(for: error)
            if pendingPatch.isEmpty { await loadSettings() }
        }
    }

    // MARK: 错误说人话

    static func message(for error: Error) -> String {
        if case let APIError.badStatus(code, message) = error {
            if code == 409 { return message.isEmpty ? "柯正在忙上一件事，等一下再试。" : message }
            return message.isEmpty ? "服务器这次没接住（\(code)），稍后再试。" : message
        }
        if case APIError.decoding = error { return "柯那边回来的内容没读懂，稍后再试。" }
        return error.localizedDescription
    }
}
