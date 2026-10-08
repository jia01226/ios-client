import SwiftUI

// 【我们】—— 两个人的日子、便利贴与排班，顺着页面慢慢展开。

struct UsView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.scenePhase) private var scenePhase
    let line: ChatLine
    @StateObject private var vm: UsViewModel
    @StateObject private var periods: PeriodStore
    @StateObject private var notes: StickyNotesStore
    @State private var anniversaryID = "together"
    @State private var editAnniversaries = false
    @State private var editTemplates = false
    @State private var editDay: CalendarEditSelection?
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    private let anniversaryIDs = ["together", "confession", "mine", "ke"]
    private let anniversaryTitles = ["纪念日", "表白日", "我的生日", "柯生日"]
    init(line: ChatLine = .test1) {
        self.line = line
        let api = APIClient(baseURL: line.apiBaseURL)
        _vm = StateObject(wrappedValue: UsViewModel(api: api))
        _periods = StateObject(wrappedValue: PeriodStore(api: api, scope: line.rawValue))
        _notes = StateObject(wrappedValue: StickyNotesStore(api: api, scope: line.rawValue))
    }
    private var selected: Anniversary? { vm.anniversaries.first { $0.id == anniversaryID } ?? vm.anniversaries.first }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MoonlightHeader(title: "我们", subtitle: "和你一起，把每一天都变成喜欢的日子。", artwork: "UsMoonBloom")
                        .padding(.top, theme.skin == .day ? 20 : 0)
                    anniversary.padding(.top, theme.skin == .day ? 40 : 14)
                    HStack(spacing: 0) {
                        ForEach(Array(anniversaryIDs.enumerated()), id: \.element) { index, id in
                            Button { anniversaryID = id } label: {
                                VStack(spacing: 7) {
                                    Text(anniversaryTitles[index]).font(Moonlight.serif(14))
                                    Circle().fill(anniversaryID == id ? theme.pageAccent : theme.pageAccent.opacity(0)).frame(width: 4, height: 4)
                                }.foregroundStyle(anniversaryID == id ? theme.pageAccent : theme.pageColor.textSecondary)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }.accessibilityIdentifier("anniversary-" + id)
                        }
                    }.padding(.top, theme.skin == .day ? 32 : 16)
                    MoonStickyNotesView(store: notes).padding(.top, theme.skin == .day ? 48 : 8)
                    // The weekly schedule follows below the fold; don't compress the anniversary to fit it.
                    weekly.padding(.top, theme.skin == .day ? 60 : 26)
                    Button {
                        withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("month-calendar", anchor: .top) }
                    } label: {
                        VStack(spacing: 7) {
                            Text("\(Calendar.current.component(.month, from: month))月").font(Moonlight.serif(16))
                            Image(systemName: "chevron.down").font(.system(size: 12, weight: .ultraLight))
                        }.frame(maxWidth: .infinity, minHeight: 64)
                    }.padding(.vertical, theme.skin == .day ? 24 : 10).accessibilityIdentifier("us-show-month")
                    VStack(spacing: 20) {
                        PeriodQuickActions(store: periods)
                        calendar
                    }.id("month-calendar").padding(.top, 12)
                    if let status = vm.shiftSyncStatus {
                        Button(status) { Task { await vm.syncShifts() } }.font(Moonlight.serif(12)).padding(.top, 16)
                    }
                    if let error = vm.reminderLoadError {
                        Button(error) { Task { await vm.loadReminders() } }.font(Moonlight.serif(12)).padding(.top, 12)
                    }
                    Button("编辑纪念日") { editAnniversaries = true }
                        .font(Moonlight.serif(12)).foregroundStyle(theme.pageColor.textSecondary).padding(.top, 28)
                }.padding(.horizontal, 26).padding(.bottom, 32)
            }.scrollIndicators(.hidden).refreshable { await load() }
        }
        .buttonStyle(.plain).foregroundStyle(theme.pageColor.textPrimary)
        .background(theme.pageBackground.ignoresSafeArea()).tint(theme.pageAccent)
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
        .sheet(isPresented: $editTemplates) { HomeReminderSettingsView(model: vm).environmentObject(theme) }
        .sheet(isPresented: $editAnniversaries, onDismiss: { Task { await vm.loadReminders() } }) {
            CompanionPages(page: .anniversaries, line: line).environmentObject(theme)
        }
        .sheet(item: $editDay) { selection in
            ScheduleEditorSheet(model: vm, date: selection.date, currentShift: vm.shift(on: selection.date), currentNote: vm.shiftNote(on: selection.date)) { shift, note in
                vm.setShift(shift, note: note, on: selection.date); editDay = nil
            }.presentationDetents([.large]).presentationBackground(theme.pageBackground)
        }
    }
    private func load() async {
        async let a: Void = vm.loadReminders()
        async let b: Void = periods.load()
        async let c: Void = notes.load()
        _ = await (a, b, c)
    }
    @ViewBuilder private var anniversary: some View {
        if let selected {
            let display = vm.display(for: selected)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(selected.id == "together" ? "在一起" : display.title).font(Moonlight.serif(22))
                    Text("with you").font(Moonlight.script(23)).foregroundStyle(theme.pageAccent)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(display.number).font(Moonlight.numeral(theme.skin == .day ? 92 : 88)).minimumScaleFactor(0.6).lineLimit(1)
                        .frame(height: theme.skin == .day ? 126 : 110)
                    Text(display.unit).font(Moonlight.serif(27))
                }.padding(.top, theme.skin == .day ? 10 : 3)
                HStack(spacing: 12) {
                    Rectangle().fill(theme.pageAccent).frame(width: 24, height: 0.7)
                    Text(display.dateLabel).font(Moonlight.serif(14)).tracking(1)
                }.padding(.top, theme.skin == .day ? 8 : 0)
            }.accessibilityElement(children: .combine).accessibilityIdentifier("us-anniversary-pager")
        }
    }
    private var weekly: some View {
        VStack(alignment: .leading, spacing: theme.skin == .day ? 22 : 14) {
            HStack {
                Text("这一周").font(Moonlight.serif(23))
                Spacer()
                Button { editTemplates = true } label: {
                    Image(systemName: "pencil.line").font(.system(size: 19, weight: .ultraLight)).frame(width: 44, height: 44)
                }.accessibilityLabel("设置班次时间").accessibilityIdentifier("us-shift-settings")
            }
            HStack(spacing: 0) {
                ForEach(Array(vm.thisWeek.enumerated()), id: \.element.id) { index, day in
                    Button { tapDay(day.date) } label: {
                        VStack(spacing: 10) {
                            Text(["一", "二", "三", "四", "五", "六", "日"][index]).font(Moonlight.serif(13))
                            Text("\(Calendar.current.component(.day, from: day.date))")
                                .font(Moonlight.numeral(25)).frame(width: 34, height: 34)
                                .overlay(Circle().stroke(Calendar.current.isDateInToday(day.date) ? theme.pageAccent : theme.pageAccent.opacity(0), lineWidth: 0.7))
                            Text(vm.shift(on: day.date).map { vm.shiftDisplay($0, on: day.date) } ?? "—")
                                .font(Moonlight.serif(12)).lineLimit(1).minimumScaleFactor(0.7)
                        }.foregroundStyle(Calendar.current.isDateInToday(day.date) ? theme.pageAccent : theme.pageColor.textSecondary)
                            .frame(maxWidth: .infinity).contentShape(Rectangle())
                    }.accessibilityIdentifier("week-day-\(index)")
                        .accessibilityLabel(vm.calendarDayAccessibilityLabel(day.date))
                        .accessibilityHint(vm.shift(on: day.date) == nil ? "轻点写班表" : "轻点直接取消当天排班")
                }
            }
        }
    }
    private func tapDay(_ date: Date) {
        if vm.shift(on: date) != nil { vm.setShift(nil, on: date) }
        else { editDay = CalendarEditSelection(date: date) }
    }
    private var calendar: some View {
        VStack(spacing: 16) {
            HStack {
                Button { month = vm.month(byAdding: -1, to: month) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("上个月")
                Spacer()
                Text(vm.monthTitle(for: month)).font(Moonlight.serif(21))
                Spacer()
                Button { month = vm.month(byAdding: 1, to: month) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("下个月")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 10) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text($0).font(Moonlight.serif(12)).foregroundStyle(theme.pageColor.textSecondary) }
                ForEach(Array(vm.monthCells(for: month).enumerated()), id: \.offset) { _, date in
                    if let date {
                        Button { tapDay(date) } label: {
                            VStack(spacing: 4) {
                                Text("\(Calendar.current.component(.day, from: date))").font(Moonlight.numeral(20))
                                Text(vm.shift(on: date).map { vm.shiftDisplay($0, on: date) } ?? " ")
                                    .font(Moonlight.serif(10)).lineLimit(1).minimumScaleFactor(0.7)
                                Circle().fill(isAnniversary(date) ? theme.pageAccent : theme.pageAccent.opacity(0)).frame(width: 3, height: 3)
                            }.frame(maxWidth: .infinity, minHeight: 52)
                                .background(theme.pageAccent.opacity(isPeriod(date) ? 0.16 : 0), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.pageAccent.opacity(Calendar.current.isDateInToday(date) ? 0.7 : 0), lineWidth: 0.6))
                        }.accessibilityIdentifier(vm.calendarDayIdentifier(date))
                            .accessibilityLabel(vm.calendarDayAccessibilityLabel(date) + (isPeriod(date) ? "，经期" : "") + (isAnniversary(date) ? "，纪念日" : ""))
                    } else { Color.clear.frame(height: 52) }
                }
            }.accessibilityIdentifier("us-month-grid")
            if !vm.isCurrentMonth(month) { Button("回到本月") { month = vm.startOfMonth(for: .now) }.font(Moonlight.serif(12)) }
        }
    }
    private func isPeriod(_ date: Date) -> Bool {
        let key = HomeReminderCoordinator.dayKey(date)
        return periods.records.contains { $0.start_date <= key && key <= (periods.pendingEnds[$0.id] ?? $0.end_date ?? periods.today) }
    }
    private func isAnniversary(_ date: Date) -> Bool {
        vm.anniversaries.contains {
            Calendar.current.component(.month, from: $0.date) == Calendar.current.component(.month, from: date) &&
            Calendar.current.component(.day, from: $0.date) == Calendar.current.component(.day, from: date)
        }
    }
}

