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
    /// 11-17 奶茶、粑粑：日历切到那两面时画
    @ObservedObject private var bodyLog: BodyLogStore
    /// 11-17 她：「正常就是排班日历，然后切换奶茶、粑粑、亲密」——每次进来都是排班那面
    @State private var face: CalendarFace = .shift
    @State private var faceDay: PondDay?
    /// 11-17 奶茶本本：点哪天，日历下面就列哪天的几杯
    @State private var teaDay = Date.now
    @State private var editingCup: TeaCup?
    @State private var teaBudgetOpen = false
    /// 11-17 出恭本本：点哪天，日历下面列哪天的几次
    @State private var poopDay = Date.now
    @State private var editingPoop: PoopLog?
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    /// 11-25 她：「翻月有点卡，还容易误触到具体日子」——月历跟着手指走；在滑就不算点格子
    @State private var swipeX: CGFloat = 0
    @State private var swiping = false
    @State private var tapQuietUntil = Date.distantPast
    /// 1116：她自己记的日程（看医生的号），存在这台手机上
    @ObservedObject private var events = CalendarEventStore.shared
    @State private var floating = false
    /// 11-17 她：「天数是滚轮滑动，改成往上滑」——这次往哪边滚（往上划 = 下一个，数字从下面滚上来）
    @State private var rollingUp = true
    @State private var editDay: PondDay?
    /// 11-17 她：「点进去就弹窗出来」——日历下面那行一点，直接弹出这个日程
    @State private var openEvent: CalendarEvent?
    @State private var open: PondEntry?
    @State private var choosingAnniversary = false
    @State private var managingDates = false
    @AppStorage("us.hero.anniversary") private var heroID = "together"
    /// 126：底栏浮在页面上，滚到最底时让出它那一截
    @Environment(\.floatingDockInset) private var dockInset
    /// 11-28 挑粉色用：换了就整页重画
    @AppStorage(Cool.pinkKey) private var pinkIndex = 0
    private static let showsPinkPicker = ProcessInfo.processInfo.arguments.contains("-ui-test-pink-picker")
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
        _bodyLog = ObservedObject(wrappedValue: stores.bodyLog)
    }

    var body: some View {
        // 11-17 她：「日历占满空间了，不要再往下了，直接做里面的回滚」——整页不滚，
        // 天数和月历钉住，只有下面的日程在自己那一块里上下滑
        VStack(alignment: .leading, spacing: 0) {
            // 10-31 她：最上面不要标题。右上那枚月牙是 RootTabView 画的，页面从它下面起
            heroBlock.padding(.top, 0).simultaneousGesture(monthSwipe)
            // 11-28 她给的样子：页首和日历之间一道通栏细线
            Rectangle().fill(Cool.line).frame(height: 1)
                .padding(.top, 12)
                .accessibilityHidden(true)
            // 1116：一屏放下——月历常驻展开，翻月的箭头并进标题那一行
            calendarHeader.padding(.top, 6)
            // 换一面就是一整张新的月历：旧的淡出，新的从下面轻轻浮上来
            // 11-28 她：不要最外面的框（卡片拿掉，月历直接铺在纸上）
            monthGrid
                .offset(x: swipeX)
                .simultaneousGesture(monthSwipe)
                .id(face)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 12)),
                                                                  removal: .opacity))
                .padding(.horizontal, -4)
                .padding(.top, 2)
            // 11-28 她：「不想要那个即将到来」——小标题拿掉；
            // 又说「上面日历和下面提醒要有点区别」——跟页首下面一样来一道通栏细线，中间一颗粉色小花点，上下留够空
            ZStack {
                Rectangle().fill(Cool.line).frame(height: 1)
                Text("✿").font(.system(size: 11)).foregroundStyle(Cool.pink)
                    .padding(.horizontal, 8).background(Cool.paper)
            }
            .padding(.top, 10).padding(.bottom, 14)
            .accessibilityHidden(true)
            ScrollView {
                if face == .shift {
                    // 11-18 她：「中间 ----- 下面看医生 / 奶茶杯数 / 本月次数要一致的高度」——三面下面第一行都从同一个高度起
                    upcomingSection.padding(.top, 2).padding(.bottom, 18)
                } else if face == .tea {
                    TeaPanel(store: bodyLog, month: month, day: teaDay,
                             onAdd: { editingCup = TeaCup(day: HomeReminderCoordinator.dayKey(teaDay)) },
                             onEdit: { editingCup = $0 },
                             onBudget: { teaBudgetOpen = true })
                        .padding(.top, 8).padding(.bottom, 18)
                } else {
                    PoopPanel(store: bodyLog, month: month, day: poopDay,
                              onAdd: { editingPoop = PoopLog(day: HomeReminderCoordinator.dayKey(poopDay)) },
                              onEdit: { editingPoop = $0 })
                        .padding(.top, 8).padding(.bottom, 18)
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity)
            // 底下一截淡进纸色，滑到底的那行不是被硬切掉
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [paper.opacity(0), paper], startPoint: .top, endPoint: .bottom)
                    .frame(height: 16)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 4 + dockInset)
        // 11-28 挑粉色：模拟器里底部一排切换（正式版不出现）
        .overlay(alignment: .bottom) {
            if Self.showsPinkPicker {
                HStack(spacing: 6) {
                    ForEach(Array(Cool.pinkPalettes.enumerated()), id: \.offset) { i, p in
                        Button { pinkIndex = i } label: {
                            HStack(spacing: 4) {
                                Circle().fill(Color(hex: p.accent)).frame(width: 10, height: 10)
                                Text(p.name).font(.system(size: 12, weight: pinkIndex == i ? .semibold : .regular))
                            }
                            .padding(.horizontal, 9).frame(height: 32)
                            .background(Capsule().fill(Color(hex: p.soft)))
                            .overlay(Capsule().strokeBorder(pinkIndex == i ? Color(hex: p.accent) : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, dockInset + 8)
            }
        }
        .id(pinkIndex)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(paper.ignoresSafeArea())
        .foregroundStyle(Cool.ink)
        // 137：切过来照样刷新；回前台 5 分钟内拉过就不再整页重拉（没告诉上柯的「走了」还是会再送）
        // 11-18 她：「底栏切换 tab，我们这里会有点卡」——每次切过来都整页重拉、拉回来又一样样重画。
        // 五分钟内拉过就只补没送上的（跟回前台一样）；日程照旧每次拉（很轻，柯刚记的号要马上出现）
        .task { await stores.refresh(month: month, onlyIfStale: true) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await stores.refresh(month: month, onlyIfStale: true) } } }
        .onChange(of: month) { _, m in Task { await love.load(m); await bodyLog.load(m) } }
        .sheet(item: $faceDay) { day in faceSheet(day.date) }
        .sheet(item: $editingCup) { cup in
            TeaCupEditor(cup: cup, isNew: cup.id.isEmpty, recentBrands: bodyLog.recentBrands,
                         upload: { await bodyLog.uploadPhoto($0) },
                         onSave: { saved in Task { await bodyLog.saveCup(saved) } },
                         onDelete: { gone in Task { await bodyLog.deleteCup(gone) } })
                .environmentObject(Theme.shared)
        }
        .sheet(item: $editingPoop) { log in
            PoopEditor(log: log, isNew: log.id.isEmpty,
                       onSave: { saved in Task { await bodyLog.savePoop(saved) } },
                       onDelete: { gone in Task { await bodyLog.deletePoop(gone) } })
        }
        .sheet(isPresented: $teaBudgetOpen) {
            TeaBudgetSheet(budget: bodyLog.teaBudget) { m, w in Task { await bodyLog.setBudget(monthBudget: m, weekCups: w) } }
        }
        .sheet(item: $editDay, onDismiss: { periods.clearStatus() }) { day in daySheet(day.date) }
        .sheet(item: $openEvent) { event in
            CalendarEventEditor(event: event, isNew: false) { saved in
                events.save(saved)
            } onDelete: { id in
                events.delete(id)
            }
            .presentationDetents([.medium, .large])
        }
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
                        // 106：点名字换成别的纪念日（还有几天、今天是……）
                        // 11-17 她：「上面的说明也会动」——名字原地淡入淡出，不跟着走
                        Button { choosingAnniversary = true } label: {
                            Text(eyebrow(a)).font(.custom("NotoSerifSC-Light", size: 12, relativeTo: .caption)).tracking(2.2)
                                .foregroundStyle(Cool.pinkText)
                                .id("eyebrow-" + a.id)
                                .transition(.opacity)
                                .frame(minHeight: 32, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("换一个纪念日，现在是\(Self.shortName(a))")
                        .accessibilityIdentifier("us-anniversary-pick")
                        // 11-17 她：「天数是滚轮滑动，改成往上滑」——一格窗口里，旧的数字往上滚出去、新的从下面滚上来
                        ZStack(alignment: .bottomLeading) {
                            HStack(alignment: .lastTextBaseline, spacing: 6) {
                                Text(n.number).font(Cool.didot(n.number == "今天" ? 38 : 56, .largeTitle))
                                    .foregroundStyle(Cool.number).lineLimit(1).minimumScaleFactor(0.6)
                                    .monospacedDigit()
                                Text(n.unit).font(.custom("NotoSerifSC-Regular", size: 22, relativeTo: .title3)).foregroundStyle(Cool.ink)
                            }
                            .id("number-" + a.id)
                            .transition(rollTransition)
                        }
                        .frame(maxWidth: .infinity, minHeight: 68, maxHeight: 68, alignment: .bottomLeading)
                        .clipped()
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("往上划换下一个日子，往下划换回上一个")
                    }
                }
                // 原型那两行：一句中文、一行斜体英文（她：留白克制，日期那行挪到纪念日面板里看）
                Text(verseZh).font(.custom("NotoSerifSC-Light", size: 13, relativeTo: .footnote)).tracking(0.6).lineSpacing(5).foregroundStyle(Cool.ink.opacity(0.78))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                Text(verseEn).font(Cool.didot(13, .footnote)).tracking(0.4).lineSpacing(3).foregroundStyle(Cool.faint)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.top, 7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image("UsFishCamellia").resizable().scaledToFit()
                .containerRelativeFrame(.horizontal) { w, _ in min(190, w * 0.44) }
                .offset(x: 16, y: floating ? -14 : -9)
                // 11-16 她：「日历下方的提醒在动」——以前用 withAnimation(repeatForever) 起浮，
                // 同一拍里排出来的日程行也被卷进这个永远来回的动画，一直上下晃。动画只挂在小鱼自己身上。
                .animation(reduceMotion ? nil : .easeInOut(duration: 3.4).repeatForever(autoreverses: true), value: floating)
                .opacity(0.92)
                // 1116 她：点小鱼也能挑日子（加生日、纪念日）
                .contentShape(Rectangle())
                .onTapGesture { choosingAnniversary = true }
                .accessibilityHidden(true)
        }
        // 1116：整块都能划（插画上也行），不是只有字那一小块
        .contentShape(Rectangle())
        .simultaneousGesture(heroSwipe)
        .sensoryFeedback(.selection, trigger: heroID)
        // 小鱼轻轻浮着；系统开了「减弱动态效果」就不动
        .onAppear {
            guard !reduceMotion, !floating else { return }
            floating = true
        }
    }

    /// 11-17 她：「左滑卡卡的」「改成往上滑」——手指划的时候什么都不跟着动（以前整块跟手走、每帧重排，就卡），
    /// 松手时看方向：往上划换下一个，往下划换回上一个，数字像滚轮一样滚一格，轻轻震一下。
    private var heroSwipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                let dy = value.translation.height, dx = value.translation.width
                guard abs(dy) > abs(dx) * 1.2,
                      abs(dy) > 28 || abs(value.predictedEndTranslation.height) > 90 else { return }
                cycleAnniversary(dy < 0 ? 1 : -1)
            }
    }

    private var rollTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: rollingUp ? .bottom : .top).combined(with: .opacity),
            removal: .move(edge: rollingUp ? .top : .bottom).combined(with: .opacity)
        )
    }

    /// 1116：换到上/下一个纪念日——先转到侧面，换完再从另一侧转回来（像翻牌）
    private func cycleAnniversary(_ step: Int) {
        let list = vm.anniversaries
        guard list.count > 1 else { return }
        let index = list.firstIndex { $0.id == heroID } ?? 0
        let next = list[(index + step + list.count) % list.count]
        guard next.id != heroID else { return }
        guard !reduceMotion else { heroID = next.id; return }
        // 先把方向定下来、画一遍，旧数字才知道该往哪边滚出去；下一拍再换
        rollingUp = step > 0
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.92)) { heroID = next.id }
        }
    }

    /// 11-25 她：日历要能左右滑动翻月，不用去点那两个小箭头
    private var monthSwipe: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let dx = value.translation.width, dy = value.translation.height
                guard swiping || (abs(dx) > 12 && abs(dx) > abs(dy) * 1.2) else { return }
                swiping = true
                // 跟着手指走一点（带阻尼），让她觉得「抓住了」，不是松手后才动
                swipeX = reduceMotion ? 0 : dx * 0.45
            }
            .onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                let predicted = value.predictedEndTranslation.width
                let wasSwiping = swiping
                swiping = false
                if wasSwiping { tapQuietUntil = Date().addingTimeInterval(0.35) }
                let flip = wasSwiping && abs(dx) > abs(dy) * 1.2 && (abs(dx) > 40 || abs(predicted) > 90)
                guard flip else {
                    withAnimation(.snappy(duration: 0.18)) { swipeX = 0 }
                    return
                }
                let step = dx < 0 ? 1 : -1
                if reduceMotion {
                    month = vm.month(byAdding: step, to: month)
                } else {
                    // 新的一月从手指来的那一侧滑进来
                    var quiet = Transaction(); quiet.disablesAnimations = true
                    withTransaction(quiet) {
                        month = vm.month(byAdding: step, to: month)
                        swipeX = CGFloat(step) * 60
                    }
                    withAnimation(.snappy(duration: 0.2)) { swipeX = 0 }
                }
                UISelectionFeedbackGenerator().selectionChanged()
            }
    }

    // MARK: 这一周 / 月历（原地展开）

    private static var mondayCalendar: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    private static let monthNames = ["一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月"]
    private static let weekdayNames = ["一", "二", "三", "四", "五", "六", "日"]

    private var calendarHeader: some View {
        VStack(spacing: 0) {
            // 11-17：原来的「日历 · 亲密几次」换成「排班 · 奶茶 · 出恭」三面切换（亲密的小心照旧挂在排班那面的格子上）
            HStack(alignment: .center, spacing: 6) {
                CalendarFacePicker(face: $face)
                Spacer(minLength: 4)
                // 137：点的范围放到 44×44，箭头本身不变
                Button { month = vm.month(byAdding: -1, to: month) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .medium)).foregroundStyle(Cool.pink).frame(width: 36, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("上个月")
                // 不在本月时点年月回到本月（原来那个「回到本月」挪到这里，顶上放不下了）
                Button { if !vm.isCurrentMonth(month) { month = vm.startOfMonth(for: .now) } } label: {
                    // 11-28 她：「优化视觉层级」——年月是日历的标题，跟数字一个颜色、大一号；箭头退到最淡
                    Text(Self.yearMonth(month)).font(.system(size: 18, weight: .semibold, design: .default))
                        .foregroundStyle(vm.isCurrentMonth(month) ? Cool.ink : Cool.mauve)
                        .lineLimit(1).fixedSize()
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // 不用 .disabled：系统会把禁用的字自动调灰，年月就又退成背景了
                .accessibilityLabel(vm.monthTitle(for: month) + (vm.isCurrentMonth(month) ? "" : "，点一下回到本月"))
                Button { month = vm.month(byAdding: 1, to: month) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .medium)).foregroundStyle(Cool.pink).frame(width: 36, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("下个月")
            }
        }
        .foregroundStyle(Cool.secondary)
    }

    private var monthGrid: some View {
        let annDays = anniversaryKeys(month)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Self.weekdayNames, id: \.self) { name in
                // 星期比以前清楚一档；周末两天用主色，一眼分得出来
                Text(name).font(.system(size: 13, weight: .light)).foregroundStyle(Cool.pinkText.opacity(0.6))
                    .frame(height: 34).accessibilityHidden(true)
            }
            ForEach(Array(vm.monthCells(for: month).enumerated()), id: \.offset) { _, date in
                if let date { cell(date, anniversaries: annDays) } else { Color.clear.frame(height: 56) }
            }
        }
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
            // 11-16 她：「空白就空白」——没有日程就什么都不写
            ForEach(upcoming) { event in upcomingRow(event) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("us-upcoming")
    }

    /// 11-17 她：「我们页有点太满了」——一行只写「11 月 20 日 · 周五 16:00」和「广脑 李启荣 · 江村二楼诊室11 · 序号13」，
    /// 点这一行直接弹出这个日程，再看备注、要跟医生说的。
    private func upcomingRow(_ event: CalendarEvent) -> some View {
        let c = Calendar.current
        let weekday = Self.weekdayNames[(c.component(.weekday, from: event.start) + 5) % 7]
        let time = event.start.formatted(.dateTime.hour().minute())
        // 11-28 她给的样子：一张淡底圆角卡，左边一道主色竖条；左边日期小方块（月在上、日在下），中间标题加粗、下面周几和时间，右边一个小箭头
        return HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text("\(c.component(.month, from: event.start))月").font(.system(size: 12, weight: .medium))
                Text("\(c.component(.day, from: event.start))").font(.system(size: 20, weight: .semibold)).monospacedDigit()
            }
            .foregroundStyle(Cool.pinkText)
            .frame(width: 50, height: 50)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.75)))
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.upcomingLine(event)).font(.system(size: 17, weight: .semibold)).foregroundStyle(Cool.ink)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text("周\(weekday) · \(time)").font(.system(size: 13)).foregroundStyle(Cool.pinkText.opacity(0.75))
            }
            Spacer(minLength: 0)
            if let said = event.symptoms, !said.isEmpty {
                // 有记下要跟医生说的，挂一个小点提示点进去看
                Circle().fill(Cool.mauve).frame(width: 5, height: 5).accessibilityHidden(true)
            }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .medium)).foregroundStyle(Cool.pink)
        }
        .padding(.vertical, 14).padding(.leading, 16).padding(.trailing, 16)
        // 11-28 她：颜色太深难看——整张卡浅粉底，左边粉色竖条
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Cool.pinkSoft))
        .overlay(alignment: .leading) { Capsule().fill(Cool.pink.opacity(0.8)).frame(width: 3).padding(.vertical, 10) }
        .padding(.bottom, 10)
        .contentShape(Rectangle())
        .onTapGesture { openEvent = event }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("打开这个日程")
    }

    /// 看病的写「广脑 李启荣 · 江村二楼诊室11 · 序号13」（备注里前两截 + 序号那截），别的事写标题
    static func upcomingLine(_ event: CalendarEvent) -> String {
        guard event.title == "看医生", !event.note.isEmpty else { return event.title }
        let parts = event.note.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var shown = Array(parts.prefix(2))
        if let number = parts.dropFirst(2).first(where: { $0.contains("序号") }) { shown.append(number) }
        return shown.joined(separator: " · ")
    }

    private static func yearMonth(_ date: Date) -> String {
        let c = Calendar.current
        return "\(c.component(.year, from: date))年 \(c.component(.month, from: date))月"
    }

    @ViewBuilder private func cell(_ date: Date, anniversaries: Set<String>) -> some View {
        switch face {
        case .shift: dayCell(date, anniversary: anniversaries.contains(HomeReminderCoordinator.dayKey(date)))
        case .tea:
            TeaDayCell(date: date, cups: bodyLog.teaCups(on: date),
                       selected: Calendar.current.isDate(date, inSameDayAs: teaDay)) { teaDay = date }
        case .poop:
            PoopDayCell(date: date, logs: bodyLog.poopLogs(on: date),
                        selected: Calendar.current.isDate(date, inSameDayAs: poopDay)) { poopDay = date }
        }
    }

    /// 奶茶 / 粑粑 / 亲密那几面，月历下面写这个月一共多少
    private var faceSummary: some View {
        let line: String
        switch face {
        case .tea: line = "这个月喝了 \(bodyLog.teaMonth(month)) 杯奶茶"
        case .poop:
            let gap = bodyLog.daysSinceLastPoop()
            line = "这个月出恭 \(bodyLog.poopMonth(month)) 次" + (gap.map { $0 == 0 ? " · 今天有过了" : " · 上一次是 \($0) 天前" } ?? "")
        case .shift: line = ""
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text(line).font(Cool.song(13, .subheadline)).foregroundStyle(Cool.ink)
            Text("点哪一天就改哪一天，柯也看得到；跟柯说一声他也会帮你记。")
                .font(Cool.tiny()).foregroundStyle(Cool.secondary)
            if let error = bodyLog.error {
                Text(error).font(Cool.tiny()).foregroundStyle(Cool.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func faceSheet(_ date: Date) -> some View {
        switch face {
        case .tea:
            EmptyView()   // 奶茶点一天是在日历下面列出来（TeaPanel），不弹小窗
        case .poop:
            EmptyView()   // 出恭点一天是在日历下面列出来（PoopPanel）
        case .shift:
            EmptyView()
        }
    }

    /// 一天：Didot 数字，下面就是班次；今天淡蓝圆底，月经淡粉圆底，纪念日 ☾、亲密小心挂在右上
    private func dayCell(_ date: Date, anniversary: Bool) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        // 11-28：过去的日子退后一点，今天和以后的更清楚
        let isPast = !isToday && date < Calendar.current.startOfDay(for: .now)
        let period = isPeriod(date)
        let times = love.count(on: date)
        let dayEvents = events.events(on: date)
        // 1116：没排班的那天，格子下面写第一个日程的名字（像苹果月历那样）；有班照旧写班
        let shift = vm.shift(on: date).map { vm.shiftDisplay($0, on: date) } ?? dayEvents.first.map(Self.cellLabel)
        // 字调到很大时，班次只写第一个字（白 / 夜 / 休），七格不挤爆
        let shown = shift.map { typeSize >= .accessibility1 ? String($0.prefix(1)) : $0 }
        return Button {
            // 刚滑过月就不算点了这一天
            guard !swiping, Date() > tapQuietUntil else { return }
            editDay = PondDay(date: date)
        } label: {
            VStack(spacing: -3) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 18, weight: isToday && !period ? .semibold : .regular)).monospacedDigit()
                    .foregroundStyle(isToday && !period ? Cool.paper : (isPast ? Cool.secondary.opacity(0.75) : Cool.number))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 38, height: 38)
                    // 11-17 她：「经期我想要方块的粉色阴影，比如 1-5 号可以连起来的那种」——粉色画在整格后面（见下面 periodBand），
                    // 数字这里只留「今天」的圈；今天正好在经期，就描一圈细线
                    // 11-28：今天是整张日历的锚——实心主色圆、纸色数字（以前的淡圈跟别的格子分不出来）
                    .background(Circle().fill(isToday && !period ? Cool.pink : .clear))
                    .overlay(Circle().stroke(isToday && period ? Cool.number.opacity(0.45) : .clear, lineWidth: 0.8))
                    // 11-28 她：亲密还是小爱心挂右上（纪念日的☾跟着它）；有事的小圆点挂左上
                    .overlay(alignment: .topTrailing) {
                        if anniversary || times > 0 {
                            HStack(spacing: 1) {
                                if anniversary { Text("☾").font(.system(size: 9)) }
                                if times > 0 { Image(systemName: "heart.fill").font(.system(size: 7)) }
                            }
                            .foregroundStyle(Cool.heart).offset(x: 6, y: -1)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if !dayEvents.isEmpty {
                            Circle().fill(Cool.pink).frame(width: 5, height: 5).offset(x: -1, y: 2)
                        }
                    }
                // 有班写班（淡）；没班、写的是日程名（看医生）就用主色，有事的日子一眼看得到
                let isEventLabel = vm.shift(on: date) == nil && !dayEvents.isEmpty
                Text(shown ?? " ").font(Cool.tiny()).tracking(0.5).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(isEventLabel ? Cool.pinkText : (isPast ? Cool.faint : Cool.secondary))
            }
            .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56, alignment: .top)   // 三面同一个高度，切换不跳
            .background(alignment: .top) { if period { periodBand(date) } }
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
    /// 1116 她：生日往回数（还有 N 天），纪念日往前数（在一起 N 天，一天比一天大）。
    /// 生日不一定带「每年」这个标记（服务器回来的可能没有），按 id / 名字再兜一层；
    /// 「管理日期」里加的、还没到的日子（比如「下次见面」）也当倒数。
    /// 每年来一次的日子（生日）；它们按「下一次是几月几号」倒数
    private func isRecurring(_ a: Anniversary) -> Bool {
        a.isYearly || a.id == "mine" || a.id == "ke" || a.title.contains("生日")
    }

    private func countsDown(_ a: Anniversary) -> Bool {
        isRecurring(a) || a.date > Date.now
    }

    private func numbers(_ a: Anniversary) -> (number: String, unit: String, line: String, past: Bool) {
        let c = Calendar.current, comps = c.dateComponents([.year, .month, .day], from: a.date)
        if countsDown(a) {
            // 生日按年循环（只看月日）；一次性的日子按真实日期倒数，隔一年以上也不会算少
            let left = isRecurring(a) ? vm.daysUntil(a) : vm.daysAhead(to: a.date)
            let line = a.isLunar
                ? "每年" + LunarDay.label(month: a.lunarMonth ?? 1, day: a.lunarDay ?? 1)
                : a.isYearly
                ? "每年 \(comps.month ?? 0) 月 \(comps.day ?? 0) 日"
                : "\(comps.year ?? 0) 年 \(comps.month ?? 0) 月 \(comps.day ?? 0) 日"
            return left == 0 ? ("今天", "", "今天是" + Self.shortName(a), false) : ("\(left)", "天后", line, false)
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

    /// 经期那几天连成一条粉色的块：前一天也在经期就和左边接上，后一天也在就和右边接上；
    /// 一周的头（周一）、尾（周日）和经期的头尾收成小圆角
    private func periodBand(_ date: Date) -> some View {
        let c = Calendar.current
        let weekday = c.component(.weekday, from: date)   // 1 = 周日，2 = 周一
        let prev = c.date(byAdding: .day, value: -1, to: date).map(isPeriod) ?? false
        let next = c.date(byAdding: .day, value: 1, to: date).map(isPeriod) ?? false
        let left = !prev || weekday == 2, right = !next || weekday == 1
        let r: CGFloat = 9
        return UnevenRoundedRectangle(topLeadingRadius: left ? r : 0, bottomLeadingRadius: left ? r : 0,
                                      bottomTrailingRadius: right ? r : 0, topTrailingRadius: right ? r : 0,
                                      style: .continuous)
            .fill(Cool.period)
            .frame(height: 32)
            .padding(.leading, left ? 4 : 0)
            .padding(.trailing, right ? 4 : 0)
            .accessibilityHidden(true)
    }

    private func isPeriod(_ date: Date) -> Bool {
        let key = HomeReminderCoordinator.dayKey(date)
        // 127 她：「昨天还是粉色的显示来了，我不舒服」——她点了「走了」的那天就不染粉了
        return periods.records.contains { record in
            let end = periods.shownEnd(of: record)
            let marked = periods.pendingEnds[record.id] != nil || record.end_date != nil
            return record.start_date <= key && (marked ? key < end || key == record.start_date : key <= end)
        }
    }
    /// 这个月哪几天是纪念日：一个月算一次（以前每画一格都把农历换算一遍）
    private func anniversaryKeys(_ month: Date) -> Set<String> {
        Set(vm.monthCells(for: month).compactMap { $0 }.filter(isAnniversary).map(HomeReminderCoordinator.dayKey))
    }

    private func isAnniversary(_ date: Date) -> Bool {
        let c = Calendar.current
        return vm.anniversaries.contains {
            if let m = $0.lunarMonth, let d = $0.lunarDay { return LunarDay.matches(date, month: m, day: d) }
            return c.component(.month, from: $0.date) == c.component(.month, from: date) && c.component(.day, from: $0.date) == c.component(.day, from: date)
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
            // 1118 她给的稿：上面「日期 + 今日安排」，下面一张张卡片
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.dayTitleFormatter.string(from: date)).font(Ink.song(12)).foregroundStyle(Ink.secondary)
                    Text("今日安排").font(Ink.song(21)).tracking(2).foregroundStyle(Ink.primary)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
                Button { editDay = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.secondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Ink.primary.opacity(0.05)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关上")
                .accessibilityIdentifier("day-sheet-close")
            }
            .padding(.horizontal, 20).padding(.top, 32).padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 10) {
                    sheetCard {
                        DayEventsSection(store: events, date: date)
                        // 1118 稿子上有这句：那天没排日程就说一声
                        if events.events(on: date).isEmpty {
                            Text("今天还没有日程")
                                .font(Ink.song(12)).foregroundStyle(Ink.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 12)
                        }
                    }

                    sheetCard {
                        HStack {
                            Text("月经记录").font(Ink.song(15)).foregroundStyle(Ink.primary)
                            Spacer()
                            PeriodCalendarControls(store: periods)
                        }
                        .padding(.horizontal, 20).padding(.top, 9)

                        if !Calendar.current.isDateInToday(date) {
                            Text("「今天来了」「今天走了」都记在今天，不记在这一天")
                                .font(Ink.song(11.5)).foregroundStyle(Ink.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20).padding(.top, 2)
                        }
                        Text(periods.summary).font(Ink.song(12)).foregroundStyle(Ink.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20).padding(.top, 6)
                            .accessibilityIdentifier("period-summary")
                        periodSyncRow
                        Text("记录状态会自动更新周期信息")
                            .font(Ink.song(11.5)).foregroundStyle(Ink.secondary.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20).padding(.top, 2).padding(.bottom, 9)
                    }

                    sheetCard {
                        HStack {
                            Text("亲密记录").font(Ink.song(15)).foregroundStyle(Ink.primary)
                            Spacer()
                            let times = love.count(on: date)
                            Button { Task { await love.setCount(times - 1, on: date) } } label: {
                                Image(systemName: "minus").frame(width: 40, height: 40).contentShape(Rectangle())
                            }.disabled(times == 0).accessibilityLabel("减一次")
                            Text("\(times) 次").font(Ink.song(15)).monospacedDigit().frame(minWidth: 52)
                            Button { Task { await love.setCount(times + 1, on: date) } } label: {
                                Image(systemName: "plus").frame(width: 40, height: 40).contentShape(Rectangle())
                            }.accessibilityLabel("加一次")
                        }
                        .foregroundStyle(Ink.accent)
                        .padding(.horizontal, 20).padding(.top, 8)

                        Text("轻点 + 记录今天的次数")
                            .font(Ink.song(11.5)).foregroundStyle(Ink.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20).padding(.top, 2)
                        if let error = love.error {
                            Text(error).font(Ink.song(12)).foregroundStyle(Ink.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
                        }
                        Color.clear.frame(height: 9)
                    }

                    sheetCard {
                        HStack {
                            Text("今日班次").font(Ink.song(15)).foregroundStyle(Ink.primary)
                            Spacer()
                            Text("选择一项").font(Ink.song(11.5)).foregroundStyle(Ink.secondary)
                        }
                        .padding(.horizontal, 20).padding(.top, 9)

                        ScheduleEditorSheet(model: vm, date: date,
                                            currentShift: vm.shift(on: date),
                                            currentNote: vm.shiftNote(on: date),
                                            showsTitle: false) { shift, note in
                            vm.setShift(shift, note: note, on: date); editDay = nil
                        }
                        .padding(.bottom, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        // 1118 她：底下不要空着一大块，也别顶到最上面——按内容高度停在下面，想拉到全屏也能拉
        .presentationDetents([.fraction(0.87), .large])
        .presentationBackground(paper)
        .foregroundStyle(Ink.primary)
    }

    /// 1118：「今日安排」里的一张卡片（里面先包一层 VStack，背景才会整块，不会一行一条）
    private func sheetCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Ink.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Ink.line.opacity(0.45), lineWidth: 0.7)
            )
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
/// 11-17 她：「设置的那个统一，就应该统一所有的背景颜色」——「我们」「柯的」原来是一套冷的蓝灰（纸偏蓝、字蓝灰），
/// 跟设置、聊天的暖墨对不上。现在纸跟她在「主题色」里挑的那张走，字、线、强调色都用设置那套暖墨（Ink）。
enum Cool {
    static var paper: Color { CamelliaPalette.stored().paper }
    static var ink: Color { Ink.primary }
    static var number: Color { Ink.primary }
    static var secondary: Color { Ink.secondary }
    static var mauve: Color { Ink.accent }
    static var faint: Color { Ink.secondary.opacity(0.65) }   // 装饰用
    static var line: Color { Ink.line.opacity(0.6) }
    static var today: Color { Ink.track }
    static let period = Color(hex: 0xF5E2EC)
    /// 11-28 她：「整体有点深了，要粉色、浅粉色」→「太荧光了」→ 挑了 1/2/4/5 四版柔和粉在模拟器里切着比。
    /// 每版三个色：主色（今天的圆、下划线、爱心、有事的点）、浅底（日程卡）、粉字。
    static let pinkPalettes: [(name: String, accent: UInt32, soft: UInt32, text: UInt32)] = [
        ("樱花雾粉", 0xE3A1B6, 0xFBF0F3, 0xA65F7B),
        ("豆沙粉", 0xC88C9C, 0xF6ECEF, 0x8C5467),
        ("藕粉", 0xCBA2AE, 0xF5EEF0, 0x896170),
        ("奶油粉", 0xEDB8C7, 0xFEF5F7, 0xB06D86),
    ]
    static let pinkKey = "us.pink.palette"
    private static var pinkNow: (name: String, accent: UInt32, soft: UInt32, text: UInt32) {
        let i = UserDefaults.standard.integer(forKey: pinkKey)
        return pinkPalettes[min(max(0, i), pinkPalettes.count - 1)]
    }
    static var heart: Color { Color(hex: pinkNow.accent) }
    static var pink: Color { Color(hex: pinkNow.accent) }        // 今天的圆、选中的下划线、有事的小圆点
    static var pinkSoft: Color { Color(hex: pinkNow.soft) }      // 日程卡的底
    static var pinkText: Color { Color(hex: pinkNow.text) }      // 粉色的小字
    /// 11-25 她：要锁屏时钟那种衬线数字。锁屏那档是苹果的 New York（系统自带衬线），
    /// 取不到就退回 Didot，不至于变成无衬线。
    private static let numberFont: String = {
        // 11-25 她定的：Source Serif 4 正体（跟中文的思源宋体是一套字形，小字号也清楚）
        // 11-25：包里那份字体的 PostScript 名是 SourceSerif4Roman-Regular（原来找 SourceSerif4-Regular 找不到，悄悄退回了 Didot）
        for name in ["SourceSerif4Roman-Regular", "SourceSerif4-Regular", "Source Serif 4", "SourceSerif4"]
        where UIFont(name: name, size: 12) != nil {
            return name
        }
        return "Didot"
    }()
    static func didot(_ size: CGFloat, _ style: Font.TextStyle) -> Font { .custom(numberFont, size: size, relativeTo: style) }
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
    /// 11-17 奶茶、粑粑
    let bodyLog: BodyLogStore
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
        bodyLog = BodyLogStore(api: api, scope: line.rawValue)
        CalendarEventStore.shared.attach(api)
        verseKey = "us.verse." + line.rawValue
        if let saved = UserDefaults.standard.stringArray(forKey: verseKey), saved.count == 2 { savedVerse = (saved[0], saved[1]) }
    }

    /// 拉一遍。放在不跟着页面走的 Task 里：拉到一半切走了也会拉完，不会被取消、错写成「没接上」。
    /// onlyIfStale（回前台）：5 分钟内好好拉过就不再整页重拉，只把没告诉上柯的「走了」再送一次。
    func refresh(month: Date, onlyIfStale: Bool = false) async {
        if let loading { await loading.value; return }
        // 11-16：日程每次都拉（柯刚记的号要马上出现），很轻
        Task { await CalendarEventStore.shared.sync() }
        if onlyIfStale, let lastLoad, Date().timeIntervalSince(lastLoad) < Self.foregroundGap {
            if periods.hasUnsentEnd { await periods.syncEnds() }
            return
        }
        let task = Task { @MainActor [vm, periods, notes, book, love, bodyLog] in
            async let a: Void = vm.loadReminders()
            async let b: Void = periods.load()
            async let c: Void = notes.load()
            async let d: Void = book.load()
            async let e: Void = love.load(month)
            async let f: Void = bodyLog.load(month)
            _ = await (a, b, c, d, e, f)
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
