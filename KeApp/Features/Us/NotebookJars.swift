import SwiftUI

// 121：荷包分成「花钱｜攒钱」两页，这里是「攒钱」：一个个罐子（服务器 /api/notebook/jars）。
// 随手攒（没有目标，想放就放）排第一，下面是有目标的罐子。只画进度条，不画花、不画罐子。
// 她和柯都能往里存、往外取；每一笔写着是谁放的（佳佳 / 柯），改过的再写「佳佳改过」。
// 删一笔、删一个罐子都给 5 秒「撤销」。说法要软：不说「欠」「还差多少」「记账」「账本」。
// 金额：服务器回来的都是分（*_cents）；发出去的 amount / target 是元，可以带小数。

// MARK: - 数据

struct Jar: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    let title: String
    /// "free" 随手攒 / "goal" 有目标的
    let kind: String
    let target_cents: Int
    let saved_cents: Int
    let percent: Int?
    let reached: Bool
    /// "YYYY-MM-DD"，没定日期是 ""
    let deadline: String
    let days_left: Int?
    let created_at: String
    let updated_at: String

    var isFree: Bool { kind == "free" }
    /// 条子画多长（0…1）：攒够了就满
    var fraction: Double {
        if reached { return 1 }
        if target_cents > 0 { return min(1, max(0, Double(saved_cents) / Double(target_cents))) }
        return min(1, max(0, Double(percent ?? 0) / 100))
    }
    var percentText: String {
        let value = percent ?? (target_cents > 0 ? Int((Double(saved_cents) / Double(target_cents) * 100).rounded(.down)) : 0)
        return "\(value)%"
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, kind, target_cents, saved_cents, percent, reached, deadline, days_left, created_at, updated_at
    }
    /// 服务器少给一两个字段也照样认（随手攒可能不带目标、日期）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "goal"
        target_cents = try c.decodeIfPresent(Int.self, forKey: .target_cents) ?? 0
        saved_cents = try c.decodeIfPresent(Int.self, forKey: .saved_cents) ?? 0
        percent = try c.decodeIfPresent(Int.self, forKey: .percent)
        reached = try c.decodeIfPresent(Bool.self, forKey: .reached) ?? false
        deadline = try c.decodeIfPresent(String.self, forKey: .deadline) ?? ""
        days_left = try c.decodeIfPresent(Int.self, forKey: .days_left)
        created_at = try c.decodeIfPresent(String.self, forKey: .created_at) ?? ""
        updated_at = try c.decodeIfPresent(String.self, forKey: .updated_at) ?? ""
    }
}

struct JarEntry: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    /// 负数是取出来的
    let amount_cents: Int
    /// "佳佳" / "柯"
    let actor: String
    let note: String
    let created_at: String
    let edited_by: String?
    let updated_at: String?

    private enum CodingKeys: String, CodingKey { case id, amount_cents, actor, note, created_at, edited_by, updated_at }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        amount_cents = try c.decodeIfPresent(Int.self, forKey: .amount_cents) ?? 0
        actor = try c.decodeIfPresent(String.self, forKey: .actor) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        created_at = try c.decodeIfPresent(String.self, forKey: .created_at) ?? ""
        edited_by = try c.decodeIfPresent(String.self, forKey: .edited_by)
        updated_at = try c.decodeIfPresent(String.self, forKey: .updated_at)
    }

    /// 新的在上面：先比时间，同一秒再比 id
    static func newestFirst(_ a: JarEntry, _ b: JarEntry) -> Bool { (a.created_at, a.id) > (b.created_at, b.id) }
}

struct JarMonthTip: Decodable, Equatable, Sendable {
    /// "2026-10"
    let month: String
    let saved_cents: Int
}

struct JarOverview: Decodable, Equatable, Sendable {
    let total_cents: Int
    let jars: [Jar]
    let month_tip: JarMonthTip?