private struct AnniversaryPager: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let events: [Anniversary]
    @Binding var selectedIndex: Int
    let displayFor: (Anniversary) -> AnniversaryDisplay

    var body: some View {
        VStack(spacing: 6) {
            TabView(selection: $selectedIndex) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    AnniversaryPage(display: displayFor(event))
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: selectedIndex)
            .accessibilityIdentifier("us-anniversary-pager")

            HStack(spacing: 7) {
                ForEach(events.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index == selectedIndex ? UsPalette.coral : UsPalette.hairline.opacity(0.42))
                        .frame(width: index == selectedIndex ? 22 : 7, height: 5)
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 1), value: selectedIndex)
            .accessibilityHidden(true)
        }
        .sensoryFeedback(.alignment, trigger: selectedIndex)
    }
}

private struct AnniversaryPage: View {
    let display: AnniversaryDisplay

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Image("WatercolorMoon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: min(proxy.size.width * 0.82, 320))
                    .position(x: proxy.size.width * 0.83, y: 132)
                    .opacity(0.72)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    Text("我们的时间")
                        .font(.custom("STSongti-SC-Light", size: 27, relativeTo: .title))
                        .tracking(2.8)
                    Text(display.title)
                        .font(.custom("STSongti-SC-Light", size: 14, relativeTo: .subheadline))
                        .tracking(2)
                        .foregroundStyle(UsPalette.mutedInk)
                        .padding(.top, 27)
                    HStack(alignment: .lastTextBaseline, spacing: 7) {
                        Text(display.number)
                            .font(.custom("Didot", size: 72, relativeTo: .largeTitle))
                            .tracking(-2)
                            .monospacedDigit()
                            .foregroundStyle(UsPalette.coral)
                        Text(display.unit)
                            .font(.custom("STSongti-SC-Light", size: 16, relativeTo: .body))
                            .padding(.bottom, 9)
                    }
                    Text(display.dateLabel)
                        .font(.custom("STSongti-SC-Light", size: 13, relativeTo: .caption))
                        .tracking(1)
                        .foregroundStyle(UsPalette.mutedInk)
                }
                .foregroundStyle(UsPalette.ink)
                .padding(.horizontal, 31)
                .padding(.top, 48)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(display.title)，\(display.number)\(display.unit)，\(display.dateLabel)")
            .accessibilityHint("左右滑动切换纪念日")
        }
    }
}

