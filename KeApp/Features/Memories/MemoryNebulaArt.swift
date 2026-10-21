import SwiftUI
import ImageIO

// 129：记忆星河改成六团星云（10-21 她定的）。画法照 GPT 的星河包（six-worlds.mjs / star-seats.mjs）一笔一笔搬过来：
// 同一张 640×640 的画布、同样的颜色和形状。不用照片，全是程序画的。
// 每团画一次就记住（贴图），之后只是挪、转、拉近，不再重画——所以不卡。

enum NebulaKind: String, CaseIterable, Identifiable {
    case pleiades, orion, sombrero, heart, horsehead, whirlpool
    var id: String { rawValue }
}

struct NebulaGroup: Identifiable, Equatable {
    let kind: NebulaKind
    let name: String
    let astro: String
    let hue: Double
    let desc: String
    /// 厚度：从正面看不出来，转到侧面就是这团的「厚」。星团圆一点，旋涡星系薄一点，中心鼓起来
    let thickness: Double
    var id: String { name }

    static let all: [NebulaGroup] = [
        NebulaGroup(kind: .pleiades, name: "日常吃喝", astro: "昴星团 · M45", hue: 214, desc: "奶茶、千层，还有路边的小店。\n很小的快乐，一颗一颗亮着。", thickness: 0.5),
        NebulaGroup(kind: .orion, name: "身体和药", astro: "猎户座大星云 · M42", hue: 300, desc: "把累了的时候，轻轻包起来。\n在这一团里，可以慢慢休息。", thickness: 0.34),
        NebulaGroup(kind: .sombrero, name: "以后的家", astro: "草帽星系 · M104", hue: 38, desc: "一圈温柔的屋檐，\n里面留着一盏等我们的灯。", thickness: 0.22),
        NebulaGroup(kind: .heart, name: "亲密时刻", astro: "心脏星云 · IC 1805", hue: 352, desc: "一些只属于我们的话，\n被柔软的红色星云抱着。", thickness: 0.3),
        NebulaGroup(kind: .horsehead, name: "难过的夜里", astro: "马头星云 · Barnard 33", hue: 338, desc: "有些夜晚很暗。\n但光，一直在后面。", thickness: 0.26),
        NebulaGroup(kind: .whirlpool, name: "说好的", astro: "涡状星系 · M51", hue: 215, desc: "拉过钩的事，放在这里。\n一件一件，慢慢做到。", thickness: 0.16),
    ]
    static func named(_ name: String) -> NebulaGroup? { all.first { $0.name == name } }
    static let background = "背景"

    /// 服务器还没给 group 的（旧服务器、刚记下还没分的）：按原来的分类先放进去，和服务器那边同一张表
    static func groupName(for flower: MemoryFlower) -> String {
        if let g = flower.group, !g.isEmpty { return g }
        switch flower.category {
        case "医疗", "身体", "健康": return "身体和药"
        case "恋爱": return "亲密时刻"
        case "心理": return "难过的夜里"
        case "约定", "关系": return "说好的"
        case "居家": return "以后的家"
        default: return "日常吃喝"
        }
    }
}

// MARK: - 颜色、噪声（和网页版同一套公式）

