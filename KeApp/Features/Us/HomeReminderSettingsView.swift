import SwiftUI

/// A quiet shift journal; home and medication controls live on their own page.
struct HomeReminderSettingsView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: UsViewModel
    @ObservedObject private var reminders = HomeReminderCoordinator.shared
    @State private var selectedDate: Date
    @State private var start = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
    @State private var hours = 8.0
    @State private var shiftKind = ShiftDay.Kind.early
    @State private var showingDay = false
    @State private var saved = false
    @State private var showingStart = false
    @AppStorage("us.shift-profile.early.start") private var earlyStart = -1
    @AppStorage("us.shift-profile.early.minutes") private var earlyMinutes = 0
    @AppStorage("us.shift-profile.deputy.start") private var deputyStart = -1
    @AppStorage("us.shift-profile.deputy.minutes") private var deputyMinutes = 0
    @AppStorage("us.shift-profile.other.start") private var otherStart = -1
    @AppStorage("us.shift-profile.other.minutes") private var otherMinutes = 0

    init(model: UsViewModel, date: Date = .now) {
        self.model = model
        _selectedDate = State(initialValue: date)
    }
    private var beginning: Date {
        let p = Calendar.current.dateComponents([.hour, .minute], from: start)
        return Calendar.current.date(bySettingHour: p.hour!, minute: p.minute!, second: 0, of: selectedDate)!
    }
    private var calculatedEnd: Date {
        let p = Calendar.current.dateComponents([.hour, .minute], from: start)
        return ShiftTiming.end(on: selectedDate, startMinutes: p.hour! * 60 + p.minute!, durationMinutes: Int(hours * 60)) ?? beginning
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Button("返回") { dismiss() }.font(theme.font.journalCaption).padding(.bottom, 8)
                Text("先写下你的班次。")
                    .font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary)
                Text("班次小记").font(theme.font.journalTitle)
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 28) {
                        Text("班次").foregroundStyle(theme.pageColor.textSecondary).frame(width: 36)
                        Menu {
                            ForEach(ShiftDay.Kind.allCases, id: \.self) { kind in
                                Button(model.shiftLabel(kind)) { shiftKind = kind }
                            }
                        } label: {
                            Text(model.shiftLabel(shiftKind)).frame(width: 110, alignment: .leading)
                                .padding(.bottom, 5).overlay(alignment: .bottom) { Rectangle().fill(theme.pageAccent).frame(height: 0.5) }
                        }.accessibilityIdentifier("shift-profile-kind")
                    }
                    HStack(spacing: 28) {
                        Text("上班").foregroundStyle(theme.pageColor.textSecondary).frame(width: 36)
                        Button(clockText(start)) { showingStart = true }
                            .frame(width: 110, alignment: .leading).padding(.bottom, 5)
                            .overlay(alignment: .bottom) { Rectangle().fill(theme.pageAccent).frame(height: 0.5) }
                            .accessibilityIdentifier("shift-start-time")
                    }
                    HStack(spacing: 18) {
                        Text("时长").foregroundStyle(theme.pageColor.textSecondary).frame(width: 36).padding(.trailing, 10)
                        Text("\(hours.formatted(.number.precision(.fractionLength(0...1)))) 小时")
                            .frame(width: 75, alignment: .leading).padding(.bottom, 5)
                            .overlay(alignment: .bottom) { Rectangle().fill(theme.pageAccent).frame(height: 0.5) }
                        durationButton("minus", label: "减少半小时", enabled: hours > 0.5) { hours -= 0.5 }
                        durationButton("plus", label: "增加半小时", enabled: hours < 24) { hours += 0.5 }
                    }.accessibilityIdentifier("shift-duration")
                }.padding(.leading, 18).padding(.top, 14)
                .onChange(of: shiftKind) { _, _ in loadProfile() }
                VStack(alignment: .leading, spacing: 44) {
                    timelineRow(beginning, text: "上班", icon: "circle.fill")
                    timelineRow(calculatedEnd, text: "下班", icon: "circle")
                    timelineRow(calculatedEnd.addingTimeInterval(3600), text: "惦记 D3", icon: "moon")
                    Text("下班后一个小时，跟晚饭一起。")
                        .font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary)
                        .padding(.leading, 28)
                }
                .padding(.vertical, 16)
                .background(alignment: .leading) {
                    MoonOrbitGuide().stroke(theme.pageColor.separator, lineWidth: 0.7)
                        .frame(width: 12).padding(.bottom, 38).allowsHitTesting(false)
                }
                Button {
                    saveProfile(); applyProfiles(); saved = true
                } label: {
                    HStack(spacing: 10) { Text(saved ? "这个班次记好了" : "记住这个班次").underline(); Image(systemName: saved ? "checkmark" : "chevron.right").font(.system(size: 10, weight: .light)) }.font(theme.font.journalBody).foregroundStyle(theme.pageAccent).frame(maxWidth: .infinity)
                }.accessibilityIdentifier("shift-profile-save")
                Divider().overlay(theme.pageColor.separator)
                Button { showingDay.toggle() } label: {
                    HStack(spacing: 10) { Text("某一天不一样？单独记").underline(); Image(systemName: "chevron.right").font(.system(size: 10, weight: .light)) }.font(theme.font.journalCaption).foregroundStyle(theme.pageAccent).frame(maxWidth: .infinity)
                }.accessibilityIdentifier("shift-day-adjust")
                if showingDay {
                    DatePicker("日期", selection: $selectedDate, displayedComponents: .date)
                    Text(model.shift(on: selectedDate).map { "当天班次：" + model.shiftLabel($0) } ?? "这天还没排班，请先在月历填班次。")
                        .font(theme.font.journalCaption)
                    Text("按上面的起点与时长，算到 \(calculatedEnd.formatted(date: .abbreviated, time: .shortened)) 下班。")
                        .font(theme.font.journalCaption)
                    Button("只记这一天的下班时间") { reminders.setEndTime(calculatedEnd, on: selectedDate) }
                        .disabled(model.shift(on: selectedDate) == nil)
                        .accessibilityIdentifier("shift-day-save")
                    if let end = reminders.endTime(on: selectedDate) {
                        Text("已记：\(end.formatted(date: .abbreviated, time: .shortened)) 下班，\(end.addingTimeInterval(3600).formatted(date: .omitted, time: .shortened)) 提醒 D3")
                            .font(theme.font.journalCaption)
                        Button("清除当天的单独调整", role: .destructive) { reminders.clearEndTime(on: selectedDate) }
                    }
                }
                Text("数值由你填写，点“记住”才用于计算。跨午夜会算到次日；单独调整的日期优先。")
                    .font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary)
            }
            .padding(.horizontal, 28).padding(.vertical, 20)
        }
        .font(theme.font.journalBody).buttonStyle(.plain)
        .foregroundStyle(theme.pageColor.textPrimary)
        .tint(theme.pageAccent)
        .background { MoonJournalBackground().overlay(alignment: .topTrailing) { JournalMoonArtwork().frame(width: 180, height: 180).offset(x: 75, y: -55) }.clipped() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingStart) {
            VStack(spacing: 12) {
                DatePicker("上班时间", selection: $start, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel).labelsHidden().environment(\.locale, Locale(identifier: "zh_CN"))
                Button("记好了") { showingStart = false }.font(theme.font.journalBody)
            }.presentationDetents([.height(290)]).presentationBackground(theme.pageBackground).tint(theme.pageAccent)
        }
        .onAppear {
            shiftKind = model.shift(on: selectedDate) ?? .early
            loadProfile(); applyProfiles()
        }
        .onChange(of: model.savedShifts) { _, _ in applyProfiles() }
        .onChange(of: start) { _, _ in saved = false }
        .onChange(of: hours) { _, _ in saved = false }
    }
    private func timelineRow(_ time: Date, text: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(theme.pageAccent).frame(width: 12)
            Text(clockText(time)).monospacedDigit()
            Text(text)
            if !Calendar.current.isDate(time, inSameDayAs: selectedDate) {
                Text("次日").font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary)
            }
        }.font(theme.font.journalQuote)
    }
    private func clockText(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"; return formatter.string(from: date)
    }
    private func durationButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .ultraLight))
                .frame(width: 27, height: 27)
                .overlay(Circle().stroke(theme.pageAccent, lineWidth: 0.6))
                .frame(width: 36, height: 44)
        }.foregroundStyle(theme.pageAccent).disabled(!enabled).accessibilityLabel(label)
    }
    private func loadProfile() {
        saved = false
        let p = profile(for: shiftKind)
        guard p.0 >= 0, p.1 > 0 else { return }
        start = Calendar.current.date(bySettingHour: p.0 / 60, minute: p.0 % 60, second: 0, of: .now)!
        hours = Double(p.1) / 60
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
    private func applyProfiles() {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let dates = Set(model.thisWeek.map(\.date) + model.savedShifts.keys.compactMap { formatter.date(from: $0) } + reminders.endTimes.keys.compactMap { formatter.date(from: $0) })
        for date in dates {
            guard let kind = model.shift(on: date) else { reminders.clearEndTime(on: date); continue }
            let p = profile(for: kind)
            guard p.0 >= 0, p.1 > 0, let start = Calendar.current.date(bySettingHour: p.0 / 60, minute: p.0 % 60, second: 0, of: date) else { continue }
            reminders.setEndTime(start.addingTimeInterval(Double(p.1) * 60), on: date, override: false)
        }
    }
}