private struct BotanicalSprig: View {
    var body: some View {
        Canvas { context, size in
            let stem = Path { path in
                path.move(to: CGPoint(x: size.width * 0.22, y: size.height * 0.96))
                path.addCurve(
                    to: CGPoint(x: size.width * 0.72, y: size.height * 0.06),
                    control1: CGPoint(x: size.width * 0.28, y: size.height * 0.60),
                    control2: CGPoint(x: size.width * 0.62, y: size.height * 0.35)
                )
            }
            context.stroke(stem, with: .color(UsPalette.sage.opacity(0.80)), lineWidth: 1)
            for leaf in [
                CGRect(x: 7, y: 21, width: 13, height: 7),
                CGRect(x: 19, y: 10, width: 12, height: 7),
                CGRect(x: 16, y: 31, width: 11, height: 6),
            ] {
                context.fill(Path(ellipseIn: leaf), with: .color(UsPalette.sage.opacity(0.64)))
            }
            context.fill(Path(ellipseIn: CGRect(x: 27, y: 1, width: 6, height: 6)), with: .color(UsPalette.coral.opacity(0.72)))
            context.fill(Path(ellipseIn: CGRect(x: 33, y: 7, width: 4, height: 4)), with: .color(UsPalette.blush.opacity(0.82)))
        }
    }
}

