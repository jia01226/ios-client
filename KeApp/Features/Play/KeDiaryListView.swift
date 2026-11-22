import SwiftUI

// 105：日记照 GPT 的「日记目录 / 点开一篇」做。只放柯写的（她一般不写）。
// 108：她的意见——锁着的和没锁的一眼分清（锁过后来打开的也标出来）；点开不要翻页动画；
// 月份标题跟着往下翻（翻到九月就显示九月）；每一篇一样高，同一天的几篇是一整块，篇与篇之间一条短线，两天之间一条通栏线。
// 123：标题下面加「日记｜夜里」，样子和荷包的「花钱｜攒钱」一样（InkTabSwitch）；「夜里」那一栏在 KeNightDiary.swift。

/// 123：日记页顶上的两栏。记住她上次看的是哪一栏；从「爸爸开锁了」那张卡、「柯的」页写着日记的那张卡点进来，一定落在日记。
enum DiaryTab: String, CaseIterable {
    case diary, night, drawer, favorites
    static let storageKey = "diary.page.tab"
    /// 1116 她：抽屉挪进日记，跟日记、夜里并排
    /// 1120 她：聊天里想原样留着的一段，放进日记页第四栏「收藏」
    var label: String { ["diary": "日记", "night": "夜里", "drawer": "抽屉", "favorites": "收藏"][rawValue]! }
    /// 带着要翻开的那一篇进来（pinnedToDiary）就是日记；不然照她上次选的，认不出来的当日记
    static func current(saved: String, pinnedToDiary: Bool, pinnedToNight: Bool = false) -> DiaryTab {
        // 128：从聊天里「夜里日记」卡点进来的，一定落在夜里
        if pinnedToNight { return .night }
        return pinnedToDiary ? .diary : (DiaryTab(rawValue: saved) ?? .diary)
    }
}

struct KeDiaryListView: View {
    let line: ChatLine
    var onClose: () -> Void
    /// 120：从聊天里「爸爸开锁了」那张卡点进来：一进来就翻开这一篇（「目录」照样回日记目录）
    var openingID: Int? = nil
    /// 123：从「柯的」页底下那张写着日记的卡片点进来：卡片说的是日记，就落在日记，不管她上次停在哪一栏（点花还是照上次的）
    var startOnDiary = false
    /// 128：从聊天里「夜里日记」卡点进来：落在「夜里」，那一条展开、滚到上面
    var openingNightID: Int? = nil
    /// 128：那一条已经滚到过了（她往别处翻以后不再拽回去）
    @State private var nightOpened = false
    /// 拉过一遍了（转圈可以撤了）
    @State private var openingDone = false
    /// 那一篇已经翻开过（她退回目录后不再拽回去）
    @State private var opened = false
    @AppStorage(CamelliaPalette.storageKey) private var savedPalette = CamelliaPalette.defaultPalette.rawValue
    @State private var entries: [RemoteDiary] = []
    @State private var loading = true
    @State private var failed = false
    @State private var query = ""
    @State private var onlyLocked = false
    @State private var reading: RemoteDiary?
    @State private var pickingDate = false
    @State private var jumpDate = Date()
    /// 123：她上次看的是「日记」还是「夜里」
    @AppStorage(DiaryTab.storageKey) private var savedTab = DiaryTab.diary.rawValue
    /// 123：带着 openingID 或 startOnDiary 进来先钉在日记；她自己点了切换才放开（钉着的时候不改她记住的那一栏）
    @State private var leftPin = false
    /// 123：「夜里」那一栏的数据和她手上的样子（筛选、点开的、没发的那句话）跟着日记页一起开着，切来切去都还在
    /// 128：和聊天里「夜里日记」卡共用一份（NightStore.shared），卡上点过的这里就是点过的样子
    @ObservedObject private var night: NightStore

    init(line: ChatLine, onClose: @escaping () -> Void, openingID: Int? = nil, startOnDiary: Bool = false,
         openingNightID: Int? = nil) {
        self.line = line
        self.onClose = onClose
        self.openingID = openingID
        self.startOnDiary = startOnDiary
        self.openingNightID = openingNightID
        _night = ObservedObject(wrappedValue: NightStore.shared(line))
    }
    private var paper: Color { CamelliaPalette.resolve(savedPalette).paper }
    private var tab: DiaryTab {
        DiaryTab.current(saved: savedTab, pinnedToDiary: (openingID != nil || startOnDiary) && !leftPin,
                         pinnedToNight: openingNightID != nil && !leftPin)
    }
    private static let rowHeight: CGFloat = 66

