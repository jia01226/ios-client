import SwiftUI

// 129：记忆星河 = 六团星云（10-21 她定的）。
// 整片星河：说好的（涡状星系）在正中，像钟一样很慢地转；日常吃喝、身体和药、以后的家、亲密时刻、难过的夜里围在旁边；
// 归不进去的小事是暗暗的小星星。点一团（或者双指拉开）进去：
// · 一根手指拖：转着看（左右、上下都能转一整圈）；拉近以后再拖就是挪位置
// · 双指拉近：拉近一层，名字就多出来一层；拉回去就回到整片星河
// · 点星星读记忆；亲密时刻上了锁，点开才看
// 不碰它的时候画面停着（除了「说好的」慢慢转），不白耗电。
// 130 她：点了要等一秒才出卡片（单击在等双击）、进去要缓冲、拉近后挪不动还偏上、不要十字星芒、
// 点身体和药会点到说好的、进去会跳一下。——单击不再等双击；六团画一次存在手机里、开 App 就在后台备好；
// 星团在标题和按钮中间的正中、绕自己的重心转；拉近后拖动是挪；整片星河按离哪团近来认；画布用自己的尺寸，不跳。

struct NebulaStar: Identifiable {
    let id: String
    let title: String
    let ke: Bool
    let importance: Int
    let loved: Bool
    let position: SIMD3<Double>
}

final class NebulaMotion {
    private var from = NebulaCamera.home, to = NebulaCamera.home
    private var start = Date.distantPast, duration = 0.0
    private var base: NebulaCamera?
    private var dragOrigin: CGSize?, pinchOrigin: CGFloat?
    /// 这一下拖是挪还是转：起手时定，拖到一半不换
    private var panning = false
    /// 拉近到这么多以后，一根手指拖就是挪位置
    static let panZoom = 1.15

    func camera(at date: Date) -> NebulaCamera {
        guard duration > 0 else { return to }
        let p = min(1, max(0, date.timeIntervalSince(start) / duration)), e = 1 - pow(1 - p, 3)
        return NebulaCamera(yaw: from.yaw + (to.yaw - from.yaw) * e, pitch: from.pitch + (to.pitch - from.pitch) * e,
                            zoom: from.zoom + (to.zoom - from.zoom) * e,
                            pan: CGSize(width: from.pan.width + (to.pan.width - from.pan.width) * e,
                                        height: from.pan.height + (to.pan.height - from.pan.height) * e))
    }
    func fly(_ target: NebulaCamera, duration: Double) {
        let now = Date()
        from = camera(at: now)
        to = target; to.zoom = min(4.5, max(0.6, to.zoom))
        start = now; self.duration = duration
    }
    func jump(_ c: NebulaCamera) { from = c; to = c; duration = 0 }

    /// 挪的时候别把星团挪出屏幕
    static func clamp(_ c: NebulaCamera, _ size: CGSize) -> NebulaCamera {
        var c = c
        let limit = NebulaProjection.baseScale(size) * c.zoom * 0.95
        c.pan.width = min(limit, max(-limit, c.pan.width))
        c.pan.height = min(limit, max(-limit, c.pan.height))
        return c
    }
    /// 拖：没拉近时转（不设限，可以转一整圈）；拉近了是挪
    func drag(_ t: CGSize, size: CGSize) {
        if base == nil {
            base = camera(at: Date()); pinchOrigin = nil
            panning = (base?.zoom ?? 1) > Self.panZoom
        }
        if dragOrigin == nil { dragOrigin = t }
        guard var c = base, let o = dragOrigin else { return }
        let dx = Double(t.width - o.width), dy = Double(t.height - o.height)
        if panning {
            c.pan.width += dx; c.pan.height += dy
            c = Self.clamp(c, size)
        } else {
            c.yaw += dx * 0.009
            c.pitch -= dy * 0.009
        }
        jump(c)
    }
    /// 拉近：两根手指中间那一点不动
    func pinch(_ m: CGFloat, anchor: CGPoint, size: CGSize) {
        if base == nil { base = camera(at: Date()); dragOrigin = nil }
        if pinchOrigin == nil { pinchOrigin = m }
        guard var c = base, let o = pinchOrigin else { return }
        let old = c.zoom
        c.zoom = min(4.5, max(0.6, old * Double(m / max(0.05, o))))
        let k = c.zoom / old
        let center = NebulaProjection.screenCenter(size, c.pan)
        c.pan.width += (center.x - anchor.x) * (k - 1)
        c.pan.height += (center.y - anchor.y) * (k - 1)
        jump(Self.clamp(c, size))
    }
    /// 松手：拉回原大小时，顺手回到正中
    func endGesture(size: CGSize) {
        base = nil; dragOrigin = nil; pinchOrigin = nil
        let c = camera(at: Date())
        if c.zoom <= 1.05, c.pan != .zero {
            var t = c; t.pan = .zero; t.zoom = max(1, t.zoom)
            fly(t, duration: 0.3)
        }
    }
}

// MARK: - 一团里面

private struct NebulaDetailCanvas: View {
    let group: NebulaGroup
    let art: NebulaArt
    let stars: [NebulaStar]
    let motion: NebulaMotion
    let selectedID: String?
    let reduceMotion: Bool
    let active: Bool
    /// 外面让镜头飞了（回到正面、挪开卡片）：这边跟着画
    let cameraVersion: Int
    var onTap: (String?) -> Void
    var onPinchOut: () -> Void
    @State private var size = CGSize(width: 390, height: 760)
    @State private var touching = false
    @State private var pinching = false
    @State private var flyingUntil = Date.distantPast
    @State private var settle = 0
    @State private var pinchAnchor: CGPoint?

