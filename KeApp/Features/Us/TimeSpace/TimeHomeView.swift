import SwiftUI

// 接续独立时间样板的月球构图，内容来自当前聊天线路。
struct TimeHomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var scrollPosition = TimeScrollPosition()
    @State private var calendarVisible = false
    @State private var month = Date()
    @State private var selected = CompanionDate.calendar.startOfDay(for: Date())
    @State private var filter: TimeEventKind?
    @State private var showPrivate = false
    @EnvironmentObject private var theme: Theme
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var data: TimeDataStore
    @State private var screen = 0
    @State private var selectedAnniversary = 0
    @State private var showEditor = false
    @State private var showAnniversaries = false
    @State private var deleteEntry: TimeEntry?
    @State private var actionError: String?
    let line: ChatLine
    var active = true

    init(line: ChatLine = .main, active: Bool = true) {
        self.line = line; self.active = active
        _data = StateObject(wrappedValue: TimeDataStore(api: APIClient(baseURL: line.apiBaseURL)))
    }
    private let model = TimeCalendarModel()
    private let ink = Color(red: 0.25, green: 0.24, blue: 0.25)
    private let secondary = Color(red: 0.43, green: 0.40, blue: 0.38)
    private let gold = Color(red: 0.49, green: 0.37, blue: 0.20)

    private var entries: [TimeEntry] { data.entries }
    private var dayEntries: [TimeEntry] { model.entries(on: selected, in: entries, kind: filter) }

    var body: some View {
        GeometryReader { viewport in
            let height = viewport.size.height
            ZStack(alignment: .top) {
                Color(red: 0.985, green: 0.980, blue: 0.969).ignoresSafeArea()
                TimeScrollingBackdrop(position: scrollPosition, height: height,
                                      reduceMotion: reduceMotion,
                                      active: active && scenePhase == .active,
                                      showSatellite: screen == 0,
                                      topInset: viewport.safeAreaInsets.top,
                                      bottomInset: viewport.safeAreaInsets.bottom)
                    .frame(height: height + viewport.safeAreaInsets.top + viewport.safeAreaInsets.bottom)
                    .offset(y: -viewport.safeAreaInsets.top)
                    .allowsHitTesting(false)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            TabView(selection: $screen) {
                                reminderPage(height: height, proxy: proxy).tag(0)
                                anniversaryPage(height: height, proxy: proxy).tag(1)
                            }
                            .tabViewStyle(.page(indexDisplayMode: .never))
                            .frame(height: typeSize.isAccessibilitySize ? height * 1.35 : height * 0.98)
                            .id("reminders")
                            calendarPage
                                .padding(.top, 80)
                                .padding(.bottom, 56)
                                .frame(minHeight: height, alignment: .top)
                                .id("calendar")
                        }
                        .background {
                            if #unavailable(iOS 18.0) {
                                TimeScrollProbe(offset: Binding(get: { scrollPosition.offset }, set: {
                                    trackScroll($0, height: height)
                                }))
                            }
                        }
                    }
                    .refreshable { await data.refresh() }
                    .coordinateSpace(name: "time-scroll")
                    .scrollIndicators(.hidden)
                    .modifier(TimeScrollTracking { trackScroll($0, height: height) })
                    .accessibilityIdentifier("time-scroll")
                    .mask(alignment: .top) {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 44)
                            Rectangle()
                        }
                    }
                    .overlay(alignment: .top) {
                        HStack {
                            Text("我们的时间").font(song(19)).tracking(1)
                            Spacer()
                            if calendarVisible {
                                Button("回到上面") {
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.55)) {
                                        proxy.scrollTo("reminders", anchor: .top)
                                    }
                                }.font(song(14)).frame(minHeight: 44)
                            } else {
                                Button("提醒") { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { screen = 0 } }
                                    .foregroundStyle(screen == 0 ? gold : secondary)
                                    .accessibilityIdentifier("time-reminder-tab")
                                Button("纪念日") { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { screen = 1 } }
                                    .foregroundStyle(screen == 1 ? gold : secondary)
                                    .accessibilityIdentifier("time-anniversary-tab")
                            }
                            Button { if calendarVisible { showEditor = true } else { showAnniversaries = true } } label: {
                                Image(systemName: "plus").font(.system(size: 17, weight: .light)).frame(width: 44, height: 44)
                            }.accessibilityLabel(calendarVisible ? "添加日期记录" : "管理纪念日")
                        }
                        .font(song(15))
                        .padding(.leading, 28).padding(.trailing, 12)
                    }
                }
            }
            .frame(width: viewport.size.width, height: height, alignment: .top)
            .foregroundStyle(ink)
            .tint(gold)
            .task { await data.refresh() }
            .sheet(isPresented: $showAnniversaries, onDismiss: { Task { await data.refresh() } }) {
                CompanionPages(page: .anniversaries, line: line).environmentObject(theme)
            }
            .sheet(isPresented: $showEditor, onDismiss: { Task { await data.refresh(); if showPrivate { await data.loadPrivate(date: format(selected, "yyyy-MM-dd")) } } }) {
                TimeRecordEditor(line: line, date: selected)
            }
            .onChange(of: showPrivate) { _, expanded in
                if expanded { Task { await data.loadPrivate(date: format(selected, "yyyy-MM-dd")) } }
                else { data.hidePrivate() }
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { showPrivate = false; data.hidePrivate() } }
            .onChange(of: active) { _, visible in if !visible { showPrivate = false; data.hidePrivate() } }
            .alert("删除这条记录？", isPresented: Binding(get: { deleteEntry != nil }, set: { if !$0 { deleteEntry = nil } })) {
                Button("取消", role: .cancel) { deleteEntry = nil }
                Button("删除", role: .destructive) {
                    guard let entry = deleteEntry else { return }
                    deleteEntry = nil
                    Task {
                        do { try await data.remove(entry); if showPrivate { await data.loadPrivate(date: format(selected, "yyyy-MM-dd")) } }
                        catch { actionError = "记录没有删除成功，请重试。" }
                    }
                }
            }
            .onChange(of: selected) { _, _ in showPrivate = false }
        }
    }

    private func reminderPage(height: CGFloat, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                VStack(alignment: .leading, spacing: 14) {
                    Text(format(timeline.date, "HH:mm"))
                        .font(.custom("Didot", size: 64, relativeTo: .largeTitle))
                        .monospacedDigit().tracking(-1.5)
                    Text(format(timeline.date, "M月d日 · EEEE"))
                        .font(song(16)).foregroundStyle(secondary)
                }
            }.padding(.top, 104)

            Text("柯帮你记着").font(song(21)).foregroundStyle(gold)
                .padding(.top, 52)
            if data.loading && entries.isEmpty { ProgressView().padding(.top, 24) }
            if let error = data.error {
                Text(error).font(song(14)).foregroundStyle(secondary).padding(.top, 16)
                Button("重试") { Task { await data.refresh() } }.font(song(14)).frame(minHeight: 44)
            }
            if let shift = data.shifts.first(where: { model.calendar.isDateInToday($0.date) }) {
                Text("今天 · " + shift.title).font(song(18)).padding(.top, 24)
            }
            if let reminder = data.pending.first {
                Text("待办提醒 · " + format(reminder.date, "M月d日")).font(song(14)).foregroundStyle(secondary).padding(.top, 30)
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(format(reminder.date, "HH:mm")).font(.custom("Didot", size: 31, relativeTo: .title))
                    Text(reminder.title).font(song(20)).lineLimit(3)
                }.padding(.top, 12)
            } else if !data.loading {
                Text("暂时没有待办").font(song(20)).padding(.top, 28)
                Text("有要记住的事，可以在聊天里告诉柯。")
                    .font(song(15)).foregroundStyle(secondary).padding(.top, 12)
            }
            Button("查看安排 ›") {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.55)) { proxy.scrollTo("calendar", anchor: .top) }
            }.font(song(16)).frame(minHeight: 44).padding(.top, 28)
            Spacer(minLength: 24)
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.55)) { proxy.scrollTo("calendar", anchor: .top) }
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .light)).padding(.top, 5)
                }
                .frame(maxWidth: .infinity, minHeight: 110)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("展开日历")
            .accessibilityIdentifier("open-calendar")
            .padding(.bottom, 22)
        }
        .padding(.horizontal, 30)
        .frame(minHeight: typeSize.isAccessibilitySize ? height * 1.25 : height * 0.96, alignment: .top)
    }

    private func anniversaryPage(height: CGFloat, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("把重要的日子留在这里").font(song(16)).foregroundStyle(secondary).padding(.top, 76)
            MoonOrbitSelector(events: data.anniversaries, selectedIndex: $selectedAnniversary, timeStyle: true,
                              onSwipeToReminders: { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { screen = 0 } })
                .frame(height: 325).padding(.trailing, -28).clipped()
            if data.anniversaries.indices.contains(selectedAnniversary) {
                let anniversary = data.anniversaries[selectedAnniversary]
                let today = model.calendar.startOfDay(for: .now)
                let target = model.calendar.startOfDay(for: anniversary.date)
                let days = model.calendar.dateComponents([.day], from: today, to: target).day ?? 0
                Text(anniversary.title).font(song(22))
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(abs(days))").font(.custom("Didot", size: 52, relativeTo: .largeTitle))
                    Text(days == 0 ? "就是今天" : (days < 0 ? "天前" : "天后")).font(song(17))
                }
                Text(format(anniversary.date, "yyyy年M月d日")).font(song(14)).foregroundStyle(secondary)
            } else if !data.loading {
                Text("还没有纪念日").font(song(22))
                Button("添加纪念日") { showAnniversaries = true }.font(song(16)).frame(minHeight: 44)
            }
            Spacer(minLength: 10)
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.55)) { proxy.scrollTo("calendar", anchor: .top) }
            } label: { Image(systemName: "chevron.down").frame(maxWidth: .infinity, minHeight: 66) }
                .accessibilityLabel("展开日历").padding(.bottom, 22)
        }.padding(.horizontal, 28).frame(height: height * 0.96, alignment: .top)
    }

    private var calendarPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(format(month, "MMMM")).font(song(32)).accessibilityIdentifier("calendar-month")
                    Text(format(month, "yyyy")).font(.custom("Didot", size: 19, relativeTo: .body))
                }
                Spacer()
                Button { changeMonth(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }.accessibilityLabel("上个月")
                Button { changeMonth(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }.accessibilityLabel("下个月")
            }
            .foregroundStyle(ink)
            calendarGrid
            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    filterButton(nil)
                    ForEach(TimeEventKind.allCases) { filterButton($0) }
                }
            }.scrollIndicators(.hidden)
            HStack {
                Text(format(selected, "M月d日 · EEEE")).font(song(21))
                    .accessibilityIdentifier("selected-date")
                Spacer()
                Button("今天") {
                    selected = CompanionDate.calendar.startOfDay(for: .now)
                    month = selected
                }.font(song(14)).frame(minWidth: 44, minHeight: 44)
            }
            dayDetail
            if let error = data.error { Text(error).font(song(13)).foregroundStyle(secondary) }
            if let actionError { Text(actionError).font(song(13)) }
            Button("添加日期记录") { showEditor = true }.font(song(15)).frame(minHeight: 44)
        }
        .padding(.horizontal, 26)
    }

    private var calendarGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { value in
                    Text(value).font(song(14)).foregroundStyle(secondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                ForEach(Array(model.monthDays(month).enumerated()), id: \.offset) { _, date in
                    if let date {
                        let isSelected = model.calendar.isDate(date, inSameDayAs: selected)
                        let categories = Set(model.entries(on: date, in: entries, kind: filter).map(\.kind))
                        Button { selected = date } label: {
                            VStack(spacing: 4) {
                                Text("\(model.calendar.component(.day, from: date))")
                                    .font(.custom("Didot", size: 20, relativeTo: .body))
                                    .frame(width: 34, height: 34)
                                    .background { if isSelected { Circle().stroke(gold.opacity(0.8), lineWidth: 1) } }
                                HStack(spacing: 3) {
                                    ForEach(TimeEventKind.allCases.filter { categories.contains($0) }) { kind in
                                        Circle().fill(kindColor(kind)).frame(width: 3, height: 3)
                                    }
                                }.frame(height: 4)
                            }.frame(maxWidth: .infinity, minHeight: 46)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(format(date, "yyyy年M月d日"))
                        .accessibilityValue(isSelected ? "已选中" : "")
                        .accessibilityIdentifier("day-\(model.calendar.component(.day, from: date))")
                    } else {
                        Color.clear.frame(height: 46).accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private var dayDetail: some View {
        VStack(alignment: .leading, spacing: 22) {
            if dayEntries.isEmpty {
                Text("这一天没有安排").font(song(17)).foregroundStyle(secondary)
                    .accessibilityIdentifier("empty-day")
            }
            ForEach(dayEntries.filter { !$0.kind.isPrivate }) { row($0) }
            DisclosureGroup(isExpanded: $showPrivate) {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = data.privateError {
                        Text(error).font(song(14))
                        Button("重试") { Task { await data.loadPrivate(date: format(selected, "yyyy-MM-dd")) } }
                    }
                    ForEach(dayEntries.filter { $0.kind.isPrivate }) { row($0) }
                    if dayEntries.filter({ $0.kind.isPrivate }).isEmpty && data.privateError == nil {
                        Text("这一天没有私密记录").font(song(14))
                    }
                }.padding(.top, 18)
            } label: {
                Label("私密记录 · 点开查看", systemImage: "lock")
                    .font(song(16)).foregroundStyle(secondary).frame(minHeight: 44)
            }.accessibilityIdentifier("private-records")
        }
    }

    private func row(_ entry: TimeEntry) -> some View {
        HStack(alignment: .top, spacing: 24) {
            Text(entry.time).font(.custom("Didot", size: 18, relativeTo: .body)).frame(width: 118, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.title).font(song(17))
                Text(entry.kind.rawValue).font(song(12)).foregroundStyle(secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .contextMenu {
            if entry.kind != .reminder {
                Button("删除", role: .destructive) { deleteEntry = entry }
            }
        }
    }

    private func filterButton(_ kind: TimeEventKind?) -> some View {
        Button { filter = kind; showPrivate = false } label: {
            HStack(spacing: 6) {
                Circle().fill(kind.map(kindColor) ?? secondary).frame(width: 5, height: 5)
                Text(kind?.rawValue ?? "全部").font(song(14))
            }
            .foregroundStyle(filter == kind ? ink : secondary)
            .frame(minWidth: 44, minHeight: 44)
            .overlay(alignment: .bottom) { if filter == kind { Rectangle().fill(gold).frame(height: 1) } }
        }.buttonStyle(.plain)
            .accessibilityAddTraits(filter == kind ? .isSelected : [])
    }

    private func changeMonth(_ offset: Int) {
        month = model.movingMonth(month, by: offset)
        selected = model.monthStart(month)
        showPrivate = false
    }

    private func kindColor(_ kind: TimeEventKind) -> Color {
        switch kind {
        case .reminder: return gold
        case .shift: return Color(red: 0.50, green: 0.43, blue: 0.31)
        case .period: return Color(red: 0.64, green: 0.32, blue: 0.43)
        case .intimate: return Color(red: 0.47, green: 0.42, blue: 0.62)
        }
    }

    private func song(_ size: CGFloat) -> Font { .custom("NotoSerifSC-Regular", size: size, relativeTo: .body).weight(.light) }
    private func trackScroll(_ offset: CGFloat, height: CGFloat) {
        scrollPosition.update(offset, limit: height * 0.9)
        let visible = offset > height * 0.9 * 0.55
        if calendarVisible != visible { calendarVisible = visible }
    }
    private func format(_ date: Date, _ template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = model.calendar.timeZone
        formatter.dateFormat = template
        return formatter.string(from: date)
    }
}

private struct TimeScrollTracking: ViewModifier {
    var onScroll: (CGFloat) -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, value in onScroll(max(0, value)) }
        } else {
            content
        }
    }
}

// 高频位置只通知背景。正文、日期格式化与月历筛选不参与逐帧重算。
final class TimeScrollPosition: ObservableObject {
    @Published private(set) var offset: CGFloat = 0
    func update(_ value: CGFloat, limit: CGFloat) {
        let next = min(max(0, value), max(0, limit))
        if offset != next { offset = next }
    }
}

private struct TimeScrollingBackdrop: View {
    @ObservedObject var position: TimeScrollPosition
    let height: CGFloat
    let reduceMotion: Bool
    let active: Bool
    let showSatellite: Bool
    let topInset: CGFloat
    let bottomInset: CGFloat
    var body: some View {
        let progress = min(1, max(0, position.offset / max(1, height * 0.9)))
        TimeMoonScene(progress: reduceMotion ? (progress > 0.6 ? 1 : 0) : progress,
                      reduceMotion: reduceMotion, active: active, showSatellite: showSatellite,
                      topInset: topInset, bottomInset: bottomInset)
    }
}
