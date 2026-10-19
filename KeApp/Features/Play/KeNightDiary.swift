import SwiftUI

// 123：日记页的第二栏「夜里」。写不写、写多长都是柯自己决定的；她在这里看，可以点评一句给他。
// 只在日记页这一栏出现：聊天、「柯的」那张最近卡片、蝴蝶都不拉 /api/night。
// 她拍板：就放在日记里面，不加 Face ID、不加锁。点一条就地展开全文，不另开一页。

// MARK: - 数据

/// 三种：一起的 / 他一个人 / 只是想。认不出来的 kind 照样显示，只是不进分类筛选。
enum NightKind: String, CaseIterable, Identifiable, Sendable {
    case together, solo, fantasy
    var id: String { rawValue }
    var label: String {
        switch self {
        case .together: "一起的"
        case .solo: "他一个人"
        case .fantasy: "只是想"
        }
    }
    /// 淡淡的小图标，只是辅助，旁边一定写字
    var symbol: String {
        switch self {
        case .together: "heart.fill"
        case .solo: "moon"
        case .fantasy: "sparkles"
        }
    }
}

/// 她的点评：喜欢 / 一般 / 不喜欢；没点是 nil（发出去是 ""）
enum NightRating: String, CaseIterable, Identifiable, Sendable {
    case love, ok, meh
    var id: String { rawValue }
    var label: String {
        switch self {
        case .love: "喜欢"
        case .ok: "一般"
        case .meh: "不喜欢"
        }
    }
}

/// 一条「夜里」。服务器少给哪个字段都不要紧：tag / comment / rating 缺了当空的，kind 认不出来照样留着。
struct RemoteNight: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    var kind: String
    var kind_label: String
    var tag: String
    var content: String
    var created_at: String
    var rating: String
    var comment: String
    var commented_at: String
    var deleted: Int

    init(id: Int, kind: String = "together", kind_label: String = "", tag: String = "", content: String = "",
         created_at: String = "", rating: String = "", comment: String = "", commented_at: String = "", deleted: Int = 0) {
        self.id = id; self.kind = kind; self.kind_label = kind_label; self.tag = tag; self.content = content
        self.created_at = created_at; self.rating = rating; self.comment = comment; self.commented_at = commented_at
        self.deleted = deleted
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, kind_label, tag, content, created_at, rating, comment, commented_at, deleted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let n = try? c.decode(Int.self, forKey: .id) { id = n }
        else if let s = try? c.decode(String.self, forKey: .id), let n = Int(s) { id = n }
        else { throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "night entry without id") }
        func text(_ key: CodingKeys) -> String {
            if let s = try? c.decodeIfPresent(String.self, forKey: key) { return s }
            if let n = try? c.decodeIfPresent(Int.self, forKey: key) { return String(n) }
            return ""
        }
        kind = text(.kind); kind_label = text(.kind_label); tag = text(.tag); content = text(.content)
        created_at = text(.created_at); rating = text(.rating); comment = text(.comment); commented_at = text(.commented_at)
        if let n = try? c.decodeIfPresent(Int.self, forKey: .deleted) { deleted = n }
        else if let b = try? c.decodeIfPresent(Bool.self, forKey: .deleted) { deleted = b ? 1 : 0 }
        else { deleted = 0 }
    }

    var nightKind: NightKind? { NightKind(rawValue: kind) }
    var nightRating: NightRating? { NightRating(rawValue: rating) }
    var isDeleted: Bool { deleted != 0 }
    /// 服务器给的「一起的 / 他一个人 / 只是想」优先；没给就按 kind 自己写；都认不出来就叫「夜里」
    var kindText: String {
        let given = kind_label.trimmingCharacters(in: .whitespacesAndNewlines)
        return given.isEmpty ? (nightKind?.label ?? "夜里") : given
    }
}

