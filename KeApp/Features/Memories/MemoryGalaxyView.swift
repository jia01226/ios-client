import SwiftUI

// 97：记忆星河。她要的样子：整片紫色星云，中间一团银河，记忆星散在银河里、下面写名字；
// 每颗星都要点得到、点了就弹卡片（95 的 3D 点不中，96 又退成了星座圈，都不对）。
// 这次全用 2D 自己画：银河的转动和倾斜都是自己算的，所以每颗星在屏幕上的位置都知道，点哪颗都准。
// 星尘少，真实记忆有几条就亮几颗；以前整理的打开开关才出现，是暗的小点。

// MARK: - 随机与贴图

struct GalaxyRandom {
    private var state: UInt32
    init(seed: UInt32) { state = seed }
    static func hash(_ text: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for byte in text.utf8 { h ^= UInt32(byte); h = h &* 16_777_619 }
        return h
    }
    mutating func next() -> Double {
        state = state &* 1_664_525 &+ 1_013_904_223
        return Double(state) / 4_294_967_296
    }
    mutating func normal() -> Double { sqrt(-2 * log(max(0.00001, next()))) * cos(next() * 2 * .pi) }
}

enum GalaxyArt {
    static let space = CGColorSpaceCreateDeviceRGB()
    static func context(_ size: Int) -> CGContext? {
        CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
    static func radial(_ ctx: CGContext, _ c: CGPoint, _ radius: CGFloat, _ rgb: (CGFloat, CGFloat, CGFloat), _ alpha: CGFloat) {
        let colors = [CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: alpha), CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 0)] as CFArray
        guard let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return }
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: radius, options: [])
    }

    /// 星光：白色光晕，画的时候上色
    static let glow: Image = {
        guard let ctx = context(128) else { return Image(systemName: "circle.fill") }
        let colors = [CGColor(red: 1, green: 1, blue: 1, alpha: 1), CGColor(red: 1, green: 1, blue: 1, alpha: 0.6),
                      CGColor(red: 1, green: 1, blue: 1, alpha: 0.12), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.1, 0.32, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
        }
        guard let image = ctx.makeImage() else { return Image(systemName: "circle.fill") }
        return Image(decorative: image, scale: 1).renderingMode(.template)
    }()

    /// 星云：照最早那版星图（她 10-14 点名要回来的）——墨蓝的夜，几团深紫、玫瑰粉、靛蓝的云，一条斜着的淡银河带。
    static let nebula: Image = {
        let s = 1024
        guard let ctx = context(s) else { return Image(systemName: "circle") }
        ctx.setFillColor(CGColor(red: 0.027, green: 0.035, blue: 0.078, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        var random = GalaxyRandom(seed: 7)
        let S = CGFloat(s)
        // (x, y 从上往下, 半径, 颜色)
        let clouds: [(CGFloat, CGFloat, CGFloat, (CGFloat, CGFloat, CGFloat))] = [
            (0.30, 0.35, 0.42, (96 / 255, 62 / 255, 140 / 255)), (0.72, 0.30, 0.38, (52 / 255, 64 / 255, 140 / 255)),
            (0.55, 0.68, 0.46, (120 / 255, 58 / 255, 104 / 255)), (0.20, 0.75, 0.30, (40 / 255, 70 / 255, 120 / 255)),
            (0.80, 0.78, 0.30, (90 / 255, 50 / 255, 110 / 255)), (0.50, 0.45, 0.55, (30 / 255, 34 / 255, 80 / 255))
        ]
        for (x, y, r, rgb) in clouds {
            for _ in 0..<26 {
                let p = CGPoint(x: (x + CGFloat(random.next() - 0.5) * 0.28) * S, y: (1 - y + CGFloat(random.next() - 0.5) * 0.22) * S)
                radial(ctx, p, r * S * CGFloat(0.25 + random.next() * 0.45), rgb, CGFloat(0.07 + random.next() * 0.06))
            }
        }
        ctx.saveGState()
        ctx.translateBy(x: S / 2, y: S / 2)
        ctx.rotate(by: 0.55)
        for _ in 0..<70 {
            let p = CGPoint(x: CGFloat(random.next() - 0.5) * S * 1.3, y: CGFloat(random.next() - 0.5) * S * 0.13)
            radial(ctx, p, S * CGFloat(0.04 + random.next() * 0.09), (0.86, 0.82, 0.94), CGFloat(0.025 + random.next() * 0.03))
        }
        for _ in 0..<2600 {
            let d: CGFloat = random.next() < 0.9 ? 0.7 : 1.3
            ctx.setFillColor(CGColor(red: 0.94, green: 0.93, blue: 0.98, alpha: CGFloat(random.next() * 0.35)))
            ctx.fill(CGRect(x: CGFloat(random.next() - 0.5) * S * 1.4, y: CGFloat(random.next() + random.next() + random.next() - 1.5) * S * 0.06, width: d, height: d))
        }
        ctx.restoreGState()
        guard let image = ctx.makeImage() else { return Image(systemName: "circle") }
        return Image(decorative: image, scale: 1)
    }()

    /// 银河，正面看的样子（画的时候再转、再压扁成斜着躺）。单位：半径 1 = 图宽的 1/2.7。
    static let galaxyUnit: CGFloat = 1024 / 2.7
    static let galaxy: Image = {
        let s = 1024
        guard let ctx = context(s) else { return Image(systemName: "circle") }
        let c = CGPoint(x: s / 2, y: s / 2), u = Double(galaxyUnit)
        radial(ctx, c, CGFloat(u * 1.3), (0.86, 0.8, 0.95), 0.22)
        radial(ctx, c, CGFloat(u * 0.6), (1, 0.93, 0.88), 0.22)
        ctx.setBlendMode(.plusLighter)
        var random = GalaxyRandom(seed: 52_000)
        let n = 9000
        for i in 0..<n {
            var r: Double, a: Double
            if i < n * 22 / 100 {
                r = pow(random.next(), 1.1) * 0.34; a = random.next() * 2 * .pi
            } else {
                r = 0.13 + pow(random.next(), 0.8) * 1.12
                let arm = Double(i % 2), scatter = random.normal() * (0.065 + 0.08 * r) * (i % 5 == 0 ? 2.5 : 1)
                a = arm * .pi + r * 5.2 + 0.19 * sin(r * 14 + arm) + scatter / max(0.18, r)
                if i % 7 == 0 { a += 0.45 + random.normal() * 0.24 }
                r += random.normal() * 0.035
            }
            let lane = pow(max(0, cos(a * 2 - r * 10 + 0.5)), 10)
            let cloud = 0.72 + 0.28 * sin(a * 7 + r * 23) * sin(a * 3 - r * 17)
            var b = (0.4 + random.next() * 0.7) * cloud * (1 - 0.84 * lane) * min(1, (1.4 - r) * 2.5)
            b *= r < 0.3 ? 0.8 + r : 1
            guard b > 0.02 else { continue }
            let warm = max(0, 1 - r * 2.6)
            ctx.setFillColor(CGColor(red: 1, green: 0.95 + 0.03 * warm, blue: 0.95 - 0.1 * warm, alpha: CGFloat(min(1, b))))
            let d: CGFloat = random.next() < 0.8 ? 1.8 : 2.8
            // CGContext 的 y 朝上，画出来的图会上下翻；这里先翻回来，让旋臂和记忆星用的是同一个方向
            ctx.fill(CGRect(x: c.x + CGFloat(cos(a) * r * u) - d / 2, y: c.y - CGFloat(sin(a) * r * u) - d / 2, width: d, height: d))
        }
        radial(ctx, c, CGFloat(u * 0.32), (1, 0.95, 0.9), 0.55)
        radial(ctx, c, CGFloat(u * 0.09), (1, 0.98, 0.95), 0.7)
        guard let image = ctx.makeImage() else { return Image(systemName: "circle") }
        return Image(decorative: image, scale: 1)
    }()

    struct Dust { let x: Double; let y: Double; let size: CGFloat; let alpha: Double; let phase: Double }
    /// 远处一层很稀的小星
    static let dust: [Dust] = {
        var random = GalaxyRandom(seed: 99)
        return (0..<160).map { _ in
            Dust(x: random.next(), y: random.next(), size: 0.6 + CGFloat(random.next()) * 1.1, alpha: 0.2 + random.next() * 0.5, phase: random.next() * 6)
        }
    }()
}

// MARK: - 镜头：转角、倾斜、远近、平移。只跟时间有关，画布每帧读。

struct GalaxyView3: Equatable {
    var angle: Double
    var tilt: Double      // 1 = 正面看，越小越斜
    var zoom: Double
    var pan: CGSize       // 屏幕上的平移（点到一颗星时，把它挪到卡片上方）
    static let home = GalaxyView3(angle: 0, tilt: 0.62, zoom: 1, pan: .zero)
}

final class GalaxyMotion {
    private var from = GalaxyView3.home, to = GalaxyView3.home
    private var start = Date.distantPast, duration = 0.0
    private var base: GalaxyView3?
    private var dragOrigin: CGSize?, pinchOrigin: CGFloat?
    private var drift = Date()
    var hiddenUntil: [String: Date] = [:]
    var meteors: [(target: String?, start: Date, duration: Double, from: CGPoint, delta: CGPoint)] = []
    var nextMeteor = Date().addingTimeInterval(6)
    var reduceMotion = false
    var holding = false

    func view(at date: Date) -> GalaxyView3 {
        var v = to
        if duration > 0 {
            let p = min(1, max(0, date.timeIntervalSince(start) / duration)), e = 1 - pow(1 - p, 3)
            v = GalaxyView3(angle: from.angle + (to.angle - from.angle) * e, tilt: from.tilt + (to.tilt - from.tilt) * e,
                            zoom: from.zoom + (to.zoom - from.zoom) * e,
                            pan: CGSize(width: from.pan.width + (to.pan.width - from.pan.width) * e,
                                        height: from.pan.height + (to.pan.height - from.pan.height) * e))
        }
        // 没人碰的时候，银河自己很慢地转
        if !reduceMotion && !holding && base == nil { v.angle += date.timeIntervalSince(drift) * 0.012 }
        return v
    }
    func fly(_ target: GalaxyView3, duration: Double) {
        let now = Date()
        from = view(at: now); drift = now
        to = target; to.tilt = min(0.85, max(0.25, to.tilt)); to.zoom = min(2.6, max(0.8, to.zoom))
        start = now; self.duration = duration
    }
    private func jump(_ v: GalaxyView3) { from = v; to = v; duration = 0; drift = Date() }
    func drag(_ t: CGSize) {
        if base == nil { base = view(at: Date()); pinchOrigin = nil }
        if dragOrigin == nil { dragOrigin = t }
        guard var v = base, let o = dragOrigin else { return }
        v.angle -= Double(t.width - o.width) * 0.006
        v.tilt = min(0.85, max(0.25, v.tilt + Double(t.height - o.height) * 0.0016))
        jump(v)
    }
    func pinch(_ m: CGFloat) {
        if base == nil { base = view(at: Date()); dragOrigin = nil }
        if pinchOrigin == nil { pinchOrigin = m }
        guard var v = base, let o = pinchOrigin else { return }
        v.zoom = min(2.6, max(0.8, v.zoom * Double(m / max(0.05, o))))
        jump(v)
    }
    func endGesture(fling: CGSize = .zero) {
        let now = Date(), v = view(at: now)
        base = nil; dragOrigin = nil; pinchOrigin = nil
        guard !reduceMotion, abs(fling.width) > 20 else { jump(v); return }
        var t = v; t.angle -= Double(fling.width) * 0.0035
        fly(t, duration: 0.9)
    }
}

// MARK: - 投影：盘面上的点 → 屏幕上的点（画和点击用同一套）

struct GalaxyProjection {
    let view: GalaxyView3
    let size: CGSize
    static let roll = -0.19
    var scale: Double { Double(min(size.width, size.height * 0.62)) * 0.45 * view.zoom }
    var center: CGPoint { CGPoint(x: size.width / 2 + view.pan.width, y: size.height * 0.55 + view.pan.height) }
    /// 返回屏幕位置和「远近」（-1 远 … 1 近）
    /// z：记忆星不全贴在盘面上，有高有低，所以上下也散得开（网页版同一个公式）
    func project(_ x: Double, _ y: Double, _ z: Double = 0) -> (CGPoint, Double) {
        let c = cos(view.angle), s = sin(view.angle)
        let xr = x * c - y * s, yr = (x * s + y * c) * view.tilt - z * sqrt(max(0, 1 - view.tilt * view.tilt))
        let cr = cos(Self.roll), sr = sin(Self.roll)
        let px = (xr * cr - yr * sr) * scale, py = (xr * sr + yr * cr) * scale
        return (CGPoint(x: center.x + px, y: center.y + py), max(-1, min(1, (x * s + y * c) / 1.6)))
    }
}

// MARK: - 一颗记忆星

struct GalaxyStar: Identifiable {
    let id: String
    let title: String
    let category: String
    let ke: Bool
    let x: Double, y: Double, z: Double
    let importance: Int
    let loved: Bool
    let phase: Double
    /// 柯记的星按记下的先后，像向日葵籽一样一圈圈往外排（第 index 颗）：间距匀，名字不打架；
    /// 新记的一条排在最外面，旧的不挪。以前整理的散在盘面里，位置只看 ID。
    init(_ f: MemoryFlower, index: Int = 0) {
        id = f.id; title = f.title; category = f.category; ke = f.author == "ke"; importance = f.importance; loved = f.loved
        var random = GalaxyRandom(seed: GalaxyRandom.hash(f.id))
        if ke {
            let i = Double(index), r = 0.5 + 0.19 * sqrt(i), a = i * 2.399_963 + 0.6
            x = cos(a) * r; y = sin(a) * r; z = (random.next() - 0.5) * 0.9
        } else {
            let r = 0.18 + pow(random.next(), 0.7) * 1.1, a = random.next() * 2 * .pi
            x = cos(a) * r; y = sin(a) * r; z = (random.next() - 0.5) * 0.12
        }
        phase = random.next() * 6.28
    }
}

// MARK: - 画布

private struct GalaxyCanvas: View {
    let stars: [GalaxyStar]
    let motion: GalaxyMotion
    let category: String?
    let selectedID: String?
    let paused: Bool
    let reduceMotion: Bool
    var onTap: (String?) -> Void
    @State private var size = CGSize(width: 390, height: 760)

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: paused)) { timeline in
            Canvas(rendersAsynchronously: false) { context, size in draw(&context, size, timeline.date) }
        }
        .background(GeometryReader { g in Color.clear.onAppear { size = g.size }.onChange(of: g.size) { _, s in size = s } })
        .contentShape(Rectangle())
        .gesture(
            SimultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { motion.holding = true; motion.drag($0.translation) }
                    .onEnded { v in
                        motion.holding = false
                        motion.endGesture(fling: CGSize(width: v.predictedEndTranslation.width - v.translation.width,
                                                        height: v.predictedEndTranslation.height - v.translation.height))
                    },
                MagnifyGesture()
                    .onChanged { motion.holding = true; motion.pinch($0.magnification) }
                    .onEnded { _ in motion.holding = false; motion.endGesture() }
            )
        )
        .onTapGesture(coordinateSpace: .local) { onTap(hit($0)) }
        .accessibilityElement()
        .accessibilityLabel("记忆星河，\(stars.filter(\.ke).count) 颗记忆")
        .accessibilityHint("用下面的「查看记忆」按列表一条一条读")
    }

    private func visible(_ s: GalaxyStar) -> Bool { category == nil || s.category == category }

    /// 点击：和画用同一套投影。柯记的星优先，范围按屏幕 34 点算。
    private func hit(_ point: CGPoint) -> String? {
        let pr = GalaxyProjection(view: motion.view(at: Date()), size: size)
        var best: (String, CGFloat)?
        for star in stars where star.ke && visible(star) {
            if let until = motion.hiddenUntil[star.id], until > Date() { continue }
            let (p, _) = pr.project(star.x, star.y, star.z)
            let d = hypot(p.x - point.x, p.y - point.y)
            if d < 34, d < (best?.1 ?? .infinity) { best = (star.id, d) }
        }
        if best == nil {
            let reach = 16 + CGFloat(pr.view.zoom) * 6
            for star in stars where !star.ke && visible(star) {
                let (p, _) = pr.project(star.x, star.y, star.z)
                let d = hypot(p.x - point.x, p.y - point.y)
                if d < reach, d < (best?.1 ?? .infinity) { best = (star.id, d) }
            }
        }
        return best?.0
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ now: Date) {
        let t = now.timeIntervalSinceReferenceDate
        let v = motion.view(at: now), pr = GalaxyProjection(view: v, size: size)
        // 星云铺满，跟着平移轻轻错开
        let ns = max(size.width, size.height) * 1.25
        ctx.draw(GalaxyArt.nebula, in: CGRect(x: size.width / 2 - ns / 2 + v.pan.width * 0.15, y: size.height / 2 - ns / 2 + v.pan.height * 0.15, width: ns, height: ns))
        // 远处稀稀的小星
        for d in GalaxyArt.dust {
            let a = d.alpha * (reduceMotion ? 1 : 0.75 + 0.25 * sin(t * 1.2 + d.phase))
            ctx.fill(Path(CGRect(x: d.x * size.width + v.pan.width * 0.3, y: d.y * size.height + v.pan.height * 0.3, width: d.size, height: d.size)),
                     with: .color(Color(red: 0.86, green: 0.88, blue: 1).opacity(a)))
        }
        // 银河：正面的图，先转，再压扁，再整体歪一点 —— 和投影公式一模一样
        var g = ctx
        g.translateBy(x: pr.center.x, y: pr.center.y)
        g.rotate(by: .radians(GalaxyProjection.roll))
        g.scaleBy(x: 1, y: v.tilt)
        g.rotate(by: .radians(v.angle))
        let gw = 1024 * pr.scale / Double(GalaxyArt.galaxyUnit)
        g.draw(GalaxyArt.galaxy, in: CGRect(x: -gw / 2, y: -gw / 2, width: gw, height: gw))

        // 以前整理的：小而暗的星，每颗都点得开；拉近（≥1.8 倍）才写名字
        let glow = ctx.resolve(GalaxyArt.glow)
        let oldLabels = v.zoom >= 1.8
        // 115 她：「一放大全是密密麻麻的字」。小星星的名字只挑离屏幕中心最近的几颗，跟亮星一起排、互不压
        var oldCandidates: [(title: String, at: CGPoint, dist: CGFloat, selected: Bool)] = []
        let center = CGPoint(x: size.width / 2, y: size.height * 0.5)
        for star in stars where !star.ke {
            let (p, depth) = pr.project(star.x, star.y, star.z)
            guard p.x > -20, p.x < size.width + 20, p.y > -20, p.y < size.height + 20 else { continue }
            let on = visible(star)
            let a = (on ? 0.55 : 0.1) * (0.85 + 0.15 * depth) * (reduceMotion ? 1 : 0.85 + 0.15 * sin(t * 0.9 + star.phase))
            let r = 1.4 * (0.8 + v.zoom * 0.25)
            var sprite = glow
            sprite.shading = .color(Color(red: 0.9, green: 0.89, blue: 0.97))
            var layer = ctx
            layer.opacity = a * 0.6
            layer.draw(sprite, in: CGRect(x: p.x - r * 3, y: p.y - r * 3, width: r * 6, height: r * 6))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.45, y: p.y - r * 0.45, width: r * 0.9, height: r * 0.9)),
                     with: .color(Color(red: 0.9, green: 0.89, blue: 0.97).opacity(a)))
            if star.id == selectedID {
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20)),
                           with: .color(Color(red: 0.94, green: 0.88, blue: 0.73).opacity(0.85)), lineWidth: 1)
            }
            if (oldLabels && on) || star.id == selectedID {
                oldCandidates.append((star.title, p, hypot(p.x - center.x, p.y - center.y), star.id == selectedID))
            }
        }
        // 柯记的：亮星 + 名字
        var labels: [(title: String, at: CGPoint, r: Double, alpha: Double, rank: Int, selected: Bool)] = []
        for star in stars where star.ke {
            let (p, depth) = pr.project(star.x, star.y, star.z)
            var alpha = visible(star) ? 0.85 : 0.15
            var reveal = 1.0
            if let until = motion.hiddenUntil[star.id] {
                reveal = min(1, max(0, now.timeIntervalSince(until) / 1.4))
                alpha *= reveal
            }
            guard alpha > 0.01 else { continue }
            let pulse = reduceMotion ? 1 : 0.82 + 0.13 * sin(t * (0.83 + Double(star.importance) * 0.037) + star.phase)
                + 0.25 * exp(-pow((((t + star.phase * 2.73).truncatingRemainder(dividingBy: 17)) / 17 - 0.5) / 0.026, 2))
            let near = 0.88 + 0.12 * depth
            let r = (4.2 + Double(star.importance) * 0.45) * near * pulse * (1 + (1 - reveal) * 2) * (0.8 + v.zoom * 0.2)
            var sprite = glow
            sprite.shading = .color(Color(red: 0.95, green: 0.93, blue: 1))
            var layer = ctx
            layer.opacity = alpha * 0.85
            layer.draw(sprite, in: CGRect(x: p.x - r * 4, y: p.y - r * 4, width: r * 8, height: r * 8))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.3, y: p.y - r * 0.3, width: r * 0.6, height: r * 0.6)),
                     with: .color(.white.opacity(alpha)))
            if star.loved {
                let ring = r * 2.2 + (reduceMotion ? 0 : sin(t * 1.6) * 1.2)
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: ring * 2, height: ring * 2)),
                           with: .color(Color(red: 0.91, green: 0.66, blue: 0.71).opacity(alpha * 0.7)), lineWidth: 0.9)
            }
            if star.id == selectedID {
                let ring = r * 3 + 8
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: ring * 2, height: ring * 2)),
                           with: .color(Color(red: 0.94, green: 0.88, blue: 0.73).opacity(0.85)), lineWidth: 1)
            }
            if alpha > 0.3 { labels.append((star.title, p, r, alpha, star.importance, star.id == selectedID)) }
        }
        // 名字不打架：选中的、重要的先放；下面撞了就放上面；上下都撞，先不写（拉近了自然分开）。也不出屏幕边。
        var placed: [CGRect] = []
        let maxLabels = 12
        for l in labels.sorted(by: { ($0.selected ? 1 : 0, $0.rank) > ($1.selected ? 1 : 0, $1.rank) }) {
            guard placed.count < maxLabels || l.selected else { break }
            let w = CGFloat(l.title.count) * 12.5 + 6, hgt: CGFloat = 16
            let x = min(max(l.at.x, w / 2 + 4), size.width - w / 2 - 4)
            let below = CGRect(x: x - w / 2, y: l.at.y + l.r * 2 + 6, width: w, height: hgt)
            let above = CGRect(x: x - w / 2, y: l.at.y - l.r * 2 - 6 - hgt, width: w, height: hgt)
            guard let spot = [below, above].first(where: { c in !placed.contains { $0.intersects(c) } }) else { continue }
            placed.append(spot)
            ctx.draw(Text(l.title).font(.system(size: 12)).foregroundColor(Color(red: 0.93, green: 0.9, blue: 0.97).opacity(l.alpha)),
                     at: CGPoint(x: spot.midX, y: spot.midY))
        }
        // 小星星：选中的那颗一定写；其余只写离中心最近的 6 颗，撞了就不写，一屏总共不超过 maxLabels
        let fade = min(1, max(0, (v.zoom - 1.8) * 3)) * 0.75
        var oldShown = 0
        for l in oldCandidates.sorted(by: { ($0.selected ? 0 : 1, $0.dist) < ($1.selected ? 0 : 1, $1.dist) }) {
            if !l.selected && (oldShown >= 6 || placed.count >= maxLabels) { break }
            let w = CGFloat(l.title.count) * 10.5 + 6, hgt: CGFloat = 14
            let x = min(max(l.at.x, w / 2 + 4), size.width - w / 2 - 4)
            let below = CGRect(x: x - w / 2, y: l.at.y + 6, width: w, height: hgt)
            let above = CGRect(x: x - w / 2, y: l.at.y - 6 - hgt, width: w, height: hgt)
            guard let spot = [below, above].first(where: { c in !placed.contains { $0.intersects(c) } }) else { continue }
            placed.append(spot)
            if !l.selected { oldShown += 1 }
            ctx.draw(Text(l.title).font(.system(size: 10)).foregroundColor(Color(red: 0.85, green: 0.83, blue: 0.92).opacity(l.selected ? 0.9 : fade)),
                     at: CGPoint(x: spot.midX, y: spot.midY))
        }

        // 流星：偶尔一颗从右上划到左下；新记忆的那颗落到它的位置
        if !reduceMotion && now > motion.nextMeteor {
            motion.meteors.append((nil, now, 1.1 + Double.random(in: 0...0.5), CGPoint(x: Double.random(in: 0.75...1), y: Double.random(in: 0.1...0.25)),
                                   CGPoint(x: -Double.random(in: 0.8...1), y: Double.random(in: 0.32...0.44))))
            motion.nextMeteor = now.addingTimeInterval(Double.random(in: 8...17))
        }
        motion.meteors.removeAll { now.timeIntervalSince($0.start) > $0.duration }
        for m in motion.meteors {
            let p = now.timeIntervalSince(m.start) / m.duration
            guard p > 0 else { continue }
            let from = CGPoint(x: m.from.x * size.width, y: m.from.y * size.height)
            var end = CGPoint(x: from.x + m.delta.x * size.width, y: from.y + m.delta.y * size.height)
            if let id = m.target, let star = stars.first(where: { $0.id == id }) { end = pr.project(star.x, star.y, star.z).0 }
            let e = m.target == nil ? 1 - pow(1 - p, 2.2) : 1 - pow(1 - p, 3)
            let head = CGPoint(x: from.x + (end.x - from.x) * e, y: from.y + (end.y - from.y) * e)
            let ang = atan2(end.y - from.y, end.x - from.x), len: CGFloat = m.target == nil ? 110 : 130
            let tail = CGPoint(x: head.x - cos(ang) * len, y: head.y - sin(ang) * len)
            let fade = m.target == nil ? sin(.pi * p) : 1
            var path = Path(); path.move(to: head); path.addLine(to: tail)
            ctx.stroke(path, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.98, blue: 0.94).opacity(0.92 * fade), .clear]),
                                                   startPoint: head, endPoint: tail), lineWidth: m.target == nil ? 1.3 : 1.8)
        }
    }
}

