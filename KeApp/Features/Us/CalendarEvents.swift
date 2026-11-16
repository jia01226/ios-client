import SwiftUI
import UserNotifications

// 1116 她：「日历我还想做提醒，因为我要看医生，我会忘记什么时候的号了」「在日历中显示，比如一个标记，
// 我点进去有提醒，和苹果那样」。
// 到点用本地通知提醒——不靠网络，跟苹果日历一样到点就响。
// 11-16 她：「柯可以自己记，我发截图给他就可以了」——日程在服务器上也存一份（/api/calendar/events，和柯共用），
// 手机上留一份照着画、照着排通知。她在这儿加/改/删先记在手机上、再送上去，没送上的下回接着送；
// 柯记的，「我们」页一刷新、回前台就拉下来。
// 不走 HomeReminderCoordinator：那边的提醒要等她到家、没在开车才放出来，看医生的号不能等。

struct CalendarEvent: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var title: String
    var start: Date
    /// 提前几分钟提醒（像苹果那样最多两个）；空就是不提醒
    var alerts: [Int] = [60]
    var note = ""
    /// ke = 柯记的；空或 me = 她自己记的
    var author: String?
    /// 11-17 要跟医生说的（「11-17 03:53 凌晨 3 点多醒了就睡不着」）：柯平时问她、替她记下的，这里只看不改
    var symptoms: [String]?
}

enum CalendarAlertOption: Int, CaseIterable, Identifiable {
    case off = -1, atTime = 0, m5 = 5, m15 = 15, m30 = 30, h1 = 60, h2 = 120, d1 = 1440, d2 = 2880, w1 = 10080
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .off: return "无"
        case .atTime: return "日程开始时"
        case .m5: return "5 分钟前"
        case .m15: return "15 分钟前"
        case .m30: return "30 分钟前"
        case .h1: return "1 小时前"
        case .h2: return "2 小时前"
        case .d1: return "1 天前"
        case .d2: return "2 天前"
        case .w1: return "1 周前"
        }
    }
    static func label(minutes: Int) -> String {
        CalendarAlertOption(rawValue: minutes)?.label ?? "\(minutes) 分钟前"
    }
}

@MainActor final class CalendarEventStore: ObservableObject {
    static let shared = CalendarEventStore()
    static let notificationPrefix = "ke.appt."

