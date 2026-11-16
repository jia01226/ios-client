import SwiftUI
import UserNotifications

// 1116 她：「日历我还想做提醒，因为我要看医生，我会忘记什么时候的号了」「在日历中显示，比如一个标记，
// 我点进去有提醒，和苹果那样」。
// 日程只存在这台手机上（UserDefaults），到点用本地通知提醒——不靠网络、不靠服务器，跟苹果日历一样到点就响。
// 不走 HomeReminderCoordinator：那边的提醒要等她到家、没在开车才放出来，看医生的号不能等。

struct CalendarEvent: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var title: String
    var start: Date
    /// 提前几分钟提醒（像苹果那样最多两个）；空就是不提醒
    var alerts: [Int] = [60]
    var note = ""
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
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([CalendarEvent].self, from: data) {
            events = saved
        }
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
        persist()
        Task { await schedule(event) }
    }

    func delete(_ id: String) {
        events.removeAll { $0.id == id }
        persist()
        cancel(id)
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(events), forKey: key)
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
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: identifiers(for: event.id)[index],
                                                        content: content, trigger: trigger))
        }
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
