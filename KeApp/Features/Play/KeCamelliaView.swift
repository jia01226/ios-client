import SwiftUI
import UIKit

// 98：「柯的」六个入口：日记、梦、抽屉、塔罗、朋友圈、记忆。140 起是半朵山茶，见下面 KeSpaceView。

enum CamelliaEntry: String, CaseIterable, Identifiable {
    case diary, dream, drawer, tarot, moments, memory
    var id: String { rawValue }
    var label: String {
        switch self {
        case .diary: "日记"
        case .dream: "梦"
        case .drawer: "抽屉"
        case .tarot: "塔罗"
        case .moments: "朋友圈"
        case .memory: "记忆"
        }
    }
    var english: String {
        switch self {
        case .diary: "Dear diary"
        case .dream: "In dreams"
        case .drawer: "Kept close"
        case .tarot: "Written in stars"
        case .moments: "Little moments"
        case .memory: "To remember"
        }
    }
    var tagline: String {
        switch self {
        case .diary: "把今天，慢慢写给你。"
        case .dream: "昨晚的梦里，也有你。"
        case .drawer: "悄悄收好的小小珍藏。"
        case .tarot: "抽一张，和你慢慢聊。"
        case .moments: "一些想和你分享的小事。"
        case .memory: "你说过的话，我记着。"
        }
    }
    var action: String {
        switch self {
        case .diary: "翻开日记"
        case .dream: "走进梦里"
        case .drawer: "打开抽屉"
        case .tarot: "进入塔罗"
        case .moments: "看看动态"
        case .memory: "翻阅记忆"
        }
    }
}

// MARK: - 柯留下的东西

struct CamelliaEvent: Equatable {
    let entry: CamelliaEntry
    let at: String          // 服务器时间字符串（yyyy-MM-dd HH:mm…），能直接比大小
    let title: String
    let excerpt: String
}

@MainActor final class KeCamelliaStore: ObservableObject {
    /// 137：每条线路一份（连同朋友圈那份、同一个 APIClient）。切回来先画上次那条，再在后台刷新。
    private static var all: [String: (camellia: KeCamelliaStore, moments: MomentsStore)] = [:]
    static func shared(_ line: ChatLine) -> (camellia: KeCamelliaStore, moments: MomentsStore) {
        if let stores = all[line.rawValue] { return stores }
        let api = APIClient(baseURL: line.apiBaseURL)
        let stores = (camellia: KeCamelliaStore(api: api), moments: MomentsStore(api: api, scope: line.rawValue))
        all[line.rawValue] = stores
        return stores
    }

    @Published private(set) var latest: [CamelliaEntry: CamelliaEvent] = [:]
    @Published private(set) var loaded = false
    private let api: APIClient
    private let defaults = UserDefaults.standard
    private var loading: Task<Void, Never>?
    private var lastLoad: Date?
    init(api: APIClient) { self.api = api }

    /// 137：拉一遍放在不跟着页面走的 Task 里：拉到一半切走了也拉完，不会被取消成「什么都没有」。
    /// onlyIfStale（回前台）：5 分钟内四样都拉到过，就不再拉。
    func load(onlyIfStale: Bool = false) async {
        if let loading { await loading.value; return }
        if onlyIfStale, let lastLoad, Date().timeIntervalSince(lastLoad) < 5 * 60 { return }
        let task = Task { await self.fetch() }
        loading = task
        await task.value
        loading = nil
    }