struct ReminderJournalView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reminders = HomeReminderCoordinator.shared
    @State private var showingHome = false
    @State private var promise = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button("返回") { dismiss() }.font(theme.font.journalCaption).padding(.bottom, 24)
                HStack(alignment: .top) {
                    Text("到家了，再慢慢来。").font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary)
                    Spacer()
                    Button { showingHome = true } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "gearshape").font(.system(size: 18, weight: .ultraLight))
                            Text("家的位置").font(.custom("NotoSerifSC-ExtraLight", size: 9))
                        }
                    }.accessibilityLabel("家的位置和提醒设置").accessibilityIdentifier("reminder-home-settings")
                }
                Text("今晚的惦记").font(theme.font.journalTitle).padding(.top, 10)
                HStack(spacing: 7) {
                    Circle().stroke(theme.pageAccent, lineWidth: 0.6).frame(width: 9, height: 9)
                    Text(reminders.status).font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary)
                }.padding(.top, 10)
                HStack(spacing: 9) {
                    Text("D3 · 下班后 1 小时").font(theme.font.journalCaption)
                    Spacer()
                    completion("d3", title: "D3")
                }.padding(.top, 22)
                journalHeading("饭后", symbol: "moon.fill").padding(.top, 26)
                HStack {
                    Text("鲁拉西酮")
                    Spacer()
                    Button("我吃过晚饭了") { reminders.dinnerFinished() }
                        .font(theme.font.journalCaption).padding(.horizontal, 16).padding(.vertical, 9)
                        .overlay(Capsule().stroke(theme.pageAccent, lineWidth: 0.6))
                        .accessibilityIdentifier("reminder-dinner-finished")
                }.padding(.top, 24)
                completion("dinner", title: "饭后这一拨").padding(.top, 13)
                journalHeading("睡前 · 21:30", symbol: "moon.fill").padding(.top, 28)
                VStack(alignment: .leading, spacing: 14) {
                    Text("碳酸锂 · 晚上那片")
                    Text("劳拉西泮 · 一片半")
                    Text("佐匹克隆 · 一片")
                }.padding(.top, 23)
                completion("bedtime", title: "睡前这一拨").padding(.top, 15)
                Text("到家、没在开车时才提醒。")
                    .font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary).padding(.top, 15)
                journalHeading("答应你的事", symbol: "circle").padding(.top, 30)
                ForEach(reminders.promises) { item in
                    Button { reminders.togglePromise(item.id) } label: {
                        Label(item.text, systemImage: item.done ? "checkmark.circle" : "circle")
                    }.padding(.top, 20)
                }
                HStack {
                    TextField("添一句答应的事", text: $promise)
                    Button("记下") { reminders.addPromise(promise); promise = "" }
                        .disabled(promise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(.top, 20)
            }.padding(.horizontal, 28).padding(.top, 14).padding(.bottom, 30)
        }
        .font(theme.font.journalBody).buttonStyle(.plain).foregroundStyle(theme.pageColor.textPrimary).tint(theme.pageAccent)
        .background {
            MoonJournalBackground().overlay(alignment: .bottomTrailing) {
                JournalMoonArtwork().frame(width: 280, height: 280).offset(x: 135, y: 80).opacity(0.65)
            }.clipped()
        }
        .navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingHome) {
            NavigationStack {
                Form {
                    Section("家的位置") {
                        Text(reminders.homeLabel)
                        Button("把当前位置设为家") { reminders.setHomeHere() }
                        Toggle("自动到家检测和提醒", isOn: $reminders.enabled)
                        Text(reminders.status)
                    }
                    Section {
                        Text("只在家中设置当前位置。需要通知、始终定位与运动权限。系统后台检查可能延后；状态不确定时不会催。")
                    }
                }
                .scrollContentBackground(.hidden).background(theme.pageBackground).tint(theme.pageAccent)
                .navigationTitle("家的位置")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingHome = false } } }
            }
        }
    }
    private func journalHeading(_ text: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(theme.pageAccent)
            Text(text).font(theme.font.journalHeading)
            Rectangle().fill(theme.pageColor.separator).frame(height: 0.7)
        }.padding(.top, 10)
    }
    private func completion(_ kind: String, title: String) -> some View {
        Button { reminders.markCompleted(kind) } label: {
            Label(reminders.isCompleted(kind) ? "今天记好了" : "确认\(title)已完成",
                  systemImage: reminders.isCompleted(kind) ? "checkmark.circle" : "circle")
                .font(.custom("NotoSerifSC-ExtraLight", size: 10)).foregroundStyle(theme.pageColor.textSecondary)
        }.disabled(reminders.isCompleted(kind))
    }
}
