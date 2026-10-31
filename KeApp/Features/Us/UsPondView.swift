import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// 140：「我们」页换成清冷水彩（Design/UsWatercolorReview，她 10-29 定的）：
// 页首团子小鱼依偎无叶山茶、Didot 细数字；日期下面就是班次，不再单列班次卡片；月历在首页原地展开收起；
// 荷包、食单、药盒、纸条两列纯文字。锦鲤池拿掉了（换之前的样子在 backup/us-pond-before-watercolor-1029 分支）。
// 数据照旧是真的：纪念日、排班、月经、亲密、寄语都沿用 UsViewModel / PeriodStore / LoveLogStore / 小本子；
// 点一天还是打开原来那张当天面板（排班、月经来了走了、亲密几次）。

struct UsPondView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    let line: ChatLine
    /// 137：几样数据按线路各留一份（UsPondStores），切到别的页再回来不重建，先画上次的
    private let stores: UsPondStores
    @ObservedObject private var vm: UsViewModel
    @ObservedObject private var periods: PeriodStore
    @ObservedObject private var notes: StickyNotesStore
    @ObservedObject private var book: NotebookStore
    /// 133：亲密记录（132 错加在旧的 UsView 上了，她这页看不到）
    @ObservedObject private var love: LoveLogStore
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    /// 140：周历显示哪一天所在的那一周（默认今天；点过哪天、月历里翻过去点了哪天，收起后就回到那一周）
    @State private var focus = Calendar.current.startOfDay(for: .now)
    @State private var expanded = false
    @State private var floating = false
    @State private var editDay: PondDay?
    @State private var open: PondEntry?
    @State private var choosingAnniversary = false
    @State private var managingDates = false
    @AppStorage("us.hero.anniversary") private var heroID = "together"
    /// 126：底栏浮在页面上，滚到最底时让出它那一截
    @Environment(\.floatingDockInset) private var dockInset
    private var paper: Color { Cool.paper }

    init(line: ChatLine) {
        self.line = line
        let stores = UsPondStores.shared(line)
        self.stores = stores
        _vm = ObservedObject(wrappedValue: stores.vm)
        _periods = ObservedObject(wrappedValue: stores.periods)
        _notes = ObservedObject(wrappedValue: stores.notes)
        _book = ObservedObject(wrappedValue: stores.book)
        _love = ObservedObject(wrappedValue: stores.love)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 10-31 她：最上面不要标题。右上那枚月牙是 RootTabView 画的，页面从它下面起
                heroBlock.padding(.top, 48)
                Rectangle().fill(Cool.line).frame(width: 28, height: 1)
                    .frame(maxWidth: .infinity).padding(.top, 18)
                    .accessibilityHidden(true)
                calendarHeader.padding(.top, 26)
                if expanded {
                    monthGrid.transition(.opacity)
                } else {
                    weekStrip.transition(.opacity)
                }
                tools.padding(.top, 34)
                quote.padding(.top, 40)
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28 + dockInset)
        }
        .scrollIndicators(.hidden)
        .background(paper.ignoresSafeArea())
        .foregroundStyle(Cool.ink)
        // 137：切过来照样刷新；回前台 5 分钟内拉过就不再整页重拉（没告诉上柯的「走了」还是会再送）
        .task { await stores.refresh(month: month) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await stores.refresh(month: month, onlyIfStale: true) } } }
        .onChange(of: month) { _, m in Task { await love.load(m) } }
        .sheet(item: $editDay, onDismiss: { periods.clearStatus() }) { day in daySheet(day.date) }
        .sheet(isPresented: $choosingAnniversary) { anniversarySheet }
        .sheet(isPresented: $managingDates, onDismiss: { Task { await vm.loadReminders() } }) {
            CompanionPages(page: .anniversaries, line: line).environmentObject(Theme.shared)
        }
        .fullScreenCover(item: $open) { entry in page(entry).swipeBackToClose { open = nil; Task { await book.load(); await notes.load() } } }
    }

    // MARK: 页首：在一起的日子 + 团子小鱼

    private var verseEn: String { book.snapshot?.verse?.en ?? stores.savedVerse?.en ?? "With you, even ordinary days shine." }
    private var verseZh: String { book.snapshot?.verse?.zh ?? stores.savedVerse?.zh ?? "和你一起，平常的日子也有光。" }

    private func eyebrow(_ a: Anniversary) -> String { a.id == "together" ? "在一起的日子" : Self.shortName(a) }

    private var heroBlock: some View {
        // 插画浮在右上，字照常从左排到右：插画在天数旁边，下面两行字从它底下过（不再跟插画抢同一行的宽度）
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                if let a = hero {
                    let n = numbers(a)
                    // 106：点名字换成别的纪念日（还有几天、今天是……）
                    Button { choosingAnniversary = true } label: {
                        Text(eyebrow(a)).font(Cool.tiny()).tracking(2.2)
                            .foregroundStyle(Cool.mauve)
                            .frame(minHeight: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("换一个纪念日，现在是\(Self.shortName(a))")
                    .accessibilityIdentifier("us-anniversary-pick")
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(n.number).font(Cool.didot(n.number == "今天" ? 34 : 46, .largeTitle))
                            .foregroundStyle(Cool.number).lineLimit(1).minimumScaleFactor(0.6)
                        Text(n.unit).font(Cool.song(12, .footnote)).foregroundStyle(Cool.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                // 原型那两行：一句中文、一行斜体英文（她：留白克制，日期那行挪到纪念日面板里看）
                Text(verseZh).font(Cool.song(12, .footnote)).tracking(0.6).lineSpacing(5).foregroundStyle(Cool.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                Text(verseEn.lowercased()).font(Cool.didotItalic(12, .footnote)).tracking(0.4).lineSpacing(3).foregroundStyle(Cool.faint)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.top, 9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image("UsFishCamellia").resizable().scaledToFit()
                .containerRelativeFrame(.horizontal) { w, _ in min(190, w * 0.44) }
                .offset(x: 16, y: floating ? -14 : -9)
                .opacity(0.92)
                .accessibilityHidden(true)
        }
        // 小鱼轻轻浮着；系统开了「减弱动态效果」就不动
        .onAppear {
            guard !reduceMotion, !floating else { return }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) { floating = true }
        }
    }

    // MARK: 这一周 / 月历（原地展开）

    private static var mondayCalendar: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    private static let monthNames = ["一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月"]
    private static let weekdayNames = ["一", "二", "三", "四", "五", "六", "日"]

    private var weekDays: [Date] {
        let c = Self.mondayCalendar
        let start = c.dateInterval(of: .weekOfYear, for: focus)?.start ?? focus
        return (0..<7).compactMap { c.date(byAdding: .day, value: $0, to: start) }
    }
    private var focusIsThisWeek: Bool { Self.mondayCalendar.isDate(focus, equalTo: .now, toGranularity: .weekOfYear) }
    private var weekTitle: String {
        let m = Calendar.current.component(.month, from: focus)
        return Self.monthNames[m - 1] + (focusIsThisWeek ? " · 这一周" : " · 那一周")
    }

    private func toggleMonth() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            if !expanded { month = vm.startOfMonth(for: focus) }
            expanded.toggle()
        }
    }

    private var calendarHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(expanded ? "日历" : weekTitle).font(Cool.song(13, .subheadline)).tracking(2.2).foregroundStyle(Cool.ink)
                .accessibilityAddTraits(.isHeader)
            if expanded, love.monthCount(month) > 0 {
                Text("亲密 \(love.monthCount(month)) 次").font(Cool.song(11, .caption)).foregroundStyle(Cool.mauve)
            }
            Spacer(minLength: 4)
            if !expanded, !focusIsThisWeek {
                Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { focus = Calendar.current.startOfDay(for: .now) } } label: {
                    Text("回到今天").font(Cool.tiny(.caption)).foregroundStyle(Cool.secondary).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button(action: toggleMonth) {
                HStack(spacing: 4) {
                    Text(expanded ? "收起月历" : "展开月历")
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .light))
                }
                .font(Cool.tiny(.caption)).tracking(1).foregroundStyle(Cool.secondary)
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "收起月历" : "展开月历")
            .accessibilityIdentifier("us-month-toggle")
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekDays.enumerated()), id: \.offset) { i, date in
                VStack(spacing: 4) {
                    Text(Self.weekdayNames[i]).font(Cool.tiny()).foregroundStyle(Cool.faint)
                        .accessibilityHidden(true)
                    dayCell(date)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, -6)
    }

    private var monthGrid: some View {
        VStack(spacing: 0) {
            HStack {
                // 137：点的范围放到 44×44，箭头本身不变
                Button { month = vm.month(byAdding: -1, to: month) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .ultraLight)).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("上个月")
                Spacer()
                Text(Self.yearMonth(month)).font(Cool.didot(15, .subheadline)).foregroundStyle(Cool.secondary)
                    .accessibilityLabel(vm.monthTitle(for: month))
                Spacer()
                Button { month = vm.month(byAdding: 1, to: month) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .ultraLight)).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("下个月")
            }
            .foregroundStyle(Cool.secondary)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Self.weekdayNames, id: \.self) {
                    Text($0).font(Cool.tiny()).foregroundStyle(Cool.faint).frame(height: 24).accessibilityHidden(true)
                }
                ForEach(Array(vm.monthCells(for: month).enumerated()), id: \.offset) { _, date in
                    if let date { dayCell(date) } else { Color.clear.frame(height: 52) }
                }
            }
            .padding(.horizontal, -6)
            if !vm.isCurrentMonth(month) {
                Button("回到本月") { month = vm.startOfMonth(for: .now) }
                    .font(Cool.song(12, .caption)).foregroundStyle(Cool.secondary).frame(minHeight: 44)
            }
        }
        .padding(.top, 2)
    }

    private static func yearMonth(_ date: Date) -> String {
        let c = Calendar.current
        return "\(c.component(.year, from: date)) / " + String(format: "%02d", c.component(.month, from: date))
    }

    /// 一天：Didot 数字，下面就是班次；今天淡蓝圆底，月经淡粉圆底，纪念日 ☾、亲密小心挂在右上
    private func dayCell(_ date: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        let period = isPeriod(date)
        let times = love.count(on: date)
        let anniversary = isAnniversary(date)
        let shift = vm.shift(on: date).map { vm.shiftDisplay($0, on: date) }
        // 字调到很大时，班次只写第一个字（白 / 夜 / 休），七格不挤爆
        let shown = shift.map { typeSize >= .accessibility1 ? String($0.prefix(1)) : $0 }
        return Button {
            focus = Calendar.current.startOfDay(for: date)
            editDay = PondDay(date: date)
        } label: {
            VStack(spacing: 3) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(Cool.didot(17, .body)).monospacedDigit()
                    .foregroundStyle(isToday ? Cool.ink : Cool.number)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(period ? Cool.period : (isToday ? Cool.today : .clear)))
                    .overlay(Circle().stroke(isToday && period ? Cool.number.opacity(0.45) : .clear, lineWidth: 0.8))
                    .overlay(alignment: .topTrailing) {
                        if anniversary || times > 0 {
                            HStack(spacing: 1) {
                                if anniversary { Text("☾").font(.system(size: 9)) }
                                if times > 0 { Image(systemName: "heart.fill").font(.system(size: 6)) }
                            }
                            .foregroundStyle(Cool.heart).offset(x: 9, y: -2)
                        }
                    }
                Text(shown ?? " ").font(Cool.tiny()).tracking(0.5).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(Cool.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(vm.calendarDayAccessibilityLabel(date) + (period ? "，月经" : "") + (anniversary ? "，纪念日" : "")
                            + (times > 0 ? "，亲密 \(times) 次" : ""))
        .accessibilityHint("打开这一天：排班、月经、亲密")
        .accessibilityIdentifier(vm.calendarDayIdentifier(date))
        .contextMenu {
            Text(times > 0 ? "这天亲密 \(times) 次" : "这天还没有亲密记录")
            Button { Task { await love.setCount(times + 1, on: date) } } label: { Label("加一次", systemImage: "plus") }
            if times > 0 { Button { Task { await love.setCount(times - 1, on: date) } } label: { Label("减一次", systemImage: "minus") } }
        }
    }

    // MARK: 四个入口（两列纯文字）

    private var tools: some View {
        let rows: [[PondEntry]] = [[.purse, .menu], [.meds, .notes]]
        return VStack(spacing: 0) {
            Rectangle().fill(Cool.line).frame(height: 1)
            ForEach(rows, id: \.first) { row in
                HStack(spacing: 0) {
                    toolButton(row[0])
                    Rectangle().fill(Cool.line).frame(width: 1, height: 18).accessibilityHidden(true)
                    toolButton(row[1])
                }
                Rectangle().fill(Cool.line).frame(height: 1)
            }
        }
    }

    /// 药盒有没吃的那顿才在下面写一小行（「晚上的还没吃」），别的入口只有名字
    private var medsPending: String? {
        guard let s = book.snapshot, !s.meds.rx.isEmpty else { return nil }
        let left = (s.meds.order ?? []).filter { !(s.meds.today[$0]?.taken ?? false) }
        return left.first.map { "\($0)的还没吃" }
    }

    private func toolButton(_ e: PondEntry) -> some View {
        let status = e == .meds ? medsPending : nil
        return Button { open = e } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(e.title).font(Cool.song(14.5, .body)).tracking(5).foregroundStyle(Cool.ink)
                    if let status { Text(status).font(Cool.tiny()).foregroundStyle(Cool.mauve) }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .ultraLight)).foregroundStyle(Cool.faint)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(e.title + (status.map { "，" + $0 } ?? ""))
        .accessibilityIdentifier("us-entry-\(e.rawValue)")
    }

    // MARK: 柯留下的话（小本子里的寄语）

    /// 柯最近贴的一张纸条（原型里「柯留下的话」）；他还没贴过就不放
    private var kesNote: String? {
        notes.notes.filter { $0.author == .ai }.max { $0.created_at < $1.created_at }?
            .content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder private var quote: some View {
        if let note = kesNote, !note.isEmpty {
            Button { open = .notes } label: {
                VStack(alignment: .leading, spacing: 10) {
                    Text("“\(note)”").font(Cool.song(13, .footnote)).tracking(0.8).lineSpacing(5)
                        .foregroundStyle(Cool.secondary).lineLimit(3).multilineTextAlignment(.leading)
                    Text("柯留下的话").font(Cool.tiny()).tracking(2).foregroundStyle(Cool.faint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("打开纸条")
        }
    }

    // MARK: 纪念日

    // 106：她选了方案 B——寄语收成一行小字，纪念日放大当主角，点名字换成别的纪念日。
    private var hero: Anniversary? { vm.anniversaries.first { $0.id == heroID } ?? vm.anniversaries.first }

    static func shortName(_ a: Anniversary) -> String {
        ["together": "在一起", "confession": "表白日", "mine": "我的生日", "ke": "柯的生日"][a.id] ?? a.title
    }
    private func numbers(_ a: Anniversary) -> (number: String, unit: String, line: String, past: Bool) {
        let c = Calendar.current, comps = c.dateComponents([.year, .month, .day], from: a.date)
        if a.isYearly {
            let left = vm.daysUntil(a)
            let line = "每年 \(comps.month ?? 0) 月 \(comps.day ?? 0) 日"
            return left == 0 ? ("今天", "", "今天是" + Self.shortName(a), false) : ("\(left)", "天后", line, false)
        }
        // 137：「管理日期」里加的、还没到的日子（比如「下次见面」）往后数
        if a.date > Date.now {
            return ("\(vm.daysAhead(to: a.date))", "天后", "\(comps.year ?? 0) 年 \(comps.month ?? 0) 月 \(comps.day ?? 0) 日", false)
        }
        // 那天就算第一天，和柯那边说的「今天第 113 天」一样
        return ("\(vm.daysTogether(since: a.date) + 1)", "天", "从 \(comps.year ?? 0) 年 \(comps.month ?? 0) 月 \(comps.day ?? 0) 日那天起", true)
    }

    private var anniversarySheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(vm.anniversaries) { a in
                        let n = numbers(a)
                        Button { heroID = a.id; choosingAnniversary = false } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(Self.shortName(a)).font(Ink.song(17))
                                    Text(n.line).font(.system(size: 12)).foregroundStyle(Ink.secondary)
                                }
                                Spacer()
                                Text(n.number == "今天" ? "就是今天" : (n.past ? "已过 " : "还有 ") + n.number + " 天")
                                    .font(Ink.latin(17)).monospacedDigit()
                                Image(systemName: a.id == heroID ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(a.id == heroID ? Ink.accent : Ink.line).font(.system(size: 20))
                            }
                            .frame(minHeight: 52).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("在一起、表白日往前数；生日每年往后数。").font(.system(size: 12))
                }
            }
            .navigationTitle("我们的纪念日").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关上") { choosingAnniversary = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("管理日期") { choosingAnniversary = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { managingDates = true } }
                }
            }
        }
        .presentationDetents([.medium])
        .tint(Ink.accent)
        .foregroundStyle(Ink.primary)
    }

    // MARK: 当天面板

    private func isPeriod(_ date: Date) -> Bool {
        let key = HomeReminderCoordinator.dayKey(date)
        // 127 她：「昨天还是粉色的显示来了，我不舒服」——她点了「走了」的那天就不染粉了
        return periods.records.contains { record in
            let end = periods.shownEnd(of: record)
            let marked = periods.pendingEnds[record.id] != nil || record.end_date != nil
            return record.start_date <= key && (marked ? key < end || key == record.start_date : key <= end)
        }
    }
    private func isAnniversary(_ date: Date) -> Bool {
        let c = Calendar.current
        return vm.anniversaries.contains {
            c.component(.month, from: $0.date) == c.component(.month, from: date) && c.component(.day, from: $0.date) == c.component(.day, from: date)
        }
    }

    private static let dayTitleFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日 EEE"
        return f
    }()

    /// 点一天：排班（沿用原来的排班编辑），月经来了 / 走了。
    /// 137：最上面写点的是哪一天、右上「关上」；整张面板一个样子（细宋体、粉白强调色）
    private func daySheet(_ date: Date) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text(Self.dayTitleFormatter.string(from: date)).font(Ink.song(18)).tracking(1.5)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                // 137：44×44 和点的范围要放在按钮里面，放外面 .plain 只认那两个字
                Button { editDay = nil } label: {
                    Text("关上").font(Ink.song(15)).foregroundStyle(Ink.accent)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("day-sheet-close")
            }
            .padding(.horizontal, 24).padding(.top, 10)
            HStack {
                Text("月经").font(Ink.song(15))
                Spacer()
                PeriodCalendarControls(store: periods)
            }
            .padding(.horizontal, 24).padding(.top, 2)
            // 137：「来了 / 走了」只记今天——点的是别的日子就说一声，免得以为记在了那天
            if !Calendar.current.isDateInToday(date) {
                Text("「今天来了」「今天走了」都记在今天，不记在这一天").font(Ink.song(11.5)).foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
            }
            // 126：上次哪天来、哪天走；今天点了「走了」就写「今天走了 · 正在告诉柯 / 已告诉柯」
            Text(periods.summary).font(Ink.song(12)).foregroundStyle(Ink.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.top, 2)
                .accessibilityIdentifier("period-summary")
            periodSyncRow
            // 133：亲密记录，柯记的，她也能改
            HStack {
                Text("亲密").font(Ink.song(15))
                Spacer()
                let times = love.count(on: date)
                // 137：点的范围放到 44×44，加减号本身不变
                Button { Task { await love.setCount(times - 1, on: date) } } label: {
                    Image(systemName: "minus").frame(width: 44, height: 44).contentShape(Rectangle())
                }.disabled(times == 0).accessibilityLabel("减一次")
                Text("\(times) 次").font(Ink.song(15)).monospacedDigit().frame(minWidth: 44)
                Button { Task { await love.setCount(times + 1, on: date) } } label: {
                    Image(systemName: "plus").frame(width: 44, height: 44).contentShape(Rectangle())
                }.accessibilityLabel("加一次")
            }
            .foregroundStyle(Ink.accent)
            .padding(.horizontal, 24).padding(.top, 6)
            if let error = love.error {
                Text(error).font(Ink.song(12)).foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24)
            }
            ScheduleEditorSheet(model: vm, date: date, currentShift: vm.shift(on: date), currentNote: vm.shiftNote(on: date)) { shift, note in
                vm.setShift(shift, note: note, on: date); editDay = nil
            }
        }
        .presentationDetents([.large])
        .presentationBackground(paper)
        .foregroundStyle(Ink.primary)
    }

    /// 137：经期记没记上，在面板里直接说；没告诉上柯的「走了」给一个「再告诉柯一次」
    @ViewBuilder private var periodSyncRow: some View {
        if periods.hasUnsentEnd && !periods.saving {
            Button { Task { await periods.syncEnds() } } label: {
                Text("再告诉柯一次").font(Ink.song(13)).foregroundStyle(Ink.accent).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24)
            .accessibilityIdentifier("period-retry-sync")
        } else if let status = periods.status {
            Text(status).font(Ink.song(12)).foregroundStyle(Ink.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.top, 2)
        }
        if let error = periods.error {
            Button { Task { await periods.load() } } label: {
                Text(error).font(Ink.song(12)).foregroundStyle(Ink.accent).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24)
        }
    }

    @ViewBuilder private func page(_ e: PondEntry) -> some View {
        let close = { open = nil; Task { await book.load(); await notes.load() } }
        switch e {
        case .purse: PursePage(store: book, paper: paper, onClose: close)
        case .menu: MenuPage(store: book, paper: paper, onClose: close)
        case .meds: MedsPage(store: book, paper: paper, onClose: close)
        case .notes: NotesPage(notes: notes, api: book.api, paper: paper, onClose: close)
        }
    }
}