private struct CurvedWeekSchedule: View {
    let days: [ShiftDay]
    @Binding var selectedIndex: Int
    let vm: UsViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("这一周")
                    .font(.custom("STSongti-SC-Light", size: 18, relativeTo: .headline))
                    .tracking(1.8)
                    .foregroundStyle(UsPalette.ink)
                Spacer()
                Text(vm.weekRangeLabel)
                    .font(.custom("STSongti-SC-Light", size: 11, relativeTo: .caption2))
                    .tracking(0.8)
                    .foregroundStyle(UsPalette.mutedInk)
            }
            .padding(.horizontal, 30)

            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .topLeading) {
                    WeekGlowTrail(width: width, selectedIndex: selectedIndex)

                    ForEach(Array(days.prefix(7).enumerated()), id: \.element.id) { index, day in
                        let x = width * (CGFloat(index) + 0.5) / 7
                        let relative = (x - width / 2) / (width / 2)
                        let curveY = 31 + 24 * relative * relative
                        let displayedShift = vm.shift(on: day.date)

                        Button {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                                selectedIndex = index
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Text(vm.weekdayLabel(day.date))
                                    .font(.custom("STSongti-SC-Light", size: 10, relativeTo: .caption2))
                                    .foregroundStyle(index == selectedIndex ? UsPalette.coral : UsPalette.mutedInk)
                                ShiftMoonMarker(hasShift: displayedShift != nil, selected: index == selectedIndex)
                                    .frame(width: index == selectedIndex ? 42 : 34, height: index == selectedIndex ? 42 : 34)
                                Text(displayedShift.map { vm.shiftDisplay($0, on: day.date) } ?? " ")
                                    .font(.custom("STSongti-SC-Light", size: 13, relativeTo: .caption))
                                    .foregroundStyle(index == selectedIndex ? UsPalette.coral : UsPalette.ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                            }
                            .frame(width: width / 7, height: 90)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .position(x: x, y: curveY + 39)
                        .accessibilityLabel("\(vm.weekdayFullLabel(day.date))，\(displayedShift.map { vm.shiftDetail($0, on: day.date) } ?? "未排班")")
                        .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])
                    }
                }
            }
            .frame(height: 126)
            .padding(.horizontal, 15)

            if days.indices.contains(selectedIndex) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(UsPalette.coral.opacity(0.72))
                        .frame(width: 5, height: 5)
                    Text(vm.weekdayFullLabel(days[selectedIndex].date))
                        .font(.custom("STSongti-SC-Light", size: 13, relativeTo: .caption))
                        .foregroundStyle(UsPalette.mutedInk)
                    Text(vm.shift(on: days[selectedIndex].date).map { vm.shiftDetail($0, on: days[selectedIndex].date) } ?? "未填写班表 · 轻点月历添加")
                        .font(.custom("STSongti-SC-Light", size: 14, relativeTo: .body))
                        .foregroundStyle(UsPalette.ink)
                    Spacer()
                }
                .padding(.horizontal, 31)
                .contentTransition(.numericText())
            }
        }
        .sensoryFeedback(.selection, trigger: selectedIndex)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("这周排班")
    }
}

private struct WeekGlowTrail: View {
    let width: CGFloat
    let selectedIndex: Int

