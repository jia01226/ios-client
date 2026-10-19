import SwiftUI

// 101：「我们」页锦鲤池里的四本小本子：荷包、食单、药盒、纸条。
// 柯在聊天里顺手记（服务器 ke_notebook，暗号 spend/meal/rx…），她在这里记、改、删；谁记的都写着「柯记的 / 我记的」，
// 改了别人记的再加一个「柯改过 / 我改过」，不冒充原作者。颜色、字号照 GPT 的 Design/KeUs/spec/tokens.json。
// 121：荷包分成「花钱｜攒钱」两页；攒钱的罐子在 NotebookJars.swift。

// MARK: - 数据

struct NotebookItem: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    let kind: String
    let title: String
    let amount_cents: Int?
    let status: String?
    let place: String?
    let rate: String?
    let note: String?
    let day: String?
    let when: String?
    let dose: String?
    let done: Int
    let author: String
    let edited_by: String?
}

struct NotebookSavings: Decodable, Equatable, Sendable {
    let id: Int
    let title: String
    let target_cents: Int
    let saved_cents: Int
}

struct NotebookDose: Decodable, Equatable, Sendable {
    let taken: Bool
    let author: String?
}

struct NotebookLogLine: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
    let author: String
    let created_at: String
}

struct NotebookSnapshot: Decodable, Equatable, Sendable {
    struct Purse: Decodable, Equatable, Sendable {
        let month: String
        let cap_cents: Int
        let spent_cents: Int
        let left_cents: Int?
        let spends: [NotebookItem]
        let asks: [NotebookItem]
        let savings: [NotebookSavings]
    }
    struct Menu: Decodable, Equatable, Sendable {
        let meals: [NotebookItem]
        let owed: [NotebookItem]
    }
    struct Meds: Decodable, Equatable, Sendable {
        let rx: [NotebookItem]
        let today: [String: NotebookDose]
        let order: [String]?
        let log: [NotebookLogLine]
    }
    struct Verse: Decodable, Equatable, Sendable {
        let en: String
        let zh: String
    }
    let today: String
    let purse: Purse
    let menu: Menu
    let meds: Meds
    let verse: Verse?
}

@MainActor final class NotebookStore: ObservableObject {
    @Published private(set) var snapshot: NotebookSnapshot?
    @Published private(set) var busy = false
    @Published var error: String?
    let api: APIClient
    init(api: APIClient) { self.api = api }

    func load() async {
        do { snapshot = try await api.fetchNotebook(); error = nil }
        catch { self.error = "小本子暂时没接上，下拉或稍后再试。" }
    }
    /// 所有改动走这里：先发给服务器，成功了再整本刷新（柯那边也同时看到）。
    func run(_ work: @escaping () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { try await work(); await load() }
        catch { self.error = "没有保存成功，请再试一次。" }
    }
}

// MARK: - 样式（tokens.json · day）

enum Ink {
    // 126：字色、线、强调色跟着「纸色」走（默认粉白 = 设计稿 #564653 / #7A6572 / #8C617A），
    // 她自己挑过别的纸色的照旧是原来的蓝墨。值都在 Theme/CamelliaPalette.swift 的 CamelliaInks 里。
    private static var inks: CamelliaInks { CamelliaPalette.stored().inks }
    static var primary: Color { inks.primary }
    static var secondary: Color { inks.secondary }
    static var line: Color { inks.line }
    static var accent: Color { inks.accent }
    static var periodFill: Color { inks.periodFill }
    static let keText = Color(hex: 0x3D5E73), keFill = Color(hex: 0xE8F0F4)
    static let meText = Color(hex: 0x795363), meFill = Color(hex: 0xF5E8ED)
    static let positive = Color(hex: 0x466859), neutral = Color(hex: 0x626C76), negative = Color(hex: 0x905664)
    static var track: Color { inks.track }
    static var saving: Color { inks.saving }
    static var dockSelection: Color { inks.dockSelection }
    /// 121：额度条快见底时的两档：剩 10–30% 暖一点的琥珀，不到 10% 或花超了是软软的红（都不刺眼）
    static let amber = Color(hex: 0xC99A5E), softRed = Color(hex: 0xC27D80)
    /// 108：她喜欢以前那种瘦瘦的字——思源宋体的极细款。大字用极细，小字用细一档，免得看不清。聊天不跟这套。
    static func song(_ size: CGFloat) -> Font { .custom(size >= 17 ? "NotoSerifSC-ExtraLight" : "NotoSerifSC-Light", size: size) }
    /// 数字、日期也用同一款细字，和中文配套
    static func latin(_ size: CGFloat) -> Font { .custom(size >= 17 ? "NotoSerifSC-ExtraLight" : "NotoSerifSC-Light", size: size) }
    static func script(_ size: CGFloat) -> Font { .custom("PinyonScript-Regular", size: size) }
}

