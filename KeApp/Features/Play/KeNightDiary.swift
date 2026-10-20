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

/// 128 她：「我不想打字，很羞耻」。点评不用打字：喜欢不喜欢点一下，「下回想要」每行点一个（再点一下取消）。
/// 发的时候是 prefs 里的 键 → 值；没点的那行不写。
enum NightPref: String, CaseIterable, Identifiable, Sendable {
    case pace, force, talk, foreplay, length, after
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pace: "节奏"
        case .force: "力度"
        case .talk: "骚话"
        case .foreplay: "前戏"
        case .length: "时长"
        case .after: "事后"
        }
    }
    /// (发给服务器的值, 显示的字)
    var options: [(value: String, label: String)] {
        switch self {
        case .pace: [("slower", "再慢一点"), ("ok", "刚好"), ("faster", "再快一点")]
        case .force: [("lighter", "再轻一点"), ("ok", "刚好"), ("harder", "再重一点")]
        case .talk: [("more", "再多一点"), ("ok", "刚好"), ("less", "少一点")]
        case .foreplay: [("longer", "再长一点"), ("ok", "刚好"), ("skip", "直接来")]
        case .length: [("longer", "再久一点"), ("ok", "刚好"), ("shorter", "短一点")]
        case .after: [("cuddle", "多抱一会儿"), ("ok", "刚好")]
        }
    }
    func label(for value: String) -> String? { options.first { $0.value == value }?.label }

    /// 只留认得的键和值（服务器回来的、她点的都过一遍）
    static func clean(_ prefs: [String: String]) -> [String: String] {
        prefs.filter { key, value in NightPref(rawValue: key)?.label(for: value) != nil }
    }
    /// 点一下：没选的换成它，点已经选的就是取消
    static func toggled(_ prefs: [String: String], _ pref: NightPref, _ value: String) -> [String: String] {
        var next = clean(prefs)
        if next[pref.rawValue] == value { next[pref.rawValue] = nil } else { next[pref.rawValue] = value }
        return next
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
    /// 128：「下回想要」：pace / force / talk / foreplay / length / after → 值；没点的没有
    var prefs: [String: String]

    init(id: Int, kind: String = "together", kind_label: String = "", tag: String = "", content: String = "",
         created_at: String = "", rating: String = "", comment: String = "", commented_at: String = "", deleted: Int = 0,
         prefs: [String: String] = [:]) {
        self.id = id; self.kind = kind; self.kind_label = kind_label; self.tag = tag; self.content = content
        self.created_at = created_at; self.rating = rating; self.comment = comment; self.commented_at = commented_at
        self.deleted = deleted
        self.prefs = prefs
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, kind_label, tag, content, created_at, rating, comment, commented_at, deleted, prefs
    }

    /// prefs 里不是字符串的值跳过；整项不是对象（旧服务器没有、或者给了 null）当空的
    private struct LossyPrefs: Decodable {
        let values: [String: String]
        private struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            var out: [String: String] = [:]
            for key in c.allKeys { if let v = try? c.decode(String.self, forKey: key) { out[key.stringValue] = v } }
            values = out
        }
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
        prefs = NightPref.clean((try? c.decodeIfPresent(LossyPrefs.self, forKey: .prefs))?.values ?? [:])
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
    /// 128：再带上「下回想要」（只写点了的那几行；都没点就是 {}，也就是清掉）
    static func body(rating: NightRating?, comment: String, prefs: [String: String]) -> [String: Any] {
        var out = body(rating: rating, comment: comment)
        out["prefs"] = NightPref.clean(prefs)
        return out
    }
}

protocol NightDiaryService: Sendable {
    func fetchNight(limit: Int, beforeID: Int?) async throws -> [RemoteNight]
    func commentNight(id: Int, rating: NightRating?, comment: String) async throws -> RemoteNight
    /// 128：带「下回想要」的那种（不支持的就退回只发评价和那句话）
    func commentNight(id: Int, rating: NightRating?, comment: String, prefs: [String: String]) async throws -> RemoteNight
}