struct PondDay: Identifiable { let date: Date; var id: Date { date } }

enum PondEntry: String, Identifiable {
    case purse, menu, notes, meds
    var id: String { rawValue }
    var title: String { ["purse": "荷包", "menu": "食单", "notes": "纸条", "meds": "药盒"][rawValue]! }
    var sub: String { ["purse": "Bourse", "menu": "Menu", "notes": "Billets", "meds": "Remèdes"][rawValue]! }
}

/// 140：「我们」页清冷水彩的颜色和字（Design/UsWatercolorReview/cool.css）。
/// 原型里的浅字太淡（班次 #94a1b3 约 2.6:1），这里正文、班次、星期都加深到 4.5:1 以上；只有装饰的斜体英文和箭头用淡色。
enum Cool {
    static let paper = Color(hex: 0xFCFDFF)
    static let ink = Color(hex: 0x5E6877)        // 约 5.6:1
    static let number = Color(hex: 0x66748A)     // 约 4.7:1
    static let secondary = Color(hex: 0x737E8C)  // 约 4.1:1
    static let mauve = Color(hex: 0x86728C)      // 约 4.6:1
    static let faint = Color(hex: 0x9CA6B4)      // 装饰用
    static let line = Color(hex: 0xE9EDF3)
    static let today = Color(hex: 0xEAEFF7)
    static let period = Color(hex: 0xF5E2EC)
    static let heart = Color(hex: 0xB0849F)
    /// Didot 是 iOS 自带的；跟着系统字号放大
    static func didot(_ size: CGFloat, _ style: Font.TextStyle) -> Font { .custom("Didot", size: size, relativeTo: style) }
    static func didotItalic(_ size: CGFloat, _ style: Font.TextStyle) -> Font { .custom("Didot-Italic", size: size, relativeTo: style) }
    /// 跟 Ink.song 同一款思源宋体细字，只是跟着系统字号放大
    /// 思源宋体：13 号以上用极细（原型的宋体是细的），更小的用细一档
    static func song(_ size: CGFloat, _ style: Font.TextStyle) -> Font {
        .custom(size >= 13 ? "NotoSerifSC-ExtraLight" : "NotoSerifSC-Light", size: size, relativeTo: style)
    }
    /// 星期、班次、小标签：原型用的是系统无衬线细字，小字号下比宋体干净
    static func tiny(_ style: Font.TextStyle = .caption2) -> Font { .system(style).weight(.light) }
}

