import SwiftUI
import Charts

struct UsagePeriod: Decodable, Identifiable {
    let key: String
    let label: String
    let calls: Int
    let input_tokens: Int
    let output_tokens: Int
    let cached_tokens: Int
    let estimated_usd: Double
    let average_ms: Double
    var id: String { key }
}

struct UsageDay: Decodable, Identifiable {
    let day: String
    let calls: Int
    let input_tokens: Int
    let output_tokens: Int
    var id: String { day }
    var tokens: Int { input_tokens + output_tokens }
}

struct UsageModelTotal: Decodable, Identifiable {
    let model: String
    let calls: Int
    let input_tokens: Int
    let output_tokens: Int
    var id: String { model }
}

struct UsageDashboardReport: Decodable {
    let updated_at: String
    let started_at: String?
    let periods: [UsagePeriod]
    let daily: [UsageDay]
    let models: [UsageModelTotal]
    let notice: String
}

struct UsageDashboardView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    let line: ChatLine
    @State private var report: UsageDashboardReport?
    @State private var quotas: ChatModelQuotaCatalog?
    @State private var selectedPeriod = "today"
    @State private var loading = false
    @State private var error: String?
    @State private var quotaError: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if let quotas { quotaSection(quotas) }
                else if let quotaError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("订阅额度").font(theme.font.sectionTitle)
                        Text("额度暂时没读到：\(quotaError)")
                            .font(.caption).foregroundStyle(theme.color.textSecondary)
                    }
                }
                if let report {
                    Picker("统计时段", selection: $selectedPeriod) {
                        ForEach(report.periods) { Text($0.label).tag($0.key) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("usage-period-picker")
                    if let period = report.periods.first(where: { $0.key == selectedPeriod }) {
                        metricSection(period)
                    }
                    if !report.daily.isEmpty { trendSection(report.daily) }
                    modelSection(report.models)
                    Text(report.notice)
                        .font(.caption).foregroundStyle(theme.color.textSecondary)
                    if let started = report.started_at {
                        Text("从 \(started.prefix(10)) 开始统计")
                            .font(.caption).foregroundStyle(theme.color.textSecondary)
                    }
                    NavigationLink("查看 DeepSeek 记忆整理明细") {
                        MemoryUsageView(line: line).environmentObject(theme)
                    }
                }
                if loading { ProgressView("读取用量与额度…") }
                if let error {
                    ContentUnavailableView("暂时没读到完整数据", systemImage: "chart.line.downtrend.xyaxis", description: Text(error))
                    Button("重试") { Task { await load() } }
                        .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .background(theme.color.bg.ignoresSafeArea())
        .navigationTitle("用量与额度")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        .tint(theme.effectiveAccent)
        .task { await load() }
        .refreshable { await load() }
        .accessibilityIdentifier("usage-dashboard-page")
    }

    private func quotaSection(_ catalog: ChatModelQuotaCatalog) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("订阅额度").font(theme.font.sectionTitle)
            ForEach(catalog.groups.filter { $0.configured }) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(group.label).font(.headline); Spacer(); Text(quotaStatus(group)).font(.caption) }
                    ForEach(Array(group.windows.enumerated()), id: \.offset) { _, window in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(windowLabel(window.windowMinutes))
                                Spacer()
                                Text(remainingText(window.remainingPercent))
                            }.font(.caption).foregroundStyle(theme.color.textSecondary)
                            if let remaining = window.remainingPercent {
                                ProgressView(value: max(0, min(100, remaining)), total: 100).tint(theme.effectiveAccent)
                            }
                            if let reset = resetText(window.resetAt) { Text(reset).font(.caption2).foregroundStyle(theme.color.textSecondary) }
                        }
                    }
                    if group.windows.isEmpty {
                        Text("官方额度暂时没读到，稍后下拉刷新。")
                            .font(.caption).foregroundStyle(theme.color.textSecondary)
                    }
                }
                .padding(14)
                .background(theme.color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func metricSection(_ value: UsagePeriod) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("实际调用").font(theme.font.sectionTitle)
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow { metric("调用", "\(value.calls.formatted()) 次"); metric("总 Token", count(value.input_tokens + value.output_tokens)) }
                GridRow { metric("输入", count(value.input_tokens)); metric("输出", count(value.output_tokens)) }
                GridRow { metric("缓存命中", count(value.cached_tokens)); metric("平均耗时", duration(value.average_ms)) }
            }
            HStack { Text("API 等价费用估算"); Spacer(); Text(String(format: "$%.4f", value.estimated_usd)).monospacedDigit() }
                .font(.subheadline)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(theme.color.textSecondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .padding(12).background(theme.color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func trendSection(_ days: [UsageDay]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("近 30 天").font(theme.font.sectionTitle)
            Chart(days) { day in
                BarMark(x: .value("日期", day.day), y: .value("Token", day.tokens))
                    .foregroundStyle(theme.effectiveAccent.gradient)
            }.frame(height: 150).chartXAxis(.hidden)
        }
    }

    private func modelSection(_ models: [UsageModelTotal]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("累计模型构成").font(theme.font.sectionTitle)
            ForEach(models) { model in
                LabeledContent(model.model, value: "\(model.calls.formatted()) 次 · \(count(model.input_tokens + model.output_tokens)) Token")
                    .font(.subheadline)
            }
        }
    }

    private func quotaStatus(_ quota: ChatModelQuotaGroup) -> String {
        quota.stale ? "上次数据" : (quota.available ? "可用" : "暂不可用")
    }
    private func remainingText(_ value: Double?) -> String {
        guard let value else { return "暂时没读到" }
        return "剩余 \(Int(value.rounded()))%"
    }
    private func windowLabel(_ minutes: Int?) -> String {
        guard let minutes else { return "订阅额度" }
        if minutes == 300 { return "5 小时额度" }
        if minutes == 10_080 { return "7 天额度" }
        return minutes % 60 == 0 ? "\(minutes / 60) 小时额度" : "\(minutes) 分钟额度"
    }
    private func resetText(_ epoch: TimeInterval?) -> String? {
        guard let epoch else { return nil }
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened)
            .locale(Locale(identifier: "zh_CN"))
        return "重置于 \(Date(timeIntervalSince1970: epoch).formatted(style))"
    }
    private func count(_ value: Int) -> String { value.formatted(.number.notation(.compactName)) }
    private func duration(_ ms: Double) -> String { ms <= 0 ? "—" : String(format: "%.1f 秒", ms / 1000) }

    @MainActor private func load() async {
        loading = true; error = nil
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-test-usage-dashboard") {
            report = UsageDashboardReport(updated_at: "2026-09-09", started_at: "2026-08-01", periods: [
                UsagePeriod(key: "today", label: "今天", calls: 7, input_tokens: 184200, output_tokens: 12600, cached_tokens: 138000, estimated_usd: 1.28, average_ms: 3200),
                UsagePeriod(key: "7d", label: "7 天", calls: 41, input_tokens: 920000, output_tokens: 68000, cached_tokens: 701000, estimated_usd: 7.16, average_ms: 3600),
                UsagePeriod(key: "30d", label: "30 天", calls: 126, input_tokens: 2800000, output_tokens: 207000, cached_tokens: 2100000, estimated_usd: 21.2, average_ms: 3700),
                UsagePeriod(key: "all", label: "累计", calls: 304, input_tokens: 6200000, output_tokens: 481000, cached_tokens: 4700000, estimated_usd: 46.9, average_ms: 3900)
            ], daily: [UsageDay(day: "09-07", calls: 4, input_tokens: 90000, output_tokens: 7000), UsageDay(day: "09-08", calls: 8, input_tokens: 210000, output_tokens: 15000), UsageDay(day: "09-09", calls: 7, input_tokens: 184200, output_tokens: 12600)], models: [UsageModelTotal(model: "Claude", calls: 5, input_tokens: 150000, output_tokens: 10000), UsageModelTotal(model: "GPT", calls: 2, input_tokens: 34200, output_tokens: 2600)], notice: "费用按已记录的 API 单价折算，仅供比较，不代表订阅账单。")
            quotas = ChatModelQuotaCatalog(updatedAt: Date().timeIntervalSince1970, selectedGroup: "claude_1", currentRouteGroup: "claude_1", groups: [ChatModelQuotaGroup(id: "claude_1", label: "Claude", configured: true, available: true, status: "available", usedPercent: 34, remainingPercent: 66, resetAt: nil, stale: false, source: "anthropic_oauth", windows: [ChatModelQuotaWindow(kind: "five_hour", usedPercent: 34, remainingPercent: 66, windowMinutes: 300, resetAt: Date().addingTimeInterval(7200).timeIntervalSince1970), ChatModelQuotaWindow(kind: "seven_day", usedPercent: 18, remainingPercent: 82, windowMinutes: 10080, resetAt: Date().addingTimeInterval(400000).timeIntervalSince1970)])])
            loading = false; return
        }
#endif
        let usageTask = Task { try await APIClient(baseURL: line.apiBaseURL).usageDashboard() }
        let quotaTask = Task { () throws -> ChatModelQuotaCatalog in
            let api = APIClient(baseURL: line.apiBaseURL)
            let sessionID = try await api.activeSessionID()
            return try await api.fetchModelQuotas(sessionID: sessionID)
        }
        do { report = try await usageTask.value }
        catch { self.error = error.localizedDescription }
        do { quotas = try await quotaTask.value; quotaError = nil }
        catch { quotaError = error.localizedDescription }
        loading = false
    }
}

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