/// 「柯记的 / 我记的」，改过再加一句。颜色只是辅助，一定写字。
struct AuthorTag: View {
    let author: String
    var editedBy: String?
    var body: some View {
        HStack(spacing: 4) {
            Text(author == "ke" ? "柯记的" : "我记的")
                .font(.system(size: 12)).padding(.horizontal, 7).padding(.vertical, 1)
                .foregroundStyle(author == "ke" ? Ink.keText : Ink.meText)
                .background(Capsule().fill(author == "ke" ? Ink.keFill : Ink.meFill))
            if let editedBy, !editedBy.isEmpty, editedBy != author {
                Text(editedBy == "ke" ? "柯改过" : "我改过").font(.system(size: 11)).foregroundStyle(Ink.secondary)
            }
        }
    }
}

/// 121：攒钱那页（NotebookJars.swift）也用这两个，不再是 private
func yuan(_ cents: Int?) -> String {
    guard let cents else { return "" }
    let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = cents % 100 == 0 ? 0 : 2
    return "¥" + (f.string(from: NSNumber(value: Double(cents) / 100)) ?? "\(cents / 100)")
}
func shortDay(_ day: String?) -> String {
    guard let day, day.count >= 10 else { return day ?? "" }
    let parts = day.prefix(10).split(separator: "-")
    guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return day }
    return "\(m).\(d)"
}

/// 一本小本子的外壳：纸色底、标题 + 花体小字、「完成」返回。
struct NotebookShell<Content: View>: View {
    let title: String
    let script: String
    let paper: Color
    var onClose: () -> Void
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 0) {
                    Button("完成", action: onClose).font(Ink.song(15)).foregroundStyle(Ink.accent)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("notebook-close")
                    Text(title).font(Ink.song(28)).tracking(2).foregroundStyle(Ink.primary)
                    Text(script).font(Ink.script(27)).foregroundStyle(Ink.secondary).padding(.top, -4)
                }
                content()
            }
            .padding(.horizontal, 28).padding(.bottom, 48)
        }
        .background(paper.ignoresSafeArea())
        .foregroundStyle(Ink.primary)
    }
}

struct NotebookSection<Content: View>: View {
    let title: String
    var hint: String?
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(Ink.song(17)).tracking(1)
                Spacer()
                if let hint { Text(hint).font(.system(size: 12)).foregroundStyle(Ink.secondary) }
            }
            VStack(alignment: .leading, spacing: 12) { content() }
                .notebookCard()
        }
    }
}

extension View {
    /// 白卡片：圆角 18、一道细边，和网页那版一样。
    func notebookCard() -> some View {
        padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { KeGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), minPaper: 0.75) }
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Ink.line.opacity(0.45), lineWidth: 0.7))
    }
}

/// 状态小色块：柯点头了 / 先等等 / 好吃 / 踩雷……
struct StatusChip: View {
    let text: String
    let tone: Tone
    enum Tone { case good, wait, plain }
    var body: some View {
        Text(text).font(.system(size: 11.5)).padding(.horizontal, 8).padding(.vertical, 2)
            .foregroundStyle(tone == .good ? Ink.positive : tone == .wait ? Ink.negative : Ink.neutral)
            .background(Capsule().fill(tone == .good ? Color(hex: 0xE5F0E9) : tone == .wait ? Color(hex: 0xF6E7EA) : Ink.track))
    }
}

/// 一行：标题、右边金额或日期、下面一行小字和作者；点一下改。
struct NotebookRow: View {
    let title: String
    var trailing: String = ""
    var detail: String = ""
    var quote: String?
    let author: String
    var editedBy: String?
    var struck = false
    var chip: StatusChip?
    var onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(Ink.song(16)).strikethrough(struck).foregroundStyle(struck ? Ink.secondary : Ink.primary)
                    Spacer(minLength: 8)
                    Text(trailing).font(Ink.latin(16)).monospacedDigit()
                }
                HStack(spacing: 8) {
                    if let chip { chip }
                    if !detail.isEmpty { Text(detail).font(.system(size: 12)).foregroundStyle(Ink.secondary) }
                    AuthorTag(author: author, editedBy: editedBy)
                }
                if let quote, !quote.isEmpty {
                    Text("「\(quote)」").font(Ink.song(14)).foregroundStyle(Ink.secondary).lineSpacing(4)
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Ink.line.opacity(0.5)).frame(height: 0.5) }
        }
        .buttonStyle(.plain)
    }
}