// MARK: - 页面

struct MemoryGalaxyView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: MemoryGardenStore
    @Binding var page: Int
    var onClose: (() -> Void)?
    @State private var motion = GalaxyMotion()
    @State private var includeOthers = true
    @State private var category: String?
    @State private var selectedID: String?
    @State private var listOpen = false
    @State private var dimmedOpen = false
    @State private var correcting: MemoryFlower?
    @State private var note = ""
    @State private var toast = false
    @State private var visible = false
    @State private var canvasSize = CGSize(width: 390, height: 760)
    @AppStorage("memory.galaxy.lastSeen") private var lastSeen = ""

    private static let ink = Color(red: 0.945, green: 0.94, blue: 0.93)
    private static let muted = Color(red: 0.76, green: 0.77, blue: 0.85)
    private static let line = Color(red: 0.76, green: 0.8, blue: 0.87).opacity(0.22)

    private var mine: [MemoryFlower] {
        store.visible(includeOthers: false).sorted { ($0.occurred_at ?? $0.written_at ?? "") < ($1.occurred_at ?? $1.written_at ?? "") }
    }
    private var others: [MemoryFlower] { store.visible(includeOthers: true).filter { $0.author != "ke" } }
    private var ordered: [MemoryFlower] { mine.filter { category == nil || $0.category == category } }
    private var orderedOthers: [MemoryFlower] { others.filter { category == nil || $0.category == category } }
    private var stars: [GalaxyStar] {
        let placed = mine.sorted { ($0.written_at ?? "", $0.id) < ($1.written_at ?? "", $1.id) }
        return placed.enumerated().map { GalaxyStar($1, index: $0) } + (includeOthers ? others.map { GalaxyStar($0) } : [])
    }
    private var selected: MemoryFlower? { selectedID.flatMap { id in store.flowers.first { $0.id == id } } }
    private var categories: [String] {
        let used = Set(mine.map(\.category))
        return store.categories.filter { used.contains($0) }
    }

    var body: some View {
        ZStack {
            Color(red: 0.027, green: 0.035, blue: 0.078).ignoresSafeArea()
            GalaxyCanvas(stars: stars, motion: motion, category: category, selectedID: selectedID,
                         paused: !visible, reduceMotion: reduceMotion, onTap: tapped)
                .ignoresSafeArea()
                .background(GeometryReader { g in Color.clear.onAppear { canvasSize = g.size }.onChange(of: g.size) { _, s in canvasSize = s } }.ignoresSafeArea())
            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                if selected == nil { footer }
            }
            if let flower = selected {
                VStack { Spacer(); card(flower) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            overlays
            Text("柯记下了一件新的事")
                .font(.custom("NotoSerifSC-Regular", size: 14, relativeTo: .subheadline)).tracking(4)
                .foregroundStyle(Color(red: 0.94, green: 0.88, blue: 0.73))
                .shadow(color: Color(red: 0.94, green: 0.88, blue: 0.73).opacity(0.55), radius: 14)
                .opacity(toast ? 1 : 0)
                .frame(maxHeight: .infinity, alignment: .top).padding(.top, 230)
                .allowsHitTesting(false)
                .accessibilityHidden(!toast)
        }
        .foregroundStyle(Self.ink)
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.88), value: selectedID)
        .sensoryFeedback(.selection, trigger: selectedID)
        .task { motion.reduceMotion = reduceMotion; await store.load() }
        .onAppear { visible = true; motion.reduceMotion = reduceMotion; welcomeNewMemory() }
        .onDisappear { visible = false }
        .onChange(of: store.flowers) { _, _ in
            if let id = selectedID, !store.flowers.contains(where: { $0.id == id && $0.isDrawable }) { selectedID = nil }
            welcomeNewMemory()
        }
        .onChange(of: category) { _, _ in if selectedID == nil { focus(nil) } else { selectedID = nil } }
        .onChange(of: selectedID) { _, id in focus(id) }
        .sheet(isPresented: $listOpen) { memoryList }
        .sheet(isPresented: $dimmedOpen) { dimmedList }
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

    // MARK: 上面

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("记忆").font(.custom("NotoSerifSC-Regular", size: 28, relativeTo: .title)).tracking(3.4)
                Spacer()
                if let onClose {
                    Button("合上", action: onClose)
                        .font(.system(size: 13)).foregroundStyle(Self.muted)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("memory-close")
                }
                Button("语录") { page = 1 }
                    .font(.system(size: 13)).foregroundStyle(Self.muted)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("memory-quotes")
                Menu {
                    Toggle("以前整理的", isOn: $includeOthers)
                    Button("熄灭的星") { dimmedOpen = true }
                    Button("看一颗流星") {
                        motion.meteors.append((nil, Date(), 1.3, CGPoint(x: 0.9, y: 0.12), CGPoint(x: -0.9, y: 0.4)))
                    }
                    Button("回到最初视角") { selectedID = nil; category = nil; motion.fly(.home, duration: reduceMotion ? 0 : 1) }
                    Button("刷新") { Task { await store.load() } }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("星河设置")
                .accessibilityIdentifier("memory-menu")
                .padding(.trailing, -10)
            }
            Text("A small universe of us")
                .font(.custom("PinyonScript-Regular", size: 36, relativeTo: .largeTitle))
                .foregroundStyle(Color(red: 0.95, green: 0.94, blue: 0.97))
                .lineLimit(1).fixedSize()
                .transformEffect(CGAffineTransform(a: 0.9, b: 0, c: -0.287, d: 1, tx: 14, ty: 0))
                .padding(.top, 2)
                .shadow(color: .black.opacity(0.35), radius: 6)
                .accessibilityHidden(true)
            Text(includeOthers ? "\(Self.monthName())的星河 · 柯记的 \(ordered.count) 颗 · 以前的 \(orderedOthers.count) 颗" : "\(Self.monthName())的星河 · \(ordered.count) 颗记忆")
                .font(.system(size: 12)).tracking(1.3).foregroundStyle(Self.muted)
                .shadow(color: .black.opacity(0.5), radius: 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    categoryButton(nil, "全部")
                    ForEach(categories, id: \.self) { categoryButton($0, $0) }
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 26).padding(.top, 6)
    }

    private func categoryButton(_ key: String?, _ title: String) -> some View {
        let on = category == key
        return Button { category = key } label: {
            Text(title).font(.system(size: 13)).tracking(1)
                .foregroundStyle(on ? Color(red: 0.97, green: 0.95, blue: 0.94) : Self.muted)
                .shadow(color: .black.opacity(0.5), radius: 4)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(red: 0.92, green: 0.87, blue: 0.9)).frame(height: 1).opacity(on ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("memory-category-\(title)")
    }

    // MARK: 下面

    private var footer: some View {
        VStack(spacing: 12) {
            Text(mine.isEmpty ? " " : (includeOthers ? "亮的是柯亲手记的 · 小的是以前整理的 · 拉近能看见名字" : "拖动转星河 · 双指拉近 · 点一颗星"))
                .font(.system(size: 11)).tracking(0.6).foregroundStyle(Self.muted)
                .shadow(color: .black.opacity(0.5), radius: 4)
            HStack {
                Text(includeOthers ? "含以前整理的 \(others.count) 颗" : "柯亲手记下")
                    .font(.system(size: 11)).tracking(1.3).foregroundStyle(Self.muted)
                Spacer()
                Button { listOpen = true } label: {
                    HStack(spacing: 4) { Text("查看 \(ordered.count) 颗记忆"); Image(systemName: "chevron.right").font(.system(size: 11)) }
                        .font(.system(size: 13)).frame(minHeight: 44)
                }
                .accessibilityIdentifier("memory-list")
            }
            .padding(.top, 6)
            .overlay(alignment: .top) { Rectangle().fill(Self.line).frame(height: 1) }
        }
        .padding(.horizontal, 26).padding(.bottom, 8)
    }

    // MARK: 卡片

    private func card(_ flower: MemoryFlower) -> some View {
        let list = flower.author == "ke" ? ordered : orderedOthers, index = list.firstIndex { $0.id == flower.id }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(flower.category).font(.system(size: 12)).tracking(1.7).foregroundStyle(Color(red: 0.8, green: 0.74, blue: 0.9))
                Spacer()
                Button { selectedID = nil } label: { Image(systemName: "xmark").font(.system(size: 15)).frame(width: 44, height: 44) }
                    .accessibilityLabel("收起").padding(.trailing, -12)
            }
            Text(flower.title).font(.custom("NotoSerifSC-Regular", size: 23, relativeTo: .title2)).padding(.top, 2).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
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
                Text(flower.author == "ke" ? "柯亲手记下" : "以前整理的").font(.system(size: 11)).foregroundStyle(Self.muted)
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
                .background(RoundedRectangle(cornerRadius: 12).fill(flower.loved ? Color(red: 0.69, green: 0.31, blue: 0.36).opacity(0.2) : Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain).disabled(store.busy).padding(.top, 14)
            .accessibilityIdentifier("memory-love")
            if index != nil {
                HStack {
                    Button("上一颗") { if let index, index > 0 { selectedID = list[index - 1].id } }
                        .disabled(index == nil || index == 0)
                    Spacer()
                    if let index { Text("\(index + 1) / \(list.count)").font(.system(size: 12).monospacedDigit()).foregroundStyle(Self.muted) }
                    Spacer()
                    Button("下一颗") { if let index, index < list.count - 1 { selectedID = list[index + 1].id } }
                        .disabled(index == nil || index == list.count - 1)
                }
                .font(.system(size: 13)).frame(minHeight: 44).padding(.top, 6)
            }
            Button("记错了") { note = ""; correcting = flower }
                .font(.system(size: 12)).foregroundStyle(Self.muted)
                .frame(maxWidth: .infinity, minHeight: 36)
                .accessibilityIdentifier("memory-correct")
            if let error = store.error { Text(error).font(.system(size: 12)).foregroundStyle(Self.muted) }
        }
        .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
        .padding(.horizontal, 14).padding(.bottom, 12)
        .frame(maxWidth: 500)
    }

    // MARK: 列表

    private var memoryList: some View {
        NavigationStack {
            List {
                ForEach(ordered.reversed()) { flower in
                    Button { listOpen = false; selectedID = flower.id } label: {
                        HStack(spacing: 12) {
                            Text(flower.title)
                            Spacer()
                            Text("\(flower.category) · \(Self.dateText(flower))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("\(Self.monthName())，记住的瞬间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { listOpen = false } } }
        }
        .presentationDetents([.medium, .large])
        .environment(\.colorScheme, .dark)
    }

    private var dimmedList: some View {
        NavigationStack {
            List {
                if let error = store.error { Text(error).foregroundStyle(.secondary) }
                let dimmed = store.flowers.filter { $0.state == "withered" && (includeOthers || $0.author == "ke") }
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
        } else if store.loaded && mine.isEmpty && !includeOthers {
            Text("柯还没开始点星星，他每天会自己记下你们的事")
                .font(.subheadline).multilineTextAlignment(.center).lineSpacing(6).foregroundStyle(Self.muted)
                .padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(30)
                .accessibilityIdentifier("memory-empty")
        } else if let error = store.error, !store.loaded {
            VStack(spacing: 10) {
                Text(error).font(.subheadline).multilineTextAlignment(.center)
                Button("重试") { Task { await store.load() } }.disabled(store.loading || store.busy)
            }.padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(30)
        }
    }

    // MARK: 动作

    private func tapped(_ id: String?) {
        if let id { selectedID = id } else if selectedID != nil { selectedID = nil }
    }

    /// 选中一颗：拉近一点，把它挪到卡片上方
    private func focus(_ id: String?) {
        guard let id, let star = stars.first(where: { $0.id == id }) else {
            var v = motion.view(at: Date()); v.pan = .zero; v.zoom = 1
            motion.fly(v, duration: reduceMotion ? 0 : 0.8)
            return
        }
        var v = motion.view(at: Date())
        v.zoom = max(v.zoom, 1.35); v.pan = .zero
        let p = GalaxyProjection(view: v, size: canvasSize).project(star.x, star.y, star.z).0
        v.pan = CGSize(width: canvasSize.width / 2 - p.x, height: canvasSize.height * 0.3 - p.y)
        motion.fly(v, duration: reduceMotion ? 0 : 0.8)
    }

    /// 柯上次之后新记的事：一颗流星从右上角划过来，落下，那颗星亮起来。
    private func welcomeNewMemory() {
        guard store.loaded, visible else { return }
        let ke = store.flowers.filter { $0.author == "ke" && $0.isDrawable }
        guard let newest = ke.compactMap(\.written_at).max() else { return }
        defer { lastSeen = max(lastSeen, newest) }
        guard newest > lastSeen, !reduceMotion, let target = ke.first(where: { $0.written_at == newest }) else { return }
        let start = Date().addingTimeInterval(1.2)
        motion.hiddenUntil[target.id] = start.addingTimeInterval(1.6)
        motion.meteors.append((target.id, start, 1.6, CGPoint(x: 0.92, y: -0.01), .zero))
        withAnimation(.easeOut(duration: 0.8).delay(1.2)) { toast = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4.2))
            withAnimation(.easeIn(duration: 0.9)) { toast = false }
        }
    }

    private static func monthName(_ date: Date = Date()) -> String {
        let m = Calendar.current.component(.month, from: date)
        return ["一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月"][max(0, min(11, m - 1))]
    }
    private static func dateText(_ flower: MemoryFlower) -> String {
        let raw = flower.occurred_at ?? flower.written_at ?? ""
        let parts = raw.prefix(10).split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return "" }
        return "\(y).\(m).\(d)"
    }
}
