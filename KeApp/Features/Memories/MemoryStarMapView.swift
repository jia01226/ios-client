import SwiftUI
import CoreGraphics

// 94：记忆页从山茶花园换成宇宙星图。一颗星 = 一条记忆，一个星座 = 一个分类。
// 整片星空连成一片；上面的「门」飞进某个星座，底下的卡片左右翻，镜头跟着一颗一颗走。
// 全部用代码画（星云、星光、流星），没有贴图，放多大都清楚。

// MARK: - 布星

struct StarPoint: Identifiable {
    let id: String
    let category: String
    let x: CGFloat
    let y: CGFloat
    let ke: Bool
    let importance: Int
    let tone: StarTone
    let twinkles: Bool
    let archived: Bool
    let loved: Bool
    let phase: Double
    let speed: Double
}

struct StarTone: Hashable {
    let r: Double, g: Double, b: Double
    var color: Color { Color(red: r, green: g, blue: b) }
}

struct StarConstellation: Identifiable {
    let id: String
    let center: CGPoint
    let tone: StarTone
}

struct StarAtlas {
    var stars: [StarPoint] = []
    var constellations: [StarConstellation] = []
    var lines: [(String, String)] = []
    private(set) var index: [String: Int] = [:]

    static let tones: [StarTone] = [
        StarTone(r: 0.93, g: 0.84, b: 0.91), StarTone(r: 0.84, g: 0.81, b: 0.96),
        StarTone(r: 0.89, g: 0.91, b: 0.96), StarTone(r: 0.81, g: 0.89, b: 0.94),
        StarTone(r: 0.96, g: 0.89, b: 0.84), StarTone(r: 0.96, g: 0.81, b: 0.86),
        StarTone(r: 0.86, g: 0.94, b: 0.90), StarTone(r: 0.94, g: 0.92, b: 0.82)
    ]

    init() {}