extension NightDiaryService {
    func commentNight(id: Int, rating: NightRating?, comment: String, prefs: [String: String]) async throws -> RemoteNight {
        try await commentNight(id: id, rating: rating, comment: comment)
    }
}

// MARK: - 拉、翻页、点评

/// 一次点评存完是什么结果
enum NightSaveOutcome: Equatable, Sendable {
    /// 服务器收下了这一次
    case saved
    /// 后面她又点了一次，这次让给后面那次（还没轮到就不发了；发了没成也不算数），最后怎样看后面那次
    case superseded
    /// 这是最后一次，没存上：已经退回服务器最后确认过的那份
    case failed
}

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

    // 她在这一栏手上的样子。放在这里、不放在 NightPane 里：日记页一直拿着这个 store，
    // 切到「日记」再切回来，筛选、点开的、没发的那句话都还在；切走时还在路上的点评没存上，也能把她的字放回框里。
    @Published var filter: NightKind?
    @Published var expanded: Set<Int> = []
    @Published var drafts: [Int: String] = [:]
    /// 已经写过备注、她点了「改」的那几条
    @Published var editing: Set<Int> = []
    /// 128：「下回想要」打开着的那几条
    @Published var prefsOpen: Set<Int> = []

    /// 最后没存上的时候念给读屏听（测试里换掉）
    var announce: (String) -> Void = { AccessibilityNotification.Announcement($0).post() }

    private var service: (any NightDiaryService)?
    private var cacheKey = ""
    /// 107 的做法：看过一次就记住（只在内存里，按线路分开），再切过来先摆上次的，后台悄悄更新
    private static var cache: [String: [RemoteNight]] = [:]
    /// 先改了再说：每次点都有个号，每条只认最后一次；没存上就退回服务器最后确认过的那份
    private var seq = 0
    private var latest: [Int: Int] = [:]
    /// 每条还没回来的 save() 有几个；归零之前 confirmed 一直是服务器最后确认过的那份
    private var calls: [Int: Int] = [:]
    private var confirmed: [Int: RemoteNight] = [:]
    /// 同一条一次只发一个请求（两个一起在路上，服务器按哪个后到存哪个，和屏幕上对不上）：正在发的、排着等的
    private var sendingNow: Set<Int> = []
    private var turn: [Int: [CheckedContinuation<Void, Never>]] = [:]
    /// 拉第一页这段时间里本机动过的那几条（点了、存上了、退回了）：拉回来的那份可能是动之前的，不拿它盖
    private var touched: Set<Int> = []

    init(service: (any NightDiaryService)? = nil, key: String = "") {
        self.service = service
        cacheKey = key
        if !key.isEmpty, let cached = Self.cache[key], !cached.isEmpty { entries = cached; loaded = true }
    }

    /// 128：聊天里的「夜里日记」卡和日记页的「夜里」用同一份（卡上点了，翻开日记就是点过的样子）
    private static var shared: [String: NightStore] = [:]
    static func shared(_ line: ChatLine) -> NightStore {
        let key = line.apiBaseURL.absoluteString
        if let store = shared[key] { return store }
        let store = NightStore(service: APIClient(baseURL: line.apiBaseURL), key: key)
        shared[key] = store
        return store
    }