    private var lockedCount: Int { entries.filter(Self.isLocked).count }
    private var shown: [RemoteDiary] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return entries.filter { e in
            (!onlyLocked || Self.isLocked(e)) &&
            (q.isEmpty || e.title.localizedCaseInsensitiveContains(q) || (!e.locked_hidden && e.content.localizedCaseInsensitiveContains(q)))
        }
    }
    /// [(yyyy-MM, [(yyyy-MM-dd, 那天的几篇)])]，新的在上面
    private var months: [(String, [(String, [RemoteDiary])])] {
        var monthOrder: [String] = [], days: [String: [String]] = [:], byDay: [String: [RemoteDiary]] = [:]
        for e in shown {
            let d = String(e.created_at.prefix(10)), m = String(e.created_at.prefix(7))
            if days[m] == nil { monthOrder.append(m) }
            if byDay[d] == nil { days[m, default: []].append(d) }
            byDay[d, default: []].append(e)
        }
        return monthOrder.map { m in (m, (days[m] ?? []).map { ($0, byDay[$0] ?? []) }) }
    }
    static func isLocked(_ e: RemoteDiary) -> Bool { e.locked_hidden || ((e.locked ?? 0) == 1 && (e.revealed ?? 0) == 0) }
    static func wasUnlocked(_ e: RemoteDiary) -> Bool { (e.locked ?? 0) == 1 && (e.revealed ?? 0) == 1 }

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        header
                        tabSwitch
                        if tab == .night {
                            NightPane(store: night)
                        } else if tab == .drawer {
                            KeDrawerPage(line: line, onClose: {}, embedded: true)
                        } else if tab == .favorites {
                            FavoritesPane(line: line)
                        } else {
                            controls(proxy)
                            if loading && entries.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(40) }
                            if failed { Button("日记暂时没接上，点这里再试一次") { Task { await load() } }.font(Ink.song(14)).padding(.top, 20) }
                            if !loading && !failed && shown.isEmpty {
                                Text(onlyLocked ? "没有锁着的了。" : (query.isEmpty ? "柯还没有写日记。" : "没搜到「\(query)」"))
                                    .font(Ink.song(14)).foregroundStyle(Ink.secondary).frame(maxWidth: .infinity).padding(.vertical, 30)
                            }
                            ForEach(months, id: \.0) { month, days in
                                Section {
                                    ForEach(days, id: \.0) { day, list in dayBlock(day, list).id(day) }
                                } header: {
                                    // 往下翻的时候这一行贴在顶上：翻到九月就显示九月
                                    Text(Self.monthTitle(month)).font(Ink.latin(17)).tracking(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 10)
                                        .background(paper.opacity(0.97))
                                        .id(month)
                                }
                            }
                            if !entries.isEmpty {
                                Text("— 继续往下，翻看更早的日子 —").font(Ink.song(11.5)).foregroundStyle(Ink.secondary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 26)
                            }
                        }
                    }
                    .padding(.horizontal, 26)
                }
                .scrollIndicators(.hidden)
                // 128：「夜里日记」卡点进来：那一条拉回来了就展开、滚到顶上（只做一次）
                .task(id: night.entries.contains { $0.id == openingNightID }) {
                    guard let id = openingNightID, !nightOpened, night.entry(id) != nil else { return }
                    nightOpened = true
                    night.expanded.insert(id)
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    proxy.scrollTo(NightPane.anchor(id), anchor: .top)
                }
                .sheet(isPresented: $pickingDate) {
                    NavigationStack {
                        DatePicker("跳到哪一天", selection: $jumpDate, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.graphical).padding()
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("去这天") {
                                        pickingDate = false
                                        let key = Self.key(jumpDate)
                                        let target = months.flatMap { $0.1.map(\.0) }.first { $0 <= key }
                                        if let target { withAnimation { proxy.scrollTo(target, anchor: .top) } }
                                    }
                                }
                            }
                    }
                    .presentationDetents([.medium, .large])
                    .tint(Ink.accent)
                }
            }
            if let entry = reading {
                // 点开直接打开，不要翻页动画
                DiaryPage(entry: entry, sameDay: entries.filter { $0.id != entry.id && $0.created_at.prefix(10) == entry.created_at.prefix(10) },
                          paper: paper,
                          onBack: { reading = nil }, onOpen: { other in reading = other })
                    .id(entry.id)
                    // 118：读一篇时从左边缘右划，先回目录（搜索词和翻到的位置都还在），再划一次才合上日记
                    .swipeBackLayer { reading = nil }
                    .zIndex(1)
            } else if openingID != nil && !openingDone {
                // 120：刚开的锁，等新的拉回来再翻开，不先闪一下目录
                VStack(spacing: 10) {
                    HStack {
                        Button(action: onClose) {
                            Image(systemName: "chevron.left").font(.system(size: 20, weight: .light))
                                .frame(width: 44, height: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain).accessibilityLabel("返回")
                        Spacer()
                    }
                    .padding(.horizontal, 26).padding(.top, 6)
                    Spacer()
                    ProgressView().tint(Ink.secondary)
                    Text("正在翻开这一篇…").font(Ink.song(14)).foregroundStyle(Ink.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(paper.ignoresSafeArea())
                .zIndex(1)
            }
        }
        .foregroundStyle(Ink.primary)
        .task { await load() }
        // 123：切到「夜里」（或者一进来就是夜里）悄悄拉一遍。不用 .task(id:)：切走时会把拉到一半的取消掉
        .onAppear { if tab == .night { refreshNight() } }
        .onChange(of: tab) { _, now in if now == .night { refreshNight() } }
    }

    /// 123：标题下面一行「日记｜夜里」，居中
    private var tabSwitch: some View {
        InkTabSwitch(options: DiaryTab.allCases,
                     selection: Binding(get: { tab }, set: { leftPin = true; savedTab = $0.rawValue }),
                     label: \.label, identifier: { "diary-tab-\($0.rawValue)" },
                     accessibilityName: "日记、夜里、抽屉或收藏")
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private func refreshNight() {
        Task { await night.start(APIClient(baseURL: line.apiBaseURL), key: line.apiBaseURL.absoluteString) }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 0) {
                Text("日记").font(Ink.song(20)).tracking(4)
                Text("Diary").font(Ink.script(18)).foregroundStyle(Ink.secondary).padding(.top, -4)
            }
            HStack {
                Button(action: onClose) { Image(systemName: "chevron.left").font(.system(size: 20, weight: .light)).frame(width: 44, height: 44, alignment: .leading) }
                    .accessibilityLabel("返回").accessibilityIdentifier("diary-close")
                Spacer()
            }
        }
        .padding(.top, 6)
    }

    private func controls(_ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 12) {
            HStack {
                Menu {
                    ForEach(months, id: \.0) { m in Button(Self.monthTitle(m.0)) { withAnimation { proxy.scrollTo(m.0, anchor: .top) } } }
                } label: {
                    HStack(spacing: 6) { Text("跳到月份").font(Ink.song(15)); Image(systemName: "chevron.down").font(.system(size: 11)) }
                        .foregroundStyle(Ink.primary).frame(minHeight: 44)
                }
                Spacer()
                if lockedCount > 0 || onlyLocked {
                    Button { onlyLocked.toggle() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "lock").font(.system(size: 12))
                            Text(onlyLocked ? "看全部" : "锁着 \(lockedCount) 篇").font(Ink.song(13))
                        }
                        .padding(.horizontal, 12).frame(minHeight: 32)
                        .background(Capsule().fill(onlyLocked ? Ink.meFill : Ink.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain).foregroundStyle(onlyLocked ? Ink.meText : Ink.secondary)
                    .accessibilityIdentifier("diary-only-locked")
                }
                Button { jumpDate = Date(); pickingDate = true } label: {
                    Image(systemName: "calendar").font(.system(size: 20, weight: .light)).frame(width: 44, height: 44)
                }.accessibilityLabel("跳到某一天")
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Ink.secondary)
                TextField("搜索标题或正文", text: $query).font(Ink.song(15)).submitLabel(.search)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.line) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).frame(minHeight: 42)
            .background(Capsule().fill(Ink.primary.opacity(0.06)))
        }
        .padding(.top, 10).padding(.bottom, 4)
    }

    /// 一天一整块：左边日子只写一次；右边每篇一样高，篇与篇之间一条短线；两天之间一条通栏线
    private func dayBlock(_ day: String, _ list: [RemoteDiary]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 2) {
                Text(Self.dayNumber(day)).font(Ink.latin(30)).monospacedDigit()
                Text(Self.weekday(day)).font(Ink.song(12)).foregroundStyle(Ink.secondary)
            }
            .frame(width: 54, height: Self.rowHeight, alignment: .center)
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, e in
                    if i > 0 { Rectangle().fill(Ink.line.opacity(0.4)).frame(height: 0.5).padding(.leading, 14) }
                    row(e)
                }
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.line.opacity(0.7)).frame(height: 0.7) }
    }

    private func row(_ e: RemoteDiary) -> some View {
        let locked = Self.isLocked(e), opened = Self.wasUnlocked(e)
        return Button { reading = e } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        if locked { Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(Ink.meText) }
                        else if opened { Image(systemName: "lock.open").font(.system(size: 11)).foregroundStyle(Ink.secondary) }
                        Text(e.title.isEmpty ? "这一页" : e.title).font(Ink.song(17)).lineLimit(1)
                            .foregroundStyle(locked ? Ink.secondary : Ink.primary)
                    }
                    HStack(spacing: 6) {
                        Text("\(Self.time(e.created_at)) · 柯记的").font(Ink.latin(12)).foregroundStyle(Ink.secondary)
                        if locked { tag("锁着", fg: Ink.meText, bg: Ink.meFill) }
                        else if opened { tag("解锁了", fg: Ink.keText, bg: Ink.keFill) }
                    }
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .light)).foregroundStyle(Ink.secondary)
            }
            .padding(.leading, 14)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(e.title)，\(Self.time(e.created_at))\(locked ? "，锁着" : opened ? "，解锁了" : "")")
    }

    private func tag(_ text: String, fg: Color, bg: Color) -> some View {
        Text(text).font(.system(size: 10.5)).padding(.horizontal, 6).padding(.vertical, 1)
            .foregroundStyle(fg).background(Capsule().fill(bg))
    }

    /// 107：她说每次点开都转圈。看过一次就记住，再点开先摆上次的，后台悄悄更新。
    @MainActor static var cache: [RemoteDiary] = []
    private func load() async {
        if !Self.cache.isEmpty { entries = Self.cache; loading = false }
        else { loading = true }
        // 120：要翻开的那篇在记住的那份里已经能看，就先翻开；还锁着（多半是旧的）就等新的
        if let id = openingID, !opened, let cached = entries.first(where: { $0.id == id }), !Self.isLocked(cached) {
            reading = cached; opened = true; openingDone = true
        }
        failed = false
        defer { loading = false }
        do {
            entries = try await Self.fetchKeEntries(line: line)
        } catch { if entries.isEmpty { failed = true } }
        // 还没翻开就翻开；正翻着这一篇就换成新拉回来的；她已经退回目录就不再拽回去
        if let id = openingID, let entry = entries.first(where: { $0.id == id }), !opened || reading?.id == id {
            reading = entry; opened = true
        }
        openingDone = true
    }
    /// 120：聊天里「锁着的日记」也用这一份：只要柯写的、不要梦，新的在上面；拉到就记进 cache。
    @MainActor static func fetchKeEntries(line: ChatLine) async throws -> [RemoteDiary] {
        let rows = try await APIClient(baseURL: line.apiBaseURL).fetchDiaries(query: "", offset: 0, limit: 500)
        let ke: Set<String> = ["柯", "ke", "ai", "assistant"]
        let entries = rows.filter { $0.kind != "dream" && ke.contains($0.author ?? "柯") }.sorted { ($0.created_at, $0.id) > ($1.created_at, $1.id) }
        cache = entries
        return entries
    }
    /// 120：「去找柯要」替她说的那句。日记里的按钮和聊天里的「锁着的日记」用同一句；
    /// 没有标题的那篇说日子，不说「」。
    static func askMessage(for entry: RemoteDiary) -> String {
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return "爸比，你\(shortDate(entry.created_at))那篇日记，能给我看看吗" }
        return "爸比，你那篇「\(entry.title)」的日记，能给我看看吗"
    }
    /// 「10月12日」；不是今年的写上年份
    static func shortDate(_ at: String) -> String {
        let p = at.prefix(10).split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]) else { return String(at.prefix(10)) }
        let thisYear = String(Calendar(identifier: .gregorian).component(.year, from: Date()))
        return (p[0] == thisYear ? "" : "\(p[0])年") + "\(m)月\(d)日"
    }

    static func key(_ d: Date) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
    static func monthTitle(_ ym: String) -> String {
        let p = ym.split(separator: "-")
        guard p.count >= 2, let m = Int(p[1]) else { return ym }
        return "\(p[0])年\(m)月"
    }
    static func dayNumber(_ day: String) -> String { String(day.suffix(2)) }
    static func weekday(_ day: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: day) else { return "" }
        return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][Calendar(identifier: .gregorian).component(.weekday, from: d) - 1]
    }
    static func time(_ at: String) -> String { at.count >= 16 ? String(at.dropFirst(11).prefix(5)) : "" }
}

