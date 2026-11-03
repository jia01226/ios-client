import Foundation
import SwiftUI

/// 145：工坊页的数据。服务器那边每一轮单独跑（关了 App 也接着干），这里只管读、接着看、发、停。
@MainActor final class WorkshopStore: ObservableObject {
    struct LiveItem: Identifiable, Equatable {
        let id = UUID()
        var text: String?
        var tool: String?
        var brief: String?
        var toolID: String?
        var error: String?
    }

    @Published private(set) var messages: [WorkshopMessage] = []
    @Published private(set) var choices: [WorkshopChoice] = []
    @Published private(set) var model: String = ""
    @Published private(set) var quota: [String: [String: WorkshopQuotaWindow]] = [:]
    @Published private(set) var jobID: String?
    @Published private(set) var live: [LiveItem] = []
    @Published private(set) var loaded = false
    @Published private(set) var sending = false
    @Published var notice: String?

    private let api: any WorkshopAPI
    private var follow: Task<Void, Never>?
    private var lastSeq = 0

    init(api: any WorkshopAPI) {
        self.api = api
    }

    var running: Bool { jobID != nil }
    var current: WorkshopChoice? { choices.first { $0.id == model } }

    func load() async {
        do {
            let snap = try await api.fetchWorkshop()
            messages = snap.messages
            choices = snap.choices
            model = snap.model
            quota = snap.quota
            loaded = true
            if let job = snap.job {
                if jobID != job.id { attach(job.id) }
            } else if jobID != nil {
                stopFollowing()
            }
        } catch {
            if !loaded { notice = "工坊没接上：" + Self.reason(error) }
        }
    }

    func send(_ text: String) async -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return false }
        sending = true
        defer { sending = false }
        do {
            let result = try await api.sendWorkshop(text: text, model: nil)
            await load()
            if let id = result.job_id, jobID != id { attach(id) }
            if result.queued { notice = "前一件还在干，这句排上了，干完接着做。" }
            return true
        } catch {
            notice = "没发出去：" + Self.reason(error)
            return false
        }
    }

    func stop() async {
        do { try await api.stopWorkshop() } catch {}
        notice = "叫它停了，收个尾就停。"
    }

    func setModel(_ id: String) async {
        let old = model
        model = id
        do { try await api.setWorkshopModel(id) }
        catch {
            model = old
            notice = "没换上：" + Self.reason(error)
        }
    }

    func newConversation() async {
        do {
            try await api.newWorkshop()
            await load()
        } catch {
            notice = "没新开：" + Self.reason(error)
        }
    }

    // MARK: 跟着正在跑的那一轮

    private func attach(_ id: String) {
        follow?.cancel()
        jobID = id
        live = []
        lastSeq = 0
        follow = Task { [weak self] in await self?.followLoop(id) }
    }

    private func stopFollowing() {
        follow?.cancel()
        follow = nil
        jobID = nil
        live = []
    }

    private func followLoop(_ id: String) async {
        var failures = 0
        while !Task.isCancelled, jobID == id {
            var finished = false
            do {
                for try await event in try await api.workshopEvents(jobID: id, after: lastSeq) {
                    if Task.isCancelled { return }
                    failures = 0
                    if event.seq > 0 { lastSeq = max(lastSeq, event.seq) }
                    switch event.kind {
                    case .text: appendText(event.text)
                    case .tool: live.append(LiveItem(tool: event.tool, brief: event.text, toolID: event.id))
                    case .toolError:
                        if let i = live.lastIndex(where: { $0.toolID == event.id && !event.id.isEmpty }) {
                            live[i].error = event.error
                        }
                    case .done:
                        finished = true
                        if event.status == "error", !event.error.isEmpty { notice = event.error }
                    case .reconnect: break
                    }
                    if finished { break }
                }
            } catch {
                failures += 1
                if Task.isCancelled { return }
                try? await Task.sleep(for: .seconds(min(10, failures * 2)))
                // 连不上多半是这轮已经完了：拉一次记录看看
                if failures >= 3 { await load(); if jobID != id { return } }
                continue
            }
            if finished {
                follow = nil
                jobID = nil
                live = []
                await load()
                return
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
    }

    private func appendText(_ text: String) {
        guard !text.isEmpty else { return }
        if var last = live.last, last.tool == nil {
            last.text = (last.text ?? "") + text
            live[live.count - 1] = last
        } else {
            live.append(LiveItem(text: text))
        }
    }

    // MARK: 额度小字

    /// 「1 号 本周 4% · 5 小时 8%」；DeepSeek 就说按量花钱
    var quotaLine: String {
        guard let c = current else { return "" }
        if c.account == 0 { return "DeepSeek 按用量扣钱 · 不能联网搜索，能打开网页" }
        guard let q = quota[String(c.account)] else { return "\(c.account) 号" }
        var parts: [String] = []
        if let s = q["session"] { parts.append("5 小时 \(s.used)%") }
        if let w = q["week"] { parts.append("本周 \(w.used)%") }
        return "\(c.account) 号 · " + parts.joined(separator: " · ")
    }

    nonisolated static func reason(_ error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case let .serverMessage(message): return message
            case let .badStatus(_, message) where !message.isEmpty: return message
            default: break
            }
        }
        return "网络不太好，再试一次"
    }
}