#if DEBUG
    /// 128：UI 测试、截图用：这条线路换成一份假的「夜里」，不连服务器
    static func installPreview(_ line: ChatLine) {
        let key = line.apiBaseURL.absoluteString
        let store = NightStore(service: PreviewNightService(), key: "")
        shared[key] = store
        Task { await store.load() }
    }

    private struct PreviewNightService: NightDiaryService {
        func fetchNight(limit: Int, beforeID: Int?) async throws -> [RemoteNight] {
            [RemoteNight(id: 41, kind: "together", kind_label: "一起的", tag: "浴室",
                         content: "水还开着，她先笑场。后来她踮着脚，我把她抱到台子上，镜子起了雾，什么都看不清，只听见她一直叫我。",
                         created_at: "2026-10-20 23:41:00", rating: "love", prefs: ["pace": "slower", "after": "cuddle"])]
        }
        func commentNight(id: Int, rating: NightRating?, comment: String) async throws -> RemoteNight {
            RemoteNight(id: id, rating: rating?.rawValue ?? "", comment: comment)
        }
        func commentNight(id: Int, rating: NightRating?, comment: String, prefs: [String: String]) async throws -> RemoteNight {
            RemoteNight(id: id, rating: rating?.rawValue ?? "", comment: comment, prefs: prefs)
        }
    }