    var body: some View {
        Canvas { context, _ in
            let glow = glowPath(width: width)
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 13))
                layer.stroke(glow, with: .color(UsPalette.gold.opacity(0.22)), lineWidth: 24)
            }
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 5))
                layer.stroke(glow, with: .color(UsPalette.blush.opacity(0.28)), lineWidth: 7)
            }

            let x = width * (CGFloat(selectedIndex) + 0.5) / 7
            let relative = (x - width / 2) / (width / 2)
            let y = 31 + 24 * relative * relative
            let halo = CGRect(x: x - 28, y: y - 18, width: 56, height: 56)
            context.fill(
                Path(ellipseIn: halo),
                with: .radialGradient(
                    Gradient(colors: [UsPalette.blush.opacity(0.18), .clear]),
                    center: CGPoint(x: x, y: y + 10),
                    startRadius: 2,
                    endRadius: 29
                )
            )
        }
        .allowsHitTesting(false)
    }

    private func glowPath(width: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: -10, y: 59))
            path.addCurve(
                to: CGPoint(x: width + 10, y: 59),
                control1: CGPoint(x: width * 0.27, y: 17),
                control2: CGPoint(x: width * 0.73, y: 17)
            )
        }
    }
}

private struct AccessibleWeekSchedule: View {
    let days: [ShiftDay]
    let vm: UsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("这周排班")
                .font(.headline)
                .foregroundStyle(UsPalette.ink)
            ForEach(Array(days.prefix(7).enumerated()), id: \.element.id) { index, day in
                HStack {
                    Text("第 \(index + 1) 天")
                    Spacer()
                    Text(vm.shift(on: day.date).map { vm.shiftDisplay($0, on: day.date) } ?? "未排")
                        .foregroundStyle(UsPalette.coral)
                }
                .font(.body)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ShiftMoonMarker: View {
    let hasShift: Bool
    let selected: Bool

    var body: some View {
        ZStack {
            if hasShift {
                Circle()
                    .fill(UsPalette.paper.opacity(0.90))
                    .shadow(color: UsPalette.gold.opacity(selected ? 0.30 : 0.16), radius: selected ? 11 : 7, y: 3)
                Image("WatercolorMoon")
                    .resizable()
                    .scaledToFit()
                    .padding(selected ? 3 : 5)
                    .opacity(selected ? 0.96 : 0.78)
            } else {
                Circle()
                    .fill(UsPalette.gold.opacity(selected ? 0.34 : 0.16))
                    .frame(width: selected ? 7 : 5, height: selected ? 7 : 5)
                    .shadow(color: UsPalette.gold.opacity(0.22), radius: 5)
            }
        }
        .overlay {
            if hasShift && selected {
                Circle().stroke(UsPalette.gold.opacity(0.68), lineWidth: 1)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 1), value: selected)
    }
}

private struct MonthCalendar: View {
    @EnvironmentObject private var theme: Theme
    @ObservedObject var vm: UsViewModel
    var journal = false
    @State private var editingDate: CalendarEditSelection?
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(alignment: .leading, spacing: journal ? 12 : 26) {
            ZStack(alignment: .topTrailing) {
                Image("WatercolorMoon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: journal ? 0 : 118, height: journal ? 0 : 118)
                    .opacity(journal ? 0 : 0.12)
                    .offset(x: 18, y: -28)
                    .accessibilityHidden(true)

                HStack(alignment: .center, spacing: 12) {
                    Button { changeMonth(by: -1) } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(UsPalette.mutedInk)
                    .accessibilityLabel("上个月")

                    VStack(alignment: .leading, spacing: 6) {
                        Text(vm.monthTitle(for: displayedMonth))
                            .font(.custom(journal ? "NotoSerifSC-ExtraLight" : "STSongti-SC-Light", size: journal ? 18 : 29, relativeTo: .title))
                            .tracking(2)
                            .foregroundStyle(UsPalette.ink)
                        if !journal { Text("月亮替我们记下每一天")
                            .font(.custom("STSongti-SC-Light", size: 12, relativeTo: .caption))
                            .tracking(1.1)
                            .foregroundStyle(UsPalette.mutedInk) }
                    }
                    Spacer()
                    Button { changeMonth(by: 1) } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(UsPalette.mutedInk)
                    .accessibilityLabel("下个月")
                }
            }

            LazyVGrid(columns: columns, spacing: journal ? 2 : 12) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(journal ? "周" + weekday : weekday)
                        .font(.custom(journal ? "NotoSerifSC-ExtraLight" : "STSongti-SC-Light", size: 12, relativeTo: .caption))
                        .foregroundStyle(UsPalette.mutedInk)
                }
                ForEach(Array(vm.monthCells(for: displayedMonth).enumerated()), id: \.offset) { _, date in
                    if let date {
                        Button {
                            if vm.shift(on: date) != nil { vm.setShift(nil, on: date) }
                            else { editingDate = CalendarEditSelection(date: date) }
                        } label: {
                            let shift = vm.shift(on: date)
                            CalendarDay(
                                date: date,
                                shift: shift,
                                shiftText: shift.map { vm.shiftDisplay($0, on: date) },
                                journal: journal
                            )
                        }
                        .buttonStyle(CalendarDayButtonStyle())
                        .accessibilityIdentifier(vm.calendarDayIdentifier(date))
                        .accessibilityLabel(vm.calendarDayAccessibilityLabel(date))
                        .accessibilityHint(vm.shift(on: date) == nil ? "轻点写班表" : "轻点直接取消当天排班")
                    } else {
                        Color.clear.frame(minHeight: 50)
                    }
                }
            }
            .id(vm.monthTitle(for: displayedMonth))
            .transition(.opacity)
            .gesture(
                DragGesture(minimumDistance: 28)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        changeMonth(by: value.translation.width < 0 ? 1 : -1)
                    }
            )

            if !vm.isCurrentMonth(displayedMonth) {
                Button("回到本月") {
                    withAnimation(.easeOut(duration: 0.18)) {
                        displayedMonth = vm.startOfMonth(for: .now)
                    }
                }
                .buttonStyle(.plain)
                .font(.custom("STSongti-SC-Light", size: 13, relativeTo: .caption))
                .foregroundStyle(UsPalette.coral)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("calendar-return-current-month")
            }

            if !journal || !vm.activeReminders.isEmpty {
            HStack(spacing: 14) {
                Rectangle()
                    .fill(UsPalette.hairline.opacity(0.52))
                    .frame(height: 0.7)
                Text("今日记事")
                    .font(.custom("STSongti-SC-Light", size: 13, relativeTo: .caption))
                    .tracking(1.4)
                    .foregroundStyle(UsPalette.mutedInk)
                    .fixedSize()
                Rectangle()
                    .fill(UsPalette.hairline.opacity(0.52))
                    .frame(height: 0.7)
            }

            VStack(spacing: 16) {
                ForEach(vm.activeReminders) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: item.category == .medicine ? "cross.case" : "calendar")
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(UsPalette.coral)
                            .frame(width: 18)
                        Text(item.text)
                            .font(.custom("STSongti-SC-Light", size: 14, relativeTo: .body))
                            .foregroundStyle(UsPalette.ink)
                        Spacer(minLength: 8)
                        Text(vm.reminderTime(item))
                            .font(.custom("STSongti-SC-Light", size: 11, relativeTo: .caption2))
                            .foregroundStyle(UsPalette.gold)
                    }
                }
            }
        }
        }
        .sensoryFeedback(.selection, trigger: editingDate)
        .sheet(item: $editingDate) { selection in
            ScheduleEditorSheet(
                model: vm, date: selection.date,
                currentShift: vm.shift(on: selection.date),
                currentNote: vm.shiftNote(on: selection.date),
                onSave: { shift, note in
                    vm.setShift(shift, note: note, on: selection.date)
                    editingDate = nil
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(UsPalette.paper)
        }
    }

    private func changeMonth(by offset: Int) {
        withAnimation(.easeOut(duration: 0.18)) {
            displayedMonth = vm.month(byAdding: offset, to: displayedMonth)
        }
    }
}