    private var spins: Bool { group.kind == .whirlpool && !reduceMotion }
    static func spin(_ date: Date) -> Double { date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 300) / 300 * 2 * .pi }

    /// 镜头飞一会儿：这段时间一帧一帧画，飞完停下
    private func flying(_ seconds: Double) {
        flyingUntil = Date().addingTimeInterval(seconds)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds + 0.05))
            settle += 1
        }
    }

    var body: some View {
        // 平时停着；手指在上面、镜头在飞的时候才一帧一帧画。「说好的」慢慢转，一秒画 12 次就够
        let live = active && (touching || flyingUntil > Date()) && settle >= 0
        TimelineView(.animation(minimumInterval: live ? 1.0 / 60 : 1.0 / 12, paused: !(live || (active && spins)))) { timeline in
            Canvas(rendersAsynchronously: false) { context, canvasSize in draw(&context, canvasSize, timeline.date, labels: !touching) }
        }
        .background(GeometryReader { g in Color.clear.onAppear { size = g.size }.onChange(of: g.size) { _, s in size = s } })
        .contentShape(Rectangle())
        .gesture(
            SimultaneousGesture(
                // 一根手指：一点就是点（不等双击，马上出卡片）；动了就是转或者挪
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { v in
                        guard v.startLocation.x >= SwipeBackToClose.edge, !pinching else { return }
                        guard hypot(v.translation.width, v.translation.height) > 6 else { return }
                        if !touching { touching = true }
                        motion.drag(v.translation, size: size)
                    }
                    .onEnded { v in
                        guard v.startLocation.x >= SwipeBackToClose.edge else { return }
                        let moved = touching
                        motion.endGesture(size: size)
                        if moved { touching = false; flying(0.35) }
                        else if !pinching, hypot(v.translation.width, v.translation.height) <= 6 { onTap(hit(v.location)) }
                    },
                MagnifyGesture()
                    .onChanged { v in
                        if !pinching { pinching = true; touching = true }
                        let anchor = pinchAnchor ?? CGPoint(x: v.startAnchor.x * size.width, y: v.startAnchor.y * size.height)
                        pinchAnchor = anchor
                        motion.pinch(v.magnification, anchor: anchor, size: size)
                    }
                    .onEnded { _ in
                        motion.endGesture(size: size); pinchAnchor = nil
                        touching = false; flying(0.35)
                        Task { @MainActor in try? await Task.sleep(for: .milliseconds(150)); pinching = false }
                        if motion.camera(at: Date()).zoom < 0.8 { onPinchOut() }
                    }
            )
        )
        .onChange(of: selectedID) { _, _ in flying(0.6) }
        .onChange(of: cameraVersion) { _, _ in flying(0.9) }
        .accessibilityElement()
        .accessibilityLabel("\(group.name)，\(stars.count) 颗记忆")
        .accessibilityHint("用下面的「查看记忆」按列表一条一条读")
    }

    private func projection(_ date: Date, _ size: CGSize) -> NebulaProjection {
        NebulaProjection(camera: motion.camera(at: date), size: size, spin: spins ? Self.spin(date) : 0, origin: art.centroid)
    }

    private func hit(_ point: CGPoint) -> String? {
        let pr = projection(Date(), size)
        var best: (String, Double)?
        for s in stars {
            let (p, depth) = pr.project(s.position)
            let d = Double(hypot(p.x - point.x, p.y - point.y)) - depth * 4 - (s.ke ? 4 : 0)
            if d < 30, d < (best?.1 ?? .infinity) { best = (s.id, d) }
        }
        return best?.0
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ now: Date, labels: Bool) {
        let pr = projection(now, size)
        drawGas(&ctx, pr)
        drawDust(&ctx, pr)
        drawStars(&ctx, pr, size, labels: labels)
    }

    /// 星云的气：正对着最清楚，转到侧面淡下去，这时候星尘撑起这一团的厚度
    private func drawGas(_ ctx: inout GraphicsContext, _ pr: NebulaProjection) {
        var g = ctx
        g.opacity = (group.kind == .heart ? 0.95 : 0.8) * pow(pr.facing, 1.3)
        guard g.opacity > 0.02 else { return }
        g.concatenate(pr.planeTransform)
        g.draw(art.image, in: CGRect(x: -1, y: -1, width: 2, height: 2))
    }

    private func drawDust(_ ctx: inout GraphicsContext, _ pr: NebulaProjection) {
        let side = 1 - pr.facing
        let d = 0.9 + 0.35 * min(2, sqrt(pr.camera.zoom))
        let alphas = [0.16, 0.26, 0.38, 0.52]
        for (level, points) in art.dust.enumerated() {
            var path = Path()
            for q in points {
                let (p, _) = pr.project(q)
                path.addRect(CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d))
            }
            ctx.fill(path, with: .color(NebulaPaint.color(group.hue, 30, 84, alphas[level] * (0.5 + 0.7 * side))))
        }
    }

    private func drawStars(_ ctx: inout GraphicsContext, _ pr: NebulaProjection, _ size: CGSize, labels showLabels: Bool) {
        let cam = pr.camera
        let glow = ctx.resolve(NebulaDetailCanvas.glowSprite)
        let h = group.hue
        // 第二层：拉近到 1.5 倍，以前整理的那些也亮起来、名字多起来
        let layer2 = min(1, max(0, (cam.zoom - 1.3) / 0.5))
        var projected = stars.map { s -> (NebulaStar, CGPoint, Double) in
            let (p, depth) = pr.project(s.position); return (s, p, depth)
        }
        projected.sort { $0.2 < $1.2 }   // 远的先画
        var labels: [(title: String, at: CGPoint, r: Double, rank: Double, selected: Bool)] = []
        let screenCenter = pr.center
        var sprite = glow
        sprite.shading = .color(NebulaPaint.color(h, 52, 80))
        for (s, p, depth) in projected {
            guard p.x > -30, p.x < size.width + 30, p.y > -30, p.y < size.height + 30 else { continue }
            let bright = s.ke
            let near = 0.78 + 0.22 * max(-1, min(1, depth * 2))
            var alpha = (bright ? 1.0 : 0.55 + 0.45 * layer2) * near
            if let selectedID, selectedID != s.id { alpha *= 0.75 }
            let r = (bright ? 3.6 : 2.7) * (0.85 + 0.25 * sqrt(cam.zoom)) * (1 + Double(s.importance - 5) * 0.03)
            var outer = ctx
            outer.blendMode = .screen
            if bright {
                outer.opacity = 0.58 * alpha
                let big = r * (group.kind == .heart ? 10 : 7)
                outer.draw(sprite, in: CGRect(x: p.x - big, y: p.y - big, width: big * 2, height: big * 2))
            }
            outer.opacity = (bright ? 0.85 : 0.7) * alpha
            let small = r * (bright ? 2.4 : 3.2)
            outer.draw(sprite, in: CGRect(x: p.x - small, y: p.y - small, width: small * 2, height: small * 2))
            let core = r * 0.43
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - core, y: p.y - core, width: core * 2, height: core * 2)),
                     with: .color(NebulaPaint.color(h, group.kind == .sombrero ? 60 : 40, bright ? 91 : 81, 0.9 * alpha)))
            if s.loved {
                let ring = r * 2.6
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: ring * 2, height: ring * 2)),
                           with: .color(Color(red: 0.91, green: 0.66, blue: 0.71).opacity(0.7 * alpha)), lineWidth: 0.9)
            }
            if s.id == selectedID {
                let ring = r * 3 + 8
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: ring * 2, height: ring * 2)),
                           with: .color(Color(red: 0.94, green: 0.88, blue: 0.73).opacity(0.85)), lineWidth: 1)
            }
            guard showLabels || s.id == selectedID else { continue }
            // 名字：第一层只写柯亲手记的、重要的几颗；拉近一层，离屏幕中间近的都写
            let dist = Double(hypot(p.x - screenCenter.x, p.y - screenCenter.y))
            let rank = s.id == selectedID ? 1e9 : (layer2 > 0.5 ? 1000 - dist + (s.ke ? 60 : 0) : (s.ke ? Double(s.importance) * 10 - dist * 0.05 : -1))
            if rank >= 0 { labels.append((s.title, p, r, rank, s.id == selectedID)) }
        }
        // 手指在上面时不写名字（转的时候字跟着乱跑看着晕，也省力气），松手就出来
        let maxLabels = cam.zoom < 1.3 ? 6 : (cam.zoom < 2.4 ? 12 : 18)
        let font = cam.zoom < 2.4 ? 13.0 : 12.0
        var placed: [CGRect] = []
        for l in labels.sorted(by: { $0.rank > $1.rank }) {
            guard placed.count < maxLabels || l.selected else { break }
            let w = CGFloat(min(l.title.count, 14)) * font + 6, hgt = font + 4
            let x = min(max(l.at.x, w / 2 + 6), size.width - w / 2 - 6)
            let below = CGRect(x: x - w / 2, y: l.at.y + l.r * 2 + 5, width: w, height: hgt)
            let above = CGRect(x: x - w / 2, y: l.at.y - l.r * 2 - 5 - hgt, width: w, height: hgt)
            // 上面是标题、下面是按钮，名字不写进去
            guard let spot = [below, above].first(where: { c in c.minY > NebulaProjection.topBand && c.maxY < size.height - NebulaProjection.bottomBand
                && !placed.contains { $0.insetBy(dx: -3, dy: -2).intersects(c) } }) else { continue }
            placed.append(spot)
            let title = l.title.count > 14 ? String(l.title.prefix(13)) + "…" : l.title
            ctx.draw(Text(title).font(.custom("NotoSerifSC-Regular", size: font)).foregroundColor(Color(red: 0.84, green: 0.85, blue: 0.89)),
                     at: CGPoint(x: spot.midX, y: spot.midY))
        }
    }

    /// 白色的光晕，画的时候按这一团的颜色上色
    static let glowSprite: Image = {
        let s = 96
        guard let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Image(systemName: "circle.fill") }
        let colors = [CGColor(red: 1, green: 1, blue: 1, alpha: 1), CGColor(red: 1, green: 1, blue: 1, alpha: 0.68),
                      CGColor(red: 1, green: 1, blue: 1, alpha: 0.2), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.12, 0.45, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: 48, y: 48), startRadius: 0, endCenter: CGPoint(x: 48, y: 48), endRadius: 48, options: [])
        }
        guard let image = ctx.makeImage() else { return Image(systemName: "circle.fill") }
        return Image(decorative: image, scale: 1).renderingMode(.template)
    }()
}

