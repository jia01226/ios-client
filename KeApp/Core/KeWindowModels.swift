import Foundation

// MARK: 柯的长窗：来信设置、窗口有多满、钉住的轮、挑选带走（2026-10-16）
// 后端字段全是下划线写法；数字可能是整数也可能是小数，统一宽松地读。

/// 「来信」页：柯什么时候可以主动来找她。来不来、说什么还是柯自己决定。
struct KeProactiveSettings: Codable, Equatable, Sendable {
    var proactiveOn: Bool
    var quietWeekday: String
    var quietWeekend: String
    var nightGap: Int
    var xhsPerDay: Int
    /// 124：「柯想得多深」，只管 Claude 长窗。"" ＝ 跟服务器默认走（现在是 low）；
    /// 读到不认识的值也原样留着，不替她乱改。
    var effort: String

    enum CodingKeys: String, CodingKey {
        case proactiveOn = "proactive_on"
        case quietWeekday = "quiet_weekday"
        case quietWeekend = "quiet_weekend"
        case nightGap = "night_gap"
        case xhsPerDay = "xhs_per_day"
        case effort
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proactiveOn = (try? c.decode(Bool.self, forKey: .proactiveOn)) ?? true
        quietWeekday = (try? c.decode(String.self, forKey: .quietWeekday)) ?? "23:00-08:30"
        quietWeekend = (try? c.decode(String.self, forKey: .quietWeekend)) ?? "23:00-10:30"
        nightGap = c.lossyInt(.nightGap) ?? 40
        xhsPerDay = c.lossyInt(.xhsPerDay) ?? 2
        // 124：老服务器没有这个字段、或者回 null，都当「跟默认走」
        effort = ((try? c.decode(String.self, forKey: .effort)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// 124：页面上该亮哪一档。"" 亮服务器默认那档；不认识的值哪档都不亮。
    var effortLevel: KeEffort? { effort.isEmpty ? .serverDefault : KeEffort(rawValue: effort) }
    var effortIsDefault: Bool { effort.isEmpty }
}

/// 124 她：「我可以选择柯的用量，就像现在你是最高速度，柯app选不了」——
/// 柯想得多深的五档，从左到右越来越深、越费额度。值和服务器 /api/ke/settings 的 effort 一样。
enum KeEffort: String, CaseIterable, Identifiable, Sendable {
    case low, medium, high, xhigh, max

    /// 服务器 effort 为 "" 时用的那档
    static let serverDefault: KeEffort = .low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "省着想"
        case .medium: return "平常"
        case .high: return "认真"
        case .xhigh: return "很认真"
        case .max: return "最认真"
        }
    }

    /// 第几档（1…5），页面上点几个小点
    var depth: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }
}

/// 「23:00-08:30」这样的安静时段，拆成两头的时和分。
struct KeQuietRange: Equatable, Sendable {
    var startMinutes: Int
    var endMinutes: Int

    init(startMinutes: Int, endMinutes: Int) {
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }

    init?(_ raw: String) {
        let parts = raw.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let start = Self.minutes(parts[0]),
              let end = Self.minutes(parts[1]) else { return nil }
        startMinutes = start
        endMinutes = end
    }

    var text: String { "\(Self.clock(startMinutes))-\(Self.clock(endMinutes))" }

    static func clock(_ minutes: Int) -> String {
        let value = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private static func minutes(_ text: String) -> Int? {
        let hm = text.split(separator: ":")
        guard hm.count == 2, let h = Int(hm[0]), let m = Int(hm[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }
}

/// 一轮＝她说的几句加柯回的几句。钉住、带走都按整轮算。
struct KeRound: Decodable, Identifiable, Hashable, Sendable {
    let startID: Int
    let at: Date?
    let me: [String]
    let ke: [String]
    let messageIDs: [Int]
    let chars: Int
    let pinned: Bool

    var id: Int { startID }

    enum CodingKeys: String, CodingKey {
        case startID = "start_id"
        case at, me, ke, chars, pinned
        case messageIDs = "message_ids"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let start = c.lossyInt(.startID) else {
            throw DecodingError.keyNotFound(CodingKeys.startID, .init(codingPath: c.codingPath, debugDescription: "缺少 start_id"))
        }
        startID = start
        at = c.lossyDate(.at)
        me = (try? c.decode([String].self, forKey: .me)) ?? []
        ke = (try? c.decode([String].self, forKey: .ke)) ?? []
        messageIDs = (try? c.decode([Int].self, forKey: .messageIDs)) ?? [start]
        let counted = (me + ke).reduce(0) { $0 + $1.count }
        chars = c.lossyInt(.chars) ?? counted
        pinned = (try? c.decode(Bool.self, forKey: .pinned)) ?? false
    }
}

struct KeRoundPage: Decodable, Sendable {
    let items: [KeRound]
    let nextBefore: Int?

    enum CodingKeys: String, CodingKey {
        case items
        case nextBefore = "next_before"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decode([KeRound].self, forKey: .items)) ?? []
        nextBefore = c.lossyInt(.nextBefore)
    }
}

struct KePins: Decodable, Sendable {
    let items: [KeRound]
    let count: Int
    let chars: Int

    enum CodingKeys: String, CodingKey { case items, count, chars }

    init(items: [KeRound] = []) {
        self.items = items
        count = items.count
        chars = items.reduce(0) { $0 + $1.chars }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decode([KeRound].self, forKey: .items)) ?? []
        count = c.lossyInt(.count) ?? items.count
        chars = c.lossyInt(.chars) ?? items.reduce(0) { $0 + $1.chars }
    }
}

/// 洗澡、换窗都是后台慢慢做的活：state 为 running / done / failed。
struct KeWindowJob: Decodable, Equatable, Sendable {
    let kind: String?
    let state: String
    let resultText: String?
    let error: String?