    init(total_cents: Int, jars: [Jar], month_tip: JarMonthTip?) {
        self.total_cents = total_cents; self.jars = jars; self.month_tip = month_tip
    }
    private enum CodingKeys: String, CodingKey { case total_cents, jars, month_tip }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        jars = try c.decodeIfPresent([Jar].self, forKey: .jars) ?? []
        total_cents = try c.decodeIfPresent(Int.self, forKey: .total_cents) ?? jars.reduce(0) { $0 + $1.saved_cents }
        month_tip = try c.decodeIfPresent(JarMonthTip.self, forKey: .month_tip)
    }
    /// 随手攒排第一，其余照服务器给的顺序
    var ordered: [Jar] { jars.filter(\.isFree) + jars.filter { !$0.isFree } }
}

struct JarDetail: Decodable, Equatable, Sendable {
    let jar: Jar
    let entries: [JarEntry]

    init(jar: Jar, entries: [JarEntry]) { self.jar = jar; self.entries = entries }
    private enum CodingKeys: String, CodingKey { case jar, entries }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        jar = try c.decode(Jar.self, forKey: .jar)
        entries = try c.decodeIfPresent([JarEntry].self, forKey: .entries) ?? []
    }
}

/// 写操作回来的东西：有的带整张总览（新罐子、删罐子、月底那笔），有的只带改好的罐子或那一笔
struct JarReply: Decodable, Sendable {
    let ok: Bool?
    let error: String?
    let jar: Jar?
    let entry: JarEntry?
    let total_cents: Int?
    let jars: [Jar]?
    let month_tip: JarMonthTip?

    var overview: JarOverview? {
        guard let jars else { return nil }
        return JarOverview(total_cents: total_cents ?? jars.reduce(0) { $0 + $1.saved_cents }, jars: jars, month_tip: month_tip)
    }
}

// MARK: - 小工具（纯函数，测试里也用）

enum JarText {
    /// 「还有 73 天」「今天到期」「过了 3 天」；没定日期就不说
    static func daysLeft(_ days: Int?) -> String? {
        guard let days else { return nil }
        if days > 0 { return "还有 \(days) 天" }
        if days == 0 { return "今天到期" }
        return "过了 \(-days) 天"
    }

    /// "2026-10" → 「10月」
    static func monthName(_ month: String) -> String {
        let parts = month.split(separator: "-")
        guard parts.count >= 2, let m = Int(parts[1]) else { return "这个月" }
        return "\(m)月"
    }

    /// "2026-12-31" → 「12月31日」
    static func dayName(_ day: String) -> String {
        let parts = day.prefix(10).split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return day }
        return "\(m)月\(d)日"
    }

    /// 她输进来的金额（元）：去掉 ¥、元、逗号和空格，只认大于 0 的数，留两位小数。不对就是 nil。
    static func parseYuan(_ text: String) -> Double? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for junk in ["¥", "￥", "元", ",", "，", " "] { cleaned = cleaned.replacingOccurrences(of: junk, with: "") }
        cleaned = cleaned.replacingOccurrences(of: "。", with: ".")
        guard let value = Double(cleaned), value.isFinite, value > 0, value < 100_000_000 else { return nil }
        let rounded = (value * 100).rounded() / 100
        return rounded > 0 ? rounded : nil
    }

    /// 分 → 输入框里的元：「200」「12.50」
    static func yuanField(_ cents: Int) -> String {
        let c = abs(cents)
        return c % 100 == 0 ? String(c / 100) : String(format: "%.2f", Double(c) / 100)
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func isKe(_ who: String?) -> Bool { who == "柯" || who == "ke" }
    /// 谁放的这一笔：只认「柯」，别的都是佳佳
    static func actorName(_ who: String) -> String { isKe(who) ? "柯" : "佳佳" }
}

/// 一根细条（花钱的额度、攒钱的罐子都用它）。数变了慢慢滑过去；开了「减弱动态效果」就直接跳。
struct NotebookBar: View {
    let value: Double
    let color: Color
    var height: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            let v = min(1, max(0, value))
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.track)
                // 一点点也给一个小圆点，别让人以为是空的
                Capsule().fill(color).frame(width: v > 0 ? max(height, g.size.width * v) : 0)
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: value)
        .accessibilityHidden(true)
    }
}