    /// 星座的位置只看分类的顺序，星的位置只看记忆 ID：新记一条不会把旧的星挪走。
    init(flowers: [MemoryFlower], categories: [String]) {
        var order = categories
        for flower in flowers where !order.contains(flower.category) { order.append(flower.category) }
        let used = Set(flowers.map(\.category))
        order = order.filter { used.contains($0) }
        let firstRing = min(order.count, 6)
        constellations = order.enumerated().map { i, key in
            let ring = i < 6 ? 0 : 1
            let count = ring == 0 ? firstRing : max(1, order.count - 6)
            let slot = ring == 0 ? i : i - 6
            let radius: CGFloat = order.count == 1 ? 0 : (ring == 0 ? 900 : 1750)
            let angle = Double(slot) / Double(count) * .pi * 2 - .pi / 2 + (ring == 0 ? 0 : .pi / Double(count))
            return StarConstellation(id: key,
                                     center: CGPoint(x: cos(angle) * radius * 1.15, y: sin(angle) * radius * 0.95),
                                     tone: Self.tones[i % Self.tones.count])
        }
        let centers = Dictionary(uniqueKeysWithValues: constellations.map { ($0.id, $0) })
        stars = flowers.compactMap { flower in
            guard let home = centers[flower.category] else { return nil }
            var random = StarRandom(seed: StarRandom.hash(flower.id))
            let ke = flower.author == "ke"
            let spread: Double = ke ? 270 : 540
            let angle = random.next() * .pi * 2
            let distance = pow(random.next(), ke ? 0.8 : 0.55) * spread
            let warmth = (flower.valence - 0.5) * 0.6
            let mix = warmth > 0 ? (0.97, 0.87, 0.84) : (0.81, 0.84, 0.97)
            let f = abs(warmth)
            let base = home.tone
            return StarPoint(id: flower.id, category: flower.category,
                             x: home.center.x + cos(angle) * distance * 1.25,
                             y: home.center.y + sin(angle) * distance * 0.85,
                             ke: ke, importance: flower.importance,
                             tone: StarTone(r: base.r * (1 - f) + mix.0 * f, g: base.g * (1 - f) + mix.1 * f, b: base.b * (1 - f) + mix.2 * f),
                             twinkles: flower.state == "bloom", archived: flower.state == "fallen", loved: flower.loved,
                             phase: random.next() * .pi * 2, speed: 0.6 + random.next() * 1.4)
        }
        index = Dictionary(stars.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        lines = Self.connect(stars, categories: order)
    }

    func star(_ id: String) -> StarPoint? { index[id].map { stars[$0] } }
    func center(of category: String) -> CGPoint? { constellations.first { $0.id == category }?.center }

    /// 每个星座把柯亲手记的星连成一棵最短的树；柯记得少时借几颗最亮的旧星。
    private static func connect(_ stars: [StarPoint], categories: [String]) -> [(String, String)] {
        var result: [(String, String)] = []
        for key in categories {
            let own = stars.filter { $0.category == key }
            var nodes = own.filter(\.ke)
            if nodes.count < 3 {
                nodes += own.filter { !$0.ke }.sorted { $0.importance > $1.importance }.prefix(5 - nodes.count)
            }
            guard nodes.count > 1 else { continue }
            var inTree = [nodes[0]]
            var rest = Array(nodes.dropFirst())
            while !rest.isEmpty {
                var best = (0, 0, CGFloat.greatestFiniteMagnitude)
                for (i, a) in inTree.enumerated() {
                    for (j, b) in rest.enumerated() {
                        let d = (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
                        if d < best.2 { best = (i, j, d) }
                    }
                }
                result.append((inTree[best.0].id, rest[best.1].id))
                inTree.append(rest.remove(at: best.1))
            }
        }
        return result
    }
}

struct StarRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    static func hash(_ text: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 { h ^= UInt64(byte); h = h &* 0x100_0000_01b3 }
        return h
    }
    mutating func next() -> Double {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}

// MARK: - 镜头与流星（只跟时间有关，Canvas 每帧读）

struct StarCamera: Equatable {
    var x: CGFloat
    var y: CGFloat
    var zoom: CGFloat
    static let overview = StarCamera(x: 0, y: 60, zoom: 0.4)
    static func clamp(_ zoom: CGFloat) -> CGFloat { min(2.6, max(0.2, zoom)) }
}

struct StarMeteor {
    let target: String?
    let start: Date
    let duration: Double
    let from: CGPoint
}

final class StarSkyMotion {
    private var from = StarCamera.overview
    private var to = StarCamera.overview
    private var start = Date.distantPast
    private var duration = 0.0
    var meteors: [StarMeteor] = []
    /// 流星落下之前，新记忆的星先藏着；落下后慢慢亮起来。
    var hiddenUntil: [String: Date] = [:]
    var nextAmbient = Date().addingTimeInterval(14)

    private var base: StarCamera?
    private var dragOrigin: CGSize?
    private var pinchOrigin: CGFloat?
    private var translation = CGSize.zero
    private var scale: CGFloat = 1

    func camera(at date: Date) -> StarCamera {
        guard duration > 0 else { return to }
        let p = min(1, max(0, date.timeIntervalSince(start) / duration))
        let e = CGFloat(1 - pow(1 - p, 3))
        return StarCamera(x: from.x + (to.x - from.x) * e, y: from.y + (to.y - from.y) * e,
                          zoom: from.zoom + (to.zoom - from.zoom) * e)
    }
    func fly(to target: StarCamera, duration: Double, now: Date = Date()) {
        from = camera(at: now)
        to = StarCamera(x: target.x, y: target.y, zoom: StarCamera.clamp(target.zoom))
        start = now
        self.duration = duration
    }
    private func jump(to target: StarCamera) { from = target; to = target; duration = 0 }

    func drag(_ value: CGSize) {
        if base == nil { rebase() }
        if dragOrigin == nil { dragOrigin = value }
        translation = CGSize(width: value.width - dragOrigin!.width, height: value.height - dragOrigin!.height)
        apply()
    }
    func pinch(_ value: CGFloat) {
        if base == nil { rebase() }
        if pinchOrigin == nil { pinchOrigin = value }
        scale = value / max(0.01, pinchOrigin!)
        apply()
    }
    /// 松手后按手指的速度再滑一段，像在太空里漂。
    func endDrag(predicted: CGSize, actual: CGSize, reduceMotion: Bool) {
        let now = Date()
        let current = camera(at: now)
        endGesture()
        guard !reduceMotion else { return }
        let vx = predicted.width - actual.width, vy = predicted.height - actual.height
        guard abs(vx) + abs(vy) > 20 else { return }
        fly(to: StarCamera(x: current.x - vx * 0.55 / current.zoom, y: current.y - vy * 0.55 / current.zoom,
                           zoom: current.zoom), duration: 0.9, now: now)
    }
    func endGesture() { base = nil; dragOrigin = nil; pinchOrigin = nil }
    private func rebase() {
        base = camera(at: Date()); translation = .zero; scale = 1; dragOrigin = nil; pinchOrigin = nil
    }
    private func apply() {
        guard let b = base else { return }
        let z = StarCamera.clamp(b.zoom * scale)
        jump(to: StarCamera(x: b.x - translation.width / z, y: b.y - translation.height / z, zoom: z))
    }
}

// MARK: - 画星空用的素材（程序生成）

enum StarSprites {
    /// 白色的光晕，画的时候按星的颜色上色。
    static let glow: Image = {
        let size = 128
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Image(systemName: "circle.fill") }
        let colors = [CGColor(red: 1, green: 1, blue: 1, alpha: 1), CGColor(red: 1, green: 1, blue: 1, alpha: 0.55),
                      CGColor(red: 1, green: 1, blue: 1, alpha: 0.14), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.12, 0.35, 1])!
        let c = CGPoint(x: size / 2, y: size / 2)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(size / 2), options: [])
        guard let image = ctx.makeImage() else { return Image(systemName: "circle.fill") }
        return Image(decorative: image, scale: 1).renderingMode(.template)
    }()

    /// 星云和银河带，开页时画一张，之后每帧只是贴上去。
    static let nebula: Image = {
        let size = 1024
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Image(systemName: "circle") }
        ctx.setFillColor(CGColor(red: 0.027, green: 0.035, blue: 0.078, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        var random = StarRandom(seed: 7)
        let s = CGFloat(size)
        func cloud(_ p: CGPoint, _ radius: CGFloat, _ rgb: (CGFloat, CGFloat, CGFloat), _ alpha: CGFloat) {
            let colors = [CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: alpha),
                          CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 0)] as CFArray
            let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
            ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [])
        }
        let clouds: [(CGFloat, CGFloat, CGFloat, (CGFloat, CGFloat, CGFloat))] = [
            (0.30, 0.35, 0.42, (0.38, 0.24, 0.55)), (0.72, 0.30, 0.38, (0.20, 0.25, 0.55)),
            (0.55, 0.68, 0.46, (0.47, 0.23, 0.41)), (0.20, 0.75, 0.30, (0.16, 0.27, 0.47)),
            (0.80, 0.78, 0.30, (0.35, 0.20, 0.43)), (0.50, 0.45, 0.55, (0.12, 0.13, 0.31))
        ]
        for (x, y, r, rgb) in clouds {
            for _ in 0..<26 {
                let p = CGPoint(x: (x + CGFloat(random.next() - 0.5) * 0.28) * s, y: (y + CGFloat(random.next() - 0.5) * 0.22) * s)
                cloud(p, r * s * CGFloat(0.25 + random.next() * 0.45), rgb, CGFloat(0.05 + random.next() * 0.05))
            }
        }
        ctx.saveGState()
        ctx.translateBy(x: s / 2, y: s / 2)
        ctx.rotate(by: -0.55)
        for _ in 0..<70 {
            let p = CGPoint(x: CGFloat(random.next() - 0.5) * s * 1.3, y: CGFloat(random.next() - 0.5) * s * 0.13)
            cloud(p, s * CGFloat(0.04 + random.next() * 0.09), (0.86, 0.82, 0.94), CGFloat(0.025 + random.next() * 0.03))
        }
        for _ in 0..<2600 {
            let p = CGPoint(x: CGFloat(random.next() - 0.5) * s * 1.4,
                            y: CGFloat(random.next() + random.next() + random.next() - 1.5) * s * 0.06)
            let d: CGFloat = random.next() < 0.9 ? 0.7 : 1.3
            ctx.setFillColor(CGColor(red: 0.94, green: 0.93, blue: 0.98, alpha: CGFloat(random.next() * 0.35)))
            ctx.fill(CGRect(x: p.x, y: p.y, width: d, height: d))
        }
        ctx.restoreGState()
        guard let image = ctx.makeImage() else { return Image(systemName: "circle") }
        return Image(decorative: image, scale: 1)
    }()

    struct Dust { let x: CGFloat; let y: CGFloat; let size: CGFloat; let alpha: Double; let phase: Double }
    /// 远处的三层小星，跟着镜头走得比记忆星慢，看起来有纵深。
    static let dust: [(parallax: CGFloat, stars: [Dust])] = [CGFloat(0.15), 0.32, 0.55].enumerated().map { layer, parallax in
        var random = StarRandom(seed: UInt64(99 + layer))
        let count = [260, 200, 120][layer]
        return (parallax, (0..<count).map { _ in
            Dust(x: CGFloat(random.next() * 2600 - 1300), y: CGFloat(random.next() * 2600 - 1300),
                 size: CGFloat(layer + 1) * 0.45 + CGFloat(random.next() * 0.5),
                 alpha: 0.25 + random.next() * 0.5, phase: random.next() * 6)
        })
    }
}

