import SwiftUI

// 「我们」的数据和写班表那一页。原来跟旧 UsView 写在一个文件里；旧页面已删，
// 真正在用的「我们」是 UsPondView（锦鲤池），它用这里的 UsViewModel 和 ScheduleEditorSheet；HomeReminderSettingsView 也用 UsViewModel。

/// 137：只嵌在「我们」点一天的面板里——换成和面板上半截一样的细宋体、粉白强调色；
/// 哪一天、「关上」都挪到面板最上面了，这里不再有自己的标题日期和「取消」。
struct ScheduleEditorSheet: View {
    @ObservedObject var model: UsViewModel
    let date: Date
    let onSave: (ShiftDay.Kind?, String?) -> Void
    @State private var selectedShift: ShiftDay.Kind?
    @State private var note: String

    init(
        model: UsViewModel, date: Date,
        currentShift: ShiftDay.Kind?,
        currentNote: String?,
        onSave: @escaping (ShiftDay.Kind?, String?) -> Void
    ) {
        self.model = model
        self.date = date
        self.onSave = onSave
        _selectedShift = State(initialValue: currentShift)
        _note = State(initialValue: currentNote ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("排班").font(Ink.song(15)).foregroundStyle(Ink.primary)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                    ForEach(model.availableShiftKinds, id: \.self) { kind in
                        ShiftChoice(kind: kind, title: model.shiftLabel(kind), selected: selectedShift == kind) { selectedShift = kind }
                    }
                }
            }
            .frame(maxHeight: JournalLayout.shiftChoicesHeight)

            Group {
                if selectedShift == .other {
                    HStack(spacing: 10) {
                        Image(systemName: "pencil.line")
                            .foregroundStyle(Ink.accent)
                        TextField("写下班次，例如：培训、临时班", text: $note)
                            .textInputAutocapitalization(.never)
                            .submitLabel(.done)
                    }
                    .font(Ink.song(14))
                    .foregroundStyle(Ink.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Ink.line.opacity(0.8), lineWidth: 0.7)
                    )
                } else {
                    Text("休息日无需填写，清除当天排班即可。")
                        .font(Ink.song(12))
                        .foregroundStyle(Ink.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }

            HStack(spacing: 12) {
                Button("清除排班") {
                    selectedShift = nil
                    note = ""
                }
                .buttonStyle(KeDrawerButtonStyle())

                Button("保存班表") {
                    onSave(selectedShift, selectedShift == .other ? normalizedNote : nil)
                }
                .buttonStyle(KeDrawerButtonStyle(solid: true))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .sensoryFeedback(.selection, trigger: selectedShift)
        .accessibilityElement(children: .contain)
    }

    private var normalizedNote: String? {
        let value = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private struct ShiftChoice: View {
    let kind: ShiftDay.Kind
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .light))
                Text(label)
                    .font(Ink.song(14))
            }
            .foregroundStyle(selected ? Ink.accent : Ink.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Ink.accent.opacity(0.08) : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selected ? Ink.accent.opacity(0.7) : Ink.line.opacity(0.8), lineWidth: selected ? 1 : 0.7)
                    }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var label: String { title }

    private var icon: String {
        switch kind {
        case .normal: return "sun.max"
        case .early: return "sunrise"
        case .deputy: return "person.2"
        default: return "ellipsis"
        }
    }
}

struct AnniversaryDisplay {
    let title: String
    let number: String
    let unit: String
    let dateLabel: String
}

@MainActor
final class UsViewModel: ObservableObject {
    @Published var reminders: [Reminder] = []
    @Published var anniversaries: [Anniversary] = []
    @Published var thisWeek: [ShiftDay] = []
    @Published private(set) var savedShifts: [String: ShiftDay.Kind] = [:]
    @Published private(set) var savedShiftNotes: [String: String] = [:]
    @Published private(set) var clearedShiftKeys: Set<String> = []
    @Published private(set) var shiftTemplates: [ShiftTemplate] = []
    @Published private(set) var savedShiftNames: [String: String] = [:]
    var availableShiftKinds: [ShiftDay.Kind] { shiftTemplates.filter { !$0.archived }.map(\.id) }
    private let shiftTemplatesKey = "us.shift-templates.v1"
    private let savedShiftNamesKey = "us.shift-names.v1"