    @Published private(set) var events: [CalendarEvent] = []
    private let key = "us.calendar.events"
    private let pendingKey = "us.calendar.pending"
    private let deletedKey = "us.calendar.deleted"
    private let syncedOnceKey = "us.calendar.synced-once"
    private let defaults: UserDefaults
    /// 还没送上服务器的：改过的 id、删掉的 id
    private var pending: Set<String>
    private var deleted: Set<String>
    private var api: APIClient?
    private var syncing: Task<Void, Never>?
    private var activeObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([CalendarEvent].self, from: data) {
            events = saved
        }
        pending = Set(defaults.stringArray(forKey: pendingKey) ?? [])
        deleted = Set(defaults.stringArray(forKey: deletedKey) ?? [])
        // 头一回接上服务器：以前只存在手机上的日程全都送上去
        if !defaults.bool(forKey: syncedOnceKey) {
            pending.formUnion(events.map(\.id))
        }
    }

    /// 「我们」页那条线路的接口；接上以后回前台就同步一次
    func attach(_ api: APIClient) {
        self.api = api
        guard activeObserver == nil else { return }
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.sync() }
        }
    }

    /// 先把手机上改过、删过的送上去，再把服务器那份（含柯记的）拉下来，重排通知。
    func sync() async {
        if let syncing { await syncing.value; return }
        guard let api else { return }
        let task = Task { @MainActor in
            for id in deleted {
                if (try? await api.deleteCalendarEvent(id: id)) != nil { deleted.remove(id) }
            }
            for id in pending {
                guard let event = events.first(where: { $0.id == id }) else { pending.remove(id); continue }
                if (try? await api.saveCalendarEvent(RemoteCalendarEvent(event))) != nil { pending.remove(id) }
            }
            defaults.set(true, forKey: syncedOnceKey)
            guard let remote = try? await api.fetchCalendarEvents() else { persist(); return }
            // 还没送上去的那几条照旧留着手机上的样子
            let local = events.filter { pending.contains($0.id) }
            let serverSide = remote.compactMap(\.event).filter { !pending.contains($0.id) && !deleted.contains($0.id) }
            let merged = (serverSide + local).sorted { $0.start < $1.start }
            if merged != events {
                let gone = Set(events.map(\.id)).subtracting(merged.map(\.id))
                events = merged
                gone.forEach(cancel)
                for event in merged { await schedule(event) }
            }
            persist()
        }
        syncing = task
        await task.value
        syncing = nil
    }

    func events(on date: Date) -> [CalendarEvent] {
        events.filter { Calendar.current.isDate($0.start, inSameDayAs: date) }.sorted { $0.start < $1.start }
    }

    func hasEvents(on date: Date) -> Bool {
        events.contains { Calendar.current.isDate($0.start, inSameDayAs: date) }
    }

    func save(_ event: CalendarEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
        } else {
            events.append(event)
        }
        pending.insert(event.id)
        persist()
        Task {
            await schedule(event)
            await sync()
        }
    }

    func delete(_ id: String) {
        events.removeAll { $0.id == id }
        pending.remove(id)
        deleted.insert(id)
        persist()
        cancel(id)
        Task { await sync() }
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(events), forKey: key)
        defaults.set(Array(pending), forKey: pendingKey)
        defaults.set(Array(deleted), forKey: deletedKey)
    }

    // MARK: 本地通知

    private func identifiers(for id: String) -> [String] {
        (0..<2).map { "\(Self.notificationPrefix)\(id).\($0)" }
    }

    private func cancel(_ id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers(for: id))
    }

    private func schedule(_ event: CalendarEvent) async {
        cancel(event.id)
        let alerts = Array(event.alerts.filter { $0 >= 0 }.prefix(2))
        guard !alerts.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        let time = Self.timeFormatter.string(from: event.start)
        for (index, minutes) in alerts.enumerated() {
            let fire = event.start.addingTimeInterval(TimeInterval(-minutes * 60))
            guard fire > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = minutes == 0 ? "现在 \(time)" : "\(Self.dayWord(event.start, from: fire)) \(time)"
                + (event.note.isEmpty ? "" : " · \(event.note)")
            if let said = event.symptoms, !said.isEmpty {
                content.body += "\n记得跟医生说：" + said.map(Self.withoutStamp).joined(separator: "；")
            }
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: identifiers(for: event.id)[index],
                                                        content: content, trigger: trigger))
        }
    }

    /// 「11-17 03:53 凌晨醒了」→「凌晨醒了」（提醒里放不下时间）
    static func withoutStamp(_ line: String) -> String {
        let parts = line.split(separator: " ", maxSplits: 2)
        return parts.count == 3 && parts[0].contains("-") && parts[1].contains(":") ? String(parts[2]) : line
    }

    /// 提醒响的那天跟日程是不是同一天：「今天 9:30」「明天 9:30」「11月20日 9:30」
    private static func dayWord(_ start: Date, from fire: Date) -> String {
        let c = Calendar.current
        if c.isDate(start, inSameDayAs: fire) { return "今天" }
        if let next = c.date(byAdding: .day, value: 1, to: fire), c.isDate(start, inSameDayAs: next) { return "明天" }
        return dayFormatter.string(from: start)
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "HH:mm"; return f
    }()
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日"; return f
    }()
}

// MARK: - 服务器上那份的样子（时间是带时区的 ISO：2026-11-28T09:00:00+08:00）

struct RemoteCalendarEvent: Codable {
    let id: String
    let title: String
    let start: String
    let alerts: [Int]?
    let note: String?
    let author: String?
    let symptoms: [RemoteSymptom]?

    struct RemoteSymptom: Codable {
        let at: String
        let text: String
    }

    init(_ event: CalendarEvent) {
        id = event.id
        title = event.title
        start = Self.formatter.string(from: event.start)
        alerts = event.alerts
        note = event.note
        author = event.author
        symptoms = nil   // 要跟医生说的只有柯记，App 不往上送
    }

    var event: CalendarEvent? {
        guard let date = Self.formatter.date(from: start) else { return nil }
        let said = (symptoms ?? []).map { "\($0.at) \($0.text)" }
        return CalendarEvent(id: id, title: title, start: date, alerts: alerts ?? [60], note: note ?? "", author: author,
                             symptoms: said.isEmpty ? nil : said)
    }