private struct CalendarEditSelection: Identifiable, Equatable {
    let date: Date
    var id: Date { date }
}

private struct CalendarDayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

private struct ScheduleEditorSheet: View {
    @ObservedObject var model: UsViewModel
    @Environment(\.dismiss) private var dismiss
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
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("写班表")
                        .font(.custom("STSongti-SC-Light", size: 24, relativeTo: .title2))
                        .tracking(1.8)
                        .foregroundStyle(UsPalette.ink)
                    Text(dateLabel)
                        .font(.custom("STSongti-SC-Light", size: 13, relativeTo: .caption))
                        .foregroundStyle(UsPalette.mutedInk)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .font(.custom("STSongti-SC-Light", size: 14, relativeTo: .body))
                    .foregroundStyle(UsPalette.mutedInk)
                    .buttonStyle(.plain)
            }

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
                            .foregroundStyle(UsPalette.gold)
                        TextField("写下班次，例如：培训、临时班", text: $note)
                            .textInputAutocapitalization(.never)
                            .submitLabel(.done)
                    }
                    .font(.custom("STSongti-SC-Light", size: 14, relativeTo: .body))
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(UsPalette.blush.opacity(0.09))
                    )
                } else {
                    Text("休息日无需填写，清除当天排班即可。")
                        .font(.custom("STSongti-SC-Light", size: 13, relativeTo: .caption))
                        .foregroundStyle(UsPalette.mutedInk)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                }
            }

            HStack(spacing: 12) {
                Button {
                    selectedShift = nil
                    note = ""
                } label: {
                    Text("清除排班")
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedShift == nil ? UsPalette.coral : UsPalette.mutedInk)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(UsPalette.blush.opacity(selectedShift == nil ? 0.16 : 0.07))
                )

                Button {
                    onSave(selectedShift, selectedShift == .other ? normalizedNote : nil)
                } label: {
                    Text("保存班表")
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.plain)
                .foregroundStyle(PageColors.calendarText)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(UsPalette.coral.opacity(0.88))
                )
            }
            .font(.custom("STSongti-SC-Light", size: 15, relativeTo: .body))
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .sensoryFeedback(.selection, trigger: selectedShift)
        .accessibilityElement(children: .contain)
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
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
                    .font(.custom("STSongti-SC-Light", size: 14, relativeTo: .body))
            }
            .foregroundStyle(selected ? UsPalette.coral : UsPalette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(selected ? UsPalette.blush.opacity(0.18) : UsPalette.paper)
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(selected ? UsPalette.gold.opacity(0.72) : UsPalette.hairline.opacity(0.28), lineWidth: selected ? 1.2 : 0.7)
                    }
            )
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