    private let calendar = Calendar.current
    private let savedShiftsKey = "us.saved-shifts.v2"
    private let savedShiftNotesKey = "us.saved-shift-notes.v2"
    private let defaults: UserDefaults
    private let api: APIClient?
    private let shiftAPI: (any ShiftAPI)?
    @Published private(set) var shiftSyncStatus: String?
    @Published private(set) var syncingShifts = false
    private var pendingShifts: [String: PendingShiftChange] = [:]
    private var shiftRevision = 0
    private let pendingShiftsKey = "us.shift-sync.pending.v1"
    private let knownRemoteShiftsKey = "us.shift-sync.remote-keys.v1"
    @Published private(set) var reminderLoadError: String?
    @Published private(set) var loadingReminders = false

    var activeReminders: [Reminder] {
        reminders
            .filter { !$0.dismissedByKe }
            .sorted { $0.dueAt < $1.dueAt }
    }

    func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年 M月"
        return formatter.string(from: date)
    }

    var weekRangeLabel: String {
        guard let first = thisWeek.first?.date, let last = thisWeek.last?.date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M.d"
        return "\(formatter.string(from: first)) — \(formatter.string(from: last))"
    }

    func monthCells(for date: Date) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let dayRange = calendar.range(of: .day, in: .month, for: date) else { return [] }
        let leading = (calendar.component(.weekday, from: interval.start) + 5) % 7
        return Array(repeating: nil, count: leading) + dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }.map(Optional.some)
    }

    func startOfMonth(for date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    func month(byAdding offset: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: offset, to: startOfMonth(for: date)) ?? date
    }

    func isCurrentMonth(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: .now, toGranularity: .month)
    }

    init(defaults: UserDefaults = .standard, api: APIClient? = nil, shiftAPI: (any ShiftAPI)? = nil) {
        self.defaults = defaults
        self.api = api
        self.shiftAPI = shiftAPI ?? api
        shiftTemplates = defaults.data(forKey: shiftTemplatesKey).flatMap { try? JSONDecoder().decode([ShiftTemplate].self, from: $0) } ?? ShiftTemplate.initial()
        savedShiftNames = defaults.dictionary(forKey: savedShiftNamesKey) as? [String: String] ?? [:]
        if let data = defaults.data(forKey: pendingShiftsKey),
           let pending = try? JSONDecoder().decode([String: PendingShiftChange].self, from: data) {
            pendingShifts = pending
            if !pending.isEmpty { shiftSyncStatus = "班表已存到本机，等待同步给柯" }
        }
        let today = calendar.startOfDay(for: .now)
        if let stored = defaults.dictionary(forKey: savedShiftsKey) as? [String: String] {
            savedShifts = stored.reduce(into: [:]) { result, entry in
                if let kind = ShiftDay.Kind(rawValue: entry.value) {
                    result[entry.key] = kind
                }
            }
            clearedShiftKeys = Set(stored.compactMap { $0.value == "none" ? $0.key : nil })
        }
        savedShiftNotes = defaults.dictionary(forKey: savedShiftNotesKey) as? [String: String] ?? [:]
        func fixedDay(_ y: Int, _ m: Int, _ d: Int) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: d)) ?? today
        }
        anniversaries = [
            Anniversary(id: "confession", title: "表白的日子", date: fixedDay(2026, 8, 9), isYearly: false),
            Anniversary(id: "together", title: "在一起的日子", date: fixedDay(2026, 6, 25), isYearly: false),
            Anniversary(id: "mine", title: "佳佳的生日", date: fixedDay(2001, 2, 26)),
            Anniversary(id: "ke", title: "柯的生日", date: fixedDay(1992, 10, 26)),
        ]

        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-ui-test") || $0.hasPrefix("-preview-us") }) {
            let medicineTime = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: today) ?? today
            reminders = [
                Reminder(id: "r1", text: "吃维生素 D", dueAt: medicineTime, category: .medicine),
                Reminder(id: "r2", text: "周一有安排，提前半小时出发。", dueAt: Date().addingTimeInterval(86400), category: .work),
            ]
        }

        let weekday = calendar.component(.weekday, from: today)
        let monday = calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: today) ?? today
        let preview = ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-ui-test") || $0.hasPrefix("-preview-us") })
        let kinds: [ShiftDay.Kind?] = preview ? [nil, .early, .deputy, nil, .early, nil, .other] : Array(repeating: nil, count: 7)
        let notes: [String?] = [nil, nil, nil, nil, nil, nil, "培训"]
        thisWeek = (0..<7).map { index in
            let date = calendar.date(byAdding: .day, value: index, to: monday) ?? today
            let key = dateKey(date)
            let isCleared = clearedShiftKeys.contains(key)
            let kind = isCleared ? nil : (savedShifts[key] ?? kinds[index])
            let note = isCleared ? nil : (savedShiftNotes[key] ?? notes[index])
            return ShiftDay(id: "s\(index)", date: date, kind: kind, note: note)
        }
    }

    func loadReminders() async {
        await syncShifts()
        await refreshShifts()
        guard let api else { return }
        loadingReminders = true
        defer { loadingReminders = false }
        var failures: [String] = []
        do {
            let schedule = try await api.fetchSchedule()
            reminders = Self.reminders(from: schedule.current)
        } catch {
            failures.append("提醒")
        }
        do {
            let rows = try await api.fetchAnniversaries()
            let resolved = Self.anniversaries(from: rows)
            // 服务器缺哪一个，就留着本机那一个，不让某一格突然空掉。
            if !resolved.isEmpty {
                let fetched = Dictionary(uniqueKeysWithValues: resolved.map { ($0.id, $0) })
                anniversaries = anniversaries.map { fetched[$0.id] ?? $0 }
            }
        } catch {
            failures.append("纪念日")
        }
        reminderLoadError = failures.isEmpty ? nil : failures.joined(separator: "、") + "暂时没有接上，请下拉重试。"
    }

    static func anniversaries(from rows: [RemoteAnniversary]) -> [Anniversary] {
        // 2026-10-08：以前用服务器的数字当 id，页面上选中的是 "together" 这类固定名字，
        // 一加载完就对不上号——先显示、再消失（她说「纪念日时好时坏看不见」）。按名字认回固定 id。
        let slots: [(id: String, matches: (String) -> Bool)] = [
            ("confession", { $0.contains("表白") }),
            ("together", { $0.contains("在一起") }),
            ("mine", { $0.contains("佳佳") && $0.contains("生日") }),
            ("ke", { $0.contains("柯") && $0.contains("生日") }),
        ]
        return slots.compactMap { slot in
            // 「2026-06-25」按年月日数字拼成本地那一天，不经过时区换算（换算会差出前一天）。
            guard let row = rows.first(where: { slot.matches($0.name) }) else { return nil }
            let ymd = row.date.prefix(10).split(separator: "-").compactMap { Int($0) }
            guard let date = ymd.count == 3
                ? Calendar.current.date(from: DateComponents(year: ymd[0], month: ymd[1], day: ymd[2]))
                : CompanionDate.parse(row.date) else { return nil }
            return Anniversary(id: slot.id, title: row.name, date: date, isYearly: row.name.contains("生日"))
        }
    }

    static func reminders(from rows: [RemoteReminder]) -> [Reminder] {
        rows.map { row in
            Reminder(
                id: String(row.id),
                text: row.text,
                dueAt: CompanionDate.parse(row.scheduled_for) ?? .now,
                dismissedByKe: row.status != "pending",
                category: .other
            )
        }
    }

    func display(for item: Anniversary) -> AnniversaryDisplay {
        let number = item.isYearly ? daysUntil(item) : daysTogether(since: item.date)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月 d 日"
        return AnniversaryDisplay(
            title: item.title,
            number: "\(number)",
            unit: item.isYearly ? "天后" : "天",
            dateLabel: formatter.string(from: item.date)
        )
    }

    func daysUntil(_ item: Anniversary) -> Int {
        let today = calendar.startOfDay(for: .now)
        var components = calendar.dateComponents([.month, .day], from: item.date)
        components.year = calendar.component(.year, from: today)
        var target = calendar.date(from: components) ?? item.date
        if target < today { target = calendar.date(byAdding: .year, value: 1, to: target) ?? target }
        return max(0, calendar.dateComponents([.day], from: today, to: target).day ?? 0)
    }

    func daysTogether(since date: Date) -> Int {
        max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? 0)
    }

    func shiftLabel(_ kind: ShiftDay.Kind) -> String {
        shiftTemplates.first { $0.id == kind }?.name ?? "其他"
    }

    func shiftDisplay(_ kind: ShiftDay.Kind, on date: Date) -> String {
        if let name = savedShiftNames[dateKey(date)] { return name }
        if kind == .other, let note = shiftNote(on: date), !note.isEmpty { return note }
        return shiftLabel(kind)
    }

    func shiftDetail(_ kind: ShiftDay.Kind, on date: Date) -> String { shiftDisplay(kind, on: date) }

    /// Removing a template only removes the choice; dated records keep their snapshots.
    func archiveShiftTemplate(_ kind: ShiftDay.Kind) {
        guard let index = shiftTemplates.firstIndex(where: { $0.id == kind }) else { return }
        shiftTemplates[index].archived = true
        defaults.set(try? JSONEncoder().encode(shiftTemplates), forKey: shiftTemplatesKey)
    }

    func saveShiftTemplate(kind: ShiftDay.Kind, name: String, plan: ShiftPlan) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 16, !name.contains("\n") else { return "班名写 1–16 个字就好。" }
        guard !shiftTemplates.contains(where: { $0.id != kind && !$0.archived && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return "已经有这个班名了，换一个吧。" }
        guard plan.resolve(on: .now) != nil else { return "请检查这个班次的起止时间。" }
        // Preserve names and times on already assigned days before changing the template.
        for (key, storedKind) in savedShifts where storedKind == kind {
            guard let date = shiftDate(key) else { continue }
            if savedShiftNames[key] == nil { savedShiftNames[key] = shiftDisplay(kind, on: date) }
            if defaults.data(forKey: "us.shift-plan.remote." + key) == nil, let oldPlan = shiftPlan(on: date) {
                defaults.set(try? JSONEncoder().encode(oldPlan), forKey: "us.shift-plan.remote." + key)
            }
            if date >= calendar.startOfDay(for: .now) { savedShiftNames[key] = name }
        }
        if let index = shiftTemplates.firstIndex(where: { $0.id == kind }) {
            shiftTemplates[index].name = name; shiftTemplates[index].archived = false
        } else { shiftTemplates.append(ShiftTemplate(id: kind, name: name)) }
        defaults.set(try? JSONEncoder().encode(shiftTemplates), forKey: shiftTemplatesKey)
        defaults.set(savedShiftNames, forKey: savedShiftNamesKey)
        saveShiftProfile(plan, kind: kind)
        for (key, storedKind) in savedShifts where storedKind == kind {
            guard let date = shiftDate(key), date >= calendar.startOfDay(for: .now),
                  defaults.data(forKey: "us.shift-plan.override." + key) != nil else { continue }
            queueShift(on: date)
        }
        Task { await syncShifts() }
        return nil
    }

    func weekdayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }

    func weekdayFullLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }

    func shift(on date: Date) -> ShiftDay.Kind? {
        let key = dateKey(date)
        if clearedShiftKeys.contains(key) { return nil }
        return savedShifts[key] ?? thisWeek.first { calendar.isDate($0.date, inSameDayAs: date) }?.kind
    }

    func shiftNote(on date: Date) -> String? {
        let key = dateKey(date)
        if clearedShiftKeys.contains(key) { return nil }
        return savedShiftNotes[key] ?? thisWeek.first { calendar.isDate($0.date, inSameDayAs: date) }?.note
    }

    func setShift(_ kind: ShiftDay.Kind?, note: String? = nil, on date: Date) {
        let key = dateKey(date)
        if let kind {
            savedShifts[key] = kind
            savedShiftNames[key] = kind == .other && !(note ?? "").isEmpty ? note : shiftLabel(kind)
            if let note, !note.isEmpty {
                savedShiftNotes[key] = note
            } else {
                savedShiftNotes.removeValue(forKey: key)
            }
            clearedShiftKeys.remove(key)
        } else {
            savedShifts.removeValue(forKey: key)
            savedShiftNames.removeValue(forKey: key)
            savedShiftNotes.removeValue(forKey: key)
            clearedShiftKeys.insert(key)
        }

        if let index = thisWeek.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            thisWeek[index] = ShiftDay(
                id: thisWeek[index].id,
                date: thisWeek[index].date,
                kind: kind,
                note: kind == .other ? note : nil
            )
        }

        var stored = savedShifts.mapValues(\.rawValue)
        for key in clearedShiftKeys { stored[key] = "none" }
        defaults.set(stored, forKey: savedShiftsKey)
        defaults.set(savedShiftNotes, forKey: savedShiftNotesKey)
        defaults.set(savedShiftNames, forKey: savedShiftNamesKey)
        defaults.removeObject(forKey: "us.shift-plan.override." + key)
        defaults.removeObject(forKey: "us.shift-plan.remote." + key)
        updateEndTime(on: date)
        queueShift(on: date)
        Task { await syncShifts() }
    }

    func shiftPlan(on date: Date) -> ShiftPlan? {
        let key = dateKey(date)
        guard let kind = shift(on: date) else { return nil }
        for prefix in ["us.shift-plan.override.", "us.shift-plan.remote."] {
            if let data = defaults.data(forKey: prefix + key),
               let plan = try? JSONDecoder().decode(ShiftPlan.self, from: data) { return plan }
        }
        return ShiftPlan.load(kind: kind.rawValue, defaults: defaults)
    }

    func shiftProfile(_ kind: ShiftDay.Kind) -> ShiftPlan {
        ShiftPlan.load(kind: kind.rawValue, defaults: defaults) ?? .example
    }

    func saveShiftProfile(_ plan: ShiftPlan, kind: ShiftDay.Kind) {
        guard plan.resolve(on: .now) != nil else { return }
        plan.save(kind: kind.rawValue, defaults: defaults)
        for (key, storedKind) in savedShifts where storedKind == kind {
            guard let date = shiftDate(key), date >= calendar.startOfDay(for: .now),
                  defaults.data(forKey: "us.shift-plan.override." + key) == nil else { continue }
            defaults.removeObject(forKey: "us.shift-plan.remote." + key)
            updateEndTime(on: date)
            queueShift(on: date)
        }
        Task { await syncShifts() }
    }

    func saveShiftOverride(_ plan: ShiftPlan?, on date: Date) {
        guard shift(on: date) != nil, plan == nil || plan?.resolve(on: date) != nil else { return }
        let key = dateKey(date)
        if let plan { defaults.set(try? JSONEncoder().encode(plan), forKey: "us.shift-plan.override." + key) }
        else { defaults.removeObject(forKey: "us.shift-plan.override." + key) }
        defaults.removeObject(forKey: "us.shift-plan.remote." + key)
        updateEndTime(on: date)
        queueShift(on: date)
        Task { await syncShifts() }
    }

    private func queueShift(on date: Date) {
        let key = dateKey(date)
        if let kind = shift(on: date) {
            let plan = shiftPlan(on: date)
            if let plan {
                defaults.set(try? JSONEncoder().encode(plan), forKey: "us.shift-plan.remote." + key)
            }
            let adjusted = plan != nil && plan != ShiftPlan.preset(kind: kind.rawValue)
            pendingShifts[key] = PendingShiftChange(
                shift: shiftDisplay(kind, on: date) + (adjusted ? "（已调整）" : ""),
                note: ShiftNote.encode(plan: plan, note: savedShiftNotes[key],
                                      dayOverride: defaults.data(forKey: "us.shift-plan.override." + key) != nil))
        } else { pendingShifts[key] = PendingShiftChange(shift: nil) }
        shiftRevision += 1
        persistPendingShifts()
        shiftSyncStatus = "班表已存好，等待同步给柯"
    }

    private func persistPendingShifts() {
        defaults.set(try? JSONEncoder().encode(pendingShifts), forKey: pendingShiftsKey)
    }

    func syncShifts() async {
        guard let shiftAPI, !syncingShifts, !pendingShifts.isEmpty else { return }
        syncingShifts = true
        shiftSyncStatus = "正在同步班表给柯…"
        defer { syncingShifts = false }
        while let key = pendingShifts.keys.sorted().first, let change = pendingShifts[key] {
            do {
                if let shift = change.shift { try await shiftAPI.setShift(date: key, shift: shift, note: change.note) }
                else { try await shiftAPI.deleteShift(date: key) }
                // A tap while this request was in flight must remain queued.
                if pendingShifts[key] == change {
                    pendingShifts.removeValue(forKey: key)
                    shiftRevision += 1
                    persistPendingShifts()
                    var known = Set(defaults.stringArray(forKey: knownRemoteShiftsKey) ?? [])
                    if change.shift == nil { known.remove(key) } else { known.insert(key) }
                    defaults.set(Array(known), forKey: knownRemoteShiftsKey)
                }
            } catch {
                shiftSyncStatus = "已存到本机，暂未同步给柯。点这里重试"
                return
            }
        }
        shiftSyncStatus = "班表已同步，柯能看到"
    }

    func refreshShifts() async {
        guard let shiftAPI else { return }
        let revision = shiftRevision
        do {
            let rows = try await shiftAPI.fetchShifts()
            guard revision == shiftRevision else { return }
            let remoteKeys = Set(rows.map(\.date))
            let oldKeys = Set(defaults.stringArray(forKey: knownRemoteShiftsKey) ?? [])
            var changedDates = Set<Date>()
            for key in oldKeys.subtracting(remoteKeys) where pendingShifts[key] == nil {
                savedShifts.removeValue(forKey: key); savedShiftNotes.removeValue(forKey: key); savedShiftNames.removeValue(forKey: key)
                clearedShiftKeys.insert(key)
                defaults.removeObject(forKey: "us.shift-plan.override." + key)
                defaults.removeObject(forKey: "us.shift-plan.remote." + key)
                if let date = shiftDate(key) { changedDates.insert(date) }
            }
            for row in rows where pendingShifts[row.date] == nil {
                guard let date = shiftDate(row.date) else { continue }
                let label = row.shift.hasSuffix("（已调整）") ? String(row.shift.dropLast("（已调整）".count)) : row.shift
                let previous = savedShiftNames[row.date] == label ? savedShifts[row.date] : nil
                let kind = previous ?? shiftTemplates.first { !$0.archived && $0.name == label }?.id ?? shiftTemplates.first { $0.name == label }?.id ?? .other
                savedShiftNames[row.date] = label
                savedShifts[row.date] = kind
                clearedShiftKeys.remove(row.date)
                let note = row.note ?? ""
                savedShiftNotes[row.date] = kind == .other ? (ShiftNote.userNote(from: note) ?? label) : ShiftNote.userNote(from: note)
                defaults.removeObject(forKey: "us.shift-plan.override." + row.date)
                defaults.removeObject(forKey: "us.shift-plan.remote." + row.date)
                if let plan = ShiftNote.plan(from: note) {
                    let prefix = note.contains("\n范围：当天单独调整") ? "us.shift-plan.override." : "us.shift-plan.remote."
                    defaults.set(try? JSONEncoder().encode(plan), forKey: prefix + row.date)
                }
                changedDates.insert(date)
            }
            defaults.set(Array(remoteKeys), forKey: knownRemoteShiftsKey)
            var stored = savedShifts.mapValues(\.rawValue)
            for key in clearedShiftKeys { stored[key] = "none" }
            defaults.set(stored, forKey: savedShiftsKey)
            defaults.set(savedShiftNotes, forKey: savedShiftNotesKey)
            defaults.set(savedShiftNames, forKey: savedShiftNamesKey)
            // The reminder coordinator reloads this cache when its end time changes.
            // Persist the whole snapshot first so newly downloaded overrides survive.
            for date in changedDates { updateEndTime(on: date) }
            thisWeek = thisWeek.map { day in
                let key = dateKey(day.date)
                return ShiftDay(id: day.id, date: day.date, kind: savedShifts[key], note: savedShiftNotes[key])
            }
        } catch {
            if pendingShifts.isEmpty { shiftSyncStatus = "班表暂未接上，请下拉重试" }
        }
    }

    private func shiftDate(_ key: String) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        return formatter.date(from: key)
    }

    private func updateEndTime(on date: Date) {
        guard defaults === UserDefaults.standard else { return }
        // Clear the coordinator's previous day override before recomputing it.
        let overrideData = defaults.data(forKey: "us.shift-plan.override." + dateKey(date))
        let plan = shiftPlan(on: date)
        HomeReminderCoordinator.shared.clearEndTime(on: date)
        if let overrideData { defaults.set(overrideData, forKey: "us.shift-plan.override." + dateKey(date)) }
        if let end = plan?.resolve(on: date)?.end {
            HomeReminderCoordinator.shared.setEndTime(end, on: date, override: overrideData != nil)
        }
    }

    func calendarDayAccessibilityLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        if let kind = shift(on: date) {
            return "\(formatter.string(from: date))，\(shiftDetail(kind, on: date))"
        }
        return "\(formatter.string(from: date))，未排班"
    }

    func calendarDayIdentifier(_ date: Date) -> String {
        "calendar-day-\(dateKey(date))"
    }

    func reminderDetail(_ item: Reminder) -> String {
        item.category == .medicine ? "饭后 1 粒" : reminderTime(item)
    }

    func reminderHeadline(_ item: Reminder) -> String {
        guard item.category == .medicine else { return item.text }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "aaa h:mm"
        return "\(formatter.string(from: item.dueAt)) · \(item.text)"
    }

    func reminderTime(_ item: Reminder) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = calendar.isDateInToday(item.dueAt) ? "今天 HH:mm" : "M月d日 HH:mm"
        return formatter.string(from: item.dueAt)
    }

    private func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