    private func fetch() async {
        // 137：四样一起问（以前一个等一个）
        async let diaries = try? api.fetchDiaries(query: "", offset: 0, limit: 30)
        async let momentRows = try? api.fetchMoments()
        async let drawerPage = try? api.fetchDrawer()
        async let garden = try? api.memoryGarden()
        let (diaryRows, moments, drawer, page) = await (diaries, momentRows, drawerPage, garden)
        // 哪一样没接上，就留着上次的，不让那行字突然没了
        var found = latest
        let ke: Set<String> = ["柯", "ke", "ai", "assistant"]
        if let rows = diaryRows {
            found[.diary] = nil; found[.dream] = nil
            for row in rows where !row.locked_hidden && ke.contains(row.author ?? "柯") {
                let entry: CamelliaEntry = row.kind == "dream" ? .dream : .diary
                if found[entry].map({ $0.at < row.created_at }) ?? true {
                    found[entry] = CamelliaEvent(entry: entry, at: row.created_at, title: row.title, excerpt: Self.firstLine(row.content))
                }
            }
        }
        if let rows = moments {
            found[.moments] = nil
            for row in rows where row.author != "user" {
                if found[.moments].map({ $0.at < row.created_at }) ?? true {
                    found[.moments] = CamelliaEvent(entry: .moments, at: row.created_at, title: "柯的朋友圈", excerpt: Self.firstLine(row.content))
                }
            }
        }
        // 110：柯往抽屉里放了便签、小画，也算（不推送）
        if let drawer {
            found[.drawer] = nil
            for item in drawer.outside {
                let at = KeDrawerPage.when(item)
                if found[.drawer].map({ $0.at < at }) ?? true {
                    let excerpt = item.kind == "pixel" ? "画了一幅小画" : (item.visibility == "teaser" ? "锁上了一件东西" : Self.firstLine(item.content))
                    found[.drawer] = CamelliaEvent(entry: .drawer, at: at, title: item.title, excerpt: excerpt)
                }
            }
        }
        if let page {
            found[.memory] = nil
            for flower in page.flowers where flower.author == "ke" && flower.isDrawable {
                guard let at = flower.written_at else { continue }
                if found[.memory].map({ $0.at < at }) ?? true {
                    found[.memory] = CamelliaEvent(entry: .memory, at: at, title: flower.title, excerpt: Self.firstLine(flower.body))
                }
            }
        }
        latest = found
        loaded = true
        let complete = diaryRows != nil && moments != nil && drawer != nil && page != nil
        lastLoad = complete ? .now : nil
    }

    private func seenKey(_ e: CamelliaEntry) -> String { "camellia.seen." + e.rawValue }
    func isNew(_ e: CamelliaEvent) -> Bool { e.at > (defaults.string(forKey: seenKey(e.entry)) ?? "") }
    func markSeen(_ entry: CamelliaEntry) {
        guard let at = latest[entry]?.at else { return }
        defaults.set(at, forKey: seenKey(entry))
        objectWillChange.send()
    }
    /// 还没看过的里面最新的一条；都看过了，就是最新的一条。
    var current: CamelliaEvent? {
        let all = latest.values.sorted { ($0.at, $0.entry.rawValue) > ($1.at, $1.entry.rawValue) }
        return all.first(where: isNew) ?? all.first
    }
    static func firstLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        return line.count > 40 ? String(line.prefix(40)) + "…" : line
    }
}

// MARK: - 页面