// MARK: - 页面

struct MemoryNebulaView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: MemoryGardenStore
    @Binding var page: Int
    var onClose: (() -> Void)?
    @State private var current: NebulaGroup?
    @State private var privateOpen = false
    @State private var askUnlock = false
    @State private var selectedID: String?
    @State private var listOpen = false
    @State private var listAll = false
    @State private var search = ""
    @State private var dimmedOpen = false
    @State private var correcting: MemoryFlower?
    /// 1116 她：「记忆我也能改」——正在改的那颗和草稿
    @State private var editing: MemoryFlower?
    @State private var editTitle = ""
    @State private var editBody = ""
    @State private var editGroup = ""
    /// 1116：列表按时间筛（0 全部 / 14 / 30 天），按重要度还是按时间排
    @State private var listDays = 0
    @State private var listByImportance = false
    @State private var note = ""
    @State private var visible = false
    @State private var arts: [NebulaKind: NebulaArt] = Self.readyArts()
    @State private var motion = NebulaMotion()
    @State private var canvasSize = CGSize(width: 390, height: 760)
    @State private var toast: String?
    /// 130：分好团的记忆，只在记忆变了的时候算一次（以前每画一下都重新排序、筛选好几遍）
    @State private var byGroup: [String: [MemoryFlower]] = [:]
    @State private var shownCount = 0
    @State private var cameraVersion = 0
    /// 11-17 她：「点击没有那种自然而然放大的感觉，而是吧唧一下打开了」——进一团时从点的那团放大飞进去，出来缩回那团
    @State private var enterAnchor: UnitPoint = .center
    @State private var overviewSize = CGSize(width: 390, height: 844)
    @AppStorage("memory.galaxy.lastSeen") private var lastSeen = ""

    private static let ink = Color(red: 0.945, green: 0.94, blue: 0.93)
    private static let muted = Color(red: 0.72, green: 0.74, blue: 0.81)
    private static let line = Color(red: 0.76, green: 0.8, blue: 0.87).opacity(0.22)
    private static let night = Color(red: 5 / 255, green: 7 / 255, blue: 13 / 255)
    /// 「找一件事」那张单子：实心深蓝底、亮字
    private static let listBack = Color(red: 0.07, green: 0.08, blue: 0.13)
    private static let listRow = Color(red: 0.12, green: 0.13, blue: 0.2)
    private static let listInk = Color(red: 0.97, green: 0.96, blue: 0.95)
    private static let listSub = Color(red: 0.8, green: 0.82, blue: 0.88)
    /// 136：第七团「关于她」和日常吃喝并排在最上面
    /// 1116 她：「前面太挤，想要纵深感」——八团按远近摆，上面的小一点（远），下面的略大（近），
    /// 说好的留在正中。四元组是（哪团、x、y、大小倍率）。
    private static let spots: [(NebulaKind, CGFloat, CGFloat, CGFloat)] = [
        (.whirlpool, 0.50, 0.49, 1.00),   // 说好的：正中，最大
        (.lessons,   0.50, 0.10, 0.54),   // 他学会的：最上，最远最小
        (.pleiades,  0.16, 0.27, 0.74),   // 日常吃喝
        (NebulaGroup.about.kind, 0.84, 0.27, 0.74), // 关于她
        (.orion,     0.11, 0.59, 0.84),   // 身体和药
        (.sombrero,  0.89, 0.59, 0.84),   // 以后的家
        (.heart,     0.26, 0.87, 0.90),   // 亲密时刻
        (.horsehead, 0.74, 0.87, 0.90)    // 难过的夜里
    ]

    private static func readyArts() -> [NebulaKind: NebulaArt] {
        var out: [NebulaKind: NebulaArt] = [:]
        for k in NebulaKind.allCases { if let a = NebulaArt.cached(k) { out[k] = a } }
        return out
    }
    private func regroup() {
        let shown = store.visible(includeOthers: true).sorted { ($0.occurred_at ?? $0.written_at ?? "") < ($1.occurred_at ?? $1.written_at ?? "") }
        byGroup = Dictionary(grouping: shown, by: { NebulaGroup.groupName(for: $0) })
        shownCount = shown.count
    }
    private var shown: [MemoryFlower] { byGroup.values.flatMap { $0 }.sorted { ($0.occurred_at ?? $0.written_at ?? "") < ($1.occurred_at ?? $1.written_at ?? "") } }
    private func members(_ name: String) -> [MemoryFlower] { byGroup[name] ?? [] }
    private var loose: [MemoryFlower] { members(NebulaGroup.background) }
    private var selected: MemoryFlower? { selectedID.flatMap { id in store.flowers.first { $0.id == id } } }
    private func stars(_ g: NebulaGroup, _ art: NebulaArt) -> [NebulaStar] {
        members(g.name).map {
            NebulaStar(id: $0.id, title: $0.title, ke: $0.author == "ke", importance: $0.importance, loved: $0.loved,
                       position: art.seat(for: $0.id, thickness: g.thickness))
        }
    }

    var body: some View {
        ZStack {
            Self.night.ignoresSafeArea()
            NebulaSky().ignoresSafeArea()
            if let g = current {
                if let art = arts[g.kind] {
                    NebulaDetailCanvas(group: g, art: art, stars: stars(g, art), motion: motion, selectedID: selectedID,
                                       reduceMotion: reduceMotion, active: visible && !listOpen, cameraVersion: cameraVersion,
                                       onTap: { id in selectedID = id }, onPinchOut: { leave() })
                        .ignoresSafeArea()
                        .background(GeometryReader { geo in Color.clear.onAppear { canvasSize = geo.size }.onChange(of: geo.size) { _, s in canvasSize = s } }.ignoresSafeArea())
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.28, anchor: enterAnchor)),
                            removal: .opacity.combined(with: .scale(scale: 0.28, anchor: enterAnchor))))
                } else {
                    ProgressView().tint(Self.muted)
                }
            } else {
                overview.transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 2.2, anchor: enterAnchor)),
                    removal: .opacity.combined(with: .scale(scale: 2.8, anchor: enterAnchor))))
            }
            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                if selected == nil { footer }
            }
            if let flower = selected {
                VStack { Spacer(); card(flower) }
                    .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .bottom)))
            }
            overlays
            if let toast {
                Text(toast)
                    .font(.custom("NotoSerifSC-Regular", size: 14, relativeTo: .subheadline)).tracking(3)
                    .foregroundStyle(Color(red: 0.94, green: 0.88, blue: 0.73))
                    .shadow(color: Color(red: 0.94, green: 0.88, blue: 0.73).opacity(0.55), radius: 14)
                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, 150)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .foregroundStyle(Self.ink)
        .environment(\.colorScheme, .dark)
        // 卡片一点就出来，轻轻托上来
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: selectedID)
        // 11-17：进一团、出来都是一段放大 / 缩回，不是一闪
        .animation(reduceMotion ? nil : .spring(response: 0.62, dampingFraction: 0.9), value: current)
        .sensoryFeedback(.selection, trigger: selectedID)
        .task { await store.load() }
        .task { await paint() }
        .onAppear { visible = true; regroup(); welcomeNewMemory() }
        .onDisappear { visible = false; privateOpen = false; if current?.kind == .heart { current = nil } }
        .onChange(of: store.flowers) { _, _ in
            regroup()
            if let id = selectedID, !store.flowers.contains(where: { $0.id == id && $0.isDrawable }) { selectedID = nil }
            welcomeNewMemory()
        }
        .onChange(of: selectedID) { _, id in focus(id) }
        .sheet(isPresented: $listOpen) { memoryList }
        .sheet(isPresented: $dimmedOpen) { dimmedList }
        .sheet(item: $editing) { flower in editSheet(flower) }
        .confirmationDialog("亲密时刻", isPresented: $askUnlock, titleVisibility: .visible) {
            Button("打开这一团") { privateOpen = true; if let g = NebulaGroup.all.first(where: { $0.kind == .heart }) { enter(g) } }
            Button("先不看", role: .cancel) {}
        } message: { Text("只在你想看的时候打开。离开记忆页就会重新收好。") }
        .alert("这件事记错了吗？", isPresented: Binding(get: { correcting != nil }, set: { if !$0 { correcting = nil } })) {
            TextField("哪里错了，可以留空", text: $note)
            Button("取消", role: .cancel) { correcting = nil }
            Button("确认记错了", role: .destructive) {
                guard let flower = correcting else { return }
                correcting = nil
                Task { if await store.change(flower, action: "wither", note: note) { selectedID = nil } }
            }
        } message: { Text("会告诉柯不再记起这件事。这颗星会熄灭，点错了可以从「熄灭的星」重新点亮。") }
    }

    /// 六团在后台画（画过的直接从手机里读），好一团摆一团
    private func paint() async {
        for g in NebulaArt.paintOrder where arts[g.kind] == nil {
            let kind = g.kind
            let art = await Task.detached(priority: .userInitiated) { NebulaArt.art(kind) }.value
            // 先把这一团的星位算好，点进去不用现算
            let group = g, ids = members(g.name).map(\.id)
            await Task.detached(priority: .userInitiated) { for id in ids { _ = art.seat(for: id, thickness: group.thickness) } }.value
            arts[kind] = art
        }
    }

    // MARK: 整片星河

    private var overview: some View {
        GeometryReader { geo in
            let w = geo.size.width, top: CGFloat = 150, bottom: CGFloat = 178
            let mapH = max(300, geo.size.height - top - bottom)
            ZStack(alignment: .topLeading) {
                ForEach(loose.prefix(60)) { f in
                    let p = Self.looseSpot(f.id)
                    Circle().fill(Color(red: 0.8, green: 0.84, blue: 0.9).opacity(0.5)).frame(width: 2.4, height: 2.4)
                        .background(Circle().fill(Color(red: 0.8, green: 0.84, blue: 0.9).opacity(0.12)).frame(width: 12, height: 12))
                        .position(x: p.x * w, y: top + p.y * mapH)
                        .accessibilityElement().accessibilityAddTraits(.isButton)
                        .accessibilityLabel("还没归类的小事：\(f.title)")
                        .accessibilityAction { selectedID = f.id }
                }
                ForEach(Self.spots, id: \.0) { spot in
                    if let g = NebulaGroup.all.first(where: { $0.kind == spot.0 }) {
                        // 1116：每团按远近有自己的大小，越靠下越大，看起来有纵深
                        nebulaLabel(g, box: w * (spot.0 == .whirlpool ? 0.52 : 0.46) * spot.3)
                            .position(x: spot.1 * w, y: top + spot.2 * mapH)
                            // 越远越淡一点，近的更实，纵深感更明显
                            .opacity(0.70 + 0.30 * Double(min(1, spot.3)))
                            .zIndex(spot.0 == .whirlpool ? 3 : (2 - spot.2))
                    }
                }
            }
            .frame(width: w, height: geo.size.height)
            .contentShape(Rectangle())
            .onAppear { overviewSize = geo.size }
            .onChange(of: geo.size) { _, s in overviewSize = s }
            // 130：点哪儿就认离哪团最近（以前按钮的框叠在一起，点身体和药会点到说好的）；一点马上进
            .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                guard hypot(v.translation.width, v.translation.height) < 10 else { return }
                overviewTap(v.location, w: w, top: top, mapH: mapH)
            })
            .simultaneousGesture(MagnifyGesture().onEnded { v in
                guard v.magnification > 1.25 else { return }
                let a = CGPoint(x: v.startAnchor.x * w, y: v.startAnchor.y * geo.size.height)
                if let g = nearestGroup(a, w: w, top: top, mapH: mapH, reach: 10) { tapGroup(g) }
            })
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func overviewTap(_ p: CGPoint, w: CGFloat, top: CGFloat, mapH: CGFloat) {
        // 暗暗的小星先认（手指 22 点以内）
        var bestLoose: (String, CGFloat)?
        for f in loose.prefix(60) {
            let s = Self.looseSpot(f.id), d = hypot(s.x * w - p.x, top + s.y * mapH - p.y)
            if d < 22, d < (bestLoose?.1 ?? .infinity) { bestLoose = (f.id, d) }
        }
        if let id = bestLoose?.0 { selectedID = id; return }
        if let g = nearestGroup(p, w: w, top: top, mapH: mapH, reach: 1.25) { tapGroup(g) }
    }

    /// 离哪团最近：按这一团画出来的大小量（说好的那团画得小，按它自己的大小算）
    private func nearestGroup(_ p: CGPoint, w: CGFloat, top: CGFloat, mapH: CGFloat, reach: CGFloat) -> NebulaGroup? {
        var best: (NebulaKind, CGFloat)?
        for (kind, x, y, scale) in Self.spots {
            let radius = w * (kind == .whirlpool ? 0.2 : 0.19) * scale
            let c = CGPoint(x: x * w, y: top + y * mapH - w * 0.02)
            let d = hypot(c.x - p.x, c.y - p.y) / radius
            if d < reach, d < (best?.1 ?? .infinity) { best = (kind, d) }
        }
        return best.flatMap { b in NebulaGroup.all.first { $0.kind == b.0 } }
    }

    private func nebulaLabel(_ g: NebulaGroup, box: CGFloat) -> some View {
        let count = members(g.name).count
        return VStack(spacing: 0) {
            Group {
                if let art = arts[g.kind] {
                    if g.kind == .whirlpool && !reduceMotion {
                        // 像钟一样：五分钟转一圈，一秒挪 12 下，看不出跳
                        TimelineView(.periodic(from: .now, by: 1.0 / 12)) { t in
                            art.thumb.resizable().interpolation(.high)
                                .rotationEffect(.radians(NebulaDetailCanvas.spin(t.date)))
                        }
                    } else {
                        art.thumb.resizable().interpolation(.high)
                    }
                } else {
                    Color.clear
                }
            }
            .frame(width: box * (g.kind == .whirlpool ? 1.1 : 0.96), height: box * (g.kind == .whirlpool ? 1.1 : 0.96))
            .blur(radius: g.kind == .heart ? 0.65 : 0.35)
            .brightness(g.kind == .heart ? 0.12 : 0)
            .frame(width: box, height: box * 0.72)
            HStack(spacing: 5) {
                if g.kind == .heart && !privateOpen { Image(systemName: "lock").font(.system(size: 11, weight: .light)) }
                Text(g.name).font(.custom("NotoSerifSC-Regular", size: 16, relativeTo: .body)).tracking(1.3)
            }
            .shadow(color: Self.night, radius: 6)
            .padding(.top, -8)
            Text("\(g.astro) · \(count)").font(.system(size: 9.5)).tracking(0.8).foregroundStyle(Self.muted)
                .padding(.top, 2)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(g.name)，\(g.astro)，\(count) 颗记忆\(g.kind == .heart && !privateOpen ? "，已锁好" : "")")
        .accessibilityAction { tapGroup(g) }
        .accessibilityIdentifier("nebula-\(g.kind.rawValue)")
    }

    /// 没归类的小事撒在几团之间的空处，位置只看 id
    static func looseSpot(_ id: String) -> CGPoint {
        var r = NebulaRandom(NebulaRandom.hash(id) ^ 0x9e37)
        let centers = spots.map { CGPoint(x: $0.1, y: $0.2) }
        var best = CGPoint(x: 0.08, y: 0.25)
        for _ in 0..<40 {
            let p = CGPoint(x: 0.05 + r.next() * 0.9, y: -0.04 + r.next() * 1.06)
            if centers.allSatisfy({ hypot(($0.x - p.x) * 1.0, ($0.y - p.y) * 1.6) > 0.2 }) { best = p; break }
        }
        return best
    }

    // MARK: 上面

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if current != nil {
                    Button { leave() } label: {
                        HStack(spacing: 4) { Image(systemName: "chevron.left"); Text("整片星河") }
                            .font(.system(size: 14)).foregroundStyle(Self.muted).frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("nebula-back")
                } else {
                    HStack(spacing: 2) {
                        // 136：右边的「合上」改成左上一个小箭头，跟日记、抽屉、塔罗一样（读屏念「返回」）。
                        // 箭头往左挪进页边，和别的页的箭头对齐；底栏里的「记忆」页没有它
                        if let onClose {
                            Button(action: onClose) {
                                Image(systemName: "chevron.left").font(.system(size: 20, weight: .light))
                                    .foregroundStyle(Self.muted).frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("返回").accessibilityIdentifier("memory-close")
                            .padding(.leading, -16)
                        }
                        Text("记忆").font(.custom("NotoSerifSC-Regular", size: 28, relativeTo: .title)).tracking(3.4)
                    }
                }
                Spacer()
                Button("语录") { page = 1 }
                    .font(.system(size: 13)).foregroundStyle(Self.muted)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("memory-quotes")
                Menu {
                    Button("所有记忆") { listAll = true; search = ""; listOpen = true }
                    Button("熄灭的星") { dimmedOpen = true }
                    if current != nil {
                        Button("回到正面") { motion.fly(.home, duration: reduceMotion ? 0 : 0.8); cameraVersion += 1; selectedID = nil }
                    }
                    Button("刷新") { Task { await store.load() } }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("星河设置")
                .accessibilityIdentifier("memory-menu")
                .padding(.trailing, -10)
            }
            if let g = current {
                Text(g.name).font(.custom("NotoSerifSC-Regular", size: 26, relativeTo: .title)).tracking(3)
                    .shadow(color: .black.opacity(0.5), radius: 6)
            }
            Text(current == nil ? "A small universe of us" : "A little closer to us")
                .font(.custom("PinyonScript-Regular", size: current == nil ? 34 : 28, relativeTo: .largeTitle))
                .foregroundStyle(Color(red: 0.9, green: 0.86, blue: 0.93))
                .lineLimit(1).fixedSize()
                .transformEffect(CGAffineTransform(a: 0.9, b: 0, c: -0.287, d: 1, tx: 14, ty: 0))
                .shadow(color: .black.opacity(0.35), radius: 6)
                .accessibilityHidden(true)
            Text(current.map { "\($0.astro) · \(members($0.name).count) 颗" } ?? "说好的在中央，小事在身旁 · \(shownCount) 颗")
                .font(.system(size: 12)).tracking(1.2).foregroundStyle(Self.muted)
                .shadow(color: .black.opacity(0.5), radius: 4)
        }
        .padding(.horizontal, 26).padding(.top, 6)
    }

    // MARK: 下面

    private var footer: some View {
        VStack(spacing: 10) {
            Text(current == nil ? "轻点一团星云 · 双指拉开也能进去 · 暗暗的小星是还没归类的事"
                 : (current?.kind == .heart && !privateOpen ? "" : "拖动转着看 · 双指拉近出名字，拉近后拖动是挪 · 点星星读记忆"))
                .font(.system(size: 11)).tracking(0.5).foregroundStyle(Self.muted)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.6), radius: 4)
            HStack {
                Text("亮的是柯亲手记的").font(.system(size: 11)).tracking(1.2).foregroundStyle(Color(red: 0.83, green: 0.77, blue: 0.71))
                Spacer()
                Button { listAll = current == nil; search = ""; listOpen = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass").font(.system(size: 12))
                        Text(current.map { "查看 \(members($0.name).count) 颗" } ?? "找一件事")
                        Image(systemName: "chevron.right").font(.system(size: 11))
                    }
                    .font(.system(size: 13)).frame(minHeight: 44)
                }
                .accessibilityIdentifier("memory-list")
            }
            .padding(.top, 4)
            .overlay(alignment: .top) { Rectangle().fill(Self.line).frame(height: 1) }
        }
        .padding(.horizontal, 26).padding(.bottom, 8)
    }

    // MARK: 卡片

    private func card(_ flower: MemoryFlower) -> some View {
        let groupName = NebulaGroup.groupName(for: flower)
        let list = members(groupName), index = list.firstIndex { $0.id == flower.id }
        let hidden = groupName == "亲密时刻" && !privateOpen
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(groupName == NebulaGroup.background ? "还没归类的小事" : groupName)
                    .font(.system(size: 12)).tracking(1.7).foregroundStyle(Color(red: 0.8, green: 0.74, blue: 0.9))
                Spacer()
                Button { selectedID = nil } label: { Image(systemName: "xmark").font(.system(size: 15)).frame(width: 44, height: 44) }
                    .accessibilityLabel("收起").padding(.trailing, -12)
            }
            if hidden {
                Text("已收好").font(.custom("NotoSerifSC-Regular", size: 23, relativeTo: .title2)).padding(.vertical, 8)
                Button("打开这一团") { askUnlock = true }.font(.system(size: 14)).frame(minHeight: 44)
            } else {
                Text(flower.title).font(.custom("NotoSerifSC-Regular", size: 23, relativeTo: .title2)).padding(.top, 2).padding(.bottom, 6)
                // 1116：重要度、情绪、想起过几次，一行小字
                Text(Self.statsLine(flower)).font(.system(size: 11)).tracking(0.6).foregroundStyle(Self.muted)
                    .padding(.bottom, 12)
                    .accessibilityIdentifier("memory-stats")
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let changed = flower.changed, !changed.isEmpty {
                            Text(changed).font(.system(size: 13)).lineSpacing(6)
                                .foregroundStyle(Color(red: 0.94, green: 0.86, blue: 0.7))
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.94, green: 0.86, blue: 0.7).opacity(0.08)))
                        }
                        Text(flower.body).font(.system(size: 15)).lineSpacing(9).foregroundStyle(Color(red: 0.94, green: 0.91, blue: 0.97))
                            .textSelection(.enabled)
                        ForEach(Array(flower.quotes.prefix(2).enumerated()), id: \.offset) { _, quote in
                            Text("「\(quote)」").font(.system(size: 14)).lineSpacing(7).foregroundStyle(Color(red: 0.8, green: 0.76, blue: 0.86))
                                .padding(.leading, 14)
                                .overlay(alignment: .leading) { Rectangle().fill(Color(red: 0.62, green: 0.53, blue: 0.72)).frame(width: 1) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                HStack {
                    Text(Self.dateText(flower)).font(.system(size: 11)).foregroundStyle(Self.muted)
                    Spacer()
                    Text(flower.isFromMenu ? "从食单来的" : flower.author == "ke" ? "✦ 柯亲手记下" : "以前整理的").font(.system(size: 11)).foregroundStyle(Self.muted)
                }
                .padding(.top, 14)
                Button { Task { await store.change(flower, action: "love") } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: flower.loved ? "heart.fill" : "heart")
                        Text(flower.loved ? "喜欢着" : "这颗我很喜欢")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(flower.loved ? Color(red: 1, green: 0.77, blue: 0.82) : Color(red: 0.9, green: 0.82, blue: 0.89))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(RoundedRectangle(cornerRadius: 11).fill(flower.loved ? Color(red: 0.69, green: 0.31, blue: 0.36).opacity(0.19) : Color(red: 0.85, green: 0.77, blue: 0.91).opacity(0.11)))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain).disabled(store.busy).padding(.top, 14)
                .accessibilityIdentifier("memory-love")
                if let index, groupName != NebulaGroup.background {
                    HStack {
                        Button("上一颗") { if index > 0 { selectedID = list[index - 1].id } }.disabled(index == 0)
                        Spacer()
                        Text("\(index + 1) / \(list.count)").font(.system(size: 12).monospacedDigit()).foregroundStyle(Self.muted)
                        Spacer()
                        Button("下一颗") { if index < list.count - 1 { selectedID = list[index + 1].id } }.disabled(index == list.count - 1)
                    }
                    .font(.system(size: 13)).frame(minHeight: 44).padding(.top, 6)
                }
                if flower.isFromMenu {
                    Text("食单里的，要改跟柯说一声，他在小本子里改").font(.system(size: 12)).foregroundStyle(Self.muted)
                        .frame(maxWidth: .infinity, minHeight: 36)
                } else {
                    HStack {
                        // 1116 她：「记忆我也能改」
                        Button("改一改") { beginEdit(flower) }
                            .accessibilityIdentifier("memory-edit")
                        Spacer()
                        Button("记错了") { note = ""; correcting = flower }
                            .accessibilityIdentifier("memory-correct")
                    }
                    .font(.system(size: 12)).foregroundStyle(Self.muted)
                    .frame(maxWidth: .infinity, minHeight: 36)
                }
            }
            if let error = store.error { Text(error).font(.system(size: 12)).foregroundStyle(Self.muted) }
        }
        .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(red: 20 / 255, green: 25 / 255, blue: 35 / 255).opacity(0.95)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
        .padding(.horizontal, 12).padding(.bottom, 12)
        .frame(maxWidth: 500)
    }

    // MARK: 列表（能搜）

    private var memoryList: some View {
        let base: [MemoryFlower] = (listAll || current == nil) ? shown.reversed() : members(current!.name).reversed()
        // 1116：按时间筛（近 14 / 30 天，看发生的那天），再按重要度或时间排
        let cutoff = listDays == 0 ? "" : Self.dayKey(Calendar.current.date(byAdding: .day, value: -listDays, to: .now) ?? .now)
        let ranged = cutoff.isEmpty ? base : base.filter { String(($0.occurred_at ?? $0.written_at ?? "").prefix(10)) >= cutoff }
        let pool = listByImportance ? ranged.sorted { $0.importance > $1.importance } : ranged
        let term = search.trimmingCharacters(in: .whitespaces).lowercased()
        let rows = pool.filter { f in
            let g = NebulaGroup.groupName(for: f)
            let hidden = g == "亲密时刻" && !privateOpen
            guard !term.isEmpty else { return true }
            let hay = hidden ? g : "\(g) \(f.title) \(f.body) \(f.changed ?? "")"
            return hay.lowercased().contains(term)
        }
        return NavigationStack {
            List {
                Picker("时间", selection: $listDays) {
                    Text("全部").tag(0)
                    Text("近 14 天").tag(14)
                    Text("近 30 天").tag(30)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("memory-list-range")
                .listRowBackground(Self.listRow)
                Text(rows.isEmpty ? "没有找到，换一个词试试。" : "\(rows.count) 颗\(privateOpen ? "" : " · 亲密的保持收好")")
                    .font(.footnote).foregroundStyle(Self.listSub)
                    .listRowBackground(Self.listRow)
                ForEach(rows.prefix(400)) { flower in
                    let g = NebulaGroup.groupName(for: flower)
                    let hidden = g == "亲密时刻" && !privateOpen
                    // 11-17 她：「这个页面太淡了，看不清楚字」——列表里的按钮字被染成主题色（灰紫），压在深底上发虚。
                    // 换成亮字、副标题也提亮一档，底换成实心深蓝
                    Button { open(flower) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(hidden ? "已收好的一件事" : flower.title).lineLimit(2)
                                    .font(.body).foregroundStyle(Self.listInk)
                                Text("\(g == NebulaGroup.background ? "还没归类" : g) · \(Self.dateText(flower))\(flower.author == "ke" ? " · 柯亲手记下" : "")")
                                    .font(.footnote).foregroundStyle(Self.listSub)
                            }
                            Spacer()
                            Image(systemName: hidden ? "lock" : "chevron.right").font(.footnote).foregroundStyle(Self.listSub)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Self.listRow)
                }
            }
            .scrollContentBackground(.hidden)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "找一句话、一件小事…")
            .navigationTitle(listAll || current == nil ? "所有记忆" : current!.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(listByImportance ? "按重要度" : "按时间") { listByImportance.toggle() }
                        .accessibilityIdentifier("memory-list-sort")
                }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { listOpen = false } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Self.listBack)
        .tint(Self.listInk)
        .environment(\.colorScheme, .dark)
    }

    private var dimmedList: some View {
        NavigationStack {
            List {
                if let error = store.error { Text(error).foregroundStyle(.secondary) }
                let dimmed = store.flowers.filter { $0.state == "withered" }
                if dimmed.isEmpty { Text("还没有熄灭的星。") }
                ForEach(dimmed) { flower in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(flower.title)
                        Text(flower.body).font(.subheadline).foregroundStyle(.secondary)
                        Button("重新点亮") { Task { await store.change(flower, action: "revive") } }
                            .disabled(store.busy || store.loading)
                            .accessibilityIdentifier("memory-revive-\(flower.id)")
                    }.padding(.vertical, 8)
                }
            }
            .navigationTitle("熄灭的星").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dimmedOpen = false } } }
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var overlays: some View {
        if store.loading && !store.loaded {
            ProgressView("正在点亮星河").padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        } else if let error = store.error, !store.loaded {
            VStack(spacing: 10) {
                Text(error).font(.subheadline).multilineTextAlignment(.center)
                Button("重试") { Task { await store.load() } }.disabled(store.loading || store.busy)
            }.padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(30)
        }
    }

    // MARK: 动作

    private func tapGroup(_ g: NebulaGroup) {
        if g.kind == .heart && !privateOpen { askUnlock = true } else { enter(g) }
    }
    private func enter(_ g: NebulaGroup) {
        selectedID = nil
        motion.jump(.home)
        // 先把「从哪团飞进去」定下来画一遍，整片星河才知道往哪儿放大；下一拍再进
        if let spot = Self.spots.first(where: { $0.0 == g.kind }) {
            let top: CGFloat = 150, bottom: CGFloat = 178
            let mapH = max(300, overviewSize.height - top - bottom)
            enterAnchor = UnitPoint(x: spot.1, y: min(1, (top + spot.2 * mapH) / max(1, overviewSize.height)))
        }
        DispatchQueue.main.async { current = g }
    }
    private func leave() {
        selectedID = nil
        current = nil
        motion.jump(.home)
    }
    private func open(_ flower: MemoryFlower) {
        listOpen = false
        let g = NebulaGroup.groupName(for: flower)
        if let target = NebulaGroup.named(g), current != target {
            if target.kind == .heart && !privateOpen { askUnlock = true; return }
            enter(target)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            selectedID = flower.id
        }
    }

    /// 选中一颗：画面不动（130 她：点一下整团跑到左上去了）；只有这颗会被下面的卡片挡住时，往上挪一点
    private func focus(_ id: String?) {
        guard let id, let g = current, let art = arts[g.kind],
              let f = store.flowers.first(where: { $0.id == id }), NebulaGroup.groupName(for: f) == g.name else { return }
        var c = motion.camera(at: Date())
        let spin = g.kind == .whirlpool && !reduceMotion ? NebulaDetailCanvas.spin(Date()) : 0
        let p = NebulaProjection(camera: c, size: canvasSize, spin: spin, origin: art.centroid).project(art.seat(for: id, thickness: g.thickness)).0
        let line = canvasSize.height * 0.4
        guard p.y > line else { return }
        c.pan.height -= p.y - line + 20
        motion.fly(NebulaMotion.clamp(c, canvasSize), duration: reduceMotion ? 0 : 0.35)
        cameraVersion += 1
    }

    /// 柯上次之后新记的事：上面轻轻亮一句，说记在哪一团
    private func welcomeNewMemory() {
        guard store.loaded, visible else { return }
        let ke = store.flowers.filter { $0.author == "ke" && $0.isDrawable }
        guard let newest = ke.compactMap(\.written_at).max() else { return }
        defer { lastSeen = max(lastSeen, newest) }
        guard newest > lastSeen, let target = ke.first(where: { $0.written_at == newest }) else { return }
        let g = NebulaGroup.groupName(for: target)
        withAnimation(.easeOut(duration: 0.8).delay(0.8)) { toast = g == NebulaGroup.background ? "柯记下了一件新的事" : "柯记下了一件新的事 · \(g)" }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4.5))
            withAnimation(.easeIn(duration: 0.9)) { toast = nil }
        }
    }

    // MARK: 1116 改一颗

    private func beginEdit(_ flower: MemoryFlower) {
        editTitle = flower.title
        editBody = flower.body
        let g = NebulaGroup.groupName(for: flower)
        editGroup = NebulaGroup.named(g) != nil ? g : NebulaGroup.about.name
        editing = flower
    }

    private func editSheet(_ flower: MemoryFlower) -> some View {
        NavigationStack {
            Form {
                Section("标题") {
                    TextField("一句话", text: $editTitle).accessibilityIdentifier("memory-edit-title")
                }
                Section("正文") {
                    TextEditor(text: $editBody).frame(minHeight: 180).accessibilityIdentifier("memory-edit-body")
                }
                Section {
                    Picker("放在哪一团", selection: $editGroup) {
                        ForEach(NebulaGroup.all) { Text($0.name).tag($0.name) }
                    }
                } footer: {
                    Text("改的就是柯记着的这一份，他再想起来就是你改过的样子。")
                }
                if let error = store.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("改一改").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { editing = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let title = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let body = editBody.trimmingCharacters(in: .whitespacesAndNewlines)
                        let oldGroup = NebulaGroup.groupName(for: flower)
                        // 「关于她」在服务器那边还叫「背景」
                        let group = editGroup == oldGroup ? nil : (editGroup == NebulaGroup.about.name ? NebulaGroup.background : editGroup)
                        Task {
                            if await store.edit(flower, title: title == flower.title ? nil : title,
                                                body: body == flower.body ? nil : body, group: group) {
                                editing = nil
                            }
                        }
                    }
                    .disabled(store.busy || editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || editBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("memory-edit-save")
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    /// 重要度、情绪、想起过几次
    static func statsLine(_ flower: MemoryFlower) -> String {
        let mood = flower.valence >= 0.62 ? "偏开心" : flower.valence <= 0.38 ? "偏难过" : "平平的"
        let recall = flower.recall_count > 0 ? " · 想起过 \(flower.recall_count) 次" : ""
        return "重要度 \(flower.importance) · \(mood)\(recall)"
    }

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func dateText(_ flower: MemoryFlower) -> String {
        let raw = flower.occurred_at ?? flower.written_at ?? ""
        let parts = raw.prefix(10).split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return "" }
        return "\(y).\(m).\(d)"
    }
}

/// 最远的一层小星：一次画好，不闪不动
private struct NebulaSky: View {
    static let stars: [(Double, Double, Double, Double)] = {
        var r = NebulaRandom(4512)
        return (0..<160).map { _ in (r.next(), r.next(), 0.3 + r.next() * 0.65, 0.24 + r.next() * 0.3) }
    }()
    var body: some View {
        Canvas { ctx, size in
            for s in Self.stars {
                let d = s.2 * 2
                ctx.fill(Path(ellipseIn: CGRect(x: s.0 * size.width - d / 2, y: s.1 * size.height - d / 2, width: d, height: d)),
                         with: .color(Color(red: 193 / 255, green: 205 / 255, blue: 227 / 255).opacity(s.3)))
            }
            let c = CGPoint(x: size.width / 2, y: size.height / 2), r = size.width * 0.7
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(Gradient(colors: [NebulaPaint.color(224, 45, 90, 0.045), .clear]), center: c, startRadius: 0, endRadius: r))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