// MARK: - 「我们」页的数据，按线路各留一份

/// 137：以前每次切到别的页再回来，「我们」整页重建、几样数据全部重新联网，寄语先闪一下英文默认那句。
/// 现在每条线路只建一份（一个 APIClient），换页回来先画上次的，再在后台悄悄刷新。
@MainActor final class UsPondStores {
    private static var all: [String: UsPondStores] = [:]
    static func shared(_ line: ChatLine) -> UsPondStores {
        if let stores = all[line.rawValue] { return stores }
        let stores = UsPondStores(line: line)
        all[line.rawValue] = stores
        return stores
    }

    let vm: UsViewModel
    let periods: PeriodStore
    let notes: StickyNotesStore
    let book: NotebookStore
    let love: LoveLogStore
    /// 寄语在手机上留一份：刚开 App、还没拉到时先画上次那句
    private(set) var savedVerse: (en: String, zh: String)?
    private let verseKey: String
    private var lastLoad: Date?
    private var loading: Task<Void, Never>?
    static let foregroundGap: TimeInterval = 5 * 60

    private init(line: ChatLine) {
        let api = APIClient(baseURL: line.apiBaseURL)
        vm = UsViewModel(api: api)
        periods = PeriodStore(api: api, scope: line.rawValue)
        notes = StickyNotesStore(api: api, scope: line.rawValue)
        book = NotebookStore(api: api)
        love = LoveLogStore(api: api, scope: line.rawValue)
        verseKey = "us.verse." + line.rawValue
        if let saved = UserDefaults.standard.stringArray(forKey: verseKey), saved.count == 2 { savedVerse = (saved[0], saved[1]) }
    }

