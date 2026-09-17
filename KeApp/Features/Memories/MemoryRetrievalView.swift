import SwiftUI

struct MemoryRetrievalCandidate: Decodable, Identifiable {
    let id: String
    let fact: String
    let quote: String
    let note: String
    let occurred_at: String
    let selected: Bool
    let reason: String
    let keyword_rank: Int?
    let semantic_rank: Int?
    let similarity: Double?
}
struct MemoryRetrievalSemantic: Decodable {
    let status: String
    let eligible: Int?
    let indexed: Int?
}
struct MemoryRetrievalTrace: Decodable, Identifiable {
    let id: String
    let created_at: String
    let query: String
    let session_id: String
    let stage: String
    let fact_count: Int
    let candidates: [MemoryRetrievalCandidate]
    let raw_event_ids: [String]
    let semantic: MemoryRetrievalSemantic
    var change_guard_count: Int? = nil
}
struct MemoryRetrievalReport: Decodable {
    let recent: [MemoryRetrievalTrace]
    let notice: String
}

enum MemoryFeedbackKind: String, CaseIterable, Identifiable {
    case missing
    case memoryOutdated = "memory_outdated"
    case memoryWrong = "memory_wrong"
    case answerWrong = "answer_wrong"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .missing: return "没找到该记忆"
        case .memoryOutdated: return "记忆已经过期"
        case .memoryWrong: return "记忆内容不对"
        case .answerWrong: return "记忆正确，柯答错了"
        }
    }
    var needsCandidate: Bool { self == .memoryOutdated || self == .memoryWrong }
}

struct MemoryFeedbackReceipt: Decodable {
    let saved: Bool
    let id: String
    let patch_id: String?
    let result: String
}

struct MemoryRetrievalView: View {
    @EnvironmentObject private var theme: Theme
    let line: ChatLine
    var correctionCreated: () -> Void = {}
    @State private var report: MemoryRetrievalReport?
    @State private var query = ""
    @State private var error: String?
    @State private var loading = false
    @State private var correcting: MemoryRetrievalTrace?
    @State private var resultMessage: String?

