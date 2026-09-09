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

struct MemoryRetrievalView: View {
    @EnvironmentObject private var theme: Theme
    let line: ChatLine
    @State private var report: MemoryRetrievalReport?
    @State private var query = ""
    @State private var error: String?
    @State private var loading = false

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
