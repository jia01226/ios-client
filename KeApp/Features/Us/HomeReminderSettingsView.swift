import SwiftUI

/// One or two work periods; breaks never count towards worked time.
struct HomeReminderSettingsView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: UsViewModel
    @ObservedObject private var reminders = HomeReminderCoordinator.shared
    @State private var selectedDate: Date
    @State private var plan = ShiftPlan.example
    @State private var shiftKind = ShiftDay.Kind.early
    @State private var showingDay = false
    @State private var saved = false
    @State private var editingClock: ClockSelection?
    private struct ClockSelection: Identifiable {
        let period: Int
        let isEnd: Bool
        var id: String { "\(period)-\(isEnd)" }
    }
    init(model: UsViewModel, date: Date = .now) {
        self.model = model
        _selectedDate = State(initialValue: date)
    }
    private var resolved: ShiftPlan.Resolved? { plan.resolve(on: selectedDate) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Button("返回") { dismiss() }.font(theme.font.journalCaption).padding(.bottom, 8)
                Text("先写下你的班次。")
                    .font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary)
                Text("班次小记").font(theme.font.journalTitle)
                HStack(spacing: 24) {
                    Text("班次").foregroundStyle(theme.pageColor.textSecondary)
                    Menu {
                        ForEach(ShiftDay.Kind.allCases, id: \.self) { kind in
                            Button(model.shiftLabel(kind)) { shiftKind = kind; loadProfile() }
                        }
                    } label: {
                        Text(model.shiftLabel(shiftKind)).frame(width: 110, alignment: .leading)
                            .padding(.bottom, 5).overlay(alignment: .bottom) { hairline }
                    }.accessibilityIdentifier("shift-profile-kind")
                }.padding(.top, 8)
                HStack(spacing: 12) {
                    modeButton("连续上班", split: false)
                    modeButton("分两段", split: true)
                }
                VStack(spacing: 20) {
                    ForEach(plan.periods.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 12) {
                            if plan.periods.count == 2 {
                                Text(index == 0 ? "第一段" : "第二段").font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary)
                            }
                            HStack(spacing: 24) {
                                clockButton(index, isEnd: false)
                                Text("—").foregroundStyle(theme.pageColor.separator)
                                clockButton(index, isEnd: true)
                            }
                        }
                    }
                }
                if let resolved {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("合计上班 \(durationText(resolved.workMinutes))")
                        if resolved.breakMinutes > 0 {
                            Text("中间休息 \(durationText(resolved.breakMinutes))，不计入工时。")
                                .font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary)
                        }
                    }.accessibilityIdentifier("shift-work-duration")
                    VStack(alignment: .leading, spacing: plan.periods.count == 2 ? 20 : 38) {
                        ForEach(Array(resolved.periods.enumerated()), id: \.offset) { index, period in
                            timelineRow(period.start, text: index == 0 ? "上班" : "继续上班", icon: index == 0 ? "circle.fill" : "circle")
                            timelineRow(period.end, text: index == resolved.periods.count - 1 ? "下班" : "休息", icon: "circle")
                        }
                        timelineRow(resolved.end.addingTimeInterval(3600), text: "惦记 D3", icon: "moon")
                    }
                    .padding(.vertical, 8)
                    .background(alignment: .leading) {
                        MoonOrbitGuide().stroke(theme.pageColor.separator, lineWidth: 0.7).frame(width: 12).allowsHitTesting(false)
                    }
                    Text("最后一段下班后一个小时，跟晚饭一起。")
                        .font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary)
                } else {
                    Text("请检查起止时间：每段结束不能与开始相同，两段需按顺序填写，整班不超过一天。")
                        .font(theme.font.journalCaption).foregroundStyle(theme.pageAccent)
                }
                Button {
                    plan.save(kind: shiftKind.rawValue); applyProfiles(); saved = true
                } label: {
                    HStack(spacing: 10) {
                        Text(saved ? "这个班次记好了" : "记住这个班次").underline()
                        Image(systemName: saved ? "checkmark" : "chevron.right").font(.system(size: 10, weight: .light))
                    }.foregroundStyle(theme.pageAccent).frame(maxWidth: .infinity)
                }.disabled(resolved == nil).accessibilityIdentifier("shift-profile-save")
                hairline
                Button { showingDay.toggle() } label: {
                    HStack(spacing: 10) {
                        Text("某一天不一样？单独记").underline()
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .light))
                    }.font(theme.font.journalCaption).foregroundStyle(theme.pageAccent).frame(maxWidth: .infinity)
                }.accessibilityIdentifier("shift-day-adjust")
                if showingDay {
                    DatePicker("日期", selection: $selectedDate, displayedComponents: .date)
                    Text(model.shift(on: selectedDate).map { "当天班次：" + model.shiftLabel($0) } ?? "这天还没排班，请先在月历填班次。")
                        .font(theme.font.journalCaption)
                    Button("只记这一天的时间") {
                        guard let resolved else { return }
                        UserDefaults.standard.set(try? JSONEncoder().encode(plan), forKey: overrideKey)
                        reminders.setEndTime(resolved.end, on: selectedDate)
                    }.disabled(resolved == nil || model.shift(on: selectedDate) == nil).accessibilityIdentifier("shift-day-save")
                    if let end = reminders.endTime(on: selectedDate) {
                        Text("已记：\(end.formatted(date: .abbreviated, time: .shortened)) 下班")
                            .font(theme.font.journalCaption)
                        Button("清除当天的单独调整", role: .destructive) {
                            reminders.clearEndTime(on: selectedDate); loadProfile(); applyProfiles()
                        }
                    }
                }
                Text("时间由你填写，点“记住”才保存。跨午夜会标为次日；单独调整的日期优先。")
                    .font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary)
            }.padding(.horizontal, 28).padding(.vertical, 20)
        }
        .font(theme.font.journalBody).buttonStyle(.plain).foregroundStyle(theme.pageColor.textPrimary).tint(theme.pageAccent)
        .background { MoonJournalBackground().overlay(alignment: .topTrailing) { JournalMoonArtwork().frame(width: 180, height: 180).offset(x: 75, y: -55) }.clipped() }
        .background(theme.pageBackground.ignoresSafeArea()).navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editingClock) { selection in
            VStack(spacing: 12) {
                DatePicker(selection.isEnd ? "结束时间" : "开始时间", selection: clockBinding(selection), displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel).labelsHidden().environment(\.locale, Locale(identifier: "zh_CN"))
                Button("记好了") { editingClock = nil }.font(theme.font.journalBody)
            }.presentationDetents([.height(290)]).presentationBackground(theme.pageBackground).tint(theme.pageAccent)
        }
        .onAppear { loadDay(); applyProfiles() }
        .onChange(of: model.savedShifts) { _, _ in applyProfiles() }
        .onChange(of: plan) { _, _ in saved = false }
        .onChange(of: selectedDate) { _, _ in loadDay() }
    }
    private var hairline: some View { Rectangle().fill(theme.pageColor.separator).frame(height: 0.5) }
    private var overrideKey: String { "us.shift-plan.override." + HomeReminderCoordinator.dayKey(selectedDate) }
    private func modeButton(_ title: String, split: Bool) -> some View {
        let selected = (plan.periods.count == 2) == split
        return Button { setSplit(split) } label: {
            Text(title).font(theme.font.journalCaption).padding(.horizontal, 16).padding(.vertical, 9)
                .background(theme.pageAccent.opacity(selected ? 0.18 : 0), in: Capsule())
                .overlay(Capsule().stroke(theme.pageColor.separator, lineWidth: 0.5))
        }.accessibilityIdentifier(split ? "shift-mode-split" : "shift-mode-continuous")
    }
    private func setSplit(_ split: Bool) {
        guard split != (plan.periods.count == 2) else { return }
        if split {
            let first = plan.periods[0]
            let duration = (first.endMinutes - first.startMinutes + 1440) % 1440
            let middle = (first.startMinutes + max(30, duration / 2)) % 1440
            plan.periods = [ShiftPeriod(startMinutes: first.startMinutes, endMinutes: middle),
                            ShiftPeriod(startMinutes: (middle + 60) % 1440, endMinutes: first.endMinutes)]
        } else {
            plan.periods = [ShiftPeriod(startMinutes: plan.periods[0].startMinutes, endMinutes: plan.periods.last!.endMinutes)]
        }
    }
    private func clockButton(_ index: Int, isEnd: Bool) -> some View {
        let minutes = isEnd ? plan.periods[index].endMinutes : plan.periods[index].startMinutes
        return Button { editingClock = ClockSelection(period: index, isEnd: isEnd) } label: {
            VStack(alignment: .leading, spacing: 7) {
                Text(isEnd ? "结束" : "开始").font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary)
                HStack(spacing: 6) {
                    Text(String(format: "%02d:%02d", minutes / 60, minutes % 60))
                    if let resolved, resolved.periods.indices.contains(index) {
                        let date = isEnd ? resolved.periods[index].end : resolved.periods[index].start
                        if !Calendar.current.isDate(date, inSameDayAs: selectedDate) {
                            Text("次日").font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 5).overlay(alignment: .bottom) { hairline }
            }
            .contentShape(Rectangle())
        }.accessibilityIdentifier("shift-\(index)-\(isEnd ? "end" : "start")")
    }
    private func clockBinding(_ selection: ClockSelection) -> Binding<Date> {
        Binding(get: {
            let p = plan.periods[selection.period]
            let minutes = selection.isEnd ? p.endMinutes : p.startMinutes
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: selectedDate)!
        }, set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            if selection.isEnd { plan.periods[selection.period].endMinutes = c.hour! * 60 + c.minute! }
            else { plan.periods[selection.period].startMinutes = c.hour! * 60 + c.minute! }
            plan.periods[selection.period].fullDay = false
        })
    }
    private func durationText(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60) 小时" : "\(minutes / 60) 小时 \(minutes % 60) 分钟"
    }
    private func clockText(_ time: Date) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"; return formatter.string(from: time)
    }
    private func timelineRow(_ time: Date, text: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(theme.pageAccent).frame(width: 12)
            Text(clockText(time)).monospacedDigit()
            Text(text)
            if !Calendar.current.isDate(time, inSameDayAs: selectedDate) { Text("次日").font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary) }
        }.font(theme.font.journalQuote)
    }
    private func loadProfile() { plan = ShiftPlan.load(kind: shiftKind.rawValue) ?? .example; saved = false }
    private func loadDay() {
        shiftKind = model.shift(on: selectedDate) ?? .early
        loadProfile()
        if let data = UserDefaults.standard.data(forKey: overrideKey), let override = try? JSONDecoder().decode(ShiftPlan.self, from: data) {
            plan = override
        }
    }
    private func applyProfiles() {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let dates = Set(model.thisWeek.map(\.date) + model.savedShifts.keys.compactMap { formatter.date(from: $0) } + reminders.endTimes.keys.compactMap { formatter.date(from: $0) })
        for date in dates {
            guard let kind = model.shift(on: date) else { reminders.clearEndTime(on: date); continue }
            guard let end = ShiftPlan.load(kind: kind.rawValue)?.resolve(on: date)?.end else { continue }
            reminders.setEndTime(end, on: date, override: false)
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
        .background(theme.pageBackground.ignoresSafeArea())
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