/// 两颗一样大的按钮（放进去 / 这次不放、存一笔 / 取出来）：实心那颗墨色底，另一颗只描一道细边
struct InkPillStyle: ButtonStyle {
    var filled = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Ink.song(15)).tracking(1)
            .foregroundStyle(filled ? Color.white : Ink.primary)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Capsule().fill(filled ? Ink.accent : Color.white.opacity(0.55)))
            .overlay(Capsule().stroke(filled ? Color.clear : Ink.line, lineWidth: 0.8))
            .contentShape(Capsule())
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.7 : 1)
    }
}

/// 罐子里每一笔是谁放的：「佳佳」或「柯」。颜色只是辅助，一定写字。
struct JarActorTag: View {
    let actor: String
    var body: some View {
        let ke = JarText.isKe(actor)
        Text(JarText.actorName(actor))
            .font(.system(size: 12)).padding(.horizontal, 7).padding(.vertical, 1)
            .foregroundStyle(ke ? Ink.keText : Ink.meText)
            .background(Capsule().fill(ke ? Ink.keFill : Ink.meFill))
    }
}

// MARK: - 罐子的数据和动作

struct JarUndo: Identifiable, Equatable {
    enum Target: Equatable { case jar(Int), entry(Int, jarID: Int) }
    let id = UUID()
    let target: Target
    let text: String
}

@MainActor final class JarStore: ObservableObject {
    @Published private(set) var overview: JarOverview?
    @Published private(set) var loadFailed = false
    @Published private(set) var detail: JarDetail?
    @Published private(set) var detailFailed = false
    @Published private(set) var busy = false
    /// 没有表单可以挂的地方出错了（月底那笔、撤销），弹一句
    @Published var notice: String?
    /// 刚删掉的那个，5 秒内能撤销
    @Published private(set) var pendingUndo: JarUndo?
    let api: APIClient
    init(api: APIClient) { self.api = api }

    /// 服务器说的中文原因直接给她看（比如「罐子里没有这么多」）；网络断了就说没接上
    nonisolated static func reason(_ error: Error) -> String {
        guard let apiError = error as? APIError else { return "没接上，再试一次。" }
        switch apiError {
        case let .badStatus(_, message) where !message.isEmpty: return message
        case let .serverMessage(message) where !message.isEmpty: return message
        case .unauthorized: return "需要重新登录一下。"
        default: return "没接上，再试一次。"
        }
    }

    func load() async {
        do { overview = try await api.fetchJars(); loadFailed = false }
        catch {
            // 页面一离开就会取消，那不算没接上
            if Task.isCancelled { return }
            if overview == nil { loadFailed = true }
        }
    }

    func retry() async {
        loadFailed = false
        await load()
    }

    func loadDetail(_ id: Int) async {
        if detail?.jar.id != id { detail = nil }
        detailFailed = false
        do {
            let d = try await api.fetchJar(id: id)
            detail = JarDetail(jar: d.jar, entries: d.entries.sorted(by: JarEntry.newestFirst))
        } catch {
            if Task.isCancelled { return }
            if detail?.jar.id != id { detailFailed = true }
        }
    }

    /// 写完以后：回来的东西里有总览就直接用，没有就再拉一次；开着的罐子也一起刷新
    private func settle(_ reply: JarReply, jarID: Int? = nil) async throws {
        if let error = reply.error, !error.isEmpty, reply.ok != true { throw APIError.serverMessage(error) }
        if let next = reply.overview { overview = next } else { await load() }
        if let jarID { await loadDetail(jarID) }
    }

    // 下面这些成功回 nil，不成功回一句中文，表单里接着显示

    func createJar(title: String, target: Double, deadline: String) async -> String? {
        do { try await settle(api.createJar(title: title, target: target, deadline: deadline)); return nil }
        catch { return Self.reason(error) }
    }

    func editJar(_ id: Int, title: String, target: Double, deadline: String) async -> String? {
        do { try await settle(api.updateJar(id: id, title: title, target: target, deadline: deadline), jarID: id); return nil }
        catch { return Self.reason(error) }
    }

    func deleteJar(_ jar: Jar) async -> String? {
        do {
            try await settle(api.deleteJar(id: jar.id))
            pendingUndo = JarUndo(target: .jar(jar.id), text: "「\(jar.title)」收起来了")
            return nil
        } catch { return Self.reason(error) }
    }