    nonisolated(unsafe) static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f
    }()
}

// MARK: - 当天面板里的「日程」一块

struct DayEventsSection: View {
    @ObservedObject var store: CalendarEventStore
    let date: Date
    @State private var editing: CalendarEvent?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("日程").font(Ink.song(15))
                Spacer()
                Button { editing = Self.newEvent(on: date) } label: {
                    Label("添加", systemImage: "plus").font(Ink.song(14)).foregroundStyle(Ink.accent)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("day-event-add")
            }
            ForEach(store.events(on: date)) { event in
                Button { editing = event } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(CalendarEventStore.timeFormatter.string(from: event.start))
                            .font(Ink.latin(15)).monospacedDigit().foregroundStyle(Ink.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(Ink.song(15)).foregroundStyle(Ink.primary)
                            Text(Self.alertLine(event)).font(Ink.song(11.5)).foregroundStyle(Ink.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .light)).foregroundStyle(Ink.secondary)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(CalendarEventStore.timeFormatter.string(from: event.start)) \(event.title)，\(Self.alertLine(event))")
            }
        }
        .padding(.horizontal, 24).padding(.top, 4)
        .sheet(item: $editing) { event in
            CalendarEventEditor(event: event, isNew: !store.events.contains { $0.id == event.id }) { saved in
                store.save(saved)
            } onDelete: { id in
                store.delete(id)
            }
        }
    }

    static func alertLine(_ event: CalendarEvent) -> String {
        let alerts = event.alerts.filter { $0 >= 0 }
        return alerts.isEmpty ? "不提醒" : "提醒：" + alerts.map(CalendarAlertOption.label(minutes:)).joined(separator: "、")
    }

    /// 新日程默认放在那天早上 9 点，提前 1 小时提醒
    static func newEvent(on date: Date) -> CalendarEvent {
        let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        return CalendarEvent(title: "", start: start)
    }
}

// MARK: - 编辑一条日程（苹果日历那样：标题、时间、提醒、第二次提醒、备注）

struct CalendarEventEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var event: CalendarEvent
    let isNew: Bool
    var onSave: (CalendarEvent) -> Void
    var onDelete: (String) -> Void
    @State private var confirmingDelete = false

    private var firstAlert: Binding<Int> {
        Binding(get: { event.alerts.first ?? -1 },
                set: { value in event.alerts = value < 0 ? [] : [value] + event.alerts.dropFirst().prefix(1) })
    }
    private var secondAlert: Binding<Int> {
        Binding(get: { event.alerts.count > 1 ? event.alerts[1] : -1 },
                set: { value in
                    let first = event.alerts.first.map { [$0] } ?? []
                    event.alerts = value < 0 ? first : first + [value]
                })
    }
    private var canSave: Bool { !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("比如：佛三院 李医生", text: $event.title)
                        .accessibilityIdentifier("event-title")
                    DatePicker("时间", selection: $event.start, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                }
                Section {
                    Picker("提醒", selection: firstAlert) {
                        ForEach(CalendarAlertOption.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    if !event.alerts.isEmpty {
                        Picker("第二次提醒", selection: secondAlert) {
                            ForEach(CalendarAlertOption.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                    }
                } footer: {
                    Text("到点手机上会弹提醒。看医生可以选「1 天前」再加一个「2 小时前」。")
                }
                Section {
                    TextField("备注（挂号单号、科室、带什么）", text: $event.note, axis: .vertical)
                        .lineLimit(1...4)
                }
                if let said = event.symptoms, !said.isEmpty {
                    Section {
                        ForEach(said, id: \.self) { line in
                            Text(line).font(Ink.song(14)).foregroundStyle(Ink.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } header: {
                        Text("要跟医生说的")
                    } footer: {
                        Text("柯平时问你、帮你记下的。记错了跟柯说一声，他会删。")
                    }
                }
                if !isNew {
                    Section {
                        Button("删除这个日程", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "新日程" : "日程").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "添加" : "完成") {
                        event.title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(event); dismiss()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("event-save")
                }
            }
            .confirmationDialog("删除这个日程？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) { onDelete(event.id); dismiss() }
            }
        }
        .tint(Ink.accent)
    }
}