/// 点开的一篇
private struct DiaryPage: View {
    let entry: RemoteDiary
    let sameDay: [RemoteDiary]
    let paper: Color
    var onBack: () -> Void
    var onOpen: (RemoteDiary) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onBack) {
                    HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 18, weight: .light)); Text("目录").font(Ink.song(16)) }
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain).accessibilityIdentifier("diary-back")
                Text(Self.dateLine(entry.created_at)).font(Ink.song(13)).foregroundStyle(Ink.secondary).padding(.top, 14)
                Text(entry.title.isEmpty ? "这一页" : entry.title).font(Ink.song(28)).lineSpacing(6).padding(.top, 10)
                Text("柯记的 · \(KeDiaryListView.time(entry.created_at))").font(Ink.latin(13)).foregroundStyle(Ink.secondary).padding(.top, 10)
                Rectangle().fill(Ink.line.opacity(0.6)).frame(height: 0.7).padding(.vertical, 20)
                if entry.locked_hidden {
                    VStack(spacing: 14) {
                        Image(systemName: "lock").font(.system(size: 26, weight: .light)).foregroundStyle(Ink.secondary)
                        Text("这一页柯还锁着。").font(Ink.song(16))
                        Button {
                            NotificationCenter.default.post(name: .tarotReadingRequest, object: KeDiaryListView.askMessage(for: entry))
                        } label: {
                            Text("去找柯要").font(Ink.song(14)).padding(.horizontal, 16).frame(minHeight: 38)
                                .overlay(Capsule().stroke(Ink.line, lineWidth: 0.8))
                        }.buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
                } else {
                    Text(entry.content).font(Ink.song(16.5)).lineSpacing(11).textSelection(.enabled)
                }
                if let other = sameDay.first {
                    VStack(alignment: .leading, spacing: 8) {
                        Rectangle().fill(Ink.line.opacity(0.6)).frame(height: 0.7).padding(.bottom, 10)
                        Text("同一天的另一篇").font(Ink.song(12.5)).foregroundStyle(Ink.secondary)
                        Button { onOpen(other) } label: {
                            HStack {
                                Text(other.title.isEmpty ? "这一页" : other.title).font(Ink.song(17))
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .light))
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    .padding(.top, 30)
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(paper.ignoresSafeArea())
        .foregroundStyle(Ink.primary)
    }

    static func dateLine(_ at: String) -> String {
        let day = String(at.prefix(10)), p = day.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]) else { return day }
        let w = KeDiaryListView.weekday(day).replacingOccurrences(of: "周", with: "星期")
        return "\(p[0])年\(m)月\(d)日 · \(w)"
    }
}