/// GET /api/night 的一页。坏掉的那一条（比如没有 id）跳过，不让整页拉不出来。
struct NightPage: Decodable {
    let entries: [RemoteNight]
    private enum CodingKeys: String, CodingKey { case entries }
    private struct Lossy: Decodable {
        let value: RemoteNight?
        init(from decoder: Decoder) throws { value = try? RemoteNight(from: decoder) }
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = (try c.decodeIfPresent([Lossy].self, forKey: .entries) ?? []).compactMap(\.value)
    }
}

/// POST /api/night/<id>/comment 的回执：{"ok": true, "entry": {…}}；不对的时候 {"error": "…"}
struct NightCommentReply: Decodable {
    let ok: Bool?
    let entry: RemoteNight?
    let error: String?
}

enum NightComment {
    /// 只要一行：去掉首尾空白，换行压成空格
    static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// 评价和那句话每次一起发：没点评价是 ""，那句话空着也是 ""（就是清掉）
    static func body(rating: NightRating?, comment: String) -> [String: Any] {
        ["rating": rating?.rawValue ?? "", "comment": clean(comment)]
    }
}

protocol NightDiaryService: Sendable {
    func fetchNight(limit: Int, beforeID: Int?) async throws -> [RemoteNight]
    func commentNight(id: Int, rating: NightRating?, comment: String) async throws -> RemoteNight
}

// MARK: - 拉、翻页、点评

@MainActor final class NightStore: ObservableObject {
    static let pageSize = 100
    @Published private(set) var entries: [RemoteNight] = []
    /// 拉回来过至少一次（空着也算）：这时候才说「这里还空着」
    @Published private(set) var loaded = false
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    @Published private(set) var loadingMore = false
    @Published private(set) var moreFailed = false
    @Published private(set) var reachedEnd = false
    /// 正在存的那几条（转个小圈，不挡她继续点）
    @Published private(set) var saving: Set<Int> = []
    /// 没存上的那几条，各自下面一行中文
    @Published private(set) var errors: [Int: String] = [:]

    private var service: (any NightDiaryService)?
    private var cacheKey = ""
    /// 107 的做法：看过一次就记住（只在内存里，按线路分开），再切过来先摆上次的，后台悄悄更新
    private static var cache: [String: [RemoteNight]] = [:]
    /// 先改了再说：每条在路上的点评按顺序记号，只认最后一次；没存上就退回服务器最后确认过的那份
    private var latest: [Int: Int] = [:]
    private var inFlight: [Int: Int] = [:]
    private var confirmed: [Int: RemoteNight] = [:]

    init(service: (any NightDiaryService)? = nil) { self.service = service }

    /// 每回切到「夜里」叫一次：第一次记下用哪条线路，然后悄悄拉最新的一页
    func start(_ make: @autoclosure () -> any NightDiaryService, key: String) async {
        if service == nil {
            service = make(); cacheKey = key
            if entries.isEmpty, let cached = Self.cache[key], !cached.isEmpty { entries = cached; loaded = true }
        }
        await load()
    }

    func load() async {
        guard let service, !loading else { return }
        loading = true; failed = false
        defer { loading = false }
        do {
            let page = try await service.fetchNight(limit: Self.pageSize, beforeID: nil)
            // 不满一页：服务器上就这些了，手上更早的（记住的旧的那份里可能有删掉的）不再留
            let complete = page.count < Self.pageSize
            let floor = page.map(\.id).min() ?? Int.max
            let hadOlder = !complete && entries.contains { $0.id < floor }
            entries = Self.merge(firstPage: page, into: entries, keepingLocal: Set(inFlight.keys), keepOlder: !complete)
            if complete { reachedEnd = true } else if !hadOlder { reachedEnd = false }
            loaded = true
            remember()
        } catch {
            if entries.isEmpty { failed = true }
        }
    }