enum NebulaPaint {
    static func rgb(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        let hh = ((h.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) / 360
        let ss = s / 100, ll = l / 100
        let a = ss * min(ll, 1 - ll)
        func f(_ n: Double) -> Double {
            let k = (n + hh * 12).truncatingRemainder(dividingBy: 12)
            return ll - a * max(-1, min(k - 3, 9 - k, 1))
        }
        return (f(0), f(8), f(4))
    }
    static func cg(_ h: Double, _ s: Double, _ l: Double, _ a: Double = 1) -> CGColor {
        let c = rgb(h, s, l)
        return CGColor(red: c.0, green: c.1, blue: c.2, alpha: max(0, min(1, a)))
    }
    static func color(_ h: Double, _ s: Double, _ l: Double, _ a: Double = 1) -> Color {
        let c = rgb(h, s, l)
        return Color(red: c.0, green: c.1, blue: c.2).opacity(max(0, min(1, a)))
    }
    static func hash(_ x: Double, _ y: Double) -> Double {
        let n = sin(x * 127.1 + y * 311.7) * 43758.5453
        return n - floor(n)
    }
    static func noise(_ x: Double, _ y: Double) -> Double {
        let ix = floor(x), iy = floor(y)
        var u = x - ix, v = y - iy
        u = u * u * (3 - 2 * u); v = v * v * (3 - 2 * v)
        return (hash(ix, iy) * (1 - u) + hash(ix + 1, iy) * u) * (1 - v) + (hash(ix, iy + 1) * (1 - u) + hash(ix + 1, iy + 1) * u) * v
    }
    static func fbm(_ x: Double, _ y: Double) -> Double {
        noise(x, y) * 0.55 + noise(x * 2.1 + 11, y * 2.1) * 0.27 + noise(x * 4.3, y * 4.3 + 7) * 0.13 + noise(x * 8.8, y * 8.8) * 0.05
    }
}

/// 网页版的 random(seed)：同一个种子，同一串数
struct NebulaRandom {
    private var s: UInt32
    init(_ seed: UInt32) { s = seed }
    mutating func next() -> Double {
        s = s &* 1_664_525 &+ 1_013_904_223
        return Double(s) / 4_294_967_296
    }
    mutating func normal() -> Double { sqrt(-2 * log(max(0.000_01, next()))) * cos(next() * 2 * .pi) }
    static func hash(_ text: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for byte in text.utf8 { h ^= UInt32(byte); h = h &* 16_777_619 }
        return h
    }
}

// MARK: - 画一团

/// 画好的一团：贴图（给眼睛看）+ 亮度图（给记忆星和星尘找位置）+ 星尘（转到侧面时撑起厚度）
final class NebulaArt: @unchecked Sendable {
    static let size = 640
    /// 贴图比 640 大一倍半画，拉近了不糊
    static let scale: CGFloat = 1.5
    let image: Image
    let thumb: Image
    /// 128×128，0…1
    let density: [Double]
    let densityMax: Double
    /// 这一团亮光的重心（盘面坐标）：转和放都绕着它，画面上它在正中
    let centroid: SIMD2<Double>
    /// 星尘：盘面坐标 (u, v, z)，-1…1；按亮度分四档，画的时候一档一笔
    let dust: [[SIMD3<Double>]]

    private init(image: Image, thumb: Image, density: [Double], dust: [[SIMD3<Double>]]) {
        self.image = image; self.thumb = thumb; self.density = density
        densityMax = max(0.0001, density.max() ?? 1)
        self.dust = dust
        var sx = 0.0, sy = 0.0, sw = 0.0
        for y in 0..<128 { for x in 0..<128 {
            let w = density[y * 128 + x]; guard w > 0.02 else { continue }
            sx += w * ((Double(x) + 0.5) / 64 - 1); sy += w * ((Double(y) + 0.5) / 64 - 1); sw += w
        } }
        centroid = sw > 0 ? SIMD2(sx / sw, sy / sw) : .zero
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [NebulaKind: NebulaArt] = [:]

    static func cached(_ kind: NebulaKind) -> NebulaArt? {
        lock.lock(); defer { lock.unlock() }
        return cache[kind]
    }
    /// 第一次用的时候在后台画；画好就一直留着
    static func art(_ kind: NebulaKind) -> NebulaArt {
        if let a = cached(kind) { return a }
        let group = NebulaGroup.all.first { $0.kind == kind }!
        // 130：画过一次就存到手机里，下次直接读（以前每次打开都重画，要等一会儿）
        let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("nebula-v130-\(kind.rawValue).png")
        var image: CGImage?
        if let src = CGImageSourceCreateWithURL(file as CFURL, nil) { image = CGImageSourceCreateImageAtIndex(src, 0, nil) }
        if image == nil {
            image = render(group)
            if let image, let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
            }
        }
        let a = finish(image!, group)
        lock.lock(); cache[kind] = a; lock.unlock()
        return a
    }
    /// 一打开 App 就在后台把六团画好（或者从手机里读出来），点进记忆不用等
    static func prewarm() {
        Task.detached(priority: .utility) {
            for k in [NebulaKind.whirlpool, .orion, .pleiades, .sombrero, .horsehead, .heart] { _ = art(k) }
        }
    }