// MARK: - 收藏（1120 她：「今天和柯玩的游戏……那些对话我想原样保存，能不能做个收藏放在日记里面，专门搞个 tab」）
// 服务器把那一段原样另抄一份（ke_favorites.py），聊天以后怎么折叠都不碍事。新建：挑一天 → 点开头那句、再点结尾那句 → 起个名。

struct FavoritesPane: View {
    let line: ChatLine
    @State private var items: [FavoriteSummary] = FavoritesPane.cache
    @State private var loading = FavoritesPane.cache.isEmpty
    @State private var failed = false
    @State private var reading: FavoriteSummary?
    @State private var making = false
    /// 1122 一键收藏今天：柯在挑的时候显示一行字，挑完说收了哪几段
    @State private var autoLine: String?
    @State private var autoRunning = false
    @AppStorage(CamelliaPalette.storageKey) private var savedPalette = CamelliaPalette.defaultPalette.rawValue
    @MainActor static var cache: [FavoriteSummary] = []
    private var paper: Color { CamelliaPalette.resolve(savedPalette).paper }

    /// 按分类分组；分类按最近收的排前面，没分类的放最后
    private var groups: [(name: String, items: [FavoriteSummary])] {
        var order: [String] = []
        var bucket: [String: [FavoriteSummary]] = [:]
        for item in items {
            let name = (item.category ?? "").trimmingCharacters(in: .whitespaces)
            if bucket[name] == nil { order.append(name) }
            bucket[name, default: []].append(item)
        }
        order = order.filter { !$0.isEmpty } + order.filter { $0.isEmpty }
        return order.map { ($0, bucket[$0] ?? []) }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Text(items.isEmpty ? "" : "\(items.count) 段").font(Ink.song(12)).foregroundStyle(Ink.secondary)
                Spacer()
                Button { Task { await autoToday() } } label: {
                    Label(autoRunning ? "柯在挑…" : "一键收藏今天", systemImage: "sparkles").font(Ink.song(13.5))
                }
                .disabled(autoRunning)
                .accessibilityIdentifier("favorites-auto-today")
                Button { making = true } label: {
                    Label("收藏一段", systemImage: "plus").font(Ink.song(13.5))
                }
                .accessibilityIdentifier("favorites-new")
            }
            .foregroundStyle(Ink.accent)
            .padding(.vertical, 12)
            if let autoLine {
                Text(autoLine).font(Ink.song(12.5)).foregroundStyle(Ink.secondary)
                    .padding(.bottom, 8)
            }
            if loading && items.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(40) }
            if failed {
                Button("收藏暂时没接上，点这里再试一次") { Task { await load() } }
                    .font(Ink.song(14)).padding(.top, 20)
            }
            if !loading && !failed && items.isEmpty {
                Text("还没有收藏。点「一键收藏今天」让柯把今天的聊天分段收好，或者点「收藏一段」自己挑开头结尾。")
                    .font(Ink.song(14)).foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
            }
            ForEach(groups, id: \.name) { group in
                if groups.count > 1 || !group.name.isEmpty {
                    Text(group.name.isEmpty ? "没分类" : group.name)
                        .font(Ink.song(13)).foregroundStyle(Ink.secondary)
                        .padding(.top, 16).padding(.bottom, 2)
                }
                ForEach(group.items) { item in
                    Button { reading = item } label: { row(item) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("favorite-\(item.id)")
                    Rectangle().fill(Ink.line).frame(height: 0.5)
                }
            }
        }
        .foregroundStyle(Ink.primary)
        .task { await load() }
        .sheet(item: $reading) { summary in
            FavoriteReader(line: line, summary: summary) { Task { await load() } }
                .presentationBackground(paper)
        }
        .sheet(isPresented: $making) {
            FavoriteMaker(line: line, onSaved: { Task { await load() } },
                          onAuto: { day in Task { await autoDay(day) } })
                .presentationBackground(paper)
        }
    }

    private func row(_ item: FavoriteSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.title).font(Ink.song(16)).lineLimit(1)
            HStack(spacing: 8) {
                Text(Self.when(item.first_at)).font(Ink.song(12))
                Text("\(item.count) 句").font(Ink.song(12))
                if item.by == "ke" { Text("柯挑的").font(Ink.song(11.5)).foregroundStyle(Ink.accent) }
            }
            .foregroundStyle(Ink.secondary)
            if let preview = item.preview, !preview.isEmpty {
                Text(preview).font(Ink.song(13)).foregroundStyle(Ink.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    /// "2026-11-20 17:00:50" → "11月20日 17:00"
    static func when(_ at: String?) -> String {
        guard let at, at.count >= 16 else { return "" }
        let m = Int(at.dropFirst(5).prefix(2)) ?? 0, d = Int(at.dropFirst(8).prefix(2)) ?? 0
        return "\(m)月\(d)日 \(at.dropFirst(11).prefix(5))"
    }

    private func load() async {
        do {
            let list = try await APIClient(baseURL: line.apiBaseURL).favorites()
            items = list
            FavoritesPane.cache = list
            failed = false
        } catch {
            failed = items.isEmpty
        }
        loading = false
    }

    private func autoToday() async {
        await autoDay(FavoriteMaker.dayFormat.string(from: Date()))
    }

    /// 让柯把那天的聊天切段收藏：服务器后台跑，这里每 4 秒问一次，最多等 4 分钟
    private func autoDay(_ day: String) async {
        guard !autoRunning else { return }
        autoRunning = true
        defer { autoRunning = false }
        let label = day == FavoriteMaker.dayFormat.string(from: Date()) ? "今天" : Self.when(day + " 00:00").components(separatedBy: " ").first ?? day
        autoLine = "柯在翻\(label)的聊天，挑值得留的段落，一两分钟……"
        let api = APIClient(baseURL: line.apiBaseURL)
        do {
            var status = try await api.startAutoFavorite(date: day)
            var waited = 0
            while status.state == "running" && waited < 240 {
                try await Task.sleep(nanoseconds: 4_000_000_000)
                waited += 4
                status = try await api.autoFavoriteStatus(date: day)
            }
            switch status.state {
            case "done":
                let titles = status.titles ?? []
                autoLine = titles.isEmpty ? "\(label)收过的都在了，柯没挑出新的段落。"
                    : "柯收了 \(titles.count) 段：" + titles.map { "「\($0)」" }.joined(separator: "")
                await load()
            case "error":
                autoLine = "柯这回没挑成（\(status.error ?? "不知道哪儿卡了")），等会儿再点一次。"
            default:
                autoLine = "柯还在挑，过一会儿下拉刷新看看。"
            }
        } catch {
            autoLine = "没连上，等会儿再点一次「一键收藏今天」。"
        }
    }
}

/// 点开一段收藏：原样的对话，她在右、柯在左；柯那一条有小心思的，点一下展开。
struct FavoriteReader: View {
    let line: ChatLine
    let summary: FavoriteSummary
    var onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var item: FavoriteItem?
    @State private var failed = false
    @State private var openNotes: Set<Int> = []
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var confirmDelete = false
    @State private var recategorizing = false
    @State private var newCategory = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Button("关上") { dismiss() }
                Spacer()
                Button("改名") { newTitle = item?.title ?? summary.title; renaming = true }
                Button("分类") { newCategory = summary.category ?? ""; recategorizing = true }
                Button("删掉", role: .destructive) { confirmDelete = true }
            }
            .font(Ink.song(14))
            .foregroundStyle(Ink.accent)
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Text(item?.title ?? summary.title).font(Ink.song(20)).padding(.bottom, 2)
                    HStack(spacing: 8) {
                        Text(FavoritesPane.when(summary.first_at))
                        if let c = shownCategory, !c.isEmpty { Text("· " + c) }
                        if summary.by == "ke" { Text("· 柯挑的") }
                    }
                    .font(Ink.song(12)).foregroundStyle(Ink.secondary)
                    if let note = item?.note, !note.isEmpty {
                        Text(note).font(Ink.song(13)).foregroundStyle(Ink.secondary).padding(.top, 2)
                    }
                    Rectangle().fill(Ink.line).frame(height: 0.5).padding(.vertical, 6)
                    if item == nil && !failed { ProgressView().frame(maxWidth: .infinity).padding(40) }
                    if failed { Text("这段没取回来，等会儿再点开看看。").font(Ink.song(14)).foregroundStyle(Ink.secondary) }
                    ForEach(item?.messages ?? []) { message in bubble(message) }
                }
                .padding(.horizontal, 22).padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(Ink.primary)
        .task { await load() }
        .alert("改个名字", isPresented: $renaming) {
            TextField("名字", text: $newTitle)
            Button("好") { Task { await rename() } }
            Button("算了", role: .cancel) {}
        }
        .alert("放进哪一类", isPresented: $recategorizing) {
            TextField("比如：游戏、谈心、看病", text: $newCategory)
            Button("好") { Task { await recategorize() } }
            Button("算了", role: .cancel) {}
        }
        .confirmationDialog("这段收藏删掉以后找不回来（聊天记录里原来那几句不受影响）。", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("删掉这段收藏", role: .destructive) { Task { await remove() } }
        }
    }

    private func bubble(_ m: FavoriteMessage) -> some View {
        let mine = m.author == "her"
        return VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
            Text(m.text)
                .font(Ink.song(15))
                .foregroundStyle(mine ? Ink.meText : Ink.keText)
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(mine ? Ink.meFill : Ink.keFill))
                .textSelection(.enabled)
            if !mine, let note = m.note, !note.isEmpty {
                if openNotes.contains(m.id) {
                    Text(note).font(Ink.song(12.5)).foregroundStyle(Ink.secondary)
                        .padding(.horizontal, 6)
                        .onTapGesture { openNotes.remove(m.id) }
                } else {
                    Button("小心思") { openNotes.insert(m.id) }
                        .font(Ink.song(11.5)).foregroundStyle(Ink.secondary)
                }
            }
            Text(String(m.at.dropFirst(11).prefix(5))).font(Ink.song(10.5)).foregroundStyle(Ink.secondary)
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .padding(mine ? Edge.Set.leading : Edge.Set.trailing, 40)
    }

    private func load() async {
        do { item = try await APIClient(baseURL: line.apiBaseURL).favorite(id: summary.id) } catch { failed = true }
    }

    private func rename() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        try? await APIClient(baseURL: line.apiBaseURL).renameFavorite(id: summary.id, title: title)
        await load()
        onChanged()
    }

    @State private var changedCategory: String?
    private var shownCategory: String? { changedCategory ?? summary.category }

    private func recategorize() async {
        let category = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        try? await APIClient(baseURL: line.apiBaseURL).recategorizeFavorite(id: summary.id, category: category)
        changedCategory = category
        onChanged()
    }

    private func remove() async {
        try? await APIClient(baseURL: line.apiBaseURL).deleteFavorite(id: summary.id)
        onChanged()
        dismiss()
    }
}

