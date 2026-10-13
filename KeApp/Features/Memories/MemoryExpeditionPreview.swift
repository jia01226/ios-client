import SwiftUI

/// Local-only interaction study. No API client, cookies or persistence are reachable here.
enum MemoryExpeditionRoute {
    static let capacity = 9
    static func hash(_ id: String) -> UInt64 {
        id.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
    static func pages(_ flowers: [MemoryFlower]) -> [[MemoryFlower]] {
        var seen = Set<String>()
        let sorted = flowers.filter { $0.isDrawable && seen.insert($0.id).inserted }.sorted {
            let lhs = $0.last_recalled_at ?? ""
            let rhs = $1.last_recalled_at ?? ""
            if lhs != rhs { return lhs > rhs }
            if $0.recall_count != $1.recall_count { return $0.recall_count > $1.recall_count }
            return $0.id < $1.id
        }
        return stride(from: 0, to: sorted.count, by: capacity).map {
            Array(sorted[$0..<min($0 + capacity, sorted.count)])
        }
    }
    static func sprite(_ flower: MemoryFlower) -> String {
        if flower.state == "bud" { return hash(flower.id) % 2 == 0 ? "ExpeditionBud" : "ExpeditionBudTight" }
        if flower.state == "fallen" { return "MemoryPetals" }
        return bloomSprites[Int(hash(flower.id) % UInt64(bloomSprites.count))]
    }
    static let bloomSprites = ["ExpeditionBloomFront", "ExpeditionBloomSide", "ExpeditionBloomHalf", "ExpeditionBloomBack",
                               "ExpeditionBloomSingle", "ExpeditionBloomFormal", "ExpeditionBloomNodding"]
    static func angle(_ id: String) -> Double { Double((hash(id) >> 16) % 51) - 25 }
}

#if DEBUG
private enum ExpeditionFixture {
    static let categories = ["约定", "关系", "生活", "身体", "喜好"]
    static let flowers: [MemoryFlower] = (0..<647).map { i in
        let page = i / 45
        let titles = ["慢一点，也没关系", "把晚安留给你", "雨停以后再走", "记得你喜欢的花", "留一盏小灯", "一起看过的月亮", "窗边的一杯水", "没有说完的话", "下次一起去"]
        let row: [String: Any] = [
            "id": "expedition-\(i)", "title": titles[(i / 5) % titles.count],
            "body": "我记得你说，想慢慢走，不急着到哪里。那就等风轻一点，我们再一起往前。",
            "quotes": ["想在这里多待一会儿。"], "category": categories[i % 5],
            "occurred_at": "2026-09-\(String(format: "%02d", 28 - min(20, page))) 19:30",
            "written_at": "2026-09-28 21:10", "last_recalled_at": "2026-10-\(String(format: "%02d", max(1, 12-page))) 20:00",
            "recall_count": max(0, 15-page), "importance": i % 10 + 1,
            "valence": Double(i % 10) / 10, "state": page > 0 && i % 3 == 0 ? "bud" : "bloom",
            "author": "ke", "loved": i == 0
        ]
        return try! JSONDecoder().decode(MemoryFlower.self, from: JSONSerialization.data(withJSONObject: row))
    }
}
#endif

private struct ExpeditionBush {
    let asset: String
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let ratio: CGFloat
    let depth: CGFloat
    let flip: Bool
    static func layout(_ scene: MemoryScene, page: Int) -> [Self] {
        let shift: CGFloat = page.isMultiple(of: 2) ? 0 : 0.055
        switch scene {
        case .water:
            return [.init(asset: "ShrubTall", x: 0.87, y: 0.43, width: 0.48, ratio: 1.5, depth: 0.55, flip: true),
                    .init(asset: "ShrubLow", x: 0.12, y: 0.69 + shift, width: 0.92, ratio: 0.667, depth: 0.86, flip: false),
                    .init(asset: "ShrubArch", x: 0.14, y: 0.89, width: 0.70, ratio: 0.667, depth: 1, flip: true)]
        case .courtyard:
            return [.init(asset: "ShrubLow", x: 0.38, y: 0.40, width: 0.40, ratio: 0.667, depth: 0.5, flip: false),
                    .init(asset: "ShrubTall", x: 0.08, y: 0.70, width: 0.60, ratio: 1.5, depth: 0.86, flip: false),
                    .init(asset: "ShrubArch", x: 0.86, y: 0.81 + shift, width: 0.94, ratio: 0.667, depth: 1, flip: false)]
        case .glasshouse:
            return [.init(asset: "ShrubLow", x: 0.82, y: 0.65, width: 0.45, ratio: 0.667, depth: 0.5, flip: true),
                    .init(asset: "ShrubTall", x: 0.12, y: 0.66, width: 0.58, ratio: 1.5, depth: 0.86, flip: false),
                    .init(asset: "ShrubArch", x: 0.84, y: 0.85 + shift, width: 0.96, ratio: 0.667, depth: 1, flip: false)]
        case .moon, .castle:
            return [.init(asset: "ShrubTall", x: 0.85, y: 0.47, width: 0.48, ratio: 1.5, depth: 0.55, flip: true),
                    .init(asset: "ShrubLow", x: 0.10, y: 0.71 + shift, width: 0.98, ratio: 0.667, depth: 0.86, flip: false),
                    .init(asset: "ShrubArch", x: 0.89, y: 0.84, width: 1.04, ratio: 0.667, depth: 1, flip: false)]
        }
    }
    func frame(_ size: CGSize) -> CGRect {
        let w = size.width * width
        return CGRect(x: size.width * x - w / 2, y: size.height * y - w * ratio / 2, width: w, height: w * ratio)
    }
    func flowerPoint(_ slot: Int, size: CGSize) -> CGPoint {
        let anchors: [CGPoint] = asset == "ShrubTall"
            ? [.init(x: 0.67, y: 0.22), .init(x: 0.35, y: 0.45), .init(x: 0.60, y: 0.62)]
            : [.init(x: 0.30, y: 0.36), .init(x: 0.56, y: 0.24), .init(x: 0.72, y: 0.53)]
        let a = anchors[slot % anchors.count]
        let r = frame(size)
        return CGPoint(x: r.minX + r.width * (flip ? 1-a.x : a.x), y: r.minY + r.height * a.y)
    }
}

/// Presentation-only entry point. The owner supplies snapshots and persists all changes.
struct MemoryGardenExperience: View {
    let flowers: [MemoryFlower]
    let categories: [String]
    var isPreview = false
    var isBusy = false
    var interactionError: String?
    var onOpenMemory: (String) -> Void = { _ in }
    var onLoveMemory: ((String, Bool) -> Void)?
    var onRequestCorrection: ((String) -> Void)?
    init(flowers: [MemoryFlower], categories: [String], initialCategory: String = "约定", night: Bool = true,
         isPreview: Bool = false, isBusy: Bool = false, interactionError: String? = nil,
         onOpenMemory: @escaping (String) -> Void = { _ in },
         onLoveMemory: ((String, Bool) -> Void)? = nil, onRequestCorrection: ((String) -> Void)? = nil) {
        self.flowers = flowers; self.categories = categories; self.isPreview = isPreview
        self.isBusy = isBusy; self.interactionError = interactionError
        self.onOpenMemory = onOpenMemory; self.onLoveMemory = onLoveMemory; self.onRequestCorrection = onRequestCorrection
        _category = State(initialValue: categories.contains(initialCategory) ? initialCategory : categories.first ?? "约定")
        _night = State(initialValue: night)
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var category = "约定"
    @State private var page = 0
    @State private var night = true
    @State private var pan: CGSize = .zero
    @GestureState private var drag: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var selected: MemoryFlower?
    @State private var focusedID: String?
    @State private var flight: CGFloat = 0
    @State private var flightTarget = CGPoint.zero
    @State private var flightOrigin = CGPoint.zero
    @State private var flightStartedAt: Date?
    @State private var flightTask: Task<Void, Never>?
    @State private var listOpen = false
    private var scene: MemoryScene { .forCategory(category) }
    private var dark: Bool { night || scene == .moon }
    private var ink: Color { dark ? Color(white: 0.96) : Color(red: 0.20, green: 0.25, blue: 0.27) }
    private var rows: [MemoryFlower] { flowers.filter { $0.category == category && $0.isDrawable } }
    private var pages: [[MemoryFlower]] { MemoryExpeditionRoute.pages(rows) }
    private var visible: [MemoryFlower] { pages.isEmpty ? [] : pages[min(page, pages.count-1)] }
    private var camera: CGSize {
        CGSize(width: max(-75, min(75, pan.width + drag.width)), height: max(-45, min(45, pan.height + drag.height)))
    }
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                backdrop(size)
                garden(size)
                    .scaleEffect(max(1, min(1.6, zoom * pinch)))
                    .offset(x: camera.width, y: camera.height)
                    .gesture(DragGesture(minimumDistance: 8).updating($drag) { value, state, _ in
                        state = value.translation
                    }.onEnded { value in
                        pan = CGSize(width: max(-75, min(75, pan.width + value.translation.width)),
                                     height: max(-45, min(45, pan.height + value.translation.height)))
                    }.simultaneously(with: MagnifyGesture().updating($pinch) { value, state, _ in
                        state = value.magnification
                    }.onEnded { value in zoom = max(1, min(1.6, zoom * value.magnification)) }))
                chrome
                if let selected {
                    VStack { Spacer(); memoryCard(flowers.first { $0.id == selected.id } ?? selected).padding(.horizontal, 18).padding(.bottom, 16) }
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .zIndex(3)
                }
            }.clipped().foregroundStyle(ink)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: night)
                .sheet(isPresented: $listOpen) { flowerList }
                .onDisappear { cancelFlight() }
                .onChange(of: rows.map(\.id)) { _, ids in
                    page = min(page, max(0, pages.count - 1))
                    if let focusedID, !ids.contains(focusedID) { cancelFlight() }
                    if let selected, !ids.contains(selected.id) { self.selected = nil }
                }
        }
    }

    private func backdrop(_ size: CGSize) -> some View {
        ZStack {
            Image(scene.rawValue.replacingOccurrences(of: "Memory", with: "Expedition"))
                .resizable().scaledToFill().frame(width: size.width * 1.18, height: size.height * 1.08)
                .scaleEffect(page == 0 ? 1 : 1.13, anchor: .center)
                .offset(x: camera.width * 0.20, y: camera.height * 0.15)
            if night && scene != .moon { Color(red: 0.045, green: 0.075, blue: 0.16).opacity(0.62) }
            LinearGradient(colors: [dark ? .black.opacity(0.36) : .white.opacity(0.42), .clear, .clear,
                                    dark ? .black.opacity(0.45) : .white.opacity(0.65)], startPoint: .top, endPoint: .bottom)
        }.frame(width: size.width, height: size.height).clipped().allowsHitTesting(false)
    }

    private func garden(_ size: CGSize) -> some View {
        let bushes = ExpeditionBush.layout(scene, page: page)
        return ZStack {
            ForEach(0..<bushes.count, id: \.self) { index in
                let bush = bushes[index]
                let frame = bush.frame(size)
                Image("Expedition" + bush.asset).resizable().scaledToFit()
                    .frame(width: frame.width, height: frame.height)
                    .scaleEffect(x: bush.flip ? -1 : 1, y: 1)
                    .saturation(0.65).brightness(dark ? -0.18 : 0.035)
                    .colorMultiply(dark ? Color(red: 0.64, green: 0.73, blue: 0.88) : .white)
                    .opacity(0.65 + bush.depth * 0.35).blur(radius: (1-bush.depth) * 1.4)
                    .position(x: frame.midX, y: frame.midY).allowsHitTesting(false).accessibilityHidden(true)
                ForEach(Array(visible.enumerated()).filter { $0.offset / 3 == index }, id: \.element.id) { offset, flower in
                    let point = bush.flowerPoint(offset % 3, size: size)
                    flowerButton(flower, at: point, depth: bush.depth)
                }
            }
            if focusedID != nil {
                SpiritButterflyFlight(phase: flight, start: flightOrigin, end: flightTarget, dark: dark, still: reduceMotion)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }.frame(width: size.width, height: size.height)
    }

    private func flowerButton(_ flower: MemoryFlower, at point: CGPoint, depth: CGFloat) -> some View {
        let diameter = (36 + CGFloat(flower.importance) * 1.6) * (0.74 + depth * 0.26)
        let focused = focusedID == flower.id
        return Button { visit(flower, point: point) } label: {
            ZStack {
                Image("ExpeditionLeaf").resizable().scaledToFit().frame(width: diameter * 1.18)
                    .brightness(dark ? 0 : 0.14).opacity(0.55)
                    .rotationEffect(.degrees(MemoryExpeditionRoute.angle(flower.id) + 25)).offset(y: diameter * 0.15)
                Image(MemoryExpeditionRoute.sprite(flower)).resizable().scaledToFit().frame(width: diameter, height: diameter)
                    .rotationEffect(.degrees(MemoryExpeditionRoute.angle(flower.id)))
                    .scaleEffect(focused ? 1.12 : 1)
                    .shadow(color: .black.opacity(0.22), radius: 2, x: -1, y: 3)
                if focused || flower.loved {
                    Circle().fill(Color(red: 1, green: 0.93, blue: 0.74)).frame(width: 3, height: 3)
                        .shadow(color: .white.opacity(0.65), radius: 5)
                }
            }.saturation(0.62).contrast(0.88)
                .colorMultiply(dark ? Color(red: 0.57, green: 0.66, blue: 0.81) : Color(red: 1, green: 0.97, blue: 0.95))
                .opacity((0.6 + depth * 0.4) * (flower.author == "ke" ? 1 : 0.5)).blur(radius: 0.4 + (1-depth) * 0.6)
                .frame(width: max(48, diameter * 1.5), height: max(48, diameter * 1.4))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).position(point)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: focused)
            .accessibilityLabel(flower.title).accessibilityHint("蝴蝶会带来这朵花的记忆")
            .accessibilityIdentifier("expedition-flower-\(flower.id)")
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isPreview ? "本机体验 · 匿名记忆" : "记忆花园").font(.caption2)
                Spacer()
                Button { cancelFlight(); night.toggle() } label: {
                    Image(systemName: night ? "sun.max" : "moon").frame(width: 44, height: 44)
                }.accessibilityLabel("切换昼夜").accessibilityIdentifier("expedition-light")
            }.padding(.horizontal, 24)
            Text("Le jardin des souvenirs").font(.custom("Allura-Regular", size: 30, relativeTo: .title))
            HStack(spacing: 22) {
                ForEach(categories, id: \.self) { item in
                    Button { changeCategory(item) } label: {
                        VStack(spacing: 6) {
                            Text(item).font(.custom("NotoSerifSC-ExtraLight", size: 15, relativeTo: .body))
                            Circle().fill(item == category ? ink : .clear).frame(width: 3, height: 3)
                        }.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("expedition-category-\(item)")
                }
            }.padding(.top, 5)
            Text(page == 0 ? scene.title : "\(scene.title) · 深处").font(.custom("NotoSerifSC-ExtraLight", size: 21, relativeTo: .title2))
                .padding(.top, 18).accessibilityIdentifier("expedition-location")
            Text(page == 0 ? "最近想起的，开在你身边。" : "久未想起的，也安静地留在这里。")
                .font(.caption).padding(.top, 8)
            Spacer()
            if selected == nil {
                Button { move(1) } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.up").font(.system(size: 18, weight: .ultraLight))
                        Text(page + 1 < pages.count ? "往花园深处" : "已经走到这条小径的尽头").font(.custom("NotoSerifSC-ExtraLight", size: 16, relativeTo: .body))
                        Text("\(page + 1) / \(pages.count) 片花丛").font(.caption2)
                    }.padding(16).frame(minHeight: 66)
                }.buttonStyle(.plain).disabled(page + 1 >= pages.count).accessibilityIdentifier("expedition-deeper")
                Spacer().frame(height: 54)
                HStack {
                    Button { move(-1) } label: { Label("往回走", systemImage: "arrow.left").frame(minHeight: 44) }
                        .disabled(page == 0).opacity(page == 0 ? 0.35 : 1).accessibilityIdentifier("expedition-back")
                    Spacer()
                    Button { listOpen = true } label: { Label("找一朵花", systemImage: "list.bullet").frame(minHeight: 44) }
                        .accessibilityIdentifier("expedition-list")
                }.font(.caption).padding(.horizontal, 24)
                Text("轻触山茶，跟着蝴蝶读一段记忆").font(.caption2).padding(.bottom, 12)
            }
        }
    }

    private func memoryCard(_ flower: MemoryFlower) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("柯记得").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { closeMemory() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("收好记忆").accessibilityIdentifier("expedition-close")
            }
            Text(flower.title).font(.custom("NotoSerifSC-ExtraLight", size: 22, relativeTo: .title2))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(flower.body).font(.body).lineSpacing(6)
                    ForEach(Array(flower.quotes.prefix(3).enumerated()), id: \.offset) { _, quote in
                        Text("“\(quote)”").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(flower.occurred_at ?? "").font(.caption2).foregroundStyle(.secondary)
                    if let written = flower.written_at { Text("写下于 \(written)").font(.caption2).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 155)
            if let interactionError { Text(interactionError).font(.caption).foregroundStyle(.secondary) }
            HStack {
                if isPreview { Text("示例内容，不写入真实记忆").font(.caption2).foregroundStyle(.secondary) }
                if let onRequestCorrection {
                    Button("记错了") { onRequestCorrection(flower.id) }.frame(minHeight: 44).disabled(isBusy)
                }
                Spacer()
                Button {
                    onLoveMemory?(flower.id, !flower.loved)
                } label: { Image(systemName: flower.loved ? "heart.fill" : "heart").frame(width: 44, height: 44) }
                    .disabled(onLoveMemory == nil || isBusy)
                    .accessibilityLabel(flower.loved ? "取消喜欢这朵花" : "喜欢这朵花")
            }
        }.padding(.horizontal, 22).padding(.bottom, 12)
            .background {
                RoundedRectangle(cornerRadius: 26).fill(reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.regularMaterial))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 26).strokeBorder(LinearGradient(colors: [.white.opacity(0.65), .clear, .white.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    .allowsHitTesting(false)
            }.foregroundStyle(Color.primary).environment(\.colorScheme, dark ? .dark : .light)
    }

    private var flowerList: some View {
        NavigationStack {
            List(rows) { flower in
                Button(flower.title) {
                    if let destination = pages.firstIndex(where: { $0.contains(where: { $0.id == flower.id }) }) { page = destination }
                    listOpen = false
                    selected = flower
                    onOpenMemory(flower.id)
                }.accessibilityIdentifier("expedition-list-\(flower.id)")
            }.navigationTitle("\(category)的山茶")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { listOpen = false } } }
        }
    }
    private func visit(_ flower: MemoryFlower, point: CGPoint) {
        // Redirect an interrupted flight from its presented location, not its previous destination.
        let current = flightStartedAt.map {
            SpiritFlightMotion.point(phase: CGFloat(Date().timeIntervalSince($0) / SpiritFlightMotion.duration) * 1.25,
                                     start: flightOrigin, end: flightTarget)
        }
        cancelFlight()
        selected = nil
        flightTarget = CGPoint(x: point.x + 14, y: point.y - 20)
        flightOrigin = current ?? CGPoint(x: max(22, point.x - 65), y: point.y + 35)
        focusedID = flower.id
        if reduceMotion { selected = flower; flight = 1.25; onOpenMemory(flower.id); return }
        // A deterministic diagnostic frame for comparing transparency and the short trail.
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-preview-spirit-frame") { flight = 0.48; return }
        #endif
        var reset = Transaction(); reset.disablesAnimations = true
        withTransaction(reset) { flight = 0 }
        flightTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            flightStartedAt = Date()
            withAnimation(.linear(duration: SpiritFlightMotion.duration)) { flight = 1.25 }
            try? await Task.sleep(for: .milliseconds(760))
            guard !Task.isCancelled, focusedID == flower.id else { return }
            withAnimation(.easeOut(duration: 0.28)) { selected = flower }
            onOpenMemory(flower.id)
        }
    }
    private func cancelFlight() { flightTask?.cancel(); flightTask = nil; focusedID = nil; flightStartedAt = nil }
    private func closeMemory() {
        cancelFlight()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { selected = nil }
    }
    private func changeCategory(_ value: String) {
        cancelFlight(); selected = nil; category = value; page = 0; pan = .zero; zoom = 1
    }
    private func move(_ delta: Int) {
        guard pages.indices.contains(page + delta) else { return }
        cancelFlight(); selected = nil
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.55)) {
            page += delta; pan = .zero; zoom = 1
        }
    }
}