    /// 盘面上 (u, v) 处有多亮，0…1
    func brightness(_ u: Double, _ v: Double) -> Double {
        let x = Int(((u + 1) / 2 * 128).rounded(.down)), y = Int(((v + 1) / 2 * 128).rounded(.down))
        guard x >= 0, x < 128, y >= 0, y < 128 else { return 0 }
        return density[y * 128 + x] / densityMax
    }

    /// 一颗记忆星住哪儿：只看它自己的 id（新记的不会把旧的挤走），落在亮的地方，越亮越容易落
    private var seats: [String: SIMD3<Double>] = [:]
    private let seatLock = NSLock()
    func seat(for id: String, thickness: Double) -> SIMD3<Double> {
        seatLock.lock(); defer { seatLock.unlock() }
        if let s = seats[id] { return s }
        let s = findSeat(id, thickness)
        seats[id] = s
        return s
    }
    private func findSeat(_ id: String, _ thickness: Double) -> SIMD3<Double> {
        var random = NebulaRandom(NebulaRandom.hash(id))
        for _ in 0..<400 {
            let u = random.next() * 1.7 - 0.85, v = random.next() * 1.7 - 0.85
            let b = brightness(u, v)
            if random.next() < pow(b, 0.55) * 0.95 {
                return SIMD3(u, v, Self.depth(&random, b, thickness))
            }
        }
        return SIMD3(random.next() * 0.4 - 0.2, random.next() * 0.4 - 0.2, 0)
    }
    /// 厚度跟着形状走：亮的、密的地方厚，边上薄，所以转到侧面是这一团自己的轮廓，不是一块板
    static func depth(_ random: inout NebulaRandom, _ b: Double, _ thickness: Double) -> Double {
        random.normal() * thickness * (0.12 + 0.88 * sqrt(b)) * 0.5
    }

    // MARK: 画布（坐标和网页一样：左上角是原点，y 往下）

    private static func render(_ g: NebulaGroup) -> CGImage? {
        let px = Int(CGFloat(size) * scale)
        let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(px)); ctx.scaleBy(x: scale, y: -scale)
        let index = Double(NebulaGroup.all.firstIndex(of: g) ?? 0)
        var rng = NebulaRandom(UInt32(1021 + index * 109))
        let painter = Painter(ctx: ctx)
        painter.body(g, &rng)
        return ctx.makeImage()
    }