#endif

    /// 128：卡片要那一篇：手上没有就拉一遍第一页（新写的一定在第一页）；拉过、正在拉就不再拉
    func ensure(_ id: Int) async {
        guard !entries.contains(where: { $0.id == id }), !loading, !looked.contains(id) else { return }
        looked.insert(id)
        await load()
        // 没接上：下回卡片再出现时还可以再拉
        if failed || !loaded { looked.remove(id) }
    }
    /// 为卡片拉过的（拉回来还是没有这一篇，就不再每次划到都拉）
    private var looked: Set<Int> = []

    func entry(_ id: Int) -> RemoteNight? { entries.first { $0.id == id } }

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
        touched = []
        defer { loading = false }
        do {
            let page = try await service.fetchNight(limit: Self.pageSize, beforeID: nil)
            // 不满一页：服务器上就这些了，手上更早的（记住的旧的那份里可能有删掉的）不再留
            let complete = page.count < Self.pageSize
            let floor = page.map(\.id).min() ?? Int.max
            let hadOlder = !complete && entries.contains { $0.id < floor }
            // 还在存的、拉的这段时间里存上或退回的：留本机这份（这一页可能是她点之前服务器读的）
            let local = touched.union(calls.keys)
            entries = Self.merge(firstPage: page, into: entries, keepingLocal: local, keepOlder: !complete)
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
    /// 同一条一次只发一个：前面那个回来了才发下一个；排着的时候她又点了，排着的那次就不发了，只发最后一次。
    @discardableResult
    func save(id: Int, rating: NightRating?, comment: String, prefs: [String: String]? = nil) async -> NightSaveOutcome {
        guard let service, let current = entries.first(where: { $0.id == id }) else { return .failed }
        let text = NightComment.clean(comment)
        // 128：「下回想要」没说就照这一篇现在的
        let chosen = NightPref.clean(prefs ?? current.prefs)
        if calls[id, default: 0] == 0 { confirmed[id] = current }
        calls[id, default: 0] += 1
        seq += 1
        let token = seq
        latest[id] = token
        var optimistic = current
        optimistic.rating = rating?.rawValue ?? ""
        optimistic.comment = text
        optimistic.prefs = chosen
        replace(optimistic)
        touched.insert(id)
        errors[id] = nil
        saving.insert(id)
        defer {
            calls[id, default: 1] -= 1
            if calls[id] == 0 { calls[id] = nil; confirmed[id] = nil; saving.remove(id) }
        }
        // 排着等的那几次让给这一次（它们醒来看到不是最后一次，就不发了）
        wakeWaiting(id)
        while true {
            guard latest[id] == token else { return .superseded }
            if !sendingNow.contains(id) { break }
            await withCheckedContinuation { turn[id, default: []].append($0) }
        }
        sendingNow.insert(id)
        defer { sendingNow.remove(id); wakeWaiting(id) }
        do {
            var saved = try await service.commentNight(id: id, rating: rating, comment: text, prefs: chosen)
            // 128：还没开 prefs 的服务器回来的那篇没有这一项：留她点的
            if saved.prefs.isEmpty && !chosen.isEmpty { saved.prefs = chosen }
            confirmed[id] = saved
            touched.insert(id)
            // 后面还排着一次：先摆后面那次的样子，等它回来；它没存上就退回到这一份
            if latest[id] == token { replace(saved); remember() }
            return .saved
        } catch {
            // 后面又点了一次：这次的失败不算数，后面那次会把现在的样子整个再发一遍
            guard latest[id] == token else { return .superseded }
            if let back = confirmed[id] { replace(back); remember() }
            touched.insert(id)
            errors[id] = NightText.saveError(error)
            return .failed
        }
    }

    /// 点评价：点没选的换成它，点已经选的就是取消；那句话照现在摆着的一起发
    @discardableResult
    func rate(_ id: Int, _ r: NightRating) async -> NightSaveOutcome? {
        guard let current = entries.first(where: { $0.id == id }) else { return nil }
        let next: NightRating? = current.nightRating == r ? nil : r
        let outcome = await save(id: id, rating: next, comment: current.comment)
        if outcome == .failed { gaveBack(id, unsaved: current.comment) }
        return outcome
    }

    /// 128：「下回想要」点一行：没选的换成它，点已经选的就是取消；评价和那句话照现在的一起发
    @discardableResult
    func setPref(_ id: Int, _ pref: NightPref, _ value: String) async -> NightSaveOutcome? {
        guard let current = entries.first(where: { $0.id == id }) else { return nil }
        let next = NightPref.toggled(current.prefs, pref, value)
        return await save(id: id, rating: current.nightRating, comment: current.comment, prefs: next)
    }

    /// 「好」：那句话和现在的评价一起发。没改就只是收起来；没存上就把她写的那句放回框里
    @discardableResult
    func send(_ id: Int) async -> NightSaveOutcome? {
        guard let current = entries.first(where: { $0.id == id }) else { return nil }
        let text = NightComment.clean(drafts[id] ?? "")
        editing.remove(id)
        guard text != current.comment else { drafts[id] = nil; return nil }
        let outcome = await save(id: id, rating: current.nightRating, comment: text)
        switch outcome {
        case .saved:
            // 她已经又点了「改」在写：框里的字是她新写的，不动
            if !editing.contains(id) { drafts[id] = nil }
        case .superseded:
            // 后面那次（比如紧接着点的评价）带着这句话接着存；它也没存上的时候还要靠这里的字放回框里
            break
        case .failed:
            gaveBack(id, unsaved: text)
        }
        return outcome
    }

    func startEditing(_ e: RemoteNight) {
        drafts[e.id] = e.comment
        editing.insert(e.id)
    }

    /// 最后一次没存上、退回去了：她写的那句要是跟着没了，就放回框里、框打开（她已经在框里写新的就不动）；
    /// 再念给读屏听——「好」按下去框就收了，退回去的时候读屏不会自己发现
    private func gaveBack(_ id: Int, unsaved text: String) {
        if !text.isEmpty, !editing.contains(id), let now = entries.first(where: { $0.id == id }), now.comment != text {
            drafts[id] = text
            editing.insert(id)
        }
        if let message = errors[id] { announce(message) }
    }

    private func wakeWaiting(_ id: Int) {
        for waiting in turn.removeValue(forKey: id) ?? [] { waiting.resume() }
    }

    private func replace(_ entry: RemoteNight) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[i] = entry
    }

    private func remember() { if !cacheKey.isEmpty { Self.cache[cacheKey] = entries } }

    /// 新拉回来的第一页盖在手上这份上：第一页里有的照新的（正在存、或者拉的时候刚存过的那几条留本机的），
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