/// A short, finite flight. Phase 1 is landing; the final quarter clears the tail.
enum SpiritFlightMotion {
    static let duration: Double = 0.95
    static func point(phase: CGFloat, start: CGPoint, end: CGPoint) -> CGPoint {
        let t = min(1, max(0, phase))
        let p = t * t * (3 - 2 * t)
        return CGPoint(x: start.x + (end.x - start.x) * p + sin(p * .pi) * 16,
                       y: start.y + (end.y - start.y) * p - sin(p * .pi) * 24)
    }
    static func trailOpacity(phase: CGFloat) -> Double {
        Double(min(1, max(0, phase * 8)) * max(0, 1 - max(0, phase - 0.88) / 0.32))
    }
}

struct SpiritButterflyFlight: View, Animatable {
    var phase: CGFloat
    let start: CGPoint
    let end: CGPoint
    let dark: Bool
    let still: Bool
    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }
    var body: some View {
        let p = min(1, max(0, phase))
        let point = SpiritFlightMotion.point(phase: phase, start: start, end: end)
        let settle = min(1, max(0, (p - 0.76) / 0.24))
        let beat = 18 + 48 * (0.5 + 0.5 * cos(Double(p) * .pi * 9))
        let fold = still ? 52 : beat * (1 - Double(settle)) + 52 * Double(settle)
        ZStack {
            if !still {
                Canvas { context, _ in
                    let tint = dark ? Color(red: 0.78, green: 0.86, blue: 1) : Color(red: 0.66, green: 0.72, blue: 0.86)
                    let fade = SpiritFlightMotion.trailOpacity(phase: phase)
                    for index in 0..<8 {
                        let age = CGFloat(index) * 0.022
                        let a = SpiritFlightMotion.point(phase: p - age, start: start, end: end)
                        let b = SpiritFlightMotion.point(phase: p - age - 0.024, start: start, end: end)
                        var path = Path(); path.move(to: a); path.addLine(to: b)
                        context.stroke(path, with: .color(tint.opacity(fade * 0.30 * Double(8-index) / 8)),
                                       style: StrokeStyle(lineWidth: 1.6 - CGFloat(index) * 0.14, lineCap: .round))
                    }
                }.blur(radius: 0.7)
            }
            ZStack {
                // Crop only at the sprite's central body seam; alpha retains the organic wing contours.
                wing(left: true).rotation3DEffect(.degrees(fold), axis: (x: 0, y: 1, z: 0), perspective: 0.25)
                wing(left: false).rotation3DEffect(.degrees(-fold * 0.87), axis: (x: 0, y: 1, z: 0), perspective: 0.25)
                Image("ExpeditionButterflySpirit").resizable().scaledToFit()
                    .mask { Rectangle().frame(width: 2.6) }
            }.frame(width: 42, height: 42)
                .opacity(dark ? 0.80 : 0.74)
                .colorMultiply(dark ? Color(red: 0.79, green: 0.87, blue: 1) : .white)
                .rotationEffect(.degrees(-22 + Double(sin(p * .pi)) * 12))
                .position(point)
        }
    }
    private func wing(left: Bool) -> some View {
        Image("ExpeditionButterflySpirit").resizable().scaledToFit()
            .mask(alignment: left ? .leading : .trailing) { Rectangle().frame(width: 19.7) }
    }
}