// MARK: - 星空画布

struct StarSkyCanvas: View {
    let atlas: StarAtlas
    let motion: StarSkyMotion
    let door: String?
    let focusID: String?
    let paused: Bool
    let reduceMotion: Bool
    var onTap: (String?) -> Void

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: paused)) { timeline in
            Canvas(rendersAsynchronously: false) { context, size in
                draw(&context, size: size, now: timeline.date)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            SimultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { motion.drag($0.translation) }
                    .onEnded { motion.endDrag(predicted: $0.predictedEndTranslation, actual: $0.translation, reduceMotion: reduceMotion) },
                MagnifyGesture()
                    .onChanged { motion.pinch($0.magnification) }
                    .onEnded { _ in motion.endGesture() }
            )
        )
        .onTapGesture(coordinateSpace: .local) { location in onTap(hit(location)) }
        .accessibilityElement()
        .accessibilityLabel("记忆星图，\(atlas.stars.count) 颗星")
        .accessibilityHint("用上面的星座按钮进入一个分类，下面的卡片可以一张一张翻看")
    }

    private func screen(_ x: CGFloat, _ y: CGFloat, _ cam: StarCamera, _ size: CGSize) -> CGPoint {
        CGPoint(x: (x - cam.x) * cam.zoom + size.width / 2, y: (y - cam.y) * cam.zoom + size.height / 2)
    }

    private func hit(_ point: CGPoint) -> String? {
        // 点到的范围按屏幕算，柯亲手记的星更好点中。
        let cam = motion.camera(at: Date())
        var best: String?
        var bestDistance: CGFloat = 28 * 28
        for star in atlas.stars {
            let p = CGPoint(x: (star.x - cam.x) * cam.zoom + lastSize.width / 2, y: (star.y - cam.y) * cam.zoom + lastSize.height / 2)
            let d = (p.x - point.x) * (p.x - point.x) + (p.y - point.y) * (p.y - point.y) + (star.ke ? 0 : 140)
            if d < bestDistance { bestDistance = d; best = star.id }
        }
        return best
    }
    private var lastSize: CGSize { SizeBox.shared.size }

    private func draw(_ context: inout GraphicsContext, size: CGSize, now: Date) {
        SizeBox.shared.size = size
        let t = now.timeIntervalSinceReferenceDate
        let cam = motion.camera(at: now)
        // 偶尔划过一颗不带记忆的流星
        if !reduceMotion && now > motion.nextAmbient {
            motion.meteors.removeAll { $0.start.addingTimeInterval($0.duration) < now }
            if motion.meteors.isEmpty {
                motion.meteors.append(StarMeteor(target: nil, start: now, duration: 1.1,
                                                 from: CGPoint(x: 0.65 + Double.random(in: 0...0.3), y: -0.03)))
            }
            motion.nextAmbient = now.addingTimeInterval(Double.random(in: 25...55))
        }
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.027, green: 0.035, blue: 0.078)))

        // 星云：很慢的视差
        let nebulaSize = max(size.width, size.height) * 1.9
        context.draw(StarSprites.nebula, in: CGRect(x: size.width / 2 - nebulaSize / 2 - cam.x * 0.07 * cam.zoom,
                                                    y: size.height / 2 - nebulaSize / 2 - cam.y * 0.07 * cam.zoom,
                                                    width: nebulaSize, height: nebulaSize))
        // 远处的小星
        let dustScale = 0.55 + cam.zoom * 0.35
        for layer in StarSprites.dust {
            for s in layer.stars {
                let wx = (s.x - cam.x * layer.parallax + 3900).truncatingRemainder(dividingBy: 2600) - 1300
                let wy = (s.y - cam.y * layer.parallax + 3900).truncatingRemainder(dividingBy: 2600) - 1300
                let sx = wx * dustScale + size.width / 2, sy = wy * dustScale + size.height / 2
                guard sx > -4, sx < size.width + 4, sy > -4, sy < size.height + 4 else { continue }
                let a = s.alpha * (reduceMotion ? 1 : 0.75 + 0.25 * sin(t * 1.3 + s.phase))
                context.fill(Path(CGRect(x: sx, y: sy, width: s.size, height: s.size)),
                             with: .color(Color(red: 0.91, green: 0.89, blue: 0.96).opacity(a)))
            }
        }

        func dimFor(_ category: String) -> Double { door == nil || door == category ? 1 : 0.2 }
        func revealed(_ id: String) -> Double {
            guard let until = motion.hiddenUntil[id] else { return 1 }
            return min(1, max(0, now.timeIntervalSince(until) / 1.2))
        }

        // 星座连线
        for (a, b) in atlas.lines {
            guard let s1 = atlas.star(a), let s2 = atlas.star(b) else { continue }
            let alpha = dimFor(s1.category) * min(revealed(a), revealed(b))
            guard alpha > 0.01 else { continue }
            let p1 = screen(s1.x, s1.y, cam, size), p2 = screen(s2.x, s2.y, cam, size)
            var path = Path(); path.move(to: p1); path.addLine(to: p2)
            context.stroke(path, with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0.28 * alpha), Color.white.opacity(0.1 * alpha), Color.white.opacity(0.28 * alpha)]),
                startPoint: p1, endPoint: p2), lineWidth: 0.8)
        }

        // 星座名，放大一点才出来
        let labelAlpha = Double(max(0, min(1, (cam.zoom - 0.18) * 3))) * 0.85
        if labelAlpha > 0 {
            for c in atlas.constellations {
                let p = screen(c.center.x, c.center.y - 330, cam, size)
                let a = labelAlpha * (door == nil || door == c.id ? 1 : 0.35)
                context.draw(Text(c.id.map(String.init).joined(separator: " "))
                                .font(.custom("NotoSerifSC-ExtraLight", size: 15)).foregroundColor(.white.opacity(a)), at: p)
            }
        }

        // 记忆星
        let glowCache = context.resolve(StarSprites.glow)
        for star in atlas.stars {
            let p = screen(star.x, star.y, cam, size)
            guard p.x > -60, p.x < size.width + 60, p.y > -60, p.y < size.height + 60 else { continue }
            let reveal = revealed(star.id)
            guard reveal > 0 else { continue }
            var alpha = (star.ke ? 1.0 : (star.archived ? 0.3 : 0.5)) * dimFor(star.category) * reveal
            if !reduceMotion {
                alpha *= star.twinkles ? 0.7 + 0.3 * sin(t * star.speed * 2.2 + star.phase) : 0.9 + 0.1 * sin(t * star.speed + star.phase)
            }
            var base = star.ke ? 2.2 + CGFloat(star.importance) * 0.42 : 1 + CGFloat(star.importance) * 0.22
            base *= 1 + CGFloat(1 - reveal) * 2
            let r = base * (0.6 + cam.zoom * 0.75)
            let g = r * (star.ke ? 9 : 6)
            if g > 3 {
                var sprite = glowCache
                sprite.shading = .color(star.tone.color)
                var layer = context
                layer.opacity = alpha * (star.ke ? 0.9 : 0.7)
                layer.draw(sprite, in: CGRect(x: p.x - g / 2, y: p.y - g / 2, width: g, height: g))
            }
            let core = max(0.6, r * 0.42)
            context.fill(Path(ellipseIn: CGRect(x: p.x - core, y: p.y - core, width: core * 2, height: core * 2)),
                         with: .color(star.tone.color.opacity(alpha)))
            if star.ke && r > 2.6 {
                // 柯亲手记的亮星有十字星芒
                let l = r * 3.2
                var spikes = Path()
                spikes.move(to: CGPoint(x: p.x - l, y: p.y)); spikes.addLine(to: CGPoint(x: p.x + l, y: p.y))
                spikes.move(to: CGPoint(x: p.x, y: p.y - l)); spikes.addLine(to: CGPoint(x: p.x, y: p.y + l))
                context.stroke(spikes, with: .color(star.tone.color.opacity(alpha * 0.45)), lineWidth: 0.6)
            }
            if star.loved {
                let ring = r * 2.4 + (reduceMotion ? 0 : CGFloat(sin(t * 1.6)) * 1.2)
                context.stroke(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: ring * 2, height: ring * 2)),
                               with: .color(Color(red: 0.91, green: 0.66, blue: 0.71).opacity(alpha * 0.8)), lineWidth: 0.8)
            }
            if star.id == focusID {
                let ring = r * 3.2 + 6
                context.stroke(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: ring * 2, height: ring * 2)),
                               with: .color(Color(red: 0.95, green: 0.89, blue: 0.74).opacity(0.85)), lineWidth: 1)
            }
        }

        // 流星
        for meteor in motion.meteors {
            let p = min(1, max(0, now.timeIntervalSince(meteor.start) / meteor.duration))
            guard p > 0, p < 1 else { continue }
            let from = CGPoint(x: meteor.from.x * size.width, y: meteor.from.y * size.height)
            let end: CGPoint
            if let id = meteor.target, let star = atlas.star(id) { end = screen(star.x, star.y, cam, size) }
            else { end = CGPoint(x: from.x - size.width * 0.7, y: size.height * 0.55) }
            let e = CGFloat(1 - pow(1 - p, 3))
            let head = CGPoint(x: from.x + (end.x - from.x) * e, y: from.y + (end.y - from.y) * e)
            let angle = atan2(end.y - from.y, end.x - from.x)
            let tail = CGPoint(x: head.x - cos(angle) * 120, y: head.y - sin(angle) * 120)
            var path = Path(); path.move(to: head); path.addLine(to: tail)
            context.stroke(path, with: .linearGradient(
                Gradient(colors: [Color(red: 1, green: 0.96, blue: 0.89).opacity(0.95), .clear]), startPoint: head, endPoint: tail),
                           lineWidth: 1.6)
            var sprite = glowCache
            sprite.shading = .color(Color(red: 1, green: 0.94, blue: 0.86))
            context.draw(sprite, in: CGRect(x: head.x - 14, y: head.y - 14, width: 28, height: 28))
        }
    }
}