/// 新建收藏：挑一天 → 点开头那句 → 点结尾那句 → 起个名 → 收好。
struct FavoriteMaker: View {
    let line: ChatLine
    var onSaved: () -> Void
    /// 1122 不想自己点开头结尾：这一天交给柯挑（关掉这页，收藏栏那儿显示进度）
    var onAuto: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var day = Date()
    @State private var messages: [FavoriteMessage] = []
    @State private var loading = false
    @State private var startID: Int?
    @State private var endID: Int?
    @State private var title = ""
    @State private var saving = false
    @State private var errorText: String?
    @State private var category = ""
    @State private var categories: [String] = []

    static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private var range: ClosedRange<Int>? {
        guard let a = startID else { return nil }
        let b = endID ?? a
        return min(a, b)...max(a, b)
    }
    private var hint: String {
        if startID == nil { return "点一下开头那句" }
        if endID == nil { return "再点一下结尾那句" }
        return "选好了，起个名字就能收好（点别的句子可以重选）"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("算了") { dismiss() }
                Spacer()
                Button(saving ? "收着…" : "收好") { Task { await save() } }
                    .disabled(range == nil || saving)
                    .accessibilityIdentifier("favorite-save")
            }
            .font(Ink.song(14))
            .foregroundStyle(Ink.accent)
            .padding(.horizontal, 22).padding(.top, 18)
            VStack(alignment: .leading, spacing: 10) {
                DatePicker("哪一天", selection: $day, in: ...Date(), displayedComponents: .date)
                    .font(Ink.song(14))
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                TextField("名字（不填就用日子和时间）", text: $title)
                    .font(Ink.song(15))
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(Ink.line).frame(height: 0.5) }
                TextField("分类（可以不填）", text: $category)
                    .font(Ink.song(15))
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(Ink.line).frame(height: 0.5) }
                if !categories.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(categories, id: \.self) { c in
                                Button(c) { category = c }
                                    .font(Ink.song(12.5))
                                    .foregroundStyle(category == c ? Ink.accent : Ink.secondary)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().stroke(category == c ? Ink.accent : Ink.line, lineWidth: 0.8))
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                Button {
                    onAuto(Self.dayFormat.string(from: day))
                    dismiss()
                } label: {
                    Label("懒得挑？这一天交给柯分段收", systemImage: "sparkles").font(Ink.song(13))
                }
                .foregroundStyle(Ink.accent)
                .disabled(messages.isEmpty)
                .accessibilityIdentifier("favorite-auto-day")
                Text(errorText ?? hint).font(Ink.song(12.5))
                    .foregroundStyle(errorText == nil ? Ink.secondary : Ink.negative)
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if loading { ProgressView().frame(maxWidth: .infinity).padding(30) }
                    if !loading && messages.isEmpty {
                        Text("这一天没有聊天。").font(Ink.song(14)).foregroundStyle(Ink.secondary)
                            .frame(maxWidth: .infinity).padding(30)
                    }
                    ForEach(messages) { m in pickRow(m) }
                }
                .padding(.horizontal, 22).padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(Ink.primary)
        .task(id: Self.dayFormat.string(from: day)) { await load() }
        .task { categories = (try? await APIClient(baseURL: line.apiBaseURL).favoriteCategories()) ?? [] }
    }

    private func pickRow(_ m: FavoriteMessage) -> some View {
        let mine = m.author == "her"
        let picked = range?.contains(m.id) ?? false
        let edge = m.id == startID || m.id == endID
        return Button {
            if startID == nil || endID != nil { startID = m.id; endID = nil } else { endID = m.id }
            errorText = nil
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text(String(m.at.dropFirst(11).prefix(5))).font(Ink.song(11)).foregroundStyle(Ink.secondary)
                    .frame(width: 38, alignment: .leading)
                Text((mine ? "她　" : "柯　") + m.text)
                    .font(Ink.song(14))
                    .foregroundStyle(mine ? Ink.meText : Ink.keText)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(picked ? Ink.accent.opacity(edge ? 0.18 : 0.08) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        loading = true
        startID = nil; endID = nil
        do { messages = try await APIClient(baseURL: line.apiBaseURL).favoriteDay(Self.dayFormat.string(from: day)) }
        catch { messages = []; errorText = "这一天的聊天没取回来，等会儿再试" }
        loading = false
    }

    private func save() async {
        guard let range else { return }
        saving = true
        defer { saving = false }
        do {
            try await APIClient(baseURL: line.apiBaseURL).addFavorite(
                fromID: range.lowerBound, toID: range.upperBound,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category.trimmingCharacters(in: .whitespacesAndNewlines))
            onSaved()
            dismiss()
        } catch {
            errorText = "没收好，再点一次「收好」试试"
        }
    }
}