    func addEntry(jarID: Int, amount: Double, take: Bool, note: String, operationID: String) async -> String? {
        do {
            try await settle(api.addJarEntry(jarID: jarID, amount: amount, take: take, note: note, operationID: operationID), jarID: jarID)
            return nil
        } catch { return Self.reason(error) }
    }

    func editEntry(_ entry: JarEntry, jarID: Int, amount: Double, take: Bool, note: String) async -> String? {
        do {
            try await settle(api.updateJarEntry(id: entry.id, amount: amount, take: take, note: note), jarID: jarID)
            return nil
        } catch { return Self.reason(error) }
    }

    func deleteEntry(_ entry: JarEntry, jarID: Int) async -> String? {
        do {
            try await settle(api.deleteJarEntry(id: entry.id), jarID: jarID)
            let sign = entry.amount_cents < 0 ? "取出的" : "存的"
            pendingUndo = JarUndo(target: .entry(entry.id, jarID: jarID), text: "删掉了一笔\(sign) \(yuan(abs(entry.amount_cents)))")
            return nil
        } catch { return Self.reason(error) }
    }

    func revert(_ undo: JarUndo) async {
        guard pendingUndo?.id == undo.id else { return }
        pendingUndo = nil
        do {
            switch undo.target {
            case let .jar(id): try await settle(api.deleteJar(id: id, undo: true))
            case let .entry(id, jarID): try await settle(api.deleteJarEntry(id: id, undo: true), jarID: jarID)
            }
        } catch { notice = Self.reason(error) }
    }

    func expireUndo(_ id: UUID) {
        if pendingUndo?.id == id { pendingUndo = nil }
    }

    func answerTip(accept: Bool, jarID: Int?) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { try await settle(api.answerJarMonthTip(accept: accept, jarID: accept ? jarID : nil)) }
        catch { notice = Self.reason(error) }
    }
}

// MARK: - 攒钱这一页

struct JarListPane: View {
    @ObservedObject var store: JarStore
    let paper: Color
    var onOpen: (Jar) -> Void
    @State private var creating = false
    /// 月底那笔放进哪个罐子；没选过就是随手攒
    @State private var tipJarID: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let o = store.overview {
                Text("一共攒了 \(yuan(o.total_cents)) · \(o.jars.count) 个罐子")
                    .font(Ink.song(16)).tracking(0.5).monospacedDigit()
                    .accessibilityIdentifier("jars-overview")
                if let tip = o.month_tip, tip.saved_cents > 0 { tipCard(tip, jars: o.ordered) }
                ForEach(o.ordered) { jar in card(jar) }
                if o.jars.isEmpty {
                    Text("还没有罐子。\n想为什么慢慢攒，就放一个新罐子。")
                        .font(Ink.song(14)).foregroundStyle(Ink.secondary).lineSpacing(5)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 24)
                }
                AddLine(title: "新罐子") { creating = true }
                    .accessibilityIdentifier("jars-new")
            } else if store.loadFailed {
                Button { Task { await store.retry() } } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 18, weight: .light))
                        Text("没接上，点这里再试").font(Ink.song(15))
                    }
                    .foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("jars-retry")
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(40)
            }
        }
        .task { await store.load() }
        .sheet(isPresented: $creating) {
            JarFormSheet(jar: nil, paper: paper) { title, target, deadline in
                await store.createJar(title: title, target: target, deadline: deadline)
            }
        }
    }

    // MARK: 月底省下的那笔

    private func tipCard(_ tip: JarMonthTip, jars: [Jar]) -> some View {
        let chosen = jars.first { $0.id == tipJarID } ?? jars.first(where: \.isFree) ?? jars.first
        return VStack(alignment: .leading, spacing: 12) {
            Text("\(JarText.monthName(tip.month))省下 \(yuan(tip.saved_cents))，放进罐子里？")
                .font(Ink.song(16)).lineSpacing(4).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            if !jars.isEmpty {
                Menu {
                    Picker("放进哪个罐子", selection: Binding(get: { chosen?.id ?? -1 }, set: { tipJarID = $0 })) {
                        ForEach(jars) { jar in Text(jar.title).tag(jar.id) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("放进").foregroundStyle(Ink.secondary)
                        Text("「\(chosen?.title ?? "随手攒")」").foregroundStyle(Ink.primary)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(Ink.secondary)
                    }
                    .font(Ink.song(15))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .foregroundStyle(Ink.primary)
                .accessibilityLabel("放进哪个罐子，现在是\(chosen?.title ?? "随手攒")")
                .accessibilityIdentifier("jars-tip-picker")
            }
            HStack(spacing: 12) {
                Button("放进去") { Task { await store.answerTip(accept: true, jarID: chosen?.id) } }
                    .buttonStyle(InkPillStyle(filled: true))
                    .accessibilityIdentifier("jars-tip-accept")
                Button("这次不放") { Task { await store.answerTip(accept: false, jarID: nil) } }
                    .buttonStyle(InkPillStyle())
                    .accessibilityIdentifier("jars-tip-decline")
            }
            .disabled(store.busy)
        }
        .notebookCard()
    }

    // MARK: 一个罐子一张卡

    private func card(_ jar: Jar) -> some View {
        Button { onOpen(jar) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(jar.title).font(Ink.song(16)).tracking(0.5).lineLimit(2)
                    if jar.reached && !jar.isFree { StatusChip(text: "攒够啦", tone: .good) }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .light)).foregroundStyle(Ink.secondary)
                }
                if jar.isFree {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("一共").font(Ink.song(15))
                        Text(yuan(jar.saved_cents)).font(Ink.latin(34)).monospacedDigit()
                    }
                    Text("没有目标，想放就放").font(Ink.song(12.5)).foregroundStyle(Ink.secondary)
                } else {
                    Text(jar.percentText).font(Ink.latin(34)).monospacedDigit()
                    NotebookBar(value: jar.fraction, color: Ink.saving)
                    HStack {
                        Text("\(yuan(jar.saved_cents)) / \(yuan(jar.target_cents))")
                        Spacer(minLength: 8)
                        if !jar.reached, let days = JarText.daysLeft(jar.days_left) { Text(days) }
                    }
                    .font(Ink.song(13)).monospacedDigit().foregroundStyle(Ink.secondary)
                    .padding(.top, 2)
                }
            }
            .notebookCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("点开看每一笔")
        .accessibilityIdentifier("jar-card-\(jar.id)")
    }
}

