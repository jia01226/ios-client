import SwiftUI

struct MemoryUsageTotals: Decodable {
    let calls: Int
    let input_tokens: Int?
    let output_tokens: Int?
    let cache_hit_tokens: Int?
    let cache_miss_tokens: Int?
    let cache_hit_percent: Double?
    let estimated_cny: Double?
    let priced_calls: Int
    let unknown_calls: Int
}
struct MemoryUsageCall: Decodable, Identifiable {
    let id: String
    let kind: String
    let started_at: String
    let status: String
    let model: String?
    let input_tokens: Int?
    let output_tokens: Int?
    let cache_hit_tokens: Int?
    let estimated_cny: Double?
}
struct MemoryUsageReport: Decodable {
    let started_at: String?
    let today: MemoryUsageTotals
    let total: MemoryUsageTotals
    let recent: [MemoryUsageCall]
    let notice: String
    let price_version: String
}

struct MemoryUsageView: View {
    @EnvironmentObject private var theme: Theme
    let line: ChatLine
    @State private var report: MemoryUsageReport?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        List {
            Section {
                Text("DeepSeek · \(line.title)").font(theme.font.sectionTitle)
                Text("记忆整理的用量，包含 App 新对话和 CC 实录。")
                    .font(theme.font.caption).foregroundStyle(theme.color.textSecondary)
            }
            if let report {
                Section("今天") { totals(report.today) }
                Section("接入以来") {
                    totals(report.total)
                    Text(report.started_at.map { "统计开始于 \(dateText($0))" } ?? "第一笔整理调用后开始计数。")
                        .font(theme.font.caption).foregroundStyle(theme.color.textSecondary)
                    Text(report.notice).font(theme.font.caption).foregroundStyle(theme.color.textSecondary)
                    Text("单价核实于 \(report.price_version)").font(theme.font.caption)
                    Link("查看 DeepSeek 官方单价", destination: URL(string: "https://api-docs.deepseek.com/zh-cn/quick_start/pricing/")!)
                }
                Section("最近 20 次") {
                    ForEach(report.recent) { call in
                        VStack(alignment: .leading, spacing: theme.metric.gapS) {
                            HStack {
                                Text(call.kind == "cc_memory" ? "CC 记忆整理" : "App 记忆整理")
                                Spacer()
                                Text(money(call.estimated_cny)).monospacedDigit()
                            }
                            Text("输入 \(count(call.input_tokens)) · 输出 \(count(call.output_tokens)) · 缓存 \(count(call.cache_hit_tokens))")
                                .font(theme.font.caption)
                            Text(dateText(call.started_at)).font(theme.font.caption)
                                .foregroundStyle(theme.color.textSecondary)
                            if call.status != "received" {
                                Text(call.status == "requesting" ? "请求已发出，用量尚未确认" : "未取得完整用量，费用未知")
                                    .font(theme.font.caption)
                            }
                        }
                    }
                }
            }
            if loading { ProgressView("读取用量") }
            if let error {
                Text(error)
                Button("重试") { Task { await load() } }
            }
        }
        .font(theme.font.body)
        .navigationTitle("整理用量")
        .tint(theme.effectiveAccent)
        .task { await load() }
        .refreshable { await load() }
        .accessibilityIdentifier("memory-usage-page")
    }

    @ViewBuilder private func totals(_ value: MemoryUsageTotals) -> some View {
        HStack {
            Text("估算费用（人民币）")
            Spacer()
            Text(money(value.estimated_cny)).font(theme.font.sectionTitle).monospacedDigit()
        }
        LabeledContent("整理调用", value: "\(value.calls) 次")
        LabeledContent("输入 token", value: count(value.input_tokens))
        LabeledContent("输出 token", value: count(value.output_tokens))
        LabeledContent("缓存命中 token", value: count(value.cache_hit_tokens))
        if let hit = value.cache_hit_percent {
            LabeledContent("输入缓存命中率", value: String(format: "%.1f%%", hit))
            ProgressView(value: min(100, max(0, hit)), total: 100).tint(theme.effectiveAccent)
        }
        if value.priced_calls < value.calls {
            Text("\(value.calls - value.priced_calls) 次尚无可核实费用，未计入上方估算。")
                .font(theme.font.caption).foregroundStyle(theme.color.textSecondary)
        }
    }
    private func count(_ value: Int?) -> String { value.map { $0.formatted() } ?? "未知" }
    private func money(_ value: Double?) -> String { value.map { String(format: "¥%.6f", $0) } ?? "待核实" }
    private func dateText(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    private func load() async {
        loading = true
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-test-memory-usage") {
            let totals = MemoryUsageTotals(calls: 12, input_tokens: 18000, output_tokens: 2400,
                cache_hit_tokens: 14400, cache_miss_tokens: 3600, cache_hit_percent: 80,
                estimated_cny: 0.00456, priced_calls: 11, unknown_calls: 1)
            report = MemoryUsageReport(started_at: "2026-09-09T03:00:00.000000+00:00",
                today: totals, total: totals, recent: [], notice: "匿名测试数据。费用为人民币估算。", price_version: "2026-09-09")
            loading = false
            return
        }
#endif
        do {
            report = try await APIClient(baseURL: line.apiBaseURL).memoryUsage()
            error = nil
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}
