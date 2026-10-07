import SwiftUI

struct HomeReminderSettingsView: View {
    @EnvironmentObject private var theme: Theme
    @ObservedObject var model: UsViewModel
    @ObservedObject private var reminders = HomeReminderCoordinator.shared
    @State private var selectedDate = Date()
    @State private var start = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
    @State private var hours = 8.0
    @State private var promise = ""
    @State private var shiftKind = ShiftDay.Kind.early
    @AppStorage("us.shift-profile.early.start") private var earlyStart = -1
    @AppStorage("us.shift-profile.early.minutes") private var earlyMinutes = 0
    @AppStorage("us.shift-profile.deputy.start") private var deputyStart = -1
    @AppStorage("us.shift-profile.deputy.minutes") private var deputyMinutes = 0
    @AppStorage("us.shift-profile.other.start") private var otherStart = -1
    @AppStorage("us.shift-profile.other.minutes") private var otherMinutes = 0

    private var calculatedEnd: Date {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: start)
        let beginning = Calendar.current.date(bySettingHour: parts.hour!, minute: parts.minute!, second: 0, of: selectedDate)!
        return beginning.addingTimeInterval(hours * 3600)
    }
    var body: some View {
        Form {
            Section("班次设置 · 时间由你填写") {
                Picker("班次", selection: $shiftKind) {
                    ForEach(ShiftDay.Kind.allCases, id: \.self) { kind in Text(model.shiftLabel(kind)).tag(kind) }
                }.onChange(of: shiftKind) { _, _ in loadProfile() }
                DatePicker("上班时间", selection: $start, displayedComponents: .hourAndMinute)
                Stepper("工作时长 \(hours, specifier: "%.1f") 小时", value: $hours, in: 0.5...24, step: 0.5)
                Button("保存这个班次的时间与时长") { saveProfile(); applyWeek() }
                Text("初始数值只是输入起点，按“保存”后才用于计算。跨午夜的班次会算到次日。")
                    .font(theme.font.caption)
                DatePicker("单独调整日期", selection: $selectedDate, displayedComponents: .date)
                Text("\(selectedDate.formatted(date: .abbreviated, time: .omitted))：\(model.shift(on: selectedDate).map { model.shiftLabel($0) } ?? "还没排班")")
                Text("计算下班：\(calculatedEnd.formatted(date: .abbreviated, time: .shortened))")
                Button("将这个下班时间用于所选日期") { reminders.setEndTime(calculatedEnd, on: selectedDate) }
                    .disabled(model.shift(on: selectedDate) == nil)
                if let end = reminders.endTime(on: selectedDate) {
                    Text("D3 提醒：\(end.addingTimeInterval(3600).formatted(date: .abbreviated, time: .shortened))")
                    Button("清除该日下班时间", role: .destructive) { reminders.clearEndTime(on: selectedDate) }
                }
            }
            Section("到家后再提醒") {
                Text(reminders.homeLabel)
                Button("把当前位置设为家") { reminders.setHomeHere() }
                Toggle("自动到家检测和提醒", isOn: $reminders.enabled)
                Text(reminders.status)
                Text("需要通知、始终定位与运动权限。位置或驾驶状态不明确时暂缓。iOS 后台可能延后检查；设置不会改变你的用药安排。")
                    .font(theme.font.caption)
            }
            Section("晚饭与睡前") {
                Button("已吃晚饭 · 提醒鲁拉西酮") { reminders.dinnerFinished() }
                Text("睡前 21:30：碳酸锂、劳拉西泮一片半、佐匹克隆一片。未确认到家或正在驾驶时不催。")
                ForEach([("d3", "D3"), ("dinner", "晚饭后这一拨"), ("bedtime", "睡前这一拨")], id: \.0) { item in
                    Button { reminders.markCompleted(item.0) } label: {
                        Label(reminders.isCompleted(item.0) ? "\(item.1) · 今天已完成" : "确认\(item.1)今天已完成",
                              systemImage: reminders.isCompleted(item.0) ? "checkmark.circle.fill" : "circle")
                    }.disabled(reminders.isCompleted(item.0))
                }
            }
            Section("今天答应你的事") {
                HStack {
                    TextField("记一件答应的事", text: $promise)
                    Button("记下") { reminders.addPromise(promise); promise = "" }
                        .disabled(promise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(reminders.promises) { item in
                    Button { reminders.togglePromise(item.id) } label: {
                        Label(item.text, systemImage: item.done ? "checkmark.circle.fill" : "circle")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.pageBackground)
        .foregroundStyle(theme.pageColor.textPrimary)
        .tint(theme.pageAccent)
        .navigationTitle("班表和提醒设置")
        .onAppear { loadProfile(); applyWeek() }
        .onChange(of: model.savedShifts) { _, _ in applyWeek() }
    }
    private func loadProfile() {
        let profile = profile(for: shiftKind)
        guard profile.0 >= 0 else { return }
        start = Calendar.current.date(bySettingHour: profile.0 / 60, minute: profile.0 % 60, second: 0, of: .now)!
        hours = Double(profile.1) / 60
    }
    private func saveProfile() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: start)
        let minutes = c.hour! * 60 + c.minute!
        switch shiftKind {
        case .early: earlyStart = minutes; earlyMinutes = Int(hours * 60)
        case .deputy: deputyStart = minutes; deputyMinutes = Int(hours * 60)
        case .other: otherStart = minutes; otherMinutes = Int(hours * 60)
        }
    }
    private func profile(for kind: ShiftDay.Kind) -> (Int, Int) {
        switch kind {
        case .early: return (earlyStart, earlyMinutes)
        case .deputy: return (deputyStart, deputyMinutes)
        case .other: return (otherStart, otherMinutes)
        }
    }
    private func applyWeek() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dates = Set(model.thisWeek.map(\.date) + model.savedShifts.keys.compactMap { formatter.date(from: $0) } + reminders.endTimes.keys.compactMap { formatter.date(from: $0) })
        for date in dates {
            guard let kind = model.shift(on: date) else { reminders.clearEndTime(on: date); continue }
            let p = profile(for: kind)
            guard p.0 >= 0, p.1 > 0,
                  let start = Calendar.current.date(bySettingHour: p.0 / 60, minute: p.0 % 60, second: 0, of: date) else { continue }
            reminders.setEndTime(start.addingTimeInterval(Double(p.1) * 60), on: date, override: false)
        }
    }
}