struct AddLine: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("＋ " + title).font(Ink.song(15)).foregroundStyle(Ink.accent)
                .frame(maxWidth: .infinity, minHeight: 46)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Ink.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }.buttonStyle(.plain)
    }
}

// MARK: - 编辑一条（新记 / 改 / 删）

struct NotebookDraft: Identifiable {
    enum Field: String { case title, amount, status, place, rate, note, day, when, dose }
    let id = UUID()
    let kind: String
    var item: NotebookItem?
    var heading: String
    var fields: [(Field, String)]
}

struct NotebookEditor: View {
    @Environment(\.dismiss) private var dismiss
    let draft: NotebookDraft
    let paper: Color
    var onSave: ([String: Any]) -> Void
    var onDelete: (() -> Void)?
    @State private var values: [String: String] = [:]
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                ForEach(draft.fields, id: \.0.rawValue) { field, label in
                    switch field {
                    case .status:
                        Picker(label, selection: binding("status", default: "nod")) {
                            Text("柯点头了").tag("nod"); Text("先等等").tag("wait"); Text("没问就买了").tag("none")
                        }
                    case .rate:
                        Picker(label, selection: binding("rate", default: "good")) {
                            Text("好吃").tag("good"); Text("一般").tag("meh"); Text("踩雷").tag("bad")
                        }.pickerStyle(.segmented)
                    case .amount:
                        TextField(label, text: binding("amount")).keyboardType(.decimalPad)
                    default:
                        TextField(label, text: binding(field.rawValue))
                    }
                }
                if let item = draft.item {
                    Section {
                        HStack { Text("这条是"); AuthorTag(author: item.author, editedBy: item.edited_by) }
                            .font(.system(size: 13)).foregroundStyle(Ink.secondary)
                        if onDelete != nil {
                            Button("删掉这条", role: .destructive) { confirmDelete = true }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(paper.ignoresSafeArea())
            .navigationTitle(draft.heading).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(payload()); dismiss() }
                        .disabled((values["title"] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("删掉这条？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删掉", role: .destructive) { onDelete?(); dismiss() }
            } message: { Text("柯那边也会一起看不到这条。") }
        }
        .tint(Ink.accent)
        .onAppear { values = initialValues() }
    }

    private func binding(_ key: String, default value: String = "") -> Binding<String> {
        Binding(get: { values[key] ?? value }, set: { values[key] = $0 })
    }
    private func initialValues() -> [String: String] {
        guard let i = draft.item else { return [:] }
        var v: [String: String] = ["title": i.title]
        if let c = i.amount_cents { v["amount"] = c % 100 == 0 ? String(c / 100) : String(format: "%.2f", Double(c) / 100) }
        v["status"] = i.status; v["place"] = i.place; v["rate"] = i.rate; v["note"] = i.note
        v["day"] = i.day; v["when"] = i.when; v["dose"] = i.dose
        return v.compactMapValues { $0 }
    }
    private func payload() -> [String: Any] {
        var out: [String: Any] = [:]
        for (field, _) in draft.fields {
            let key = field.rawValue
            let value = (values[key] ?? (field == .status ? "nod" : field == .rate ? "good" : "")).trimmingCharacters(in: .whitespaces)
            if field == .amount { out["amount"] = value.isEmpty ? NSNull() : value as Any }
            else { out[key] = value }
        }
        return out
    }
}

// MARK: - 荷包

/// 121：标题下面一行「花钱｜攒钱」：选中的字深一点、底下一道细墨线，跟着滑过去
/// 123：从荷包里拿出来，日记页的「日记｜夜里」用同一个；左对齐还是居中由外面摆
struct InkTabSwitch<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    var identifier: (Option) -> String = { _ in "" }
    /// 读屏念的这一组是什么（「花钱或攒钱」）
    let accessibilityName: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tabSpace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                if index > 0 {
                    Text("｜").font(Ink.song(15)).foregroundStyle(Ink.line).accessibilityHidden(true)
                }
                let on = selection == option
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { selection = option }
                } label: {
                    Text(label(option)).font(Ink.song(17)).tracking(3)
                        .foregroundStyle(on ? Ink.primary : Ink.secondary)
                        .padding(.horizontal, 14)
                        .frame(minWidth: 44, minHeight: 44)
                        .overlay(alignment: .bottom) {
                            if on {
                                Capsule().fill(Ink.accent).frame(height: 1.2)
                                    .padding(.horizontal, 14).padding(.bottom, 5)
                                    .matchedGeometryEffect(id: "ink-tab-line", in: tabSpace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier(identifier(option))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityName)
    }
}

/// 121：荷包里的两页：花钱｜攒钱
enum PurseTab: String, CaseIterable, Identifiable {
    case spend, save
    var id: String { rawValue }
    var label: String { self == .spend ? "花钱" : "攒钱" }
}

/// 121：花钱页顶上那张额度卡要的数：还剩多少、剩百分之几、条子什么颜色、哪天重置
struct PurseQuota: Equatable {
    enum Tone: Equatable { case plenty, low, almostOut, over }
    let cap: Int
    let spent: Int
    let left: Int
    init(cap: Int, spent: Int, left: Int?) {
        self.cap = cap; self.spent = spent; self.left = left ?? (cap - spent)
    }
    var over: Bool { left < 0 }
    /// 剩下的比例（0…1），花超了算 0
    var leftRatio: Double { cap > 0 ? min(1, max(0, Double(left) / Double(cap))) : 0 }
    /// 往下取整，和条子颜色用同一个数，免得字写 30% 颜色却已经变了
    var leftPercent: Int { Int((leftRatio * 100).rounded(.down)) }
    /// 剩 30% 以上墨色；10–30% 琥珀；不到 10% 软红；花超了整条软红
    var tone: Tone {
        if over { return .over }
        if leftPercent > 30 { return .plenty }
        if leftPercent >= 10 { return .low }
        return .almostOut
    }
    var color: Color {
        switch tone {
        case .plenty: Ink.accent
        case .low: Ink.amber
        case .almostOut, .over: Ink.softRed
        }
    }
    /// "2026-10" → 下个月 1 号：「11月1日」；看不懂就按今天算
    static func resetDay(month: String, now: Date = Date()) -> String {
        let parts = month.split(separator: "-")
        var m: Int
        if parts.count >= 2, let parsed = Int(parts[1]), (1...12).contains(parsed) { m = parsed }
        else { m = Calendar.current.component(.month, from: now) }
        m = m % 12 + 1
        return "\(m)月1日"
    }
}

struct PursePage: View {
    @ObservedObject var store: NotebookStore
    let paper: Color
    var onClose: () -> Void
    /// 121：攒钱那页的罐子，跟着荷包一起开着，切来切去不重新转圈
    @StateObject private var jars: JarStore
    /// 121：记住她上次看的是花钱还是攒钱
    @AppStorage("notebook.purse.tab") private var tab = PurseTab.spend.rawValue
    @State private var draft: NotebookDraft?
    @State private var editingCap = false
    @State private var capText = ""
    /// 121：点开的那个罐子（盖在荷包上面一层，左边缘右划先收它）
    @State private var openJar: Int?

    init(store: NotebookStore, paper: Color, onClose: @escaping () -> Void) {
        _store = ObservedObject(wrappedValue: store)
        self.paper = paper
        self.onClose = onClose
        _jars = StateObject(wrappedValue: JarStore(api: store.api))
    }

    private var current: PurseTab { PurseTab(rawValue: tab) ?? .spend }

    var body: some View {
        ZStack {
            NotebookShell(title: "荷包", script: "Bourse", paper: paper, onClose: onClose) {
                tabSwitch
                if current == .save {
                    JarListPane(store: jars, paper: paper) { jar in openJar = jar.id }
                } else {
                    spendPane
                }
            }
            // 罐子盖着的时候，读屏只读上面那层
            .accessibilityHidden(openJar != nil)
            if let id = openJar {
                // 和日记点开一篇一样：直接盖上来，不放翻页动画
                JarDetailPage(store: jars, jarID: id, paper: paper) { openJar = nil }
                    .swipeBackLayer { openJar = nil }
                    .zIndex(1)
            }
        }
        // 删掉以后的「撤销」浮在最上面，罐子里外都看得到
        .overlay(alignment: .bottom) { JarUndoBar(store: jars) }
        .sheet(item: $draft) { d in editor(d) }
        .alert("每月上限", isPresented: $editingCap) {
            TextField("比如 3000", text: $capText).keyboardType(.decimalPad)
            Button("取消", role: .cancel) {}
            Button("保存") { if let v = Double(capText) { Task { await store.run { try await store.api.setNotebookCap(yuan: v) } } } }
        } message: { Text("这个月最多花多少，柯也会照这个数提醒你。") }
        .alert("没有成功", isPresented: Binding(get: { jars.notice != nil }, set: { if !$0 { jars.notice = nil } })) {
            Button("知道了", role: .cancel) { jars.notice = nil }
        } message: { Text(jars.notice ?? "") }
    }

    /// 121：标题下面一行「花钱｜攒钱」：选中的字深一点、底下一道细墨线，跟着滑过去
    /// 123：样子挪进 InkTabSwitch，日记页的「日记｜夜里」也用它
    private var tabSwitch: some View {
        InkTabSwitch(options: PurseTab.allCases,
                     selection: Binding(get: { current }, set: { tab = $0.rawValue }),
                     label: \.label, identifier: { "purse-tab-\($0.rawValue)" },
                     accessibilityName: "花钱或攒钱")
            .frame(maxWidth: .infinity, alignment: .leading)
            // 第一个字和「荷包」两个字左边对齐；离标题近一点
            .padding(.leading, -14)
            .padding(.top, -14)
    }

    @ViewBuilder private var spendPane: some View {
        if let p = store.snapshot?.purse {
            summary(p).notebookCard()
            NotebookSection(title: "问过柯的", hint: "几百块以上，先问再买") {
                VStack(spacing: 0) {
                    ForEach(p.asks) { a in
                        NotebookRow(title: a.title, trailing: yuan(a.amount_cents),
                                    quote: a.note, author: a.author, editedBy: a.edited_by,
                                    chip: StatusChip(text: a.status == "nod" ? "柯点头了" : a.status == "wait" ? "先等等" : "没问就买了",
                                                     tone: a.status == "nod" ? .good : a.status == "wait" ? .wait : .plain)) { draft = askDraft(a) }
                    }
                    if p.asks.isEmpty { empty("还没有问过的大件") }
                }
                AddLine(title: "问柯一件") { draft = askDraft(nil) }
            }
            NotebookSection(title: "这个月的流水", hint: "点一条可以改") {
                VStack(spacing: 0) {
                    ForEach(p.spends) { s in
                        NotebookRow(title: s.title, trailing: yuan(s.amount_cents), detail: shortDay(s.day),
                                    quote: s.note, author: s.author, editedBy: s.edited_by) { draft = spendDraft(s) }
                    }
                    if p.spends.isEmpty { empty("这个月还没有记过一笔") }
                }
                AddLine(title: "我记一笔") { draft = spendDraft(nil) }
            }
        } else { loading }
    }

    /// 121：照她认可的那张图：这个月还能花 → 大数字 → 一根条 → 已花 / 每月上限 → 剩几成、哪天重置。
    /// 这张总览卡上不放「我记的 / 柯记的」（那是每一笔自己的事）；「一起存」挪去攒钱页了。
    @ViewBuilder private func summary(_ p: NotebookSnapshot.Purse) -> some View {
        if p.cap_cents > 0 {
            let q = PurseQuota(cap: p.cap_cents, spent: p.spent_cents, left: p.left_cents)
            let reset = PurseQuota.resetDay(month: p.month)
            VStack(alignment: .leading, spacing: 10) {
                Text(q.over ? "这个月多花了一点" : "这个月还能花")
                    .font(Ink.song(14)).tracking(1).foregroundStyle(Ink.secondary)
                if q.over {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("超出").font(Ink.song(20))
                        Text(yuan(-q.left)).font(Ink.latin(40)).monospacedDigit()
                    }
                    // 字用深一点的玫瑰色（细字体上软红太浅看不清），条子才用软红
                    .foregroundStyle(Ink.negative)
                } else {
                    Text(yuan(q.left)).font(Ink.latin(40)).monospacedDigit()
                }
                NotebookBar(value: q.over ? 1 : q.leftRatio, color: q.color)
                    .padding(.top, 4)
                Button { capText = String(p.cap_cents / 100); editingCap = true } label: {
                    HStack {
                        Text("已花 " + yuan(p.spent_cents))
                        Spacer(minLength: 8)
                        Text("每月上限 " + yuan(p.cap_cents))
                    }
                    .font(Ink.song(13)).monospacedDigit().foregroundStyle(Ink.secondary)
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("点一下改每月上限")
                .accessibilityIdentifier("purse-cap")
                Text(q.over ? "\(reset)重置" : "剩 \(q.leftPercent)% · \(reset)重置")
                    .font(Ink.song(12)).monospacedDigit().foregroundStyle(Ink.secondary)
                    .padding(.top, -8)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("还没设这个月的额度").font(Ink.song(17))
                Text("这个月已花 " + yuan(p.spent_cents)).font(Ink.song(13)).monospacedDigit().foregroundStyle(Ink.secondary)
                Button("设一个") { capText = ""; editingCap = true }
                    .buttonStyle(InkPillStyle(filled: true))
                    .frame(maxWidth: 160)
                    .accessibilityIdentifier("purse-cap-set")
            }
        }
    }
    private func spendDraft(_ i: NotebookItem?) -> NotebookDraft {
        NotebookDraft(kind: "spend", item: i, heading: i == nil ? "记一笔" : "改一笔",
                      fields: [(.title, "买了什么"), (.amount, "多少钱"), (.day, "哪天（比如 10.14，不填就是今天）"), (.note, "备注")])
    }
    private func askDraft(_ i: NotebookItem?) -> NotebookDraft {
        NotebookDraft(kind: "ask", item: i, heading: i == nil ? "问柯一件" : "改一件",
                      fields: [(.title, "想买什么"), (.amount, "多少钱"), (.status, "柯怎么说"), (.note, "柯的话")])
    }
    private func editor(_ d: NotebookDraft) -> some View {
        NotebookEditor(draft: d, paper: paper, onSave: { fields in
            Task { await store.run {
                if let i = d.item { try await store.api.updateNotebookItem(id: i.id, fields: fields) }
                else { try await store.api.createNotebookItem(kind: d.kind, fields: fields) }
            } }
        }, onDelete: d.item.map { i in { Task { await store.run { try await store.api.deleteNotebookItem(id: i.id) } } } })
    }
    private var loading: some View { ProgressView().frame(maxWidth: .infinity).padding(40) }
    private func empty(_ text: String) -> some View {
        Text(text).font(Ink.song(14)).foregroundStyle(Ink.secondary).frame(maxWidth: .infinity).padding(.vertical, 18)
    }
}

// MARK: - 食单

struct MenuPage: View {
    @ObservedObject var store: NotebookStore
    let paper: Color
    var onClose: () -> Void
    @State private var draft: NotebookDraft?
    @State private var query = ""
    /// 118：评价筛选，nil 是全部；其余对应服务器上的 rate（good / meh / bad）
    @State private var rating: String?
    private static let ratings: [(String?, String)] = [(nil, "全部"), ("good", "好吃"), ("meh", "一般"), ("bad", "踩雷")]

    private func hit(_ i: NotebookItem) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return [i.title, i.place ?? "", i.note ?? ""].contains { $0.localizedCaseInsensitiveContains(q) }
    }
    /// 吃过的：搜索词 + 评价一起筛
    private func shownMeal(_ i: NotebookItem) -> Bool { hit(i) && (rating == nil || i.rate == rating) }

    var body: some View {
        NotebookShell(title: "食单", script: "Menu", paper: paper, onClose: onClose) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Ink.secondary)
                TextField("搜吃过的、哪家、柯说的话", text: $query).font(Ink.song(15)).submitLabel(.search)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.line) }
                        .buttonStyle(.plain).accessibilityLabel("清空搜索")
                }
            }
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Ink.line.opacity(0.45), lineWidth: 0.7))
            .accessibilityIdentifier("menu-search")
            ratingPicker
            if let m = store.snapshot?.menu {
                NotebookSection(title: "吃过的", hint: "好不好吃，柯都记着") {
                    VStack(spacing: 0) {
                        ForEach(m.meals.filter(shownMeal)) { meal in
                            NotebookRow(title: meal.title, trailing: shortDay(meal.day), detail: meal.place ?? "",
                                        quote: meal.note, author: meal.author, editedBy: meal.edited_by,
                                        chip: meal.rate.map { StatusChip(text: rateText($0), tone: $0 == "good" ? .good : $0 == "bad" ? .wait : .plain) }) { draft = mealDraft(meal) }
                        }
                        if !m.meals.isEmpty && m.meals.filter(shownMeal).isEmpty {
                            Text(query.isEmpty ? "没有记成「\(rateText(rating))」的" : "没搜到「\(query)」，换个词或评价试试")
                                .font(Ink.song(14)).foregroundStyle(Ink.secondary).frame(maxWidth: .infinity).padding(.vertical, 18)
                        }
                        if m.meals.isEmpty { Text("还没有记过吃的").font(Ink.song(14)).foregroundStyle(Ink.secondary).frame(maxWidth: .infinity).padding(.vertical, 18) }
                    }
                    AddLine(title: "我记一顿") { draft = mealDraft(nil) }
                }
                NotebookSection(title: "柯的账本上欠着的", hint: "胃好了一样一样兑现") {
                    VStack(spacing: 0) {
                        ForEach(m.owed.filter(hit)) { o in
                            HStack(spacing: 12) {
                                Button {
                                    Task { await store.run { try await store.api.updateNotebookItem(id: o.id, fields: ["done": o.done == 0]) } }
                                } label: {
                                    Image(systemName: o.done == 1 ? "checkmark.circle.fill" : "circle").font(.system(size: 22))
                                        .foregroundStyle(Ink.accent).frame(width: 44, height: 44)
                                }.buttonStyle(.plain).accessibilityLabel(o.done == 1 ? "已兑现" : "还欠着")
                                NotebookRow(title: o.title, author: o.author, editedBy: o.edited_by, struck: o.done == 1) { draft = owedDraft(o) }
                            }
                        }
                    }
                    AddLine(title: "再欠一样") { draft = owedDraft(nil) }
                }
            } else { ProgressView().frame(maxWidth: .infinity).padding(40) }
        }
        .sheet(item: $draft) { d in
            NotebookEditor(draft: d, paper: paper, onSave: { fields in
                Task { await store.run {
                    if let i = d.item { try await store.api.updateNotebookItem(id: i.id, fields: fields) }
                    else { try await store.api.createNotebookItem(kind: d.kind, fields: fields) }
                } }
            }, onDelete: d.item.map { i in { Task { await store.run { try await store.api.deleteNotebookItem(id: i.id) } } } })
        }
    }
    /// 一排小字筛选：全部 / 好吃 / 一般 / 踩雷，选中的那个浅浅垫一块底
    private var ratingPicker: some View {
        HStack(spacing: 6) {
            ForEach(Self.ratings, id: \.1) { value, label in
                let on = rating == value
                Button { rating = value } label: {
                    Text(label).font(Ink.song(14))
                        .foregroundStyle(on ? Ink.primary : Ink.secondary)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(Capsule().fill(on ? Ink.primary.opacity(0.06) : Color.clear).padding(.vertical, 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("menu-rate-\(value ?? "all")")
            }
            Spacer(minLength: 0)
        }
        .padding(.top, -16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("按评价筛选")
    }
    private func rateText(_ rate: String?) -> String { ["good": "好吃", "meh": "一般", "bad": "踩雷"][rate ?? ""] ?? "" }
    private func mealDraft(_ i: NotebookItem?) -> NotebookDraft {
        NotebookDraft(kind: "meal", item: i, heading: i == nil ? "记一顿" : "改一顿",
                      fields: [(.title, "吃了什么"), (.place, "哪家 / 自己做"), (.rate, "好不好吃"), (.note, "柯的一句话"), (.day, "哪天")])
    }
    private func owedDraft(_ i: NotebookItem?) -> NotebookDraft {
        NotebookDraft(kind: "owe", item: i, heading: i == nil ? "再欠一样" : "改一样", fields: [(.title, "欠着的好吃的")])
    }
}

// MARK: - 药盒

struct MedsPage: View {
    @ObservedObject var store: NotebookStore
    let paper: Color
    var onClose: () -> Void
    @State private var draft: NotebookDraft?

    var body: some View {
        NotebookShell(title: "药盒", script: "Remèdes", paper: paper, onClose: onClose) {
            if let m = store.snapshot?.meds {
                NotebookSection(title: "今天", hint: Self.todayText()) {
                    VStack(spacing: 0) {
                        ForEach(m.order ?? Array(m.today.keys).sorted(), id: \.self) { when in
                            let taken = m.today[when]?.taken ?? false
                            Button {
                                Task { await store.run { try await store.api.setNotebookDose(when: when, taken: !taken) } }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: taken ? "checkmark.circle.fill" : "circle").font(.system(size: 22)).foregroundStyle(Ink.accent)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(when)的药").font(Ink.song(16))
                                        Text(m.rx.filter { $0.when == when }.map(\.title).joined(separator: "、"))
                                            .font(.system(size: 12)).foregroundStyle(Ink.secondary)
                                    }
                                    Spacer()
                                    Text(taken ? "吃了" : "还没吃").font(.system(size: 12)).foregroundStyle(taken ? Ink.positive : Ink.secondary)
                                }
                                .padding(.vertical, 10).frame(minHeight: 44).contentShape(Rectangle())
                                .overlay(alignment: .bottom) { Rectangle().fill(Ink.line.opacity(0.5)).frame(height: 0.5) }
                            }.buttonStyle(.plain)
                        }
                        if m.rx.isEmpty { Text("药盒还是空的").font(Ink.song(14)).foregroundStyle(Ink.secondary).frame(maxWidth: .infinity).padding(.vertical, 18) }
                    }
                }
                NotebookSection(title: "现在在吃的", hint: "医生改了药，在这里改") {
                    VStack(spacing: 0) {
                        ForEach(m.rx) { r in
                            NotebookRow(title: r.title, trailing: r.dose ?? "", detail: r.when ?? "", author: r.author, editedBy: r.edited_by) { draft = rxDraft(r) }
                        }
                    }
                    AddLine(title: "加一种药") { draft = rxDraft(nil) }
                }
                if !m.log.isEmpty {
                    NotebookSection(title: "变动记录", hint: "谁改的、哪天改的") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(m.log.prefix(12)) { l in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(l.text).font(Ink.song(14))
                                    HStack { Text(shortDay(l.created_at)).font(.system(size: 12)).foregroundStyle(Ink.secondary); AuthorTag(author: l.author) }
                                }
                                .padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                                .overlay(alignment: .bottom) { Rectangle().fill(Ink.line.opacity(0.5)).frame(height: 0.5) }
                            }
                        }
                    }
                }
                Text("药量以医生说的为准。这里只是记下来，柯不会替你改药。")
                    .font(.system(size: 12)).foregroundStyle(Ink.secondary)
            } else { ProgressView().frame(maxWidth: .infinity).padding(40) }
        }
        .sheet(item: $draft) { d in
            NotebookEditor(draft: d, paper: paper, onSave: { fields in
                Task { await store.run {
                    if let i = d.item { try await store.api.updateNotebookItem(id: i.id, fields: fields) }
                    else { try await store.api.createNotebookItem(kind: d.kind, fields: fields) }
                } }
            }, onDelete: d.item.map { i in { Task { await store.run { try await store.api.deleteNotebookItem(id: i.id) } } } })
        }
    }
    private func rxDraft(_ i: NotebookItem?) -> NotebookDraft {
        NotebookDraft(kind: "rx", item: i, heading: i == nil ? "加一种药" : "改这种药",
                      fields: [(.title, "药名"), (.dose, "剂量"), (.when, "什么时候吃（早 / 餐后 / 晚 / 睡前）")])
    }
    private static func todayText() -> String {
        let c = Calendar.current.dateComponents([.month, .day], from: Date())
        return "\(c.month ?? 0) 月 \(c.day ?? 0) 日"
    }
}

