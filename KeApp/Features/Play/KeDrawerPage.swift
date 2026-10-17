import SwiftUI

// 110：她看了「小机的抽屉」，说柯的抽屉都没用上。改成柯随手放：便签、像素小画，放进去不推送，
// 她想起来自己翻。原来那种藏起来锁上、露一句提示等她来要的，照样留着。
// 样子跟日记一个调子：同一张纸、同一套细字。

struct KeDrawerPage: View {
    let line: ChatLine
    var onClose: () -> Void
    @AppStorage(CamelliaPalette.storageKey) private var savedPalette = CamelliaPalette.defaultPalette.rawValue
    @State private var items: [RemoteDrawer.Item] = KeDrawerPage.cache
    @State private var sealed = KeDrawerPage.cacheSealed
    @State private var loading = KeDrawerPage.cache.isEmpty
    @State private var failed = false
    @State private var zoom: RemoteDrawer.Item?
    @State private var shelf: Shelf = .all
    private var paper: Color { CamelliaPalette.resolve(savedPalette).paper }

    @MainActor static var cache: [RemoteDrawer.Item] = []
    @MainActor static var cacheSealed = false

    /// 118：照网页那版加一排筛选——全部 / 便签 / 小画 / 锁着。只在手上已经拿到的东西里挑，不另外请求。
    enum Shelf: String, CaseIterable, Identifiable {
        case all, note, pixel, locked
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "全部"
            case .note: return "便签"
            case .pixel: return "小画"
            case .locked: return "锁着"
            }
        }
        func holds(_ item: RemoteDrawer.Item) -> Bool {
            switch self {
            case .all: return true
            case .pixel: return KeDrawerPage.isPixel(item)
            case .locked: return KeDrawerPage.isLocked(item)
            // 便签：不是小画、也没锁着的（锁过后来放出来的那种也算）
            case .note: return !KeDrawerPage.isPixel(item) && !KeDrawerPage.isLocked(item)
            }
        }
    }
    static func isLocked(_ item: RemoteDrawer.Item) -> Bool { item.visibility == "teaser" }
    static func isPixel(_ item: RemoteDrawer.Item) -> Bool { item.kind == "pixel" && PixelArt(json: item.content) != nil }
    private var shown: [RemoteDrawer.Item] { items.filter(shelf.holds) }

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    header
                    if loading && items.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(40) }
                    if failed && items.isEmpty {
                        Button("抽屉暂时没打开，点这里再试一次") { Task { await load() } }
                            .font(Ink.song(14)).frame(maxWidth: .infinity).padding(.top, 20)
                    }
                    if !items.isEmpty { shelfPicker }
                    if sealed && (shelf == .all || shelf == .locked) { sealedHint }
                    if !loading && !failed && items.isEmpty {
                        Text("抽屉还空着。\n柯想到什么，会悄悄放进来。")
                            .font(Ink.song(15)).foregroundStyle(Ink.secondary).multilineTextAlignment(.center).lineSpacing(6)
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                    if !items.isEmpty && shown.isEmpty {
                        Text(shelf == .locked ? "现在没有锁着的。" : "这一格还空着。")
                            .font(Ink.song(14)).foregroundStyle(Ink.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 30)
                    }
                    ForEach(shown) { item in card(item) }
                    if !shown.isEmpty {
                        Text("— 抽屉底了 —").font(Ink.song(11.5)).foregroundStyle(Ink.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 22)
                    }
                }
                .padding(.horizontal, 22)
            }
            .scrollIndicators(.hidden)
            .refreshable { await load() }
            if let zoom, let art = PixelArt(json: zoom.content) {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { self.zoom = nil }
                    VStack(spacing: 14) {
                        PixelArtView(art: art).frame(maxWidth: 320, maxHeight: 320)
                        if !zoom.title.isEmpty { Text(zoom.title).font(Ink.song(17)) }
                        Text(Self.dateLine(zoom)).font(Ink.latin(12)).foregroundStyle(Ink.secondary)
                    }
                    .padding(24)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(paper))
                    .padding(28)
                    .onTapGesture { self.zoom = nil }
                    .accessibilityAddTraits(.isModal)
                }
                // 118：放大的小画开着时，右划先收小画，抽屉还在
                .swipeBackLayer { self.zoom = nil }
            }
        }
        .foregroundStyle(Ink.primary)
        .task { await load() }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 0) {
                Text("抽屉").font(Ink.song(20)).tracking(4)
                Text("Tiroir").font(Ink.script(18)).foregroundStyle(Ink.secondary).padding(.top, -4)
            }
            HStack {
                Button(action: onClose) { Image(systemName: "chevron.left").font(.system(size: 20, weight: .light)).frame(width: 44, height: 44, alignment: .leading) }
                    .accessibilityLabel("返回").accessibilityIdentifier("drawer-close")
                Spacer()
            }
        }
        .padding(.top, 6).padding(.bottom, 6)
    }

    /// 一排小字：选中的那格浅浅垫一块底，和日记「锁着」那颗一个调子
    private var shelfPicker: some View {
        HStack(spacing: 6) {
            ForEach(Shelf.allCases) { option in
                let on = shelf == option
                Button { shelf = option } label: {
                    Text(option.label).font(Ink.song(14))
                        .foregroundStyle(on ? Ink.primary : Ink.secondary)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(Capsule().fill(on ? Ink.primary.opacity(0.06) : Color.clear).padding(.vertical, 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("drawer-shelf-\(option.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("筛选抽屉")
    }

    private var sealedHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock").font(.system(size: 14, weight: .light))
            Text("最里面还有他藏着的东西，你不知道是什么。").font(Ink.song(13.5))
        }
        .foregroundStyle(Ink.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    @ViewBuilder private func card(_ item: RemoteDrawer.Item) -> some View {
        let locked = item.visibility == "teaser"
        if item.kind == "pixel", let art = PixelArt(json: item.content) {
            Button { zoom = item } label: {
                VStack(alignment: .leading, spacing: 10) {
                    PixelArtView(art: art).frame(width: 150, height: 150 * CGFloat(art.h) / CGFloat(art.w))
                        .frame(maxWidth: .infinity)
                    HStack {
                        Text(item.title.isEmpty ? "一幅小画" : item.title).font(Ink.song(15))
                        Spacer()
                        Text(Self.dateLine(item)).font(Ink.latin(11.5)).foregroundStyle(Ink.secondary)
                    }
                }
                .notebookCard()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("柯画的小画\(item.title.isEmpty ? "" : "：" + item.title)，\(Self.dateLine(item))")
        } else if locked {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(Ink.meText)
                    Text(item.title.isEmpty ? "锁着的一件" : item.title).font(Ink.song(16))
                    Spacer()
                    Text(Self.dateLine(item)).font(Ink.latin(11.5)).foregroundStyle(Ink.secondary)
                }
                if !item.teaser.isEmpty {
                    Text("「\(item.teaser)」").font(Ink.song(14.5)).foregroundStyle(Ink.secondary).lineSpacing(5)
                }
                Button {
                    let name = item.title.isEmpty ? item.teaser : item.title
                    NotificationCenter.default.post(name: .tarotReadingRequest, object: "爸比，你抽屉里锁着的那个「\(name)」，能给我看看吗")
                } label: {
                    Text("去找柯要").font(Ink.song(13.5)).padding(.horizontal, 14).frame(minHeight: 34)
                        .overlay(Capsule().stroke(Ink.line, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }
            .notebookCard()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if item.kind != "note" {
                        Image(systemName: "lock.open").font(.system(size: 11)).foregroundStyle(Ink.secondary)
                    }
                    if !item.title.isEmpty { Text(item.title).font(Ink.song(15.5)) }
                    Spacer()
                    Text(Self.dateLine(item)).font(Ink.latin(11.5)).foregroundStyle(Ink.secondary)
                }
                Text(item.content).font(Ink.song(16)).lineSpacing(8).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .notebookCard()
        }
    }

    @MainActor private func load() async {
        failed = false
        defer { loading = false }
        do {
            let remote = try await APIClient(baseURL: line.apiBaseURL).fetchDrawer()
            items = remote.outside.sorted { Self.when($0) > Self.when($1) }
            sealed = remote.sealed
            Self.cache = items; Self.cacheSealed = sealed
        } catch { if items.isEmpty { failed = true } }
    }

    static func when(_ item: RemoteDrawer.Item) -> String { item.released_at ?? item.created_at }

    static func dateLine(_ item: RemoteDrawer.Item) -> String {
        let at = when(item), p = at.prefix(10).split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]) else { return String(at.prefix(10)) }
        let time = at.count >= 16 ? " " + at.dropFirst(11).prefix(5) : ""
        return "\(m)月\(d)日\(time)"
    }
}

/// 柯画的像素小画：{"w","h","palette":["#0000",…],"grid":[…]}，grid 从左到右、从上到下，数字指向颜色表。
struct PixelArt: Equatable {
    let w: Int, h: Int
    let palette: [Color]
    let grid: [Int]

    init?(json: String) {
        struct Raw: Decodable { let w: Int; let h: Int; let palette: [String]; let grid: [Int] }
        guard let data = json.data(using: .utf8), let raw = try? JSONDecoder().decode(Raw.self, from: data),
              (1...64).contains(raw.w), (1...64).contains(raw.h), raw.grid.count == raw.w * raw.h else { return nil }
        let colors = raw.palette.map(PixelArt.color)
        guard colors.count >= 2, raw.grid.allSatisfy({ (0..<colors.count).contains($0) }) else { return nil }
        w = raw.w; h = raw.h; palette = colors; grid = raw.grid
    }

    static func color(_ hex: String) -> Color {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 || s.count == 4 { s = s.map { "\($0)\($0)" }.joined() }
        guard let v = UInt64(s, radix: 16) else { return .clear }
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((v >> 24) & 0xFF); g = Double((v >> 16) & 0xFF); b = Double((v >> 8) & 0xFF); a = Double(v & 0xFF)
        } else {
            r = Double((v >> 16) & 0xFF); g = Double((v >> 8) & 0xFF); b = Double(v & 0xFF); a = 255
        }
        return Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a / 255)
    }
}

struct PixelArtView: View {
    let art: PixelArt
    var body: some View {
        Canvas { ctx, size in
            let cell = min(size.width / CGFloat(art.w), size.height / CGFloat(art.h))
            let ox = (size.width - cell * CGFloat(art.w)) / 2, oy = (size.height - cell * CGFloat(art.h)) / 2
            for (i, c) in art.grid.enumerated() where c != 0 {
                let x = i % art.w, y = i / art.w
                // 多画半个点，免得格子之间露出细缝
                let rect = CGRect(x: ox + CGFloat(x) * cell, y: oy + CGFloat(y) * cell, width: cell + 0.5, height: cell + 0.5)
                ctx.fill(Path(rect), with: .color(art.palette[c]))
            }
        }
        .aspectRatio(CGFloat(art.w) / CGFloat(art.h), contentMode: .fit)
        .accessibilityHidden(true)
    }
}
