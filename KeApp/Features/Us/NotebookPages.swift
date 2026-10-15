import SwiftUI

// 101：「我们」页锦鲤池里的四本小本子：荷包、食单、药盒、纸条。
// 柯在聊天里顺手记（服务器 ke_notebook，暗号 spend/meal/rx…），她在这里记、改、删；谁记的都写着「柯记的 / 我记的」，
// 改了别人记的再加一个「柯改过 / 我改过」，不冒充原作者。颜色、字号照 GPT 的 Design/KeUs/spec/tokens.json。

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
    static let primary = Color(hex: 0x3D5478)
    static let secondary = Color(hex: 0x5C6B7D)
    static let line = Color(hex: 0xA8B6BE)
    static let accent = Color(hex: 0x526D88)
    static let periodFill = Color(hex: 0xF5D7DF)
    static let keText = Color(hex: 0x3D5E73), keFill = Color(hex: 0xE8F0F4)
    static let meText = Color(hex: 0x795363), meFill = Color(hex: 0xF5E8ED)
    static let positive = Color(hex: 0x466859), neutral = Color(hex: 0x626C76), negative = Color(hex: 0x905664)
    static let track = Color(hex: 0xE4E9EE), saving = Color(hex: 0xB8788B)
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

private func yuan(_ cents: Int?) -> String {
    guard let cents else { return "" }
    let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = cents % 100 == 0 ? 0 : 2
    return "¥" + (f.string(from: NSNumber(value: Double(cents) / 100)) ?? "\(cents / 100)")
}
private func shortDay(_ day: String?) -> String {
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
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.92)))
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

struct PursePage: View {
    @ObservedObject var store: NotebookStore
    let paper: Color
    var onClose: () -> Void
    @State private var draft: NotebookDraft?
    @State private var editingCap = false
    @State private var capText = ""
    @State private var savingMoney = false
    @State private var saveText = ""

    var body: some View {
        NotebookShell(title: "荷包", script: "Bourse", paper: paper, onClose: onClose) {
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
                        if p.spends.isEmpty { empty("这个月还没有记账") }
                    }
                    AddLine(title: "我记一笔") { draft = spendDraft(nil) }
                }
            } else { loading }
        }
        .sheet(item: $draft) { d in editor(d) }
        .alert("每月上限", isPresented: $editingCap) {
            TextField("比如 3000", text: $capText).keyboardType(.decimalPad)
            Button("取消", role: .cancel) {}
            Button("保存") { if let v = Double(capText) { Task { await store.run { try await store.api.setNotebookCap(yuan: v) } } } }
        } message: { Text("这个月最多花多少，柯也会照这个数提醒你。") }
        .alert("存进去一笔", isPresented: $savingMoney) {
            TextField("金额", text: $saveText).keyboardType(.decimalPad)
            Button("取消", role: .cancel) {}
            Button("存") { if let v = Double(saveText), v > 0 { Task { await store.run { try await store.api.saveNotebookMoney(yuan: v, note: "") } } } }
        }
    }

    private func summary(_ p: NotebookSnapshot.Purse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(p.cap_cents > 0 ? ((p.left_cents ?? 0) >= 0 ? "这个月还能花" : "这个月超出了") : "这个月已经花了")
                .font(.system(size: 12)).tracking(2).foregroundStyle(Ink.secondary)
            Text(p.cap_cents > 0 ? yuan(abs(p.left_cents ?? 0)) : yuan(p.spent_cents))
                .font(Ink.latin(40)).monospacedDigit()
                .foregroundStyle((p.left_cents ?? 0) < 0 ? Ink.negative : Ink.primary)
            if p.cap_cents > 0 {
                bar(Double(max(0, p.left_cents ?? 0)) / Double(p.cap_cents), color: Ink.accent)
            }
            Button { capText = p.cap_cents > 0 ? String(p.cap_cents / 100) : ""; editingCap = true } label: {
                HStack {
                    Text("已花 " + yuan(p.spent_cents))
                    Spacer()
                    Text(p.cap_cents > 0 ? "每月上限 " + yuan(p.cap_cents) + " ›" : "定个每月上限 ›")
                }.font(.system(size: 12.5)).foregroundStyle(Ink.secondary)
            }.buttonStyle(.plain)
            if let goal = p.savings.first {
                Button { saveText = ""; savingMoney = true } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("一起存 · \(goal.title)")
                            Spacer()
                            Text("\(yuan(goal.saved_cents)) / \(yuan(goal.target_cents)) ›").monospacedDigit()
                        }.font(.system(size: 12.5)).foregroundStyle(Ink.secondary)
                        bar(goal.target_cents > 0 ? Double(goal.saved_cents) / Double(goal.target_cents) : 0, color: Ink.saving)
                    }
                }.buttonStyle(.plain).padding(.top, 8)
            }
        }
    }
    private func bar(_ value: Double, color: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.track)
                Capsule().fill(color).frame(width: g.size.width * min(1, max(0, value)))
            }
        }.frame(height: 6)
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

    private func hit(_ i: NotebookItem) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return [i.title, i.place ?? "", i.note ?? ""].contains { $0.localizedCaseInsensitiveContains(q) }
    }

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
            if let m = store.snapshot?.menu {
                NotebookSection(title: "吃过的", hint: "好不好吃，柯都记着") {
                    VStack(spacing: 0) {
                        ForEach(m.meals.filter(hit)) { meal in
                            NotebookRow(title: meal.title, trailing: shortDay(meal.day), detail: meal.place ?? "",
                                        quote: meal.note, author: meal.author, editedBy: meal.edited_by,
                                        chip: meal.rate.map { StatusChip(text: rateText($0), tone: $0 == "good" ? .good : $0 == "bad" ? .wait : .plain) }) { draft = mealDraft(meal) }
                        }
                        if !query.isEmpty && m.meals.filter(hit).isEmpty {
                            Text("没搜到「\(query)」").font(Ink.song(14)).foregroundStyle(Ink.secondary).frame(maxWidth: .infinity).padding(.vertical, 18)
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