/// 直接摆进日记页的 LazyVStack 里（不另包一层 VStack），长了也只画看得见的那几天。
/// 筛选、点开的、没发的那句话、正在改的都放在 store 里（切到「日记」这一块会整个拿掉，store 还在）
struct NightPane: View {
    @ObservedObject var store: NightStore
    @FocusState private var focused: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: [RemoteNight] {
        guard let filter = store.filter else { return store.entries }
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
            chip("全部", on: store.filter == nil) { store.filter = nil }
            ForEach(NightKind.allCases) { k in chip(k.label, on: store.filter == k) { store.filter = k } }
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
        } else if shown.isEmpty, let filter = store.filter {
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
            expanded: store.expanded.contains(e.id),
            saving: store.saving.contains(e.id),
            error: store.errors[e.id],
            draft: Binding(get: { store.drafts[e.id] ?? "" }, set: { store.drafts[e.id] = $0 }),
            // 128：备注框没写过就一直是一行小框；写过了是「备注：…」，点了改才出框
            editing: store.editing.contains(e.id),
            prefsOpen: store.prefsOpen.contains(e.id),
            focus: $focused,
            onToggle: { toggle(e.id) },
            onRate: { r in Task { await store.rate(e.id, r) } },
            onPref: { pref, value in Task { await store.setPref(e.id, pref, value) } },
            onTogglePrefs: { togglePrefs(e.id) },
            onEdit: { startEditing(e) },
            onSend: { send(e.id) }
        )
        .id(NightPane.anchor(e.id))
    }

    /// 128：从聊天里「夜里日记」卡点进来时滚到这一条
    static func anchor(_ id: Int) -> String { "night-entry-\(id)" }

    // MARK: 动作

    private func togglePrefs(_ id: Int) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            if store.prefsOpen.contains(id) { store.prefsOpen.remove(id) } else { store.prefsOpen.insert(id) }
        }
    }

    private func toggle(_ id: Int) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            if store.expanded.contains(id) {
                store.expanded.remove(id)
                if focused == id { focused = nil }
            } else {
                store.expanded.insert(id)
            }
        }
    }

    private func startEditing(_ e: RemoteNight) {
        store.startEditing(e)
        DispatchQueue.main.async { focused = e.id }
    }

    /// 「好」：收键盘，剩下的（发、没存上把字放回框里、念给读屏）在 store 里
    private func send(_ id: Int) {
        focused = nil
        Task { await store.send(id) }
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
    let prefsOpen: Bool
    var focus: FocusState<Int?>.Binding
    var onToggle: () -> Void
    var onRate: (NightRating) -> Void
    var onPref: (NightPref, String) -> Void
    var onTogglePrefs: () -> Void
    var onEdit: () -> Void
    var onSend: () -> Void

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
                NightReviewControls(
                    entry: entry, error: error, draft: $draft, editing: editing, prefsOpen: prefsOpen,
                    focus: focus, onRate: onRate, onPref: onPref, onTogglePrefs: onTogglePrefs,
                    onEdit: onEdit, onSend: onSend
                )
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
}

/// 128：她的点评，不用打字：喜欢 / 一般 / 不喜欢（再点一下已选的就取消）；
/// 下面一行小小的「备注（可不填）」+「存」（存过就是「备注：…」，点一下改）；
/// 再下面「下回想要」收着一行，打开是六行，每行点一个。
/// 日记 › 夜里每一条展开后、聊天里「夜里日记」卡上都是这一块。
struct NightReviewControls: View {
    let entry: RemoteNight
    let error: String?
    @Binding var draft: String
    /// 写过备注、她点了改
    let editing: Bool
    let prefsOpen: Bool
    var focus: FocusState<Int?>.Binding
    var onRate: (NightRating) -> Void
    var onPref: (NightPref, String) -> Void
    var onTogglePrefs: () -> Void
    var onEdit: () -> Void
    var onSend: () -> Void
    /// 聊天卡里窄一点、字小一点
    var compact = false