    private static func finish(_ cg: CGImage, _ g: NebulaGroup) -> NebulaArt {
        let index = Double(NebulaGroup.all.firstIndex(of: g) ?? 0)
        // 亮度图：整张缩到 128 格，每格的平均亮度
        var density = [Double](repeating: 0, count: 128 * 128)
        var small = [UInt8](repeating: 0, count: 128 * 128 * 4)
        small.withUnsafeMutableBytes { raw in
            guard let c = CGContext(data: raw.baseAddress, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 128 * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            c.interpolationQuality = .medium
            c.draw(cg, in: CGRect(x: 0, y: 0, width: 128, height: 128))
        }
        for i in 0..<(128 * 128) {
            density[i] = (Double(small[i * 4]) + Double(small[i * 4 + 1]) + Double(small[i * 4 + 2])) / 765
        }
        // 缩略图（整片星河那一页用）：256 就够
        let t = 256
        let tctx = CGContext(data: nil, width: t, height: t, bitsPerComponent: 8, bytesPerRow: t * 4,
                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        tctx.interpolationQuality = .high
        tctx.draw(cg, in: CGRect(x: 0, y: 0, width: t, height: t))
        let thumb = tctx.makeImage()!
        let art = NebulaArt(image: Image(decorative: cg, scale: 1), thumb: Image(decorative: thumb, scale: 1),
                            density: density, dust: [])
        // 星尘：照亮度撒，越亮越多；四档亮度
        var dust: [[SIMD3<Double>]] = [[], [], [], []]
        var r = NebulaRandom(UInt32(77 + index * 13))
        let want = g.kind == .pleiades ? 1400 : 2200
        var tries = 0
        while dust.reduce(0, { $0 + $1.count }) < want && tries < 60_000 {
            tries += 1
            let u = r.next() * 1.8 - 0.9, v = r.next() * 1.8 - 0.9
            let b = art.brightness(u, v)
            guard r.next() < b * 1.1 else { continue }
            let level = min(3, Int(b * 4))
            dust[level].append(SIMD3(u, v, depth(&r, b, g.thickness)))
        }
        return NebulaArt(image: art.image, thumb: art.thumb, density: density, dust: dust)
    }
}

/// 网页版 renderBody 的搬运
private struct Painter {
    let ctx: CGContext
    static let tau = Double.pi * 2

    func glow(_ x: Double, _ y: Double, _ r: Double, _ h: Double = 215, _ a: Double = 0.5) {
        let colors = [NebulaPaint.cg(h, 45, 90, a), NebulaPaint.cg(h, 52, 76, a * 0.68), NebulaPaint.cg(h, 55, 55, a * 0.2), NebulaPaint.cg(h, 55, 40, 0)] as CFArray
        guard let gr = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.12, 0.45, 1]) else { return }
        ctx.drawRadialGradient(gr, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
    }
    func dot(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: CGColor) {
        ctx.setFillColor(color); ctx.fill(CGRect(x: x, y: y, width: w, height: h))
    }
    func star(_ x: Double, _ y: Double, _ r: Double, _ h: Double = 215, bright: Bool = true) {
        glow(x, y, r * 8, h, bright ? 0.66 : 0.25)
        ctx.setFillColor(CGColor(red: 249 / 255, green: 244 / 255, blue: 239 / 255, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: x - r * 0.6, y: y - r * 0.6, width: r * 1.2, height: r * 1.2))
        // 130 她：不要十字星芒
    }
    func dust(_ rng: inout NebulaRandom, _ h: Double, _ count: Int = 1500, _ spread: Double = 160) {
        for _ in 0..<count {
            let a = rng.next() * Self.tau, r = pow(rng.next(), 0.7) * spread
            let x = 320 + cos(a) * r, y = 320 + sin(a) * r * 0.8
            dot(x, y, 0.5 + rng.next(), 0.5 + rng.next(), NebulaPaint.cg(h, 25, 70 + rng.next() * 24, 0.12 + rng.next() * 0.45))
        }
    }
    /// 星云的气：一张 420 的图，每个点自己算浓淡，铺到 (40,40,560,560)
    func cloud(_ kind: NebulaKind, _ hue: Double) {
        let n = 420
        var buf = [UInt8](repeating: 0, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let u = (Double(x) - Double(n) / 2) / (Double(n) * 0.38), v = (Double(y) - Double(n) / 2) / (Double(n) * 0.38)
                let f = NebulaPaint.fbm(u * 3.2 + 12, v * 3.2 + 8), r = hypot(u, v)
                var dens = 0.0, h = hue, l = 50.0
                switch kind {
                case .orion:
                    let warp = NebulaPaint.fbm(u * 2 + 5, v * 2 + 3), a = atan2(v, u)
                    let boundary = 0.65 + 0.15 * sin(a * 3 + 0.8) + 0.13 * sin(a * 5) + 0.25 * warp
                    dens = max(0, 1 - r / boundary)
                    dens = pow(dens, 0.6) * max(0, f - 0.24) * 2.3
                    let cavity = exp(-(pow(u + 0.05, 2) * 22 + pow(v + 0.02, 2) * 28))
                    dens *= 1 - cavity * 0.5
                    h = hue + 28 * u; l = 45 + dens * 42
                case .heart:
                    let xx = u * 1.32 + (f - 0.5) * 0.12, yy = -v * 1.32 + 0.18
                    let implicit = pow(xx * xx + yy * yy - 1, 3) - xx * xx * pow(yy, 3)
                    let shell = exp(-abs(implicit) * 22), inside = implicit < 0 ? 0.25 : 0
                    let fade = max(0, 1 - max(0, r - 1.18) * 3)
                    dens = (shell * 0.46 + inside) * (0.25 + f * 0.95) * fade
                    h = hue + (f - 0.5) * 15; l = 45 + f * 30
                case .horsehead:
                    let ridge = 0.18 + sin(u * 2) * 0.1
                    dens = exp(-pow((v - ridge) * 2.2, 2)) * exp(-u * u * 1.4) * (0.22 + f * 0.65)
                    h = hue + 10 * f; l = 35 + f * 25
                default: break
                }
                let c = NebulaPaint.rgb(h, kind == .heart ? 60 : 42, l)
                let a = min(255, dens * 245) / 255
                let i = (y * n + x) * 4
                buf[i] = UInt8(max(0, min(255, c.0 * 255 * a))); buf[i + 1] = UInt8(max(0, min(255, c.1 * 255 * a)))
                buf[i + 2] = UInt8(max(0, min(255, c.2 * 255 * a))); buf[i + 3] = UInt8(a * 255)
            }
        }
        drawBuffer(&buf, n, in: CGRect(x: 40, y: 40, width: 560, height: 560))
    }
    /// 一行一行从上往下的像素，画到 rect（画布已经是 y 朝下，这里翻回来）
    func drawBuffer(_ buf: inout [UInt8], _ n: Int, in rect: CGRect) {
        let image: CGImage? = buf.withUnsafeMutableBytes { raw in
            guard let c = CGContext(data: raw.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            return c.makeImage()
        }
        guard let image else { return }
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY); ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }
    func spiral(_ rng: inout NebulaRandom, _ cx: Double, _ cy: Double, _ rad: Double, _ h: Double, arms: Int = 2) {
        glow(cx, cy, rad * 0.95, h, 0.24)
        for i in 0..<24_000 {
            let r = pow(rng.next(), 0.65) * rad
            let a = Double(i % arms) * Self.tau / Double(arms) + r / rad * 6.6 + (rng.next() - 0.5) * (0.42 + 1.2 * r / rad)
            let spread = (rng.next() - 0.5) * rad * 0.13
            let x = cx + cos(a) * (r + spread), y = cy + sin(a) * (r + spread) * 0.8
            let odd = i % 11 == 0
            dot(x, y, 0.55 + rng.next() * 0.85, 0.55 + rng.next() * 0.85,
                NebulaPaint.cg(h + (odd ? 110 : 0), odd ? 35 : 23, 62 + rng.next() * 30, (1 - r / rad) * 0.27 + 0.06))
        }
        for _ in 0..<3800 {
            let r = pow(rng.next(), 0.7) * rad, a = rng.next() * Self.tau
            dot(cx + cos(a) * r, cy + sin(a) * r * 0.8, 0.6, 0.6, NebulaPaint.cg(h, 22, 72, 0.08 + rng.next() * 0.08))
        }
        glow(cx, cy, rad * 0.33, 38, 0.8); glow(cx, cy, rad * 0.095, 42, 0.9)
    }
    func horseDust() {
        let s = NebulaArt.size
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 130, y: 568))
        let curves: [(Double, Double, Double, Double, Double, Double)] = [
            (180, 526, 214, 490, 243, 447), (253, 430, 272, 408, 271, 388), (269, 365, 257, 349, 263, 327),
            (257, 311, 264, 294, 260, 280), (262, 265, 274, 252, 269, 237)]
        for c in curves { path.addCurve(to: CGPoint(x: c.4, y: c.5), control1: CGPoint(x: c.0, y: c.1), control2: CGPoint(x: c.2, y: c.3)) }
        for p in [(263.0, 219.0), (279, 226), (294, 215), (312, 218)] { path.addLine(to: CGPoint(x: p.0, y: p.1)) }
        path.addCurve(to: CGPoint(x: 333, y: 242), control1: CGPoint(x: 321, y: 224), control2: CGPoint(x: 331, y: 231))
        path.addCurve(to: CGPoint(x: 354, y: 260), control1: CGPoint(x: 342, y: 247), control2: CGPoint(x: 338, y: 255))
        path.addLine(to: CGPoint(x: 378, y: 272))
        path.addCurve(to: CGPoint(x: 379, y: 293), control1: CGPoint(x: 390, y: 277), control2: CGPoint(x: 391, y: 287))
        path.addLine(to: CGPoint(x: 352, y: 291))
        let tail: [(Double, Double, Double, Double, Double, Double)] = [
            (345, 293, 344, 305, 330, 308), (325, 319, 332, 336, 331, 350), (339, 362, 337, 374, 350, 392),
            (364, 410, 374, 429, 392, 448), (427, 479, 457, 489, 493, 535)]
        for c in tail { path.addCurve(to: CGPoint(x: c.4, y: c.5), control1: CGPoint(x: c.0, y: c.1), control2: CGPoint(x: c.2, y: c.3)) }
        path.addLine(to: CGPoint(x: 507, y: 580)); path.closeSubpath()
        // 马头的剪影：深色，带一点颗粒，越往下越淡
        var mask = [UInt8](repeating: 0, count: s * s)
        mask.withUnsafeMutableBytes { raw in
            guard let m = CGContext(data: raw.baseAddress, width: s, height: s, bitsPerComponent: 8, bytesPerRow: s,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            m.translateBy(x: 0, y: CGFloat(s)); m.scaleBy(x: 1, y: -1)
            m.setShouldAntialias(true)
            m.setFillColor(gray: 1, alpha: 1); m.addPath(path); m.fillPath()
        }
        var buf = [UInt8](repeating: 0, count: s * s * 4)
        for y in 0..<s {
            for x in 0..<s {
                let mv = Double(mask[y * s + x]) / 255
                guard mv > 0 else { continue }
                let grain = NebulaPaint.fbm(Double(x) * 0.048 + 4, Double(y) * 0.048 + 9)
                let fade = max(0, min(1, (532 - Double(y)) / 135))
                let a = mv * fade * (0.7 + grain * 0.45)
                let i = (y * s + x) * 4
                buf[i] = UInt8(min(255, (8 + grain * 8) * a)); buf[i + 1] = UInt8(min(255, (8 + grain * 5) * a))
                buf[i + 2] = UInt8(min(255, (16 + grain * 9) * a)); buf[i + 3] = UInt8(min(255, a * 255))
            }
        }
        drawBuffer(&buf, s, in: CGRect(x: 0, y: 0, width: s, height: s))
    }

    static let sisters: [(Double, Double)] = [(216, 210), (407, 222), (202, 342), (335, 424), (322, 258), (386, 319), (282, 357)]
    static let trapezium: [(Double, Double)] = [(278, 270), (356, 266), (282, 346), (360, 347)]

    func body(_ g: NebulaGroup, _ rng: inout NebulaRandom) {
        let h = g.hue
        switch g.kind {
        case .pleiades:
            let sizes = [4, 3.4, 3.5, 4.5, 5.5, 5, 6]
            for (x, y) in Self.sisters {
                ctx.saveGState(); ctx.translateBy(x: x, y: y); ctx.rotate(by: -0.5); ctx.scaleBy(x: 0.65, y: 1.8)
                glow(0, 0, 68, h, 0.38); ctx.restoreGState()
            }
            for _ in 0..<2400 {
                let x = 150 + rng.next() * 340, y = 150 + rng.next() * 330
                let a = exp(-(pow(x - 320, 2) + pow(y - 310, 2)) / 17000)
                dot(x, y, 0.8, 1.7, NebulaPaint.cg(h, 48, 70, 0.025 + a * 0.15 * rng.next()))
            }
            dust(&rng, h, 150, 210)
            for (i, p) in Self.sisters.enumerated() { star(p.0, p.1, sizes[i], h) }
        case .orion:
            cloud(.orion, h); dust(&rng, h, 1300, 175); glow(316, 304, 90, 220, 0.55)
            for p in Self.trapezium { star(p.0, p.1, 2.6, h, bright: false) }
            star(192, 375, 2, h, bright: false); star(426, 210, 2.5, h, bright: false)
        case .sombrero:
            ctx.saveGState(); ctx.translateBy(x: 320, y: 310); ctx.rotate(by: -0.2)
            ctx.saveGState(); ctx.scaleBy(x: 1, y: 0.38); glow(0, 0, 250, h, 0.7); ctx.restoreGState()
            ctx.saveGState(); ctx.scaleBy(x: 1, y: 0.7); glow(0, -10, 125, h, 0.8); ctx.restoreGState()
            for _ in 0..<17_000 {
                let r = pow(rng.next(), 0.7) * 226, a = rng.next() * Self.tau
                dot(cos(a) * r, sin(a) * r * 0.22, 0.6 + rng.next(), 0.6 + rng.next(), NebulaPaint.cg(h, 25, 70 + rng.next() * 28, 0.12 + (1 - r / 230) * 0.4))
            }
            glow(0, -10, 36, h, 0.9)
            ctx.restoreGState()
        case .heart:
            cloud(.heart, h); dust(&rng, h, 650, 155); glow(318, 320, 38, h, 0.16)
        case .horsehead:
            cloud(.horsehead, h); horseDust(); glow(260, 470, 100, h, 0.11)
            star(433, 214, 3.8, 30); star(183, 305, 2, h)
        case .whirlpool:
            ctx.saveGState(); ctx.translateBy(x: 20, y: 35); ctx.rotate(by: -0.08)
            spiral(&rng, 280, 330, 183, h)
            for _ in 0..<2800 {
                let t = rng.next(), x = 305 + 123 * t + sin(t * 3) * 38 + (rng.next() - 0.5) * 28, y = 237 - 72 * t + (rng.next() - 0.5) * 23
                dot(x, y, 0.8, 0.8, NebulaPaint.cg(37, 24, 80, 0.12 + rng.next() * 0.28))
            }
            spiral(&rng, 435, 158, 62, 38)
            ctx.restoreGState()
        }
    }
}

