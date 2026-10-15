import SwiftUI
import UIKit

// 98：「柯的」一页是一枝山茶。六朵花是六个入口：日记、梦、抽屉、塔罗、朋友圈、记忆。
// 一只蝴蝶代表柯：他留了新东西（写了日记、做了梦、发了朋友圈、新记了一件事），蝴蝶就飞去停在那朵花上，
// 底下的卡片写的也是这一条——蝴蝶和卡片永远读同一条真实内容。
// 素材与坐标来自 Design/KeCamellia（GPT 交付，spec/layout.json、spec/motion.json）。画布 390×844，整体等比缩放。

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
    var flowerAsset: String {
        switch self {
        case .diary: "KeCamelliaDiary"
        case .dream: "KeCamelliaDream"
        case .drawer: "KeCamelliaDrawer"
        case .tarot: "KeCamelliaTarot"
        case .moments: "KeCamelliaMoments"
        case .memory: "KeCamelliaMemory"
        }
    }
    var tagAsset: String { "KeCamelliaTag" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    struct Spot {
        let frame: CGRect      // 花图层（含透明边）
        let hit: CGRect        // 点花的范围
        let tag: CGRect        // 挂签
        let string: (x: CGFloat, top: CGFloat, bottom: CGFloat)
        let perch: CGPoint     // 蝴蝶停在这朵花上的位置
    }
    /// 来自 spec/layout.json，全部是画布比例（0…1）
    var spot: Spot {
        switch self {
        case .diary: Spot(frame: CGRect(x: 0.6613, y: 0.0733, width: 0.2974, height: 0.1374), hit: CGRect(x: 0.70, y: 0.091, width: 0.22, height: 0.102),
                          tag: CGRect(x: 0.8086, y: 0.2302, width: 0.0821, height: 0.0806), string: (0.8496, 0.1968, 0.2338), perch: CGPoint(x: 0.745, y: 0.113))
        case .dream: Spot(frame: CGRect(x: 0.5113, y: 0.2013, width: 0.2974, height: 0.1374), hit: CGRect(x: 0.55, y: 0.219, width: 0.22, height: 0.102),
                          tag: CGRect(x: 0.6432, y: 0.3501, width: 0.0821, height: 0.0616), string: (0.6842, 0.3167, 0.3536), perch: CGPoint(x: 0.595, y: 0.241))
        case .drawer: Spot(frame: CGRect(x: 0.3162, y: 0.3319, width: 0.3077, height: 0.1422), hit: CGRect(x: 0.36, y: 0.352, width: 0.22, height: 0.102),
                           tag: CGRect(x: 0.462, y: 0.4841, width: 0.0821, height: 0.0806), string: (0.503, 0.4507, 0.4877), perch: CGPoint(x: 0.405, y: 0.374))
        case .tarot: Spot(frame: CGRect(x: 0.6864, y: 0.3956, width: 0.2872, height: 0.1327), hit: CGRect(x: 0.72, y: 0.411, width: 0.22, height: 0.102),
                          tag: CGRect(x: 0.789, y: 0.538, width: 0.0821, height: 0.0806), string: (0.83, 0.5046, 0.5416), perch: CGPoint(x: 0.765, y: 0.433))
        case .moments: Spot(frame: CGRect(x: 0.1087, y: 0.5081, width: 0.3026, height: 0.1398), hit: CGRect(x: 0.15, y: 0.527, width: 0.22, height: 0.102),
                            tag: CGRect(x: 0.219, y: 0.6479, width: 0.0821, height: 0.0995), string: (0.26, 0.6145, 0.6514), perch: CGPoint(x: 0.195, y: 0.549))
        case .memory: Spot(frame: CGRect(x: 0.1923, y: 0.2222, width: 0.2154, height: 0.0995), hit: CGRect(x: 0.19, y: 0.221, width: 0.22, height: 0.102),
                           tag: CGRect(x: 0.248, y: 0.348, width: 0.0821, height: 0.0806), string: (0.289, 0.3146, 0.3516), perch: CGPoint(x: 0.235, y: 0.243))
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
    @Published private(set) var latest: [CamelliaEntry: CamelliaEvent] = [:]
    @Published private(set) var loaded = false
    private let api: APIClient
    private let defaults = UserDefaults.standard
    init(api: APIClient) { self.api = api }

    func load() async {
        var found: [CamelliaEntry: CamelliaEvent] = [:]
        let ke: Set<String> = ["柯", "ke", "ai", "assistant"]
        if let rows = try? await api.fetchDiaries(query: "", offset: 0, limit: 30) {
            for row in rows where !row.locked_hidden && ke.contains(row.author ?? "柯") {
                let entry: CamelliaEntry = row.kind == "dream" ? .dream : .diary
                if found[entry].map({ $0.at < row.created_at }) ?? true {
                    found[entry] = CamelliaEvent(entry: entry, at: row.created_at, title: row.title, excerpt: Self.firstLine(row.content))
                }
            }
        }
        if let rows = try? await api.fetchMoments() {
            for row in rows where row.author != "user" {
                if found[.moments].map({ $0.at < row.created_at }) ?? true {
                    found[.moments] = CamelliaEvent(entry: .moments, at: row.created_at, title: "柯的朋友圈", excerpt: Self.firstLine(row.content))
                }
            }
        }
        if let page = try? await api.memoryGarden() {
            for flower in page.flowers where flower.author == "ke" && flower.isDrawable {
                guard let at = flower.written_at else { continue }
                if found[.memory].map({ $0.at < at }) ?? true {
                    found[.memory] = CamelliaEvent(entry: .memory, at: at, title: flower.title, excerpt: Self.firstLine(flower.body))
                }
            }
        }
        latest = found
        loaded = true
    }

    private func seenKey(_ e: CamelliaEntry) -> String { "camellia.seen." + e.rawValue }
    func isNew(_ e: CamelliaEvent) -> Bool { e.at > (defaults.string(forKey: seenKey(e.entry)) ?? "") }
    func markSeen(_ entry: CamelliaEntry) {
        guard let at = latest[entry]?.at else { return }
        defaults.set(at, forKey: seenKey(entry))
        objectWillChange.send()
    }
    /// 蝴蝶该去哪：还没看过的里面最新的一条；都看过了，就是最新的一条（静静停着，不再飞）。
    var current: CamelliaEvent? {
        let all = latest.values.sorted { ($0.at, $0.entry.rawValue) > ($1.at, $1.entry.rawValue) }
        return all.first(where: isNew) ?? all.first
    }
    static func firstLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        return line.count > 40 ? String(line.prefix(40)) + "…" : line
    }
}

// MARK: - 蝴蝶的飞行（只跟时间有关，画面每帧读）

final class CamelliaButterfly {
    private(set) var perch: CamelliaEntry
    private var from: CGPoint
    private var to: CGPoint
    private var start = Date.distantPast
    let duration = 3.0
    private var side: CGFloat = 1
    init(perch: CamelliaEntry) { self.perch = perch; from = perch.spot.perch; to = perch.spot.perch }

    func fly(to entry: CamelliaEntry, instantly: Bool) {
        let now = Date()
        let here = position(at: now).point
        perch = entry
        from = here; to = entry.spot.perch
        side = to.x >= from.x ? -1 : 1
        start = instantly ? .distantPast : now
    }
    var flying: Bool { Date().timeIntervalSince(start) < duration }
    /// 位置：直线插值 + 一道弧（motion.json：side*0.105*sin(πt), -0.06*sin(πt)）
    func position(at date: Date) -> (point: CGPoint, flying: Bool) {
        let raw = date.timeIntervalSince(start) / duration
        guard raw < 1 else { return (to, false) }
        let t = max(0, raw), e = t * t * (3 - 2 * t), arc = sin(Double.pi * t)
        return (CGPoint(x: from.x + (to.x - from.x) * e + side * 0.105 * arc, y: from.y + (to.y - from.y) * e - 0.06 * arc), true)
    }
}

// MARK: - 页面

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
    @StateObject private var store: KeCamelliaStore
    @StateObject private var moments: MomentsStore
    @State private var butterfly: CamelliaButterfly
    @State private var shown: CamelliaEvent?
    @State private var open: CamelliaEntry?
    @State private var pressed: CamelliaEntry?
    @State private var visible = false
    @AppStorage("camellia.perch") private var savedPerch = CamelliaEntry.diary.rawValue
    @AppStorage(CamelliaPalette.storageKey) private var savedPalette = CamelliaPalette.defaultPalette.rawValue
    private var palette: CamelliaPalette { .resolve(savedPalette) }

    private static let ink = Color(red: 0.24, green: 0.33, blue: 0.47)
    private static let muted = Color(red: 0.45, green: 0.52, blue: 0.62)

    init(line: ChatLine, onOpenQuote: @escaping (AppQuote) -> Void) {
        self.line = line; self.onOpenQuote = onOpenQuote
        let api = APIClient(baseURL: line.apiBaseURL)
        _store = StateObject(wrappedValue: KeCamelliaStore(api: api))
        _moments = StateObject(wrappedValue: MomentsStore(api: api, scope: line.rawValue))
        let saved = CamelliaEntry(rawValue: UserDefaults.standard.string(forKey: "camellia.perch") ?? "") ?? .diary
        _butterfly = State(initialValue: CamelliaButterfly(perch: saved))
    }

    var body: some View {
        GeometryReader { geo in
            // 画布等比缩放：宽度铺满；太高就按高度缩（底部原本的导航那一截不用，只到卡片下沿）
            let s = min(geo.size.width / 390, geo.size.height / (844 * 0.9))
            let w = 390 * s, h = 844 * s
            ZStack(alignment: .topLeading) {
                palette.paper
                Image("KeCamelliaBackground").resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height).clipped()
                    .saturation(palette.mistSaturation).opacity(palette.mistOpacity)
                    .blendMode(.multiply)
                    .accessibilityHidden(true)
                TimelineView(.animation(minimumInterval: nil, paused: !visible || reduceMotion || scenePhase != .active)) { timeline in
                    artboard(w: w, h: h, s: s, now: timeline.date)
                }
                .frame(width: w, height: h)
                .offset(x: (geo.size.width - w) / 2)
                title(s: s).padding(.leading, 26).padding(.top, 14)
            }
        }
        .ignoresSafeArea(edges: .top)
        .task { await refresh() }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
        .sensoryFeedback(.selection, trigger: open)
        // 塔罗抽完交给柯、抽屉里「去找柯要」：都会回聊天，盖着的页面先收起来
        .onReceive(NotificationCenter.default.publisher(for: .tarotReadingRequest)) { _ in open = nil }
        .fullScreenCover(item: $open) { entry in
            destination(entry).environmentObject(theme)
                .swipeBackToClose { open = nil }
                // 朋友圈跟着手机系统（像微信），别的页面跟 App 的昼夜
                .preferredColorScheme(entry == .moments ? (UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light) : (theme.skin == .night ? .dark : .light))
        }
    }

    // MARK: 标题

    private func title(s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("柯的").font(.custom("NotoSerifSC-Regular", size: 30, relativeTo: .title)).tracking(4)
                .foregroundStyle(Self.ink)
            Text("蝴蝶停的地方，\n有我留给你的东西")
                .font(.custom("NotoSerifSC-Regular", size: 11.5, relativeTo: .caption)).tracking(1.5).lineSpacing(5)
                .foregroundStyle(Self.muted)
            Menu {
                ForEach(CamelliaPalette.allCases) { option in
                    Button {
                        savedPalette = option.rawValue
                    } label: {
                        if palette == option {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                    .accessibilityIdentifier("camellia-palette-\(option.rawValue)")
                }
            } label: {
                Label(palette.label, systemImage: "paintpalette")
                    .font(.caption)
                    .foregroundStyle(CamelliaPalette.secondaryInk)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("山茶配色")
            .accessibilityValue(palette.label)
            .accessibilityHint("选择浅雾蓝、冷白、暖白或浅米色，仅在本机保存")
            .accessibilityIdentifier("camellia-palette-picker")
        }
        .padding(.top, 50)
        .accessibilityElement(children: .contain)
    }

    // MARK: 画布

    private func artboard(w: CGFloat, h: CGFloat, s: CGFloat, now: Date) -> some View {
        let t = now.timeIntervalSinceReferenceDate
        // 花枝以右上 (0.95, 0) 为轴轻轻摆：-0.48°…0.58°，9 秒一个来回
        let sway = reduceMotion ? 0 : -0.48 + (0.58 + 0.48) * (0.5 - 0.5 * cos(t * 2 * .pi / 9))
        func r(_ rect: CGRect) -> CGRect { CGRect(x: rect.minX * w, y: rect.minY * h, width: rect.width * w, height: rect.height * h) }
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    Image("KeCamelliaStem").resizable().frame(width: w, height: 0.8318 * h).accessibilityHidden(true)
                    ForEach(CamelliaEntry.allCases) { entry in
                        let f = r(entry.spot.frame)
                        Image(entry.flowerAsset).resizable().frame(width: f.width, height: f.height)
                            .scaleEffect(pressed == entry ? 0.97 : 1)
                            .offset(x: f.minX, y: f.minY)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: w, height: h, alignment: .topLeading)
                .modifier(CamelliaSoftArtwork(scale: s))
                // 挂线和挂签画在花的前面，字不会被花挡住
                ForEach(CamelliaEntry.allCases) { entry in
                    let sp = entry.spot.string
                    Path { p in p.move(to: CGPoint(x: sp.x * w, y: sp.top * h)); p.addLine(to: CGPoint(x: sp.x * w, y: sp.bottom * h)) }
                        .stroke(Color(red: 0.44, green: 0.55, blue: 0.7).opacity(0.7), lineWidth: 0.8)
                    Circle().fill(Color(red: 0.36, green: 0.47, blue: 0.63)).frame(width: 4.5 * s, height: 4.5 * s)
                        .offset(x: sp.x * w - 2.25 * s, y: sp.top * h - 2.25 * s)
                    tag(entry, rect: r(entry.spot.tag), s: s)
                }
                butterflyView(w: w, h: h, now: now)
                // 点的范围：花和挂签都能点
                ForEach(CamelliaEntry.allCases) { entry in
                    let hit = r(entry.spot.hit), tagRect = r(entry.spot.tag)
                    tapArea(entry).frame(width: hit.width, height: hit.height).offset(x: hit.minX, y: hit.minY)
                    tapArea(entry).frame(width: max(44, tagRect.width + 16), height: max(44, tagRect.height))
                        .offset(x: tagRect.midX - max(44, tagRect.width + 16) / 2, y: tagRect.minY)
                }
            }
            .frame(width: w, height: h, alignment: .topLeading)
            .rotationEffect(.degrees(sway), anchor: UnitPoint(x: 0.95, y: 0))
            petals(w: w, h: h, now: now)
            card(w: w, h: h, s: s)
        }
        .frame(width: w, height: h, alignment: .topLeading)
    }

    private func tag(_ entry: CamelliaEntry, rect: CGRect, s: CGFloat) -> some View {
        Image(entry.tagAsset).resizable().frame(width: rect.width, height: rect.height)
            .overlay(alignment: .top) {
                VStack(spacing: 1 * s) {
                    ForEach(Array(entry.label.enumerated()), id: \.offset) { _, ch in
                        // These labels belong to fixed-size illustrated tags; their full names
                        // remain available on the independent, minimum-44pt accessible buttons.
                        Text(String(ch)).font(.custom("NotoSerifSC-Regular", fixedSize: 13.5 * s))
                    }
                }
                .foregroundStyle(Self.ink)
                .padding(.top, 12 * s)
            }
            .overlay(alignment: .topTrailing) {
                if let event = store.latest[entry], store.isNew(event) {
                    Circle().fill(Color(red: 0.42, green: 0.55, blue: 0.85)).frame(width: 6 * s, height: 6 * s).offset(x: 2 * s, y: -2 * s)
                }
            }
            .offset(x: rect.minX, y: rect.minY)
            .accessibilityHidden(true)
    }

    private func tapArea(_ entry: CamelliaEntry) -> some View {
        Button { go(entry) } label: { Color.clear.contentShape(Rectangle()) }
            .buttonStyle(CamelliaPress(entry: entry, pressed: $pressed))
            .accessibilityLabel(entry.label + ((store.latest[entry].map(store.isNew) ?? false) ? "，有新的" : ""))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("camellia-\(entry.rawValue)")
    }

    private func butterflyView(w: CGFloat, h: CGFloat, now: Date) -> some View {
        let (p, flying) = butterfly.position(at: now)
        let t = now.timeIntervalSinceReferenceDate
        let period = flying ? 0.22 : 1.9
        let phase = reduceMotion ? 0.3 : 0.5 - 0.5 * cos(t * 2 * .pi / period)
        let spread = 12 + (66 - 12) * phase
        let bw = 0.16 * w, bh = 0.0739 * h
        return ZStack {
            Image("KeCamelliaWingLeft").resizable()
                .rotation3DEffect(.degrees(spread), axis: (x: 0, y: 1, z: 0), anchor: UnitPoint(x: 0.48, y: 0.51), perspective: 0.4)
            Image("KeCamelliaWingRight").resizable()
                .rotation3DEffect(.degrees(-spread), axis: (x: 0, y: 1, z: 0), anchor: UnitPoint(x: 0.51, y: 0.51), perspective: 0.4)
            Image("KeCamelliaBody").resizable().frame(width: bw * 0.84, height: bh * 0.84)
                .offset(x: (0.08 + 0.42 - 0.5) * bw, y: (0.025 + 0.42 - 0.5) * bh)
        }
        .frame(width: bw, height: bh)
        .compositingGroup()
        .saturation(0.42).contrast(0.8).brightness(0.08).opacity(0.64)
        .rotationEffect(.degrees(-25))
        .position(x: p.x * w, y: p.y * h)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 偶尔飘一片花瓣：5.5 秒一片，11 秒落完，同时最多三片
    private func petals(w: CGFloat, h: CGFloat, now: Date) -> some View {
        let t = now.timeIntervalSinceReferenceDate
        let names = ["KeCamelliaPetal01", "KeCamelliaPetal02", "KeCamelliaPetal03"]
        let newest = Int(floor(t / 5.5))
        return ZStack(alignment: .topLeading) {
            if !reduceMotion {
                ForEach(0..<2, id: \.self) { k in
                    let n = newest - k
                    let age = (t - Double(n) * 5.5) / 11
                    var rng = GalaxyRandom(seed: UInt32(truncatingIfNeeded: n &* 2_654_435_761))
                    let x0 = 0.35 + rng.next() * 0.6, y0 = 0.02 + rng.next() * 0.25
                    let size = (0.035 + rng.next() * 0.03) * w
                    let rot = -15 + (80 + 15) * age + rng.next() * 40
                    let name = names[Int(rng.next() * 3) % 3]
                    Image(name).resizable().frame(width: size, height: size)
                        .rotationEffect(.degrees(rot))
                        .opacity(0.55 * min(1, age * 6) * min(1, (1 - age) * 4))
                        .offset(x: (x0 - 0.18 * age + 0.02 * sin(age * 9)) * w, y: (y0 + 0.65 * age) * h)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: 卡片

    private func card(w: CGFloat, h: CGFloat, s: CGFloat) -> some View {
        let fs = CGSize(width: 0.3282 * w, height: 0.1517 * h)
        let center = CGPoint(x: 0.2366 * w, y: 0.825 * h)
        return Group {
            if let event = shown {
                Button { go(event.entry) } label: {
                    HStack(alignment: .center, spacing: 0) {
                        ZStack {
                            Image(event.entry.flowerAsset).resizable().scaledToFill()
                                .frame(width: fs.width * 0.5, height: fs.width * 0.5)
                                .clipShape(Rectangle().rotation(.degrees(45)).scale(0.72))
                                .modifier(CamelliaSoftArtwork(scale: s))
                            Image("KeCamelliaDiamondFrame").resizable().frame(width: fs.width, height: fs.height)
                        }
                        .frame(width: fs.width, height: fs.height)
                        VStack(alignment: .leading, spacing: 8 * s) {
                            Text(headline(event)).font(.custom("NotoSerifSC-Regular", size: 14 * s)).tracking(2)
                                .foregroundStyle(Self.ink)
                            Rectangle().fill(Self.ink.opacity(0.5)).frame(height: 0.8)
                            Text(event.excerpt.isEmpty ? event.title : event.excerpt)
                                .font(.custom("NotoSerifSC-Regular", size: 13.5 * s)).lineLimit(2)
                                .foregroundStyle(Self.ink)
                            Text(Self.relative(event.at)).font(.custom("NotoSerifSC-Regular", size: 10.5 * s))
                                .foregroundStyle(Self.muted)
                        }
                        .multilineTextAlignment(.leading)
                        .padding(.trailing, 0.06 * w)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("打开" + event.entry.label)
                .accessibilityIdentifier("camellia-card")
                .transition(.opacity)
                .id(event.entry.rawValue + event.at)
            }
        }
        .frame(width: w * 0.92, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .position(x: center.x - fs.width / 2 + w * 0.46, y: center.y)
        .animation(.easeInOut(duration: 0.5), value: shown)
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
        return (store.isNew(e) ? "柯刚刚" : "柯最近") + verb
    }

    private static func relative(_ at: String) -> String {
        guard let date = CompanionDate.parse(at) else { return "" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN"); f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }

    // MARK: 动作

    private func refresh() async {
        await store.load()
        guard let event = store.current else { return }
        // 蝴蝶和卡片绑定同一条：落定的时候一起换
        if butterfly.perch != event.entry {
            butterfly.fly(to: event.entry, instantly: reduceMotion || !visible)
            savedPerch = event.entry.rawValue
            if !reduceMotion && visible {
                try? await Task.sleep(for: .seconds(butterfly.duration))
            }
        }
        shown = event
    }

    private func go(_ entry: CamelliaEntry) {
        store.markSeen(entry)
        if let event = store.current { shown = event }
        open = entry
    }

    @ViewBuilder private func destination(_ entry: CamelliaEntry) -> some View {
        switch entry {
        case .diary: KeDiaryDrawerView(line: line, startOnDrawer: false) { open = nil }
        case .drawer: KeDiaryDrawerView(line: line, startOnDrawer: true) { open = nil }
        case .dream: KeDreamListView(line: line) { open = nil }
        case .moments:
            MomentsView(store: moments, line: line)
        case .tarot: TarotView(line: line)
        case .memory:
            MemoryTabView(line: line, onOpenQuote: { quote in open = nil; onOpenQuote(quote) }, onClose: { open = nil })
        }
    }
}

/// 按下去花轻轻一缩
private struct CamelliaPress: ButtonStyle {
    let entry: CamelliaEntry
    @Binding var pressed: CamelliaEntry?
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, down in
                withAnimation(.easeOut(duration: 0.1)) { pressed = down ? entry : nil }
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
            NotebookShell(title: "梦", script: "Rêves", paper: paper, onClose: onClose) {
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

    private func load() async {
        loading = true; failed = false
        defer { loading = false }
        do {
            let rows = try await APIClient(baseURL: line.apiBaseURL).fetchDiaries(query: "", offset: 0, limit: 500)
            dreams = rows.filter { $0.kind == "dream" && !$0.locked_hidden }.sorted { $0.created_at > $1.created_at }
        } catch { failed = true }
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