// MARK: - 纸条（接原来的便利贴）

struct NotesPage: View {
    @ObservedObject var notes: StickyNotesStore
    let api: APIClient
    let paper: Color
    var onClose: () -> Void
    @State private var editing: StickyNote?
    @State private var adding = false
    @State private var text = ""

    var body: some View {
        NotebookShell(title: "纸条", script: "Billets", paper: paper, onClose: onClose) {
            NotebookSection(title: "贴着的", hint: "柯贴的点一下收起") {
                VStack(spacing: 0) {
                    ForEach(notes.notes.filter { !$0.acked }) { note in row(note) }
                    if notes.notes.filter({ !$0.acked }).isEmpty {
                        Text("没有贴着的纸条").font(Ink.song(14)).foregroundStyle(Ink.secondary).frame(maxWidth: .infinity).padding(.vertical, 18)
                    }
                }
                AddLine(title: "我贴一张") { text = ""; adding = true }
            }
            let done = notes.notes.filter(\.acked)
            if !done.isEmpty {
                NotebookSection(title: "收起来的") {
                    VStack(spacing: 0) { ForEach(done) { note in row(note) } }
                }
            }
        }
        .task { await notes.load() }
        .alert("贴一张纸条", isPresented: $adding) {
            TextField("一句话", text: $text)
            Button("取消", role: .cancel) {}
            Button("贴上") { save(id: "", content: text) }
        }
        .alert("改这张纸条", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("一句话", text: $text)
            Button("删掉", role: .destructive) { if let n = editing { Task { try? await api.deleteStickyNote(id: n.id); await notes.load() } } }
            Button("取消", role: .cancel) {}
            Button("保存") { if let n = editing { save(id: n.id, content: text) } }
        }
    }

    private func row(_ note: StickyNote) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { if note.acked { await notes.restore(note) } else { await notes.acknowledge(note) } }
            } label: {
                Image(systemName: note.acked ? "checkmark.circle.fill" : "circle").font(.system(size: 22))
                    .foregroundStyle(Ink.accent).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(note.acked ? "放回去" : "收起")
            NotebookRow(title: note.content, detail: shortDay(note.created_at), author: note.author == .ai ? "ke" : "me", struck: note.acked) {
                if note.author == .user { text = note.content; editing = note }
            }
        }
    }
    private func save(id: String, content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task { _ = try? await api.saveStickyNote(id: id, content: trimmed); await notes.load() }
    }
}