// MARK: - 点开一个罐子

struct JarDetailPage: View {
    @ObservedObject var store: JarStore
    let jarID: Int
    let paper: Color
    var onBack: () -> Void
    @State private var money: JarMoneyDraft?
    @State private var editingJar = false
    @State private var confirmDelete = false

    private var jar: Jar? {
        if let d = store.detail, d.jar.id == jarID { return d.jar }
        return store.overview?.jars.first { $0.id == jarID }
    }
    private var entries: [JarEntry]? {
        guard let d = store.detail, d.jar.id == jarID else { return nil }
        return d.entries
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let jar {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(jar.title).font(Ink.song(28)).tracking(2)
                        Text(subtitle(jar)).font(Ink.song(13)).foregroundStyle(Ink.secondary).monospacedDigit()
                    }
                    progress(jar).notebookCard()
                    HStack(spacing: 12) {
                        Button("存一笔") { money = JarMoneyDraft(mode: .put) }
                            .buttonStyle(InkPillStyle(filled: true))
                            .accessibilityIdentifier("jar-put")
                        Button("取出来") { money = JarMoneyDraft(mode: .take) }
                            .buttonStyle(InkPillStyle())
                            .accessibilityIdentifier("jar-take")
                    }
                    NotebookSection(title: "存取记录", hint: "点一笔可以改") {
                        VStack(spacing: 0) {
                            if let entries {
                                ForEach(entries) { entry in row(entry) }
                                if entries.isEmpty {
                                    Text("还没有放过钱").font(Ink.song(14)).foregroundStyle(Ink.secondary)
                                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                                }
                            } else if store.detailFailed {
                                retry
                            } else {
                                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                            }
                        }
                    }
                } else if store.detailFailed {
                    retry
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .background(paper.ignoresSafeArea())
        .foregroundStyle(Ink.primary)
        .task(id: jarID) { await store.loadDetail(jarID) }
        .refreshable { await store.loadDetail(jarID) }
        .sheet(item: $money) { draft in moneySheet(draft) }
        .sheet(isPresented: $editingJar) {
            if let jar {
                JarFormSheet(jar: jar, paper: paper) { title, target, deadline in
                    await store.editJar(jar.id, title: title, target: target, deadline: deadline)
                }
            }
        }
        .confirmationDialog("删掉这个罐子？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删掉", role: .destructive) {
                guard let jar else { return }
                Task {
                    if let problem = await store.deleteJar(jar) { store.notice = problem } else { onBack() }
                }
            }
        } message: { Text("罐子和里面每一笔都会一起收起来，柯那边也看不到了。删了之后 5 秒内可以撤销。") }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .light))
                    Text("攒钱").font(Ink.song(16))
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Ink.accent)
            .accessibilityLabel("返回攒钱")
            .accessibilityIdentifier("jar-back")
            Spacer()
            // 随手攒不能改名、不能删，就不给这个菜单
            if let jar, !jar.isFree {
                Menu {
                    Button("改名字 / 金额 / 日期") { editingJar = true }
                    Button("删除罐子", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 18, weight: .light))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .foregroundStyle(Ink.accent)
                .accessibilityLabel("这个罐子的更多操作")
                .accessibilityIdentifier("jar-menu")
            }
        }
        .padding(.top, 2)
    }

    private func subtitle(_ jar: Jar) -> String {
        if jar.isFree { return "没有目标，想放就放" }
        if jar.reached { return "攒够啦" + (jar.deadline.isEmpty ? "" : " · 定在 \(JarText.dayName(jar.deadline))") }
        guard !jar.deadline.isEmpty else { return "没定日期，慢慢来" }
        return "定在 \(JarText.dayName(jar.deadline))" + (JarText.daysLeft(jar.days_left).map { " · " + $0 } ?? "")
    }

    /// 顶上那张大一点的卡：百分比、粗一点的条子、攒了多少 / 目标
    private func progress(_ jar: Jar) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if jar.isFree {
                Text("一共").font(Ink.song(14)).foregroundStyle(Ink.secondary)
                Text(yuan(jar.saved_cents)).font(Ink.latin(44)).monospacedDigit()
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(jar.percentText).font(Ink.latin(44)).monospacedDigit()
                    Spacer()
                    if jar.reached { StatusChip(text: "攒够啦", tone: .good) }
                }
                NotebookBar(value: jar.fraction, color: Ink.saving, height: 10)
                HStack {
                    Text("\(yuan(jar.saved_cents)) / \(yuan(jar.target_cents))")
                    Spacer(minLength: 8)
                    if !jar.reached, let days = JarText.daysLeft(jar.days_left) { Text(days) }
                }
                .font(Ink.song(13.5)).monospacedDigit().foregroundStyle(Ink.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func row(_ entry: JarEntry) -> some View {
        let take = entry.amount_cents < 0
        let amount = (take ? "−" : "+") + yuan(abs(entry.amount_cents))
        let editor = entry.edited_by.flatMap { $0.isEmpty ? nil : JarText.actorName($0) }
        return Button { money = JarMoneyDraft(mode: .edit(entry)) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(shortDay(entry.created_at)).font(Ink.latin(14)).monospacedDigit().foregroundStyle(Ink.secondary)
                    JarActorTag(actor: entry.actor)
                    if let editor { Text("\(editor)改过").font(.system(size: 11)).foregroundStyle(Ink.secondary) }
                    Spacer(minLength: 8)
                    Text(amount).font(Ink.latin(17)).monospacedDigit()
                        .foregroundStyle(take ? Ink.neutral : Ink.positive)
                }
                if !entry.note.isEmpty {
                    Text(entry.note).font(Ink.song(14)).foregroundStyle(Ink.secondary).lineSpacing(3)
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Ink.line.opacity(0.5)).frame(height: 0.5) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(JarText.dayName(entry.created_at))，\(JarText.actorName(entry.actor))\(take ? "取出" : "存了") \(yuan(abs(entry.amount_cents)))"
                            + (entry.note.isEmpty ? "" : "，\(entry.note)") + (editor.map { "，\($0)改过" } ?? ""))
        .accessibilityHint("点一下可以改或删")
    }

    private var retry: some View {
        Button { Task { await store.loadDetail(jarID) } } label: {
            Text("没接上，点这里再试").font(Ink.song(15)).foregroundStyle(Ink.secondary)
                .frame(maxWidth: .infinity, minHeight: 88).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func moneySheet(_ draft: JarMoneyDraft) -> some View {
        let title = jar?.title ?? ""
        let id = jarID
        let store = store
        return JarMoneySheet(draft: draft, jarTitle: title, paper: paper, onSave: { amount, take, note in
            switch draft.mode {
            case .put, .take:
                return await store.addEntry(jarID: id, amount: amount, take: take, note: note, operationID: draft.operationID)
            case let .edit(entry):
                return await store.editEntry(entry, jarID: id, amount: amount, take: take, note: note)
            }
        }, onDelete: {
            guard case let .edit(entry) = draft.mode else { return nil }
            return await store.deleteEntry(entry, jarID: id)
        })
    }
}

// MARK: - 存一笔 / 取出来 / 改一笔

struct JarMoneyDraft: Identifiable {
    enum Mode { case put, take, edit(JarEntry) }
    let id = UUID()
    let mode: Mode
    /// 同一次填写重试也用同一个，服务器就不会存成两笔
    let operationID = UUID().uuidString
    var entry: JarEntry? { if case let .edit(e) = mode { return e }; return nil }
}

struct JarMoneySheet: View {
    @Environment(\.dismiss) private var dismiss
    let draft: JarMoneyDraft
    let jarTitle: String
    let paper: Color
    /// 金额（元）、是不是取出来、备注 → 成功回 nil，不成功回一句中文
    var onSave: (Double, Bool, String) async -> String?
    var onDelete: () async -> String?
    @State private var amount = ""
    @State private var note = ""
    @State private var take = false
    @State private var problem: String?
    @State private var saving = false
    @State private var confirmDelete = false
    @FocusState private var amountFocused: Bool

    private var heading: String {
        switch draft.mode {
        case .put: "存一笔"
        case .take: "取出来"
        case .edit: "改一笔"
        }
    }
    private var saveLabel: String {
        switch draft.mode {
        case .put: "存进去"
        case .take: "取出来"
        case .edit: "保存"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 6) {
                        Text("¥").foregroundStyle(Ink.secondary)
                        TextField("多少钱", text: $amount).keyboardType(.decimalPad).focused($amountFocused)
                            .monospacedDigit()
                    }
                    TextField("备注（可以不写）", text: $note)
                } header: {
                    Text(draft.entry == nil ? (take ? "从「\(jarTitle)」里拿出来" : "放进「\(jarTitle)」") : "「\(jarTitle)」里的一笔")
                }
                if let entry = draft.entry {
                    Section {
                        Picker("这一笔是", selection: $take) {
                            Text("存进去").tag(false)
                            Text("取出来").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    Section {
                        HStack(spacing: 6) {
                            Text("这一笔是")
                            JarActorTag(actor: entry.actor)
                            Text("放的")
                        }
                        .font(.system(size: 13)).foregroundStyle(Ink.secondary)
                        Button("删掉这一笔", role: .destructive) { confirmDelete = true }
                            .disabled(saving)
                    }
                }
                if let problem {
                    Section { Text(problem).font(.system(size: 14)).foregroundStyle(Ink.negative) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(paper.ignoresSafeArea())
            .navigationTitle(heading).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button(saveLabel) { save() }.accessibilityIdentifier("jar-money-save") }
                }
            }
            .confirmationDialog("删掉这一笔？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删掉", role: .destructive) { remove() }
            } message: { Text("删了之后 5 秒内可以撤销。") }
        }
        .tint(Ink.accent)
        .interactiveDismissDisabled(saving)
        .onAppear {
            switch draft.mode {
            case .put: take = false; amountFocused = true
            case .take: take = true; amountFocused = true
            case let .edit(entry):
                amount = JarText.yuanField(entry.amount_cents)
                note = entry.note
                take = entry.amount_cents < 0
            }
        }
    }

    private func save() {
        guard let value = JarText.parseYuan(amount) else {
            problem = "金额写一个大于 0 的数就好，比如 200。"
            return
        }
        problem = nil
        saving = true
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let failure = await onSave(value, take, text)
            saving = false
            if let failure { problem = failure } else { dismiss() }
        }
    }

    private func remove() {
        problem = nil
        saving = true
        Task {
            let failure = await onDelete()
            saving = false
            if let failure { problem = failure } else { dismiss() }
        }
    }
}