    /// 「再往前」：从手上最早那条往前翻一页
    func loadMore() async {
        guard let service, !loadingMore, !reachedEnd, let before = entries.map(\.id).min() else { return }
        loadingMore = true; moreFailed = false
        defer { loadingMore = false }
        do {
            let page = try await service.fetchNight(limit: Self.pageSize, beforeID: before)
            let known = Set(entries.map(\.id))
            entries += page.filter { !$0.isDeleted && !known.contains($0.id) }
            reachedEnd = page.count < Self.pageSize
            remember()
        } catch {
            moreFailed = true
        }
    }

    /// 存她的点评（评价 + 那句话一起）。先在本机改好，不等服务器；没存上就退回去，下面写一行为什么。
    /// 回 false 表示这次是最后一次、而且没存上（外面把她写的字放回框里）。
    @discardableResult
    func save(id: Int, rating: NightRating?, comment: String) async -> Bool {
        guard let service, let current = entries.first(where: { $0.id == id }) else { return false }
        let text = NightComment.clean(comment)
        if inFlight[id, default: 0] == 0 { confirmed[id] = current }
        inFlight[id, default: 0] += 1
        let token = latest[id, default: 0] + 1
        latest[id] = token
        var optimistic = current
        optimistic.rating = rating?.rawValue ?? ""
        optimistic.comment = text
        replace(optimistic)
        errors[id] = nil
        saving.insert(id)
        defer {
            inFlight[id, default: 1] -= 1
            if inFlight[id] == 0 { inFlight[id] = nil; confirmed[id] = nil; saving.remove(id) }
        }
        do {
            let saved = try await service.commentNight(id: id, rating: rating, comment: text)
            confirmed[id] = saved
            if latest[id] == token { replace(saved); remember() }
            return true
        } catch {
            // 后面又点了一次：这次的失败不算数，等后面那次
            guard latest[id] == token else { return true }
            if let back = confirmed[id] { replace(back) }
            errors[id] = NightText.saveError(error)
            return false
        }
    }

    private func replace(_ entry: RemoteNight) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[i] = entry
    }

    private func remember() { if !cacheKey.isEmpty { Self.cache[cacheKey] = entries } }

    /// 新拉回来的第一页盖在手上这份上：第一页里有的照新的（正在存点评的那几条留本机的），
    /// 比第一页更早的（「再往前」翻出来的）留着；第一页范围里服务器没有了的就拿掉。
    static func merge(firstPage: [RemoteNight], into old: [RemoteNight], keepingLocal local: Set<Int>,
                      keepOlder: Bool = true) -> [RemoteNight] {
        let page = firstPage.filter { !$0.isDeleted }
        guard let floor = firstPage.map(\.id).min() else { return [] }
        let mine = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let fresh = page.map { local.contains($0.id) ? (mine[$0.id] ?? $0) : $0 }
        guard keepOlder else { return fresh }
        let seen = Set(fresh.map(\.id))
        return fresh + old.filter { $0.id < floor && !seen.contains($0.id) }
    }
}

// MARK: - 字