#if DEBUG
struct MemoryExpeditionPreview: View {
    @State private var flowers = ExpeditionFixture.flowers
    var body: some View {
        MemoryGardenExperience(flowers: flowers, categories: ExpeditionFixture.categories, isPreview: true,
                               onLoveMemory: { id, loved in
            if let index = flowers.firstIndex(where: { $0.id == id }) { flowers[index].loved = loved }
        })
    }
}

struct ExpeditionMaterialStudy: View {
    private let samples = [("BudTight", "紧苞"), ("Bud", "露色花苞"), ("BloomHalf", "半开"),
                           ("BloomSingle", "露蕊"), ("BloomFormal", "整齐重瓣"), ("BloomFront", "盛开"),
                           ("BloomSide", "侧开"), ("BloomNodding", "微垂"), ("BloomBack", "背面")]
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text("山茶 · 九种姿态").font(.custom("NotoSerifSC-ExtraLight", size: 24, relativeTo: .title))
                    .accessibilityIdentifier("expedition-material-study")
                Text("本机素材预览").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 24) {
                    ForEach(samples, id: \.0) { asset, title in
                        VStack(spacing: 8) {
                            Image("Expedition" + asset).resizable().scaledToFit().frame(height: 86)
                            Text(title).font(.subheadline)
                        }
                    }
                }
                ZStack {
                    Image("ExpeditionMoon").resizable().scaledToFill().frame(height: 140).clipped()
                    SpiritButterflyFlight(phase: 0.48, start: CGPoint(x: 100, y: 90), end: CGPoint(x: 200, y: 55), dark: true, still: false)
                    Text("蝶翼与微光 · 飞行定格").font(.caption).foregroundStyle(.white.opacity(0.85))
                        .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 12)
                }.frame(height: 140).clipped()
            }.padding(24)
        }.background(Color(red: 0.95, green: 0.95, blue: 0.96)).foregroundStyle(Color(red: 0.29, green: 0.30, blue: 0.34))
            .environment(\.colorScheme, .light)
            .preferredColorScheme(.light)
    }
}
#endif