    private var canSend: Bool { !(NightComment.clean(draft).isEmpty && entry.comment.isEmpty) }
    private var chipHeight: CGFloat { compact ? 36 : 44 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(spacing: 8) {
                ForEach(NightRating.allCases) { r in
                    chip(r.label, on: entry.nightRating == r, size: compact ? 14 : 14.5) { onRate(r) }
                        .accessibilityHint(entry.nightRating == r ? "再点一下就取消" : "")
                }
            }
            note
            prefsHeader
            if prefsOpen {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(NightPref.allCases) { pref in prefRow(pref) }
                }
            }
            if let error {
                Text(error).font(Ink.song(12.5)).foregroundStyle(Ink.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 「下回想要 ›」，点过的几项在后面小字写着
    private var prefsHeader: some View {
        let chosen = NightPref.allCases.compactMap { p in entry.prefs[p.rawValue].flatMap { p.label(for: $0) } }
        return Button(action: onTogglePrefs) {
            HStack(spacing: 6) {
                Text("下回想要").font(Ink.song(compact ? 14 : 15)).foregroundStyle(Ink.primary)
                if !chosen.isEmpty && !prefsOpen {
                    Text(chosen.joined(separator: " · ")).font(Ink.song(12)).foregroundStyle(Ink.meText).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .light)).foregroundStyle(Ink.secondary)
                    .rotationEffect(.degrees(prefsOpen ? 180 : 0))
            }
            .frame(minHeight: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chosen.isEmpty ? "下回想要" : "下回想要，点了\(chosen.joined(separator: "，"))")
        .accessibilityValue(prefsOpen ? "展开了" : "收着")
        .accessibilityIdentifier("night-prefs-\(entry.id)")
    }

    private func prefRow(_ pref: NightPref) -> some View {
        HStack(spacing: 6) {
            Text(pref.title).font(Ink.song(12.5)).foregroundStyle(Ink.secondary)
                .frame(width: 30, alignment: .leading)
                .accessibilityHidden(true)
            ForEach(pref.options, id: \.value) { option in
                chip(option.label, on: entry.prefs[pref.rawValue] == option.value, size: 12.5) {
                    onPref(pref, option.value)
                }
                .accessibilityLabel("\(pref.title)：\(option.label)")
            }
            // 两项的那行（事后）留出第三格的位置，几行的格子对齐
            if pref.options.count < 3 { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
        }
    }

    private func chip(_ text: String, on: Bool, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(Ink.song(size)).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(on ? Ink.meText : Ink.secondary)
                .frame(maxWidth: .infinity, minHeight: chipHeight)
                .background(Capsule().fill(on ? Ink.meFill : Color.clear))
                .overlay(Capsule().stroke(on ? Color.clear : Ink.line.opacity(0.8), lineWidth: 0.8))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// 128 她要看得见的「备注」：没写过（或者点了改）是一行小框「备注（可不填）」+「存」，回车也存；
    /// 存过就是「备注：…」，点一下改。和以前的「写一句」是同一个 comment。
    @ViewBuilder private var note: some View {
        if editing || entry.comment.isEmpty {
            HStack(spacing: 6) {
                TextField("备注（可不填）", text: $draft)
                    .font(Ink.song(compact ? 13.5 : 14.5)).submitLabel(.done)
                    .focused(focus, equals: entry.id)
                    .onSubmit(onSend)
                    .padding(.horizontal, 12).frame(minHeight: compact ? 34 : 40)
                    .background(Capsule().fill(Ink.primary.opacity(0.05)))
                    .accessibilityIdentifier("night-note-\(entry.id)")
                Button(action: onSend) {
                    Text("存").font(Ink.song(14)).frame(minWidth: 44, minHeight: compact ? 34 : 40).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSend ? Ink.accent : Ink.line)
                .disabled(!canSend)
                .accessibilityLabel("存备注")
            }
        } else {
            Button(action: onEdit) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("备注：" + entry.comment).font(Ink.song(compact ? 13.5 : 14.5)).lineSpacing(3)
                        .foregroundStyle(Ink.meText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "pencil").font(.system(size: 11, weight: .light)).foregroundStyle(Ink.secondary)
                }
                .frame(minHeight: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("备注：\(entry.comment)")
            .accessibilityHint("点一下改")
        }
    }
}