/// 140：「柯的」换成半朵山茶（Design/KeHalfBloomReview，她 10-31 定的）：右边半朵大花，左边六个入口。
/// 转花只是选（松手吸到最近一档，每档 60°）；点名字花转过去、转完直接进（她：「直接点，然后花转动」）。
/// 柯留下的新东西收成下面一行字（以前的卡片），名字旁边一个小点，都是真数据，看过就没了。
/// 换之前的花枝蝴蝶在 backup/ke-camellia-before-halfbloom-1031 分支。
struct KeSpaceView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool {
        #if DEBUG
        systemReduceMotion || ProcessInfo.processInfo.arguments.contains("-ui-test-reduce-motion")
        #else
        systemReduceMotion
        #endif
    }
    @Environment(\.scenePhase) private var scenePhase
    let line: ChatLine
    var onOpenQuote: (AppQuote) -> Void
    @ObservedObject private var store: KeCamelliaStore
    @ObservedObject private var moments: MomentsStore
    @State private var open: CamelliaEntry?
    /// 123：日记是从下面那行字点开的（写的是一篇日记，就落在「日记」那一栏）
    @State private var diaryFromCard = false
    /// 记的是入口的名字，不是下标
    @AppStorage("camellia.selected") private var savedSelection = CamelliaEntry.diary.rawValue
    /// 转过的总档数（能连着转好几圈，不取模），花的角度 = 档数 × 60°
    @State private var step: Int
    @State private var rotation: Double
    @State private var lastAngle: Double?
    @GestureState private var dragging = false
    @State private var entering: Task<Void, Never>?
    /// 126：底栏浮在页面上，让出它那一截
    @Environment(\.floatingDockInset) private var dockInset

    private static let order: [CamelliaEntry] = [.diary, .dream, .moments, .memory, .drawer, .tarot]
    private static let stepAngle = 60.0
    private static func wrap(_ n: Int) -> Int { ((n % order.count) + order.count) % order.count }
    private var selected: CamelliaEntry { Self.order[Self.wrap(step)] }

    init(line: ChatLine, onOpenQuote: @escaping (AppQuote) -> Void) {
        self.line = line; self.onOpenQuote = onOpenQuote
        // 137：每条线路一份，切页不重建
        let stores = KeCamelliaStore.shared(line)
        _store = ObservedObject(wrappedValue: stores.camellia)
        _moments = ObservedObject(wrappedValue: stores.moments)
        let saved = CamelliaEntry(rawValue: UserDefaults.standard.string(forKey: "camellia.selected") ?? "") ?? .diary
        let index = Self.order.firstIndex(of: saved) ?? 0
        _step = State(initialValue: index)
        _rotation = State(initialValue: Double(index) * Self.stepAngle)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, usable = geo.size.height - dockInset
            // 花的中心在屏幕右边缘，只露半朵；窄屏、矮屏跟着缩
            let flower = min(w * 1.33, usable * 0.66, 590)
            let center = CGPoint(x: w, y: min(usable * 0.56, usable - flower * 0.44))
            ZStack(alignment: .topLeading) {
                bloom(size: flower, center: center)
                VStack(alignment: .leading, spacing: 0) {
                    Text("A world in bloom.").font(.custom("Baskerville-Italic", size: 26, relativeTo: .title))
                        .foregroundStyle(Cool.ink).accessibilityAddTraits(.isHeader)
                    Text("慢慢转，慢慢认识我。").font(Cool.song(12.5, .footnote)).tracking(1).foregroundStyle(Cool.secondary)
                        .padding(.top, 12)
                    Spacer(minLength: 14)
                    // 矮屏（SE 这种）每行收紧一点，下面那行字和「翻开」别被底栏挡住
                    ForEach(Self.order) { name($0, compact: usable < 640) }
                    Spacer(minLength: usable < 640 ? 6 : 14)
                    below
                }
                .padding(.leading, 30)
                .padding(.top, usable < 640 ? 44 : 56)
                .padding(.bottom, (usable < 640 ? 8 : 26) + dockInset)
                .frame(width: min(w * 0.62, 260), alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                Text("轻轻转动花朵").font(Cool.tiny()).tracking(1.5).foregroundStyle(Cool.faint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 24).padding(.bottom, 30 + dockInset)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .coordinateSpace(name: "bloom")
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background(Cool.paper.ignoresSafeArea())
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh(onlyIfStale: true) } } }
        .onChange(of: dragging) { _, now in if !now { settle() } }   // 手势被系统取消也算松手
        .sensoryFeedback(.selection, trigger: step)
        // 塔罗抽完交给柯、抽屉里「去找柯要」：都会回聊天，盖着的页面先收起来
        .onReceive(NotificationCenter.default.publisher(for: .tarotReadingRequest)) { _ in open = nil }
        .fullScreenCover(item: $open) { entry in
            destination(entry).environmentObject(theme)
                .swipeBackToClose { open = nil }
                // 朋友圈跟着手机系统（像微信），别的页面跟 App 的昼夜
                // 136：记忆星河、塔罗是黑夜空和深色桌布，顶上的时间电量要白字
                .preferredColorScheme(entry == .moments ? (UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light)
                                      : (entry == .memory || entry == .tarot) ? .dark : (theme.skin == .night ? .dark : .light))
        }
    }

    // MARK: 花

    private func bloom(size: CGFloat, center: CGPoint) -> some View {
        Image("KeHalfBloom").resizable().frame(width: size, height: size)   // 方形母版，不裁，绕几何中心转
            .rotationEffect(.degrees(rotation), anchor: .center)
            .contentShape(Circle())
            .onTapGesture { if lastAngle == nil { turn(to: step + 1) } }    // 点花：往前走一档，只选不进
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named("bloom"))
                    .updating($dragging) { _, state, _ in state = true }
                    .onChanged { value in
                        entering?.cancel()
                        let angle = atan2(value.location.y - center.y, value.location.x - center.x) * 180 / .pi
                        if let last = lastAngle {
                            var delta = angle - last
                            if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }   // 跨 ±180° 别跳一圈
                            rotation += delta
                            step = Int((rotation / Self.stepAngle).rounded())
                        }
                        lastAngle = angle
                    }
            )
            .position(center)
            .accessibilityHidden(true)   // VoiceOver 直接选左边六个入口，不用转
    }

    /// 松手：吸到最近一档
    private func settle() {
        lastAngle = nil
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) { rotation = Double(step) * Self.stepAngle }
        savedSelection = selected.rawValue
    }

    private func turn(to target: Int) {
        step = target
        settle()
    }

    /// 点名字：花走最短的路转过去，转完直接进；已经选中的、或者减弱动态，马上进
    private func tapName(_ entry: CamelliaEntry) {
        entering?.cancel()
        guard let index = Self.order.firstIndex(of: entry) else { return }
        let n = Self.order.count
        let diff = ((index - Self.wrap(step) + n / 2) % n + n) % n - n / 2
        let moved = diff != 0
        turn(to: step + diff)
        guard moved, !reduceMotion else { go(entry); return }
        entering = Task {
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            go(entry)
        }
    }

    // MARK: 左边

    private func name(_ entry: CamelliaEntry, compact: Bool) -> some View {
        let on = entry == selected
        let fresh = store.latest[entry].map(store.isNew) ?? false
        return Button { tapName(entry) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.label).font(Cool.song(on ? 21 : 15, on ? .title3 : .body)).tracking(on ? 3 : 2)
                        .foregroundStyle(on ? Cool.ink : Cool.secondary)
                    if on {
                        Text(entry.english).font(.custom("Baskerville-Italic", size: 12, relativeTo: .caption))
                            .tracking(0.3).foregroundStyle(Cool.faint)
                    }
                }
                if fresh { Circle().fill(Cool.mauve).frame(width: 5, height: 5).accessibilityHidden(true) }
            }
            .overlay(alignment: .leading) {
                if on { Circle().fill(Cool.heart).frame(width: 5, height: 5).offset(x: -13).accessibilityHidden(true) }
            }
            .frame(minWidth: 88, minHeight: on ? (compact ? 50 : 62) : (compact ? 44 : 48), alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.label + (fresh ? "，有新的" : ""))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("camellia-\(entry.rawValue)")
    }

    /// 他有还没看过的就写一行（以前底下那张卡片），点了直接到那里；没有就是这一格自己的话
    @ViewBuilder private var below: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let event = store.current, store.isNew(event) {
                Button { go(event.entry, fromCard: true) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline(event)).font(Cool.song(12.5, .footnote)).tracking(0.8).foregroundStyle(Cool.mauve)
                        let text = event.excerpt.isEmpty ? event.title : event.excerpt
                        if !text.isEmpty {
                            Text(text).font(Cool.tiny()).foregroundStyle(Cool.secondary).lineLimit(2)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("打开" + event.entry.label)
                .accessibilityIdentifier("camellia-card")
            } else {
                Text(selected.tagline).font(Cool.song(12.5, .footnote)).tracking(0.8).foregroundStyle(Cool.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { go(selected) } label: {
                HStack(spacing: 14) {
                    Text(selected.action).font(Cool.song(14, .subheadline)).tracking(2)
                    Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .ultraLight))
                }
                .foregroundStyle(Cool.ink).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("camellia-enter")
        }
    }

    private func headline(_ e: CamelliaEvent) -> String {
        let verb: String
        switch e.entry {
        case .diary: verb = "写下了日记"
        case .dream: verb = "记下了一个梦"
        case .moments: verb = "发了一条朋友圈"
        case .memory: verb = "记住了一件事"
        case .drawer: verb = "往抽屉里放了东西"
        case .tarot: verb = "留了一张牌"
        }
        return "柯刚刚" + verb
    }

    // MARK: 动作

    private func refresh(onlyIfStale: Bool = false) async {
        await store.load(onlyIfStale: onlyIfStale)
    }

    private func go(_ entry: CamelliaEntry, fromCard: Bool = false) {
        entering?.cancel()
        diaryFromCard = fromCard && entry == .diary
        store.markSeen(entry)
        open = entry
    }

    @ViewBuilder private func destination(_ entry: CamelliaEntry) -> some View {
        switch entry {
        case .diary: KeDiaryListView(line: line, onClose: { open = nil }, startOnDiary: diaryFromCard)
        case .drawer: KeDrawerPage(line: line) { open = nil }
        case .dream: KeDreamListView(line: line) { open = nil }
        case .moments:
            MomentsView(store: moments, line: line)
        case .tarot: TarotView(line: line)
        case .memory:
            MemoryTabView(line: line, onOpenQuote: { quote in open = nil; onOpenQuote(quote) }, onClose: { open = nil })
        }
    }
}