// MARK: - 镜头：转（左右、上下都能转一整圈）、拉近、挪

struct NebulaCamera: Equatable {
    var yaw = 0.0
    var pitch = 0.0
    var zoom = 1.0
    var pan = CGSize.zero
    static let home = NebulaCamera()
}

/// 盘面 (u, v, z) → 屏幕。正投影：贴图和星用同一套算法，点哪颗都准
struct NebulaProjection {
    let camera: NebulaCamera
    let size: CGSize
    /// 说好的那团自己慢慢转（像钟），只在盘面里转
    let spin: Double
    /// 这一团的重心：绕它转、它在屏幕正中
    var origin = SIMD2<Double>(0, 0)

    /// 130：上面标题、下面按钮之间那一块的正中（以前偏上）
    static let topBand: CGFloat = 236, bottomBand: CGFloat = 120
    static func screenCenter(_ size: CGSize, _ pan: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + pan.width, y: (topBand + max(topBand + 100, size.height - bottomBand)) / 2 + pan.height)
    }
    static func baseScale(_ size: CGSize) -> Double {
        Double(min(size.width * 0.94, max(240, size.height - topBand - bottomBand))) * 0.62
    }
    var scale: Double { Self.baseScale(size) * camera.zoom }
    var center: CGPoint { Self.screenCenter(size, camera.pan) }

    /// 返回屏幕上的点、远近（越大越近）
    func project(_ p: SIMD3<Double>) -> (CGPoint, Double) {
        let cs = cos(spin), ss = sin(spin)
        let px = p.x - origin.x, py = p.y - origin.y
        let u = px * cs - py * ss, v = px * ss + py * cs
        let cy = cos(camera.yaw), sy = sin(camera.yaw), cp = cos(camera.pitch), sp = sin(camera.pitch)
        let x1 = u * cy + p.z * sy, z1 = -u * sy + p.z * cy
        let y2 = v * cp - z1 * sp, z2 = v * sp + z1 * cp
        return (CGPoint(x: center.x + x1 * scale, y: center.y + y2 * scale), z2)
    }
    /// 贴图（z = 0 那一层）在屏幕上的样子
    var planeTransform: CGAffineTransform {
        let cy = cos(camera.yaw), sy = sin(camera.yaw), cp = cos(camera.pitch), sp = sin(camera.pitch)
        let cs = cos(spin), ss = sin(spin)
        // 先在盘面里转 spin，再左右转、上下转
        let a = cy, b = sp * sy, c = 0.0, d = cp
        let m = CGAffineTransform(a: a, b: b, c: c, d: d, tx: 0, ty: 0)
        let s = CGAffineTransform(a: cs, b: ss, c: -ss, d: cs, tx: 0, ty: 0)
        return CGAffineTransform(translationX: -origin.x, y: -origin.y)
            .concatenating(s).concatenating(m).concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
    }
    /// 正对着看是 1，转到侧面是 0
    var facing: Double { abs(cos(camera.yaw) * cos(camera.pitch)) }
}