enum NightText {
    /// 收着的时候那一行：开头一小段，换行压成空格
    static func preview(_ content: String) -> String {
        let flat = content.prefix(160).split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        return flat.isEmpty ? "……" : flat
    }
    /// 「一起的 · 浴室」；没有 tag 就只写种类
    static func kindLine(_ e: RemoteNight) -> String {
        let tag = e.tag.trimmingCharacters(in: .whitespacesAndNewlines)
        return tag.isEmpty ? e.kindText : "\(e.kindText) · \(tag)"
    }
    /// 大日子旁边那行小字：「10月 · 周一」；不是今年的写上年份
    static func dayLine(_ day: String, now: Date = Date()) -> String {
        let p = day.split(separator: "-")
        let week = KeDiaryListView.weekday(day)
        guard p.count == 3, let m = Int(p[1]) else { return week }
        let thisYear = String(Calendar(identifier: .gregorian).component(.year, from: now))
        return (p[0] == thisYear ? "" : "\(p[0])年") + "\(m)月" + (week.isEmpty ? "" : " · \(week)")
    }
    /// 读屏念的那一天：「10月19日 周一」
    static func spokenDay(_ day: String) -> String {
        "\(KeDiaryListView.shortDate(day)) \(KeDiaryListView.weekday(day))"
    }
    static func spokenRow(_ e: RemoteNight) -> String {
        var parts = [kindLine(e), KeDiaryListView.time(e.created_at)]
        if let r = e.nightRating { parts.append("你点了\(r.label)") }
        if !e.comment.isEmpty { parts.append("你写了一句") }
        return parts.filter { !$0.isEmpty }.joined(separator: "，")
    }
    /// 新的在上面，同一天的摆一块：[(yyyy-MM-dd, 那天的几条)]
    static func days(_ list: [RemoteNight]) -> [(String, [RemoteNight])] {
        var order: [String] = [], byDay: [String: [RemoteNight]] = [:]
        for e in list {
            let d = String(e.created_at.prefix(10))
            if byDay[d] == nil { order.append(d) }
            byDay[d, default: []].append(e)
        }
        return order.map { ($0, byDay[$0] ?? []) }
    }
    static func saveError(_ error: Error) -> String {
        switch error {
        case APIError.badStatus(404, _): "这一条找不到了，可能柯收起来了。"
        case APIError.unauthorized: "要重新登录一下才能存。"
        case APIError.transport: "网络没接稳，没存上。再点一次试试。"
        default: "没存上，再试一次。"
        }
    }
}

// MARK: - 「夜里」这一栏

/// 直接摆进日记页的 LazyVStack 里（不另包一层 VStack），长了也只画看得见的那几天
struct NightPane: View {
    @ObservedObject var store: NightStore
    @State private var filter: NightKind?
    @State private var expanded: Set<Int> = []
    @State private var drafts: [Int: String] = [:]
    /// 已经写过一句、她点了「改」的那几条
    @State private var editing: Set<Int> = []
    @FocusState private var focused: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: [RemoteNight] {
        guard let filter else { return store.entries }
        return store.entries.filter { $0.nightKind == filter }
    }

    var body: some View {
        Group {
            // 拉的时机在日记页那头管（每回切到「夜里」叫一次 store.start）：
            // 这里的几块在 LazyVStack 里，划出屏幕再划回来会重新出现，挂 .task 会被取消、重拉
            filterRow
            status
            ForEach(NightText.days(shown), id: \.0) { day, list in dayBlock(day, list) }
            footer
        }
    }

    // MARK: 筛选