    var isRunning: Bool { state == "running" || state == "queued" || state == "pending" }
    var isDone: Bool { state == "done" }
    var isFailed: Bool { state == "failed" }

    enum CodingKeys: String, CodingKey { case kind, state, result, error }

    init(kind: String?, state: String, resultText: String? = nil, error: String? = nil) {
        self.kind = kind
        self.state = state
        self.resultText = resultText
        self.error = error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try? c.decode(String.self, forKey: .kind)
        state = (try? c.decode(String.self, forKey: .state)) ?? "running"
        error = try? c.decode(String.self, forKey: .error)
        // result 的形状后端没定死：是字符串就直接给她看，是对象就挑 message / summary。
        if let text = try? c.decode(String.self, forKey: .result) {
            resultText = text
        } else if let object = try? c.decode([String: KeLooseValue].self, forKey: .result) {
            resultText = object["message"]?.text ?? object["summary"]?.text
        } else {
            resultText = nil
        }
    }
}

/// POST 洗澡 / 换窗回 202：可能是 {"job": {...}}，也可能直接就是 job。
struct KeJobResponse: Decodable, Sendable {
    let job: KeWindowJob?

    enum CodingKeys: String, CodingKey { case job }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.job) {
            job = try? c.decode(KeWindowJob.self, forKey: .job)
        } else {
            job = try? KeWindowJob(from: decoder)
        }
    }
}

struct KeWindowState: Decodable, Sendable {
    let windowID: String?
    let openedAt: Date?
    let turns: Int?
    let contextTokens: Int
    let washAt: Int
    let rotateAt: Int
    let model: String?
    var pins: KePins
    var job: KeWindowJob?

    enum CodingKeys: String, CodingKey {
        case windowID = "window_id"
        case openedAt = "opened_at"
        case turns
        case contextTokens = "context_tokens"
        case washAt = "wash_at"
        case rotateAt = "rotate_at"
        case model, pins, job
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? c.decode(String.self, forKey: .windowID) {
            windowID = text
        } else {
            windowID = c.lossyInt(.windowID).map(String.init)
        }
        openedAt = c.lossyDate(.openedAt)
        turns = c.lossyInt(.turns)
        contextTokens = c.lossyInt(.contextTokens) ?? 0
        let rotate = c.lossyInt(.rotateAt) ?? 400_000
        rotateAt = max(1, rotate)
        washAt = c.lossyInt(.washAt) ?? Int(Double(rotateAt) * 0.8)
        model = try? c.decode(String.self, forKey: .model)
        pins = (try? c.decode(KePins.self, forKey: .pins)) ?? KePins()
        job = try? c.decode(KeWindowJob.self, forKey: .job)
    }

    /// 钉住的轮里所有消息的 id，聊天气泡旁边据此画小图钉。
    var pinnedMessageIDs: Set<Int> {
        Set(pins.items.flatMap { $0.messageIDs + [$0.startID] })
    }
}

/// 只为读 job.result 里的零散字段。
enum KeLooseValue: Decodable, Sendable {
    case text(String)
    case number(Double)
    case other

    var text: String? {
        switch self {
        case let .text(value): return value
        case let .number(value): return String(value)
        case .other: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let value = try? c.decode(String.self) { self = .text(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else { self = .other }
    }
}

// MARK: - 显示用的小换算

enum KeWindowFormat {
    /// 115000 → 「11.5 万」，400000 → 「40 万」
    static func wan(_ tokens: Int) -> String {
        "\(trimmed(Double(tokens) / 10_000)) 万"
    }

    /// 字数换成「约 3.2k」
    static func kilo(_ chars: Int) -> String {
        "\(trimmed(Double(chars) / 1_000))k"
    }

    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
    }

    static func roundTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
            ? "M月d日 HH:mm"
            : "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }

    /// 两轮之间隔了多久：「3 天」「5 小时」「20 分钟」
    static func gap(from start: Date?, to end: Date?) -> String? {
        guard let start, let end else { return nil }
        let minutes = Int(end.timeIntervalSince(start) / 60)
        guard minutes > 0 else { return nil }
        if minutes >= 1440 { return "\(minutes / 1440) 天" }
        if minutes >= 60 { return "\(minutes / 60) 小时" }
        return "\(minutes) 分钟"
    }
}

// MARK: - 宽松解码

extension KeyedDecodingContainer {
    func lossyInt(_ key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Double.self, forKey: key) { return Int(value.rounded()) }
        if let value = try? decode(String.self, forKey: key) { return Int(value) }
        return nil
    }

    func lossyDate(_ key: Key) -> Date? {
        if let value = try? decode(Double.self, forKey: key) {
            // 秒或毫秒都认
            return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
        }
        guard let raw = try? decode(String.self, forKey: key) else { return nil }
        return KeDateParser.parse(raw)
    }
}

enum KeDateParser {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()
    private static let plain: [DateFormatter] = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm"].map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = $0
        return f
    }

    static func parse(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if let date = iso.date(from: text) ?? isoPlain.date(from: text) { return date }
        let head = String(text.prefix(19))
        for formatter in plain {
            if let date = formatter.date(from: head) ?? formatter.date(from: text) { return date }
        }
        return nil
    }
}
