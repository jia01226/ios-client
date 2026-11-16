import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// 140：「我们」页换成清冷水彩（Design/UsWatercolorReview，她 10-29 定的）：
// 页首团子小鱼依偎无叶山茶、Didot 细数字；日期下面就是班次，不再单列班次卡片；月历在首页原地展开收起；
// 荷包、食单、药盒、纸条两列纯文字。锦鲤池拿掉了（换之前的样子在 backup/us-pond-before-watercolor-1029 分支）。
// 数据照旧是真的：纪念日、排班、月经、亲密、寄语都沿用 UsViewModel / PeriodStore / LoveLogStore / 小本子；
// 1116 她：一屏放下不用滑——月历常驻展开（不再有周历、展开收起）；荷包、纸条、「柯留下的话」拿掉，药盒挪去「柯的」，
// 食单以后挪进记忆库；日历里能记看医生这类日程、到点提醒（CalendarEvents.swift），有日程的那天挂个小点。
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
    /// 1116：她自己记的日程（看医生的号），存在这台手机上
    @ObservedObject private var events = CalendarEventStore.shared
    @State private var floating = false
    /// 1116：横划换纪念日用的位移和翻牌角度
    @State private var heroDrag: CGFloat = 0
    @State private var heroFlip: Double = 0
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
                heroBlock.padding(.top, 28)
                Rectangle().fill(Cool.line).frame(width: 28, height: 1)
                    .frame(maxWidth: .infinity).padding(.top, 12)
                    .accessibilityHidden(true)
                // 1116：一屏放下——月历常驻展开，翻月的箭头并进标题那一行
                calendarHeader.padding(.top, 8)
                monthGrid
                // 1116 她：日历下面空着一大块，把接下来几天的日程排在那儿（看医生的号、开会）
                upcomingSection
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 4 + dockInset)
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
                // 1116 她：左右转一下就能换日子（在一起、我的生日、柯的生日……），数字跟着转过去
                Group {
                    if let a = hero {
                        let n = numbers(a)
                        // 106：点名字换成别的纪念日（还有几天、今天是……）；1116 加了左右滑
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
                }
                .offset(x: heroDrag * 0.16)
                .rotation3DEffect(.degrees(heroFlip + Double(heroDrag) * 0.05),
                                  axis: (x: 0, y: 1, z: 0), perspective: 0.6)
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
        // 1116：整块都能划（插画上也行），不是只有字那一小块
        .contentShape(Rectangle())
        .highPriorityGesture(heroSwipe)
        // 小鱼轻轻浮着；系统开了「减弱动态效果」就不动
        .onAppear {
            guard !reduceMotion, !floating else { return }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) { floating = true }
        }
    }

    /// 1116：横着划一下换纪念日；划过去、数字翻过去，松手回弹
    private var heroSwipe: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                heroDrag = value.translation.width
            }
            .onEnded { value in
                let dx = value.translation.width
                if abs(dx) > 44 { cycleAnniversary(dx < 0 ? 1 : -1) }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { heroDrag = 0 }
            }
    }

    /// 1116：换到上/下一个纪念日——先转到侧面，换完再从另一侧转回来（像翻牌）
    private func cycleAnniversary(_ step: Int) {
        let list = vm.anniversaries
        guard list.count > 1 else { return }
        let index = list.firstIndex { $0.id == heroID } ?? 0
        let next = list[(index + step + list.count) % list.count]
        guard next.id != heroID else { return }
        guard !reduceMotion else { heroID = next.id; return }
        let edge: Double = step > 0 ? -1 : 1
        withAnimation(.easeIn(duration: 0.15)) { heroFlip = 90 * edge }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            heroID = next.id
            heroFlip = -90 * edge
            withAnimation(.easeOut(duration: 0.22)) { heroFlip = 0 }
        }
    }

    // MARK: 这一周 / 月历（原地展开）

    private static var mondayCalendar: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    private static let monthNames = ["一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月"]
    private static let weekdayNames = ["一", "二", "三", "四", "五", "六", "日"]

    private var calendarHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("日历").font(Cool.song(13, .subheadline)).tracking(2.2).foregroundStyle(Cool.ink)
                .accessibilityAddTraits(.isHeader)
            if love.monthCount(month) > 0 {
                Text("亲密 \(love.monthCount(month)) 次").font(Cool.song(11, .caption)).foregroundStyle(Cool.mauve)
            }
            Spacer(minLength: 4)
            if !vm.isCurrentMonth(month) {
                Button { month = vm.startOfMonth(for: .now) } label: {
                    Text("回到本月").font(Cool.tiny(.caption)).foregroundStyle(Cool.secondary).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            // 137：点的范围放到 44×44，箭头本身不变
            Button { month = vm.month(byAdding: -1, to: month) } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .ultraLight)).frame(width: 36, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("上个月")
            Text(Self.yearMonth(month)).font(Cool.didot(15, .subheadline)).foregroundStyle(Cool.secondary)
                .lineLimit(1).fixedSize()
                .accessibilityLabel(vm.monthTitle(for: month))
            Button { month = vm.month(byAdding: 1, to: month) } label: {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .ultraLight)).frame(width: 36, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("下个月")
        }
        .foregroundStyle(Cool.secondary)
    }

    private var monthGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Self.weekdayNames, id: \.self) {
                Text($0).font(Cool.tiny()).foregroundStyle(Cool.faint).frame(height: 26).accessibilityHidden(true)
            }
            ForEach(Array(vm.monthCells(for: month).enumerated()), id: \.offset) { _, date in
                if let date { dayCell(date) } else { Color.clear.frame(height: 50) }
            }
        }
        .padding(.horizontal, -6)
    }

    /// 格子里那行字：取标题前 4 个字，去掉尾巴上的标点和空格（「复诊 · 抽血」不至于只剩「复诊 ·」）
    private static func cellLabel(_ event: CalendarEvent) -> String {
        let head = String(event.title.trimmingCharacters(in: .whitespaces).prefix(4))
        return head.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
    }

    // MARK: 接下来（日历下面的日程行）

    /// 1116 她：「提醒在下面，就是多几行，比如预约几号去哪里看医生挂号」。
    /// 只列今天起最近的 6 条，按时间排；点一行还是打开那天的面板。
    private var upcomingSection: some View {
        let upcoming = Array(
            events.events
                .filter { $0.start >= Calendar.current.startOfDay(for: .now) }
                .sorted { $0.start < $1.start }
                .prefix(6)
        )
        return VStack(alignment: .leading, spacing: 0) {
            // 1116 她：日历结束不写「接下来」，跟上面一样来一道短横线，下面直接排日程
            Rectangle().fill(Cool.line).frame(width: 28, height: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)
                .padding(.bottom, 10)
                .accessibilityHidden(true)

            if upcoming.isEmpty {
                Text("还没有排日程。看医生的号、开会的日子，点日历上那天记下来，到点会响。")
                    .font(Cool.song(12, .footnote)).tracking(0.4).lineSpacing(5)
                    .foregroundStyle(Cool.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(upcoming) { event in upcomingRow(event) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("us-upcoming")
    }

    private func upcomingRow(_ event: CalendarEvent) -> some View {
        let c = Calendar.current
        let monthDay = "\(c.component(.month, from: event.start)) 月 \(c.component(.day, from: event.start)) 日"
        let weekday = Self.weekdayNames[(c.component(.weekday, from: event.start) + 5) % 7]
        let time = event.start.formatted(.dateTime.hour().minute())
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(monthDay).font(Cool.didot(15, .subheadline)).foregroundStyle(Cool.number).monospacedDigit()
                Text("周\(weekday) \(time)").font(Cool.tiny()).foregroundStyle(Cool.faint)
            }
            .frame(width: 96, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(Cool.song(13, .subheadline)).foregroundStyle(Cool.ink)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if !event.note.isEmpty {
                    Text(event.note).font(Cool.tiny()).foregroundStyle(Cool.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { editDay = PondDay(date: event.start) }
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开这一天")
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
        let dayEvents = events.events(on: date)
        // 1116：没排班的那天，格子下面写第一个日程的名字（像苹果月历那样）；有班照旧写班
        let shift = vm.shift(on: date).map { vm.shiftDisplay($0, on: date) } ?? dayEvents.first.map(Self.cellLabel)
        // 字调到很大时，班次只写第一个字（白 / 夜 / 休），七格不挤爆
        let shown = shift.map { typeSize >= .accessibility1 ? String($0.prefix(1)) : $0 }
        return Button {
            editDay = PondDay(date: date)
        } label: {
            VStack(spacing: 5) {
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
                    // 1116：有日程（看医生的号）的那天，左上挂一个小点
                    .overlay(alignment: .topLeading) {
                        if !dayEvents.isEmpty {
                            Circle().fill(Cool.mauve).frame(width: 5, height: 5).offset(x: -4, y: 1)
                        }
                    }
                Text(shown ?? " ").font(Cool.tiny()).tracking(0.5).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(Cool.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(vm.calendarDayAccessibilityLabel(date) + (period ? "，月经" : "") + (anniversary ? "，纪念日" : "")
                            + (times > 0 ? "，亲密 \(times) 次" : "")
                            + (dayEvents.isEmpty ? "" : "，\(dayEvents.count) 个日程"))
        .accessibilityHint("打开这一天：日程、排班、月经、亲密")
        .accessibilityIdentifier(vm.calendarDayIdentifier(date))
        .contextMenu {
            Text(times > 0 ? "这天亲密 \(times) 次" : "这天还没有亲密记录")
            Button { Task { await love.setCount(times + 1, on: date) } } label: { Label("加一次", systemImage: "plus") }
            if times > 0 { Button { Task { await love.setCount(times - 1, on: date) } } label: { Label("减一次", systemImage: "minus") } }
        }
    }

    // 1116：荷包、食单、纸条不要了，药盒挪到「柯的」那朵花里——这页只剩在一起的日子和日历。
    // 那几页的代码留着（page(_:)），食单以后接进记忆库。

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
            // 1116：看医生这类日程，点进去能设提醒
            DayEventsSection(store: events, date: date)
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