    /// 拉一遍。放在不跟着页面走的 Task 里：拉到一半切走了也会拉完，不会被取消、错写成「没接上」。
    /// onlyIfStale（回前台）：5 分钟内好好拉过就不再整页重拉，只把没告诉上柯的「走了」再送一次。
    func refresh(month: Date, onlyIfStale: Bool = false) async {
        if let loading { await loading.value; return }
        if onlyIfStale, let lastLoad, Date().timeIntervalSince(lastLoad) < Self.foregroundGap {
            if periods.hasUnsentEnd { await periods.syncEnds() }
            return
        }
        let task = Task { @MainActor [vm, periods, notes, book, love] in
            async let a: Void = vm.loadReminders()
            async let b: Void = periods.load()
            async let c: Void = notes.load()
            async let d: Void = book.load()
            async let e: Void = love.load(month)
            _ = await (a, b, c, d, e)
        }
        loading = task
        await task.value
        loading = nil
        if let verse = book.snapshot?.verse {
            savedVerse = (verse.en, verse.zh)
            UserDefaults.standard.set([verse.en, verse.zh], forKey: verseKey)
        }
        // 有一样没接上就不算拉过，回前台还会再拉
        let ok = periods.error == nil && !book.loadFailed && vm.reminderLoadError == nil
        lastLoad = ok ? .now : nil
    }
}