    var body: some View {
        List {
            Section {
                Text(line.title).font(theme.font.sectionTitle)
                Text("看看每轮找到了什么，以及哪些记忆放进了提示词。")
                    .font(theme.font.caption).foregroundStyle(theme.color.textSecondary)
                Text("语义检索在 VPS 本地运行，不另收模型调用费。这里只查看检索，不能判断柯是否理解正确。")
                    .font(theme.font.caption).foregroundStyle(theme.color.textSecondary)
            }
            Section("试着找记忆") {
                TextField("换个说法，看看能否找到", text: $query, axis: .vertical)
                    .lineLimit(1...4).accessibilityIdentifier("memory-retrieval-query")
                Button("查一下") { Task { await check() } }
                    .disabled(loading || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("memory-retrieval-check")
                Text("按当前聊天检索，不发送聊天消息。")
                    .font(theme.font.caption).foregroundStyle(theme.color.textSecondary)
            }
            if loading { ProgressView("正在查找") }
            if let error {
                Text(error).font(theme.font.caption)
                Button("刷新记录") { Task { await load() } }
            }
            if let report {
                if report.recent.isEmpty {
                    Section {
                        Text("还没有检索记录。聊一轮，或在上面试着找一条记忆。")
                    }
                }
                ForEach(report.recent) { trace in
                    Section {
                        VStack(alignment: .leading, spacing: theme.metric.gapS) {
                            Text(trace.query).font(theme.font.sectionTitle)
                            Text(trace.stage == "check" ? "检索测试 · 未发送聊天" : "聊天提示词已装配")
                                .font(theme.font.caption).foregroundStyle(theme.effectiveAccent)
                            Text("\(dateText(trace.created_at)) · 聊天 \(trace.session_id)")
                                .font(theme.font.caption).foregroundStyle(theme.color.textSecondary)
                            Text(trace.stage == "check"
                                 ? "选出 \(trace.fact_count) 条已审核记忆"
                                 : "\(trace.fact_count) 条已审核记忆已放入提示词")
                            if !trace.raw_event_ids.isEmpty {
                                Text("另找到 \(trace.raw_event_ids.count) 条历史原话线索，独立于已审核卡片。")
                                    .font(theme.font.caption)
                            }
                            if let count = trace.change_guard_count, count > 0 {
                                Text("已核对 \(count) 条旧原话对应的新情况，旧状态不会作为现状提供。")
                                    .font(theme.font.caption)
                            }
                            Text(semanticLabel(trace.semantic)).font(theme.font.caption)
                                .foregroundStyle(theme.color.textSecondary)
                            Button {
                                correcting = trace
                            } label: {
                                Label("记错了", systemImage: "exclamationmark.bubble")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("memory-feedback-\(trace.id)")
                        }
                        ForEach(trace.candidates) { candidate in
                            DisclosureGroup {
                                Text("原话 · \(candidate.quote)")
                                if !candidate.note.isEmpty { Text("你的备注 · \(candidate.note)") }
                                Text("来源时间 · \(candidate.occurred_at)")
                                    .font(theme.font.caption).foregroundStyle(theme.color.textSecondary)
                                if let similarity = candidate.similarity {
                                    Text(String(format: "语义相似度 %.2f，仅用于排序，不是可信度。", similarity))
                                        .font(theme.font.caption).foregroundStyle(theme.color.textSecondary)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: theme.metric.gapS) {
                                    Text(candidate.fact)
                                    Text(candidateLabel(candidate, isCheck: trace.stage == "check"))
                                        .font(theme.font.caption).foregroundStyle(theme.color.textSecondary)
                                }
                            }
                        }
                    }
                }
                Section { Text(report.notice).font(theme.font.caption).foregroundStyle(theme.color.textSecondary) }
            }
        }
        .font(theme.font.body)
        .navigationTitle("记忆怎么找的")
        .tint(theme.effectiveAccent)
        .task { await load() }
        .refreshable { await load() }
        .accessibilityIdentifier("memory-retrieval-page")
        .sheet(item: $correcting) { trace in
            MemoryFeedbackSheet(line: line, trace: trace) { message in
                resultMessage = message
                correctionCreated()
                Task { await load() }
            }
            .environmentObject(theme)
        }
        .alert("已处理", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("知道了", role: .cancel) { resultMessage = nil }
        } message: { Text(resultMessage ?? "") }
    }

    private func candidateLabel(_ value: MemoryRetrievalCandidate, isCheck: Bool) -> String {
        let method = value.keyword_rank != nil && value.semantic_rank != nil ? "关键词和意思都相近"
            : (value.semantic_rank != nil ? "意思相近" : "关键词匹配")
        let result = value.selected ? (isCheck ? "本次选中" : "已放入提示词")
            : (value.reason == "budget" ? "全文太长，本轮未放入" : "其他记忆排序更靠前，本轮未放入")
        return "\(method) · \(result)"
    }
    private func semanticLabel(_ value: MemoryRetrievalSemantic) -> String {
        switch value.status {
        case "ready": return "语义检索可用 · \(value.indexed ?? 0) 条已审核记忆可检索"
        case "partial": return "正在补齐语义索引 · \(value.indexed ?? 0)/\(value.eligible ?? 0) 条，关键词仍可用"
        case "fallback": return "语义检索暂不可用，本轮使用关键词"
        case "skipped": return "这句没有触发已审核记忆检索"
        default: return "本轮未使用语义检索"
        }
    }
    private func dateText(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)?.formatted(date: .abbreviated, time: .shortened) ?? value
    }
    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-test-memory-retrieval") {
            report = MemoryRetrievalReport(recent: [MemoryRetrievalTrace(id: "example", created_at: "2026-09-09T04:00:00.000000+00:00",
                query: "家里谁掌勺？", session_id: "1", stage: "check", fact_count: 1,
                candidates: [MemoryRetrievalCandidate(id: "sample", fact: "最近是妈妈做饭", quote: "最近都是妈妈做饭",
                    note: "只指最近一段时间", occurred_at: "2026-09-09", selected: true, reason: "selected",
                    keyword_rank: nil, semantic_rank: 1, similarity: 0.48)], raw_event_ids: [],
                semantic: MemoryRetrievalSemantic(status: "ready", eligible: 9, indexed: 9))], notice: "匿名测试数据。")
            return
        }
#endif
        do {
            report = try await APIClient(baseURL: line.apiBaseURL).memoryRetrieval()
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func check() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let api = APIClient(baseURL: line.apiBaseURL)
            _ = try await api.checkMemoryRetrieval(query: query)
            report = try await api.memoryRetrieval()
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct MemoryFeedbackSheet: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    let line: ChatLine
    let trace: MemoryRetrievalTrace
    let completed: (String) -> Void
    @State private var kind: MemoryFeedbackKind = .missing
    @State private var candidateID: String?
    @State private var correction = ""
    @State private var submitting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("这轮问的是") { Text(trace.query) }
                Section("哪里出了问题") {
                    Picker("错误类型", selection: $kind) {
                        ForEach(MemoryFeedbackKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
                if kind.needsCandidate {
                    Section("选择要更正的记忆") {
                        if trace.candidates.isEmpty {
                            Text("这轮没有可更正的已审核记忆，请改选“没找到该记忆”。")
                                .foregroundStyle(theme.color.textSecondary)
                        } else {
                            Picker("记忆", selection: $candidateID) {
                                Text("请选择").tag(String?.none)
                                ForEach(trace.candidates) { Text(traceLabel($0)).tag(String?.some($0.id)) }
                            }
                            .pickerStyle(.inline)
                        }
                    }
                }
                Section(kind == .answerWrong ? "柯哪里说错了" : "现在的正确情况") {
                    TextEditor(text: $correction)
                        .frame(minHeight: 110)
                        .accessibilityIdentifier("memory-feedback-correction")
                    Text(kind == .answerWrong
                         ? "这条只记录为回答问题，不会修改记忆库。"
                         : "提交后会进入待审卡；你收下后才会更新记忆库。")
                        .font(theme.font.caption).foregroundStyle(theme.color.textSecondary)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("纠正这轮记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(submitting ? "提交中" : "提交") { Task { await submit() } }
                        .disabled(!canSubmit || submitting)
                        .accessibilityIdentifier("memory-feedback-submit")
                }
            }
            .onChange(of: kind) { _, value in if !value.needsCandidate { candidateID = nil } }
        }
    }

    private var canSubmit: Bool {
        !correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && correction.count <= 1000 && (!kind.needsCandidate || candidateID != nil)
    }
    private func traceLabel(_ candidate: MemoryRetrievalCandidate) -> String {
        candidate.fact.count > 72 ? String(candidate.fact.prefix(72)) + "…" : candidate.fact
    }
    private func submit() async {
        submitting = true
        defer { submitting = false }
        do {
            let receipt = try await APIClient(baseURL: line.apiBaseURL)
                .submitMemoryRetrievalFeedback(traceID: trace.id, kind: kind,
                                               candidateID: candidateID, note: correction)
            dismiss()
            completed(receipt.result == "pending_correction"
                      ? "更正卡已经放进待审区，收下后才会替换记忆。"
                      : "已记录为柯本轮回答错误，事实记忆没有被修改。")
        } catch { self.error = error.localizedDescription }
    }
}