/// 画布的尺寸给点击用；只在主线程读写。
final class SizeBox { static let shared = SizeBox(); var size = CGSize(width: 390, height: 700) }

// MARK: - 星图页

struct MemoryStarMapView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: MemoryGardenStore
    @Binding var includeOthers: Bool
    var onOpen: (MemoryFlower) -> Void
    var onLove: (MemoryFlower) -> Void

    @State private var atlas = StarAtlas()
    @State private var motion = StarSkyMotion()
    @State private var door: String?
    @State private var focusID: String?
    @State private var visible = false
    @State private var toast = false
    @AppStorage("memory.starmap.lastSeen") private var lastSeen = ""

    private var flowers: [MemoryFlower] { store.visible(includeOthers: includeOthers) }
    private var deck: [MemoryFlower] {
        guard let door else { return [] }
        let inside = flowers.filter { $0.category == door }
        return inside.filter { $0.author == "ke" } + inside.filter { $0.author != "ke" }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            StarSkyCanvas(atlas: atlas, motion: motion, door: door, focusID: focusID,
                          paused: !visible, reduceMotion: reduceMotion, onTap: tapped)
                .ignoresSafeArea(edges: .bottom)
            VStack(spacing: 0) {
                doors
                Spacer(minLength: 0)
                if door != nil && !deck.isEmpty { cards.transition(.move(edge: .bottom).combined(with: .opacity)) }
                else { hint }
            }
            Text("柯记下了一件新的事")
                .font(.custom("NotoSerifSC-ExtraLight", size: 14, relativeTo: .subheadline)).tracking(3)
                .foregroundStyle(Color(red: 0.95, green: 0.89, blue: 0.74))
                .shadow(color: Color(red: 0.95, green: 0.89, blue: 0.74).opacity(0.6), radius: 12)
                .opacity(toast ? 1 : 0).frame(maxHeight: .infinity).allowsHitTesting(false)
                .accessibilityHidden(!toast)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.86), value: door)
        .sensoryFeedback(.selection, trigger: focusID)
        .sensoryFeedback(.impact(weight: .light), trigger: door)
        .onAppear { visible = true; rebuild() }
        .onDisappear { visible = false }
        .onChange(of: flowers.map(\.id)) { _, _ in rebuild() }
        .onChange(of: flowers.map(\.loved)) { _, _ in rebuild() }
        .onChange(of: focusID) { _, id in
            guard let id, let star = atlas.star(id) else { return }
            // 星停在卡片上方
            let zoom = max(motion.camera(at: Date()).zoom, 1.15)
            motion.fly(to: StarCamera(x: star.x, y: star.y + 120 / zoom, zoom: zoom), duration: reduceMotion ? 0 : 0.8)
        }
    }

    private var doors: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                doorButton(nil, "全部")
                ForEach(atlas.constellations) { c in doorButton(c.id, c.id) }
            }.padding(.horizontal, 18).padding(.vertical, 6)
        }
    }

    private func doorButton(_ key: String?, _ title: String) -> some View {
        let on = door == key
        return Button { enter(key) } label: {
            Text(title).font(.custom("NotoSerifSC-ExtraLight", size: 13, relativeTo: .footnote)).tracking(1.5)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .foregroundStyle(.white.opacity(on ? 0.95 : 0.62))
                .background(Capsule().fill(.white.opacity(on ? 0.1 : 0)))
                .overlay(Capsule().stroke(.white.opacity(on ? 0.5 : 0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("memory-door-\(title)")
    }

    private var hint: some View {
        Text(atlas.stars.isEmpty ? " " : "拖动看星空 · 双指放大 · 点一颗星")
            .font(.custom("NotoSerifSC-ExtraLight", size: 12, relativeTo: .caption)).tracking(1)
            .foregroundStyle(.white.opacity(0.55)).padding(.bottom, 18)
            .accessibilityHidden(true)
    }

    private var cards: some View {
        VStack(spacing: 8) {
            if let focusID, let i = deck.firstIndex(where: { $0.id == focusID }) {
                Text("\(i + 1) / \(deck.count)").font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.5))
            } else {
                Text("\(deck.count) 颗星 · 左右翻看").font(.caption2).foregroundStyle(.white.opacity(0.5))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(deck) { flower in
                        StarMemoryCard(flower: flower, focused: flower.id == focusID, busy: store.busy,
                                       onOpen: { onOpen(flower) }, onLove: { onLove(flower) })
                            .containerRelativeFrame(.horizontal) { width, _ in min(width - 64, 420) }
                            .id(flower.id)
                    }
                }.scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $focusID)
            .contentMargins(.horizontal, 32, for: .scrollContent)
            .frame(height: 178)
        }.padding(.bottom, 12)
    }

    private func enter(_ key: String?) {
        focusID = nil
        door = key
        if let key, let center = atlas.center(of: key) {
            motion.fly(to: StarCamera(x: center.x, y: center.y + 90, zoom: 0.95), duration: reduceMotion ? 0 : 1.1)
        } else {
            motion.fly(to: .overview, duration: reduceMotion ? 0 : 1.1)
        }
    }

    private func tapped(_ id: String?) {
        guard let id, let star = atlas.star(id) else {
            if focusID != nil { focusID = nil } else if door != nil { enter(nil) }
            return
        }
        if door != star.category { enter(star.category) }
        // 等卡片排好再翻到这一颗
        Task { @MainActor in
            await Task.yield()
            focusID = id
        }
    }

    private func rebuild() {
        atlas = StarAtlas(flowers: flowers, categories: store.categories)
        if let door, atlas.center(of: door) == nil { self.door = nil }
        if let focusID, atlas.star(focusID) == nil { self.focusID = nil }
        welcomeNewMemory()
    }

    /// 柯上次之后新记的事：一颗流星划过来，落下变成新星。
    private func welcomeNewMemory() {
        guard store.loaded else { return }
        let mine = store.flowers.filter { $0.author == "ke" && $0.isDrawable }
        guard let newest = mine.compactMap(\.written_at).max() else { return }
        defer { lastSeen = max(lastSeen, newest) }
        guard newest > lastSeen,
              let target = mine.first(where: { $0.written_at == newest }), atlas.star(target.id) != nil,
              !reduceMotion else { return }
        let start = Date().addingTimeInterval(0.9)
        motion.meteors.append(StarMeteor(target: target.id, start: start, duration: 1.6, from: CGPoint(x: 0.85, y: -0.03)))
        motion.hiddenUntil[target.id] = start.addingTimeInterval(1.6)
        if let center = atlas.center(of: target.category) {
            motion.fly(to: StarCamera(x: center.x, y: center.y + 60, zoom: 0.85), duration: 1.2)
        }
        withAnimation(.easeOut(duration: 0.6)) { toast = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeIn(duration: 0.8)) { toast = false }
            motion.meteors.removeAll { $0.start.addingTimeInterval($0.duration) < Date() }
        }
    }
}