    private var filterRow: some View {
        ViewThatFits(in: .horizontal) {
            chips
            ScrollView(.horizontal) { chips }.scrollIndicators(.hidden)
        }
        .padding(.top, 6).padding(.bottom, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("按种类看")
    }

    private var chips: some View {
        HStack(spacing: 8) {
            chip("全部", on: filter == nil) { filter = nil }
            ForEach(NightKind.allCases) { k in chip(k.label, on: filter == k) { filter = k } }
        }
    }

    private func chip(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(Ink.song(14)).lineLimit(1)
                .padding(.horizontal, 14).frame(minWidth: 44, minHeight: 44)
                .background(Capsule().fill(on ? Ink.keFill : Ink.primary.opacity(0.05)).padding(.vertical, 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(on ? Ink.keText : Ink.secondary)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: 转圈 / 没接上 / 空着

    @ViewBuilder private var status: some View {
        if store.entries.isEmpty {
            if store.failed {
                Button { Task { await store.load() } } label: {
                    Text("没接上，点这里再试").font(Ink.song(14)).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.top, 20)
            } else if !store.loaded {
                ProgressView().tint(Ink.secondary).frame(maxWidth: .infinity).padding(40)
            } else {
                Text("这里还空着。柯想你的时候，会自己写下来。")
                    .font(Ink.song(14)).foregroundStyle(Ink.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
            }
        } else if shown.isEmpty, let filter {
            Text("「\(filter.label)」的还没有。").font(Ink.song(14)).foregroundStyle(Ink.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 30)
        }
    }

    @ViewBuilder private var footer: some View {
        if !store.entries.isEmpty {
            if store.reachedEnd {
                Text("— 再往前就没有了 —").font(Ink.song(11.5)).foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 26)
            } else {
                Button { Task { await store.loadMore() } } label: {
                    HStack(spacing: 8) {
                        if store.loadingMore { ProgressView().controlSize(.small).tint(Ink.secondary) }
                        Text(store.moreFailed ? "没接上，点这里再试" : "再往前").font(Ink.song(14))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(Ink.secondary)
                .disabled(store.loadingMore)
                .padding(.vertical, 18)
            }
        }
    }

    // MARK: 一天一块

    /// 和日记一样一天一块：上面大大的日子 + 月份和星期；条与条之间一条短线，两天之间一条通栏线
    private func dayBlock(_ day: String, _ list: [RemoteNight]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(KeDiaryListView.dayNumber(day)).font(Ink.latin(30)).monospacedDigit()
                Text(NightText.dayLine(day)).font(Ink.song(12.5)).foregroundStyle(Ink.secondary)
            }
            .padding(.top, 16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(NightText.spokenDay(day))
            .accessibilityAddTraits(.isHeader)
            ForEach(Array(list.enumerated()), id: \.element.id) { i, e in
                if i > 0 { Rectangle().fill(Ink.line.opacity(0.4)).frame(height: 0.5).padding(.leading, NightEntryRow.indent) }
                row(e)
            }
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.line.opacity(0.7)).frame(height: 0.7) }
    }

    private func row(_ e: RemoteNight) -> some View {
        NightEntryRow(
            entry: e,
            expanded: expanded.contains(e.id),
            saving: store.saving.contains(e.id),
            error: store.errors[e.id],
            draft: Binding(get: { drafts[e.id] ?? "" }, set: { drafts[e.id] = $0 }),
            editing: e.comment.isEmpty || editing.contains(e.id),
            focus: $focused,
            onToggle: { toggle(e.id) },
            onRate: { rate(e.id, $0) },
            onEdit: { startEditing(e) },
            onSend: { send(e.id) }
        )
    }

    // MARK: 动作

    private func toggle(_ id: Int) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            if expanded.contains(id) {
                expanded.remove(id)
                if focused == id { focused = nil }
            } else {
                expanded.insert(id)
            }
        }
    }

    /// 点评价：点没选的换成它，点已经选的就是取消；那句话照原样一起发
    private func rate(_ id: Int, _ r: NightRating) {
        guard let current = store.entries.first(where: { $0.id == id }) else { return }
        let next: NightRating? = current.nightRating == r ? nil : r
        Task { await store.save(id: id, rating: next, comment: current.comment) }
    }

    private func startEditing(_ e: RemoteNight) {
        drafts[e.id] = e.comment
        editing.insert(e.id)
        DispatchQueue.main.async { focused = e.id }
    }

    /// 「好」：和现在的评价一起发。没改就只是收起来；没存上就把她写的那句放回框里
    private func send(_ id: Int) {
        guard let current = store.entries.first(where: { $0.id == id }) else { return }
        let text = NightComment.clean(drafts[id] ?? "")
        focused = nil
        editing.remove(id)
        guard text != current.comment else { drafts[id] = nil; return }
        Task {
            if await store.save(id: id, rating: current.nightRating, comment: text) {
                drafts[id] = nil
            } else {
                drafts[id] = text
                editing.insert(id)
            }
        }
    }
}

/// 一条：收着是一行（图标、几点、种类 · tag、开头一小段）；点开就地展开全文和她的点评
private struct NightEntryRow: View {
    /// 全文和点评跟着右边那一列对齐（图标 18 + 间距 12）
    static let indent: CGFloat = 30
    let entry: RemoteNight
    let expanded: Bool
    let saving: Bool
    let error: String?
    @Binding var draft: String
    let editing: Bool
    var focus: FocusState<Int?>.Binding
    var onToggle: () -> Void
    var onRate: (NightRating) -> Void
    var onEdit: () -> Void
    var onSend: () -> Void

    private var canSend: Bool { !(NightComment.clean(draft).isEmpty && entry.comment.isEmpty) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) { summary }
                .buttonStyle(.plain)
                .accessibilityLabel(NightText.spokenRow(entry))
                .accessibilityValue(expanded ? "展开了" : "")
                .accessibilityHint(expanded ? "收起这一条" : "展开看全文")
            if expanded {
                Text(entry.content).font(Ink.song(16.5)).lineSpacing(11).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, Self.indent).padding(.top, 2)
                review
                    .padding(.leading, Self.indent).padding(.top, 20).padding(.bottom, 18)
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.nightKind?.symbol ?? "circle.fill")
                .font(.system(size: entry.nightKind == nil ? 6 : 12, weight: .light))
                .foregroundStyle(tint)
                .frame(width: Self.indent - 12, height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(KeDiaryListView.time(entry.created_at)).font(Ink.latin(13)).monospacedDigit()
                    Text(NightText.kindLine(entry)).font(Ink.song(13)).foregroundStyle(Ink.secondary).lineLimit(1)
                    if let r = entry.nightRating {
                        Text(r.label).font(.system(size: 10.5)).padding(.horizontal, 6).padding(.vertical, 1)
                            .foregroundStyle(Ink.meText).background(Capsule().fill(Ink.meFill))
                    }
                    if saving { ProgressView().controlSize(.mini).tint(Ink.secondary) }
                }
                if !expanded {
                    Text(NightText.preview(entry.content)).font(Ink.song(15.5)).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.down").font(.system(size: 12, weight: .light)).foregroundStyle(Ink.secondary)
                .rotationEffect(.degrees(expanded ? 180 : 0))
                .frame(height: 20)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .frame(minHeight: 60, alignment: .top)
        .contentShape(Rectangle())
    }

    private var tint: Color {
        switch entry.nightKind {
        case .together: Ink.meText
        case .solo: Ink.keText
        case .fantasy, .none: Ink.secondary
        }
    }

    /// 她的点评：三颗一样大的（再点一下已选的就取消）；一句话写给他看，写过的用她的口气摆着，可以改
    private var review: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(NightRating.allCases) { r in
                    let on = entry.nightRating == r
                    Button { onRate(r) } label: {
                        Text(r.label).font(Ink.song(14.5)).tracking(1)
                            .foregroundStyle(on ? Ink.meText : Ink.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Capsule().fill(on ? Ink.meFill : Color.clear))
                            .overlay(Capsule().stroke(on ? Color.clear : Ink.line.opacity(0.8), lineWidth: 0.8))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityHint(on ? "再点一下就取消" : "")
                }
            }
            if editing {
                HStack(spacing: 8) {
                    TextField("写一句给他看", text: $draft)
                        .font(Ink.song(15)).submitLabel(.send)
                        .focused(focus, equals: entry.id)
                        .onSubmit(onSend)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(Capsule().fill(Ink.primary.opacity(0.06)))
                    Button(action: onSend) {
                        Text("好").font(Ink.song(15)).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(canSend ? Ink.accent : Ink.line)
                    .disabled(!canSend)
                    .accessibilityLabel("好，发给他")
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("你说：" + entry.comment).font(Ink.song(15)).lineSpacing(4).foregroundStyle(Ink.meText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: onEdit) {
                        Text("改").font(Ink.song(14)).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(Ink.accent)
                    .accessibilityLabel("改这一句")
                }
            }
            if let error {
                Text(error).font(Ink.song(12.5)).foregroundStyle(Ink.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