// MARK: - 新罐子 / 改罐子

struct JarFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// nil 是新罐子
    let jar: Jar?
    let paper: Color
    /// 名字、目标（元）、日期（"YYYY-MM-DD" 或 ""）→ 成功回 nil，不成功回一句中文
    var onSave: (String, Double, String) async -> String?
    @State private var title = ""
    @State private var target = ""
    @State private var hasDate = false
    @State private var date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var problem: String?
    @State private var saving = false

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    /// 改罐子时原来的日期已经过了，也让它留在能选的范围里
    private var earliest: Date {
        guard let jar, let old = JarText.dayFormatter.date(from: jar.deadline) else { return today }
        return min(today, old)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名字") {
                    TextField("比如：一起去海边", text: $title)
                }
                Section("目标金额") {
                    HStack(spacing: 6) {
                        Text("¥").foregroundStyle(Ink.secondary)
                        TextField("比如 3000", text: $target).keyboardType(.decimalPad).monospacedDigit()
                    }
                }
                Section {
                    Toggle("定个日期", isOn: $hasDate.animation(reduceMotion ? nil : .easeOut(duration: 0.2)))
                    if hasDate {
                        DatePicker("想在哪天前攒好", selection: $date, in: earliest..., displayedComponents: .date)
                    }
                } footer: {
                    Text("不定日期也可以，慢慢来。")
                }
                if let problem {
                    Section { Text(problem).font(.system(size: 14)).foregroundStyle(Ink.negative) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(paper.ignoresSafeArea())
            .navigationTitle(jar == nil ? "新罐子" : "改罐子").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button(jar == nil ? "放好" : "保存") { save() }.accessibilityIdentifier("jar-form-save") }
                }
            }
        }
        .tint(Ink.accent)
        .interactiveDismissDisabled(saving)
        .onAppear {
            guard let jar else { return }
            title = jar.title
            target = jar.target_cents > 0 ? JarText.yuanField(jar.target_cents) : ""
            if let old = JarText.dayFormatter.date(from: jar.deadline) { hasDate = true; date = old }
        }
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { problem = "给罐子起个名字吧。"; return }
        guard name.count <= 20 else { problem = "名字短一点吧，20 个字以内。"; return }
        guard let goal = JarText.parseYuan(target) else { problem = "目标金额写一个大于 0 的数就好，比如 3000。"; return }
        if hasDate && jar == nil && date < today { problem = "日期选今天或以后吧。"; return }
        problem = nil
        saving = true
        let deadline = hasDate ? JarText.dayFormatter.string(from: date) : ""
        Task {
            let failure = await onSave(name, goal, deadline)
            saving = false
            if let failure { problem = failure } else { dismiss() }
        }
    }
}

// MARK: - 撤销条

/// 删掉以后底下浮一条「撤销」，5 秒自己收起（开着读屏就多等一会儿）
struct JarUndoBar: View {
    @ObservedObject var store: JarStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        ZStack {
            if let undo = store.pendingUndo {
                HStack(spacing: 12) {
                    Text(undo.text).font(Ink.song(15)).foregroundStyle(Ink.primary).lineLimit(2).monospacedDigit()
                    Spacer(minLength: 8)
                    Button("撤销") { Task { await store.revert(undo) } }
                        .font(Ink.song(15)).foregroundStyle(Ink.accent)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("jars-undo")
                }
                .padding(.leading, 20).padding(.trailing, 10)
                .background { KeGlass(shape: Capsule(), minPaper: 0.85) }
                .overlay(Capsule().stroke(Ink.line.opacity(0.45), lineWidth: 0.7))
                .padding(.horizontal, 20).padding(.bottom, 12)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .task(id: undo.id) {
                    AccessibilityNotification.Announcement(undo.text + "，可以撤销").post()
                    try? await Task.sleep(nanoseconds: (voiceOver ? 10 : 5) * 1_000_000_000)
                    store.expireUndo(undo.id)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: store.pendingUndo?.id)
    }
}