// MARK: - 梦

/// 柯夜里的梦（服务器上 kind = dream 的那几页）。104：按月份分组、左边大大的日子，右上角可以跳到哪个月，好找以前的梦。
struct KeDreamListView: View {
    let line: ChatLine
    var onClose: () -> Void
    @AppStorage(CamelliaPalette.storageKey) private var savedPalette = CamelliaPalette.defaultPalette.rawValue
    @State private var dreams: [RemoteDiary] = []
    @State private var loading = true
    @State private var failed = false
    @State private var reading: RemoteDiary?
    @State private var query = ""
    private var paper: Color { CamelliaPalette.resolve(savedPalette).paper }

    private var shown: [RemoteDiary] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? dreams : dreams.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.content.localizedCaseInsensitiveContains(q) }
    }
    /// [(「2026 · 十月」, 那个月的梦)]，新的月份在上面
    private var months: [(String, [RemoteDiary])] {
        var order: [String] = [], groups: [String: [RemoteDiary]] = [:]
        for d in shown {
            let key = String(d.created_at.prefix(7))
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(d)
        }
        return order.map { (Self.monthTitle($0), groups[$0] ?? []) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            // 136：不再套「我们」小本子的外壳（左上「完成」+ 左对齐大标题），换成跟日记、抽屉一样的顶：
            // 居中「梦 · Rêves」、左上一个小箭头
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Ink.secondary)
                        TextField("搜梦里的东西", text: $query).font(Ink.song(15)).submitLabel(.search)
                        if months.count > 1 {
                            Menu {
                                ForEach(months, id: \.0) { m in Button(m.0) { withAnimation { proxy.scrollTo(m.0, anchor: .top) } } }
                            } label: { Text("跳到…").font(Ink.song(13)).foregroundStyle(Ink.accent).frame(minHeight: 44) }
                        }
                    }
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.92)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Ink.line.opacity(0.45), lineWidth: 0.7))
                    Text("梦里的事，醒来第一件想告诉你。").font(Ink.song(13)).foregroundStyle(Ink.secondary)
                    if loading && dreams.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(30) }
                    if failed { Button("梦暂时没接上，点这里再试一次") { Task { await load() } }.font(Ink.song(13)) }
                    if !loading && !failed && dreams.isEmpty { Text("柯还没有记下梦。").font(Ink.song(14)) }
                    ForEach(months, id: \.0) { month, list in
                        NotebookSection(title: month, hint: "\(list.count) 个梦") {
                            VStack(spacing: 0) {
                                ForEach(list) { dream in row(dream) }
                            }
                        }
                        .id(month)
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 48)
            }
            .background(paper.ignoresSafeArea())
            .foregroundStyle(Ink.primary)
        }
        .task { await load() }
        .sheet(item: $reading) { dream in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(Self.dayLine(dream.created_at)).font(.system(size: 12)).foregroundStyle(Ink.secondary)
                        Text(dream.title).font(Ink.song(22))
                        Text(dream.content).font(Ink.song(16)).lineSpacing(9).textSelection(.enabled)
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(Ink.primary)
                .background(paper.ignoresSafeArea())
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("收好") { reading = nil } } }
            }
            .tint(Ink.accent)
        }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 0) {
                Text("梦").font(Ink.song(20)).tracking(4)
                Text("Rêves").font(Ink.script(18)).foregroundStyle(Ink.secondary).padding(.top, -4)
            }
            HStack {
                Button(action: onClose) { Image(systemName: "chevron.left").font(.system(size: 20, weight: .light)).frame(width: 44, height: 44, alignment: .leading) }
                    .accessibilityLabel("返回").accessibilityIdentifier("dream-close")
                Spacer()
            }
        }
        .padding(.top, 6)
    }

    private func row(_ dream: RemoteDiary) -> some View {
        Button { reading = dream } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 0) {
                    Text(Self.day(dream.created_at)).font(Ink.latin(26)).monospacedDigit()
                    Text(Self.weekday(dream.created_at)).font(.system(size: 11)).foregroundStyle(Ink.secondary)
                }.frame(width: 40)
                VStack(alignment: .leading, spacing: 5) {
                    Text(dream.title).font(Ink.song(16)).foregroundStyle(Ink.primary)
                    Text(dream.content).font(Ink.song(13.5)).lineSpacing(4).lineLimit(2).foregroundStyle(Ink.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12).contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Ink.line.opacity(0.5)).frame(height: 0.5) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.dayLine(dream.created_at) + "，" + dream.title)
    }

    @MainActor static var cache: [RemoteDiary] = []
    private func load() async {
        if !Self.cache.isEmpty { dreams = Self.cache; loading = false } else { loading = true }
        failed = false
        defer { loading = false }
        do {
            let rows = try await APIClient(baseURL: line.apiBaseURL).fetchDiaries(query: "", offset: 0, limit: 500)
            dreams = rows.filter { $0.kind == "dream" && !$0.locked_hidden }.sorted { $0.created_at > $1.created_at }
            Self.cache = dreams
        } catch { if dreams.isEmpty { failed = true } }
    }
    private static func monthTitle(_ ym: String) -> String {
        let parts = ym.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]) else { return ym }
        let names = ["一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月"]
        return "\(parts[0]) · \(names[max(0, min(11, m - 1))])"
    }
    private static func day(_ at: String) -> String {
        guard at.count >= 10, let d = Int(at.dropFirst(8).prefix(2)) else { return "" }
        return String(d)
    }
    private static func weekday(_ at: String) -> String {
        guard let date = CompanionDate.parse(at) else { return "" }
        return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][Calendar.current.component(.weekday, from: date) - 1]
    }
    private static func dayLine(_ at: String) -> String {
        guard let date = CompanionDate.parse(at) else { return "" }
        return KeDiaryPage.dateLabel(date, format: "M月d日") + " " + weekday(at) + " 早上醒来"
    }
}