private struct StarMemoryCard: View {
    let flower: MemoryFlower
    let focused: Bool
    let busy: Bool
    var onOpen: () -> Void
    var onLove: () -> Void
    private static let rose = Color(red: 0.91, green: 0.66, blue: 0.71)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(flower.author == "ke" ? "柯亲手记下" : "以前整理的").tracking(1.5)
                Text(dateText).font(.custom("Allura-Regular", size: 15))
                Spacer()
                Button(action: onLove) {
                    Image(systemName: flower.loved ? "heart.fill" : "heart")
                        .foregroundStyle(Self.rose).frame(width: 36, height: 30)
                }
                .buttonStyle(.plain).disabled(busy)
                .accessibilityLabel(flower.loved ? "取消喜欢" : "这颗我很喜欢")
                .accessibilityIdentifier("memory-card-love-\(flower.id)")
            }
            .font(.caption2).foregroundStyle(.white.opacity(0.55))
            Text(flower.title)
                .font(.custom("NotoSerifSC-ExtraLight", size: 19, relativeTo: .headline)).lineLimit(1)
            Text(flower.body)
                .font(.custom("NotoSerifSC-ExtraLight", size: 13.5, relativeTo: .subheadline))
                .lineSpacing(4).lineLimit(flower.quotes.isEmpty ? 3 : 2).foregroundStyle(.white.opacity(0.82))
            if let quote = flower.quotes.first {
                Text("「\(quote)」").font(.caption).lineLimit(1).foregroundStyle(.white.opacity(0.55))
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) { Rectangle().fill(Self.rose.opacity(0.55)).frame(width: 1.5) }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.94))
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(.white.opacity(focused ? 0.34 : 0.14), lineWidth: 1))
        .scaleEffect(focused ? 1 : 0.94)
        .opacity(focused ? 1 : 0.75)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: focused)
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "打开", onOpen)
        .accessibilityIdentifier("memory-star-\(flower.id)")
    }

    private var dateText: String {
        let raw = flower.occurred_at ?? flower.written_at ?? ""
        let parts = raw.prefix(10).split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return "" }
        return "\(m).\(d)"
    }
}