private struct CalendarDay: View {
    let date: Date
    let shift: ShiftDay.Kind?
    let shiftText: String?
    var journal = false

    var body: some View {
        let isToday = Calendar.current.isDateInToday(date)
        ZStack {
            if (!journal && shift != nil) || isToday {
                Circle()
                    .fill(dayDisc(isToday: isToday))
                    .frame(width: isToday ? 34 : 31, height: isToday ? 34 : 31)
            }

            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.custom("Didot", size: 15, relativeTo: .body))
                    .foregroundStyle(isToday ? PageColors.calendarText : UsPalette.ink)
                Text(shiftText ?? " ")
                    .font(.custom(journal ? "NotoSerifSC-ExtraLight" : "STSongti-SC-Light", size: journal ? 11 : 9, relativeTo: .caption2))
                    .foregroundStyle(isToday ? PageColors.calendarText.opacity(0.90) : markerColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: 42)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 50)
    }

    private func dayDisc(isToday: Bool) -> Color {
        if isToday { return UsPalette.coral.opacity(0.84) }
        guard let shift else { return .clear }
        switch shift {
        case .normal: return UsPalette.blush.opacity(0.11)
        case .early: return UsPalette.gold.opacity(0.11)
        case .deputy: return UsPalette.sage.opacity(0.10)
        default: return UsPalette.blush.opacity(0.13)
        }
    }

    private var markerColor: Color {
        guard let shift else { return .clear }
        switch shift {
        case .normal: return UsPalette.coral
        case .early: return UsPalette.gold
        case .deputy: return UsPalette.sage
        default: return UsPalette.coral
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
            Anniversary(id: "ke", title: "柯的生日", date: fixedDay(2000, 10, 26)),
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
            if !resolved.isEmpty {
                anniversaries = resolved
            }
        } catch {
            failures.append("纪念日")
        }
        reminderLoadError = failures.isEmpty ? nil : failures.joined(separator: "、") + "暂时没有接上，请下拉重试。"
    }

    static func anniversaries(from rows: [RemoteAnniversary]) -> [Anniversary] {
        let preferredOrder = ["表白的日子", "在一起的日子", "佳佳的生日", "柯的生日"]
        let byName = Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0) })
        return preferredOrder.compactMap { name in
            guard let row = byName[name], let date = CompanionDate.parse(row.date) else { return nil }
            return Anniversary(
                id: String(row.id),
                title: row.name,
                date: date,
                isYearly: name.contains("生日")
            )
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

#Preview {
    UsView().environmentObject(Theme.shared)
}
