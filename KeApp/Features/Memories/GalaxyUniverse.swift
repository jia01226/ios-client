import MetalKit
import SwiftUI
import UIKit
import simd

// MARK: - 11-27 新星河（整片宇宙，显卡画）
// 她对着效果图改了十几版，最后定的（记在 memory-galaxy-redesign）：
// 中间只有一个——起先是草帽星系的真照片，后来她说换成发光的月亮；不写字；所有记忆是散在四周的星星，绕着它慢慢转（里圈快、外圈慢），一类一个颜色（GalaxyInk）；
// 下面一排分类按钮（带颜色小圆点，也是图例），点一类那一类亮起来、别的暗下去；
// 背景三层星星（远的动得慢）、一层紫色星盘的尘；偶尔划过白色小流星；
// 新记忆是一颗金色流星，划进它那颗星的位置，落下闪一下变成「新」星。1–3 条一颗接一颗，4 条以上流星雨。点任何一颗星出卡片。

struct GalaxySprite { var posSize: SIMD4<Float>; var color: SIMD4<Float>; var meta: SIMD4<UInt32> }
struct GalaxyQuad { var center: SIMD4<Float>; var tint: SIMD4<Float>; var meta: SIMD4<UInt32>; var extra: SIMD4<Float> }
struct GalaxyStreak { var a: SIMD4<Float>; var b: SIMD4<Float>; var ca: SIMD4<Float>; var cb: SIMD4<Float> }
struct GalaxyUniforms {
    var viewProj: simd_float4x4
    var view: simd_float4x4
    var proj: simd_float4x4
    var viewport: SIMD2<Float>
    var time: Float
    var projScale: Float
    var orbit: Float
    var focus: Float
}

/// 一颗要画的记忆星
struct GalaxyMember: Equatable {
    let id: String
    /// 柯亲手记的，亮一点
    let bright: Bool
    /// 这几天新记的：金色、会闪、标「新」
    let recent: Bool
}

struct GalaxyInput {
    var members: [NebulaKind: [GalaxyMember]] = [:]
    /// 这次打开才看到的新记忆（按时间先后）：一颗颗流星送进去
    var arrivals: [String] = []
    /// 她点亮的那一类（nil 是全部）
    var focus: NebulaKind?
    /// 正打开着卡片的那颗（镜头飞过去放大，关了再缩回来）
    var selected: String?
    /// 外面的东西变了就加一，这边才重新摆星
    var version = 0
}

enum GalaxyLayout {
    /// 分类的固定顺序（着色器里用下标认是哪一类）
    static let kinds: [NebulaKind] = [.whirlpool, .andromeda, .pleiades, .orion, .heart, .lessons, .sombrero, .horsehead]
    /// 中间那轮月亮（照片）在世界里的半边长
    static let core: Float = 130
    /// 记忆星住的那一圈：从多远到多远
    static let inner: Double = 250, outer: Double = 640
    /// 半径 230 那一圈转一圈要多久（秒）；里圈快、外圈慢
    static let period: Double = 200

    /// 一颗记忆星住哪儿：只看它自己的 id（新记的不会把旧的挤走）。返回（半径、起始角、高度）
    static func seat(_ id: String) -> SIMD3<Float> {
        var r = NebulaRandom(NebulaRandom.hash(id) ^ 0x9E37_79B9)
        let radius = inner + pow(r.next(), 0.85) * (outer - inner)
        let angle = r.next() * 2 * .pi
        let lift = r.normal() * 14 * radius / 450
        return SIMD3(Float(radius), Float(angle), Float(lift))
    }
    /// 转了 orbit 以后，这颗星在世界里的位置（和着色器里同一个算法）
    static func world(_ p: SIMD3<Float>, orbit: Float) -> SIMD3<Float> {
        let a = p.y + orbit * 230 / max(p.x, 60)
        return SIMD3(cos(a) * p.x, p.z, sin(a) * p.x)
    }
}

// MARK: 真照片
/// 11-27 她：「还是很像贴纸」——七团换成真的星云照片（哈勃 / NASA / 天文爱好者拍的），北斗七星没有照片，照旧是七颗亮星。
/// 照片已经裁成正方形、天空底色压黑、边缘化进黑色（KeApp/Resources/Nebula），作者写在「…」→「照片来源」。
final class NebulaPhoto: @unchecked Sendable {
    let cgImage: CGImage
    /// 128×128 RGBA，给星星找亮处落脚、给云气取颜色
    private let px: [UInt8]

    private init(_ cg: CGImage) {
        cgImage = cg
        var buf = [UInt8](repeating: 0, count: 128 * 128 * 4)
        buf.withUnsafeMutableBytes { raw in
            if let c = CGContext(data: raw.baseAddress, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 512,
                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                c.interpolationQuality = .medium
                c.draw(cg, in: CGRect(x: 0, y: 0, width: 128, height: 128))
            }
        }
        px = buf
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [NebulaKind: NebulaPhoto?] = [:]
    static func of(_ kind: NebulaKind) -> NebulaPhoto? {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[kind] { return hit }
        let made = kind == .lessons ? nil : load("nebula-\(kind.rawValue)")
        cache[kind] = made
        return made
    }
    /// 11-27 她：「中间是发光的月球试试」——NASA 的满月照片
    static let moon: NebulaPhoto? = load("nebula-moon")
    private static func load(_ name: String) -> NebulaPhoto? {
        guard let path = Bundle.main.path(forResource: name, ofType: "jpg"), let cg = UIImage(contentsOfFile: path)?.cgImage else { return nil }
        return NebulaPhoto(cg)
    }
    /// 详情页（还是旧的画法）也换成这张
    static func image(_ kind: NebulaKind) -> Image? { of(kind).map { Image(decorative: $0.cgImage, scale: 1) } }

    private func at(_ u: Double, _ v: Double) -> Int? {
        let x = Int((u + 1) / 2 * 128), y = Int((v + 1) / 2 * 128)
        guard x >= 0, x < 128, y >= 0, y < 128 else { return nil }
        return (y * 128 + x) * 4
    }
    func brightness(_ u: Double, _ v: Double) -> Double {
        guard let i = at(u, v) else { return 0 }
        return (Double(px[i]) + Double(px[i + 1]) + Double(px[i + 2])) / 765
    }
    func color(_ u: Double, _ v: Double) -> SIMD3<Float> {
        guard let i = at(u, v) else { return .zero }
        return SIMD3(Float(px[i]), Float(px[i + 1]), Float(px[i + 2])) / 255
    }
    /// 一颗记忆星落在照片哪儿：只看它自己的 id，落在亮的地方
    func seat(for id: String) -> SIMD3<Double> {
        var r = NebulaRandom(NebulaRandom.hash(id))
        for _ in 0..<500 {
            let u = r.next() * 1.5 - 0.75, v = r.next() * 1.5 - 0.75
            if r.next() < pow(brightness(u, v) * 1.6, 0.6) { return SIMD3(u, v, r.normal() * 0.15) }
        }
        return SIMD3(r.next() * 0.6 - 0.3, r.next() * 0.6 - 0.3, 0)
    }

    static let credits = """
    说好的 · 涡状星系 M51：NASA、ESA（哈勃），公有领域
    关于她 · 仙女座星系：Adam Evans，CC BY 2.0
    日常吃喝 · 昴星团：NASA、ESA、AURA/Caltech、Palomar Observatory，公有领域
    身体和药 · 猎户座大星云：NASA、ESA、M. Robberto（哈勃），公有领域
    亲密时刻 · 心脏星云：JPedro Bento，CC BY 4.0
    以后的家 · 草帽星系：NASA/ESA、Hubble Heritage Team，公有领域
    难过的夜里 · 马头星云：Dylan O'Donnell，CC0
    中间的月亮：NASA Goddard Space Flight Center，公有领域
    照片都来自维基共享资源，裁剪、调暗了天空、边缘做了渐隐。
    """
}

// MARK: 镜头

struct GalaxyCameraState {
    var yaw: Float
    var pitch: Float
    var zoom: Float
    var target: SIMD3<Float>
    static let home = GalaxyCameraState(yaw: 0.3, pitch: 0.42, zoom: 1, target: .zero)
}

final class GalaxyCamera {
    var s = GalaxyCameraState.home
    var vYaw: Float = 0, vPitch: Float = 0
    var dragging = false
    var pinching = false
    /// 跟着哪一团（它在公转，镜头跟着走）
    var follow: Int?
    /// 11-27 点开一颗星：镜头一直跟着它（它在绕月亮转）
    var focusPoint: SIMD3<Float>?
    private var fly: (from: GalaxyCameraState, to: GalaxyCameraState, t0: Double, d: Double, done: (() -> Void)?)?
    var flying: Bool { fly != nil }
    var busy: Bool { dragging || pinching || fly != nil || abs(vYaw) + abs(vPitch) > 0.01 }

    func flyTo(_ to: GalaxyCameraState, duration: Double, now: Double, done: (() -> Void)? = nil) {
        vYaw = 0; vPitch = 0
        fly = (s, to, now, duration, done)
    }

    func update(now: Double, dt: Float, centers: [SIMD3<Float>]) {
        if let f = fly {
            let k = Float(min(1, (now - f.t0) / f.d)), e = 1 - pow(1 - k, 3)
            var to = f.to
            if let follow { to.target = centers[follow] }
            s.yaw = f.from.yaw + (to.yaw - f.from.yaw) * e
            s.pitch = f.from.pitch + (to.pitch - f.from.pitch) * e
            s.zoom = f.from.zoom + (to.zoom - f.from.zoom) * e
            s.target = f.from.target + (to.target - f.from.target) * e
            if k >= 1 { fly = nil; f.done?() }
        } else {
            if !dragging {
                s.yaw += vYaw * dt
                s.pitch += vPitch * dt
                let decay = exp(-dt * 3.2)
                vYaw *= decay; vPitch *= decay
                if abs(vYaw) < 0.002 { vYaw = 0 }
                if abs(vPitch) < 0.002 { vPitch = 0 }
            }
            if let follow { s.target += (centers[follow] - s.target) * min(1, dt * 8) }
            if let focusPoint { s.target += (focusPoint - s.target) * min(1, dt * 6) }
        }
        s.pitch = min(1.45, max(-1.2, s.pitch))
        s.zoom = min(4.5, max(0.45, s.zoom))
    }

    var eye: SIMD3<Float> {
        let d = 2050 / s.zoom
        return s.target + d * SIMD3(sin(s.yaw) * cos(s.pitch), sin(s.pitch), cos(s.yaw) * cos(s.pitch))
    }
}

// MARK: 矩阵

enum GalaxyMath {
    static func perspective(fovy: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let y = 1 / tan(fovy * 0.5), x = y / aspect, z = far / (near - far)
        return simd_float4x4(columns: (SIMD4(x, 0, 0, 0), SIMD4(0, y, 0, 0), SIMD4(0, 0, z, -1), SIMD4(0, 0, z * near, 0)))
    }
    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float> = SIMD3(0, 1, 0)) -> simd_float4x4 {
        let f = normalize(center - eye), s = normalize(cross(f, up)), u = cross(s, f)
        return simd_float4x4(columns: (SIMD4(s.x, u.x, -f.x, 0), SIMD4(s.y, u.y, -f.y, 0), SIMD4(s.z, u.z, -f.z, 0),
                                       SIMD4(-dot(s, eye), -dot(u, eye), dot(f, eye), 1)))
    }
    static func rotationY(_ a: Float) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4(cos(a), 0, -sin(a), 0), SIMD4(0, 1, 0, 0), SIMD4(sin(a), 0, cos(a), 0), SIMD4(0, 0, 0, 1)))
    }
    static func rgb(_ h: Double, _ s: Double, _ l: Double, _ a: Float) -> SIMD4<Float> {
        let c = NebulaPaint.rgb(h, s, l)
        return SIMD4(Float(c.0), Float(c.1), Float(c.2), a)
    }
}

// MARK: - 画

@MainActor
final class GalaxyRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let spritePipe: MTLRenderPipelineState
    private let quadPipe: MTLRenderPipelineState
    private let streakPipe: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let loader: MTKTextureLoader

    let camera = GalaxyCamera()
    var reduceMotion = false
    var onTapStar: (String, CGPoint) -> Void = { _, _ in }

    private var input = GalaxyInput()
    private var shownSelected: String?
    private var builtVersion = -1
    private var staticSprites: MTLBuffer?
    private var staticCount = 0
    private var coreTexture: MTLTexture?
    private var newTexture: (MTLTexture, SIMD2<Float>)?
    /// 每一颗记忆星（点得到）：id、住哪儿、是哪一类
    private var seats: [(id: String, seat: SIMD3<Float>, cat: Int)] = []
    /// 金色的那些（这几天新记的、刚落下的）：头上写「新」
    private var golden: [(id: String, seat: SIMD3<Float>)] = []

    private let t0 = CACurrentMediaTime()
    private var last = CACurrentMediaTime()
    private var orbit: Float = 0
    private var viewProj = matrix_identity_float4x4
    private var projScale: Float = 1
    private var scale: Float = 3

    private struct Landing { let id: String; let seat: SIMD3<Float>; let offset: SIMD3<Float>; let start: Double }
    private var landings: [Landing] = []
    private var scheduled: Set<String> = []
    private var pending: Set<String> = []
    private var landed: Set<String> = []
    private var flashes: [(seat: SIMD3<Float>, start: Double)] = []
    private var meteors: [(p: SIMD2<Float>, v: SIMD2<Float>, life: Float)] = []
    private var nextMeteor = 2.0

    init?(view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = GalaxyRenderer.library(device) else { return nil }
        self.device = device
        self.queue = queue
        loader = MTKTextureLoader(device: device)
        func pipe(_ v: String, _ f: String) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: v)
            d.fragmentFunction = library.makeFunction(name: f)
            let c = d.colorAttachments[0]!
            c.pixelFormat = view.colorPixelFormat
            // 全部叠加：光加光，越叠越亮，不会有黑边
            c.isBlendingEnabled = true
            c.rgbBlendOperation = .add; c.alphaBlendOperation = .add
            c.sourceRGBBlendFactor = .one; c.destinationRGBBlendFactor = .one
            c.sourceAlphaBlendFactor = .one; c.destinationAlphaBlendFactor = .one
            return try? device.makeRenderPipelineState(descriptor: d)
        }
        guard let s = pipe("galaxySpriteVertex", "galaxySpriteFragment"),
              let q = pipe("galaxyQuadVertex", "galaxyQuadFragment"),
              let k = pipe("galaxyStreakVertex", "galaxyStreakFragment") else { return nil }
        spritePipe = s; quadPipe = q; streakPipe = k
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear; sd.magFilter = .linear; sd.mipFilter = .linear
        sd.sAddressMode = .clampToZero; sd.tAddressMode = .clampToZero
        sampler = device.makeSamplerState(descriptor: sd)!
        super.init()
    }

    /// 着色器只编一次，以后进出星河都用这一份
    private static var cachedLibrary: MTLLibrary?
    private static func library(_ device: MTLDevice) -> MTLLibrary? {
        if let l = cachedLibrary { return l }
        cachedLibrary = try? device.makeLibrary(source: GalaxyShaders.source, options: nil)
        return cachedLibrary
    }

    // MARK: 外面递进来的

    func update(_ new: GalaxyInput) {
        input = new
        guard new.selected != shownSelected else { return }
        shownSelected = new.selected
        let now = CACurrentMediaTime() - t0
        if let id = new.selected, let seat = seats.first(where: { $0.id == id })?.seat ?? golden.first(where: { $0.id == id })?.seat {
            // 点开一颗星：镜头飞过去、凑近，之后一直跟着它
            var to = camera.s
            to.zoom = max(camera.s.zoom, 2.3)
            to.target = lifted(GalaxyLayout.world(seat, orbit: orbit + 0.9 / Float(GalaxyLayout.period) * 2 * .pi), zoom: to.zoom)
            camera.focusPoint = nil
            camera.flyTo(to, duration: reduceMotion ? 0.01 : 0.9, now: now) { [weak self] in
                guard let self, self.shownSelected == id else { return }
                self.camera.focusPoint = self.lifted(GalaxyLayout.world(seat, orbit: self.orbit), zoom: self.camera.s.zoom)
            }
            focusSeat = seat
        } else {
            // 关了卡片：缩回去，看的角度不变
            camera.focusPoint = nil
            focusSeat = nil
            var to = camera.s
            to.target = .zero
            to.zoom = 1
            camera.flyTo(to, duration: reduceMotion ? 0.01 : 0.9, now: now)
        }
    }
    /// 正开着的那颗住哪儿（镜头每一帧跟着它挪）
    private var focusSeat: SIMD3<Float>?
    /// 卡片从下面盖上来占了大半屏：镜头对准星星下面一点，让那颗星停在卡片上面的空处
    private func lifted(_ star: SIMD3<Float>, zoom: Float) -> SIMD3<Float> {
        let f = normalize(camera.s.target - camera.eye), side = normalize(cross(f, SIMD3(0, 1, 0))), up = cross(side, f)
        return star - up * (2050 / zoom) * tan(25 * .pi / 180) * 0.62
    }

    func flyHome() {
        camera.follow = nil
        camera.flyTo(.home, duration: 1.0, now: CACurrentMediaTime() - t0)
    }

    // MARK: 手势

    func pan(_ g: UIPanGestureRecognizer, in view: UIView) {
        let t = g.translation(in: view)
        g.setTranslation(.zero, in: view)
        switch g.state {
        case .began:
            camera.dragging = true; camera.vYaw = 0; camera.vPitch = 0
        case .changed:
            camera.s.yaw -= Float(t.x) * 0.008
            camera.s.pitch += Float(t.y) * 0.006
        default:
            camera.dragging = false
            let v = g.velocity(in: view)
            // 甩一下会顺着劲滑一段、慢慢停（她最在意的「丝滑」）
            camera.vYaw = max(-4, min(4, -Float(v.x) * 0.004))
            camera.vPitch = max(-3, min(3, Float(v.y) * 0.003))
        }
    }

    private var pinchStart: Float = 1
    func pinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began: camera.pinching = true; pinchStart = camera.s.zoom
        case .changed: camera.s.zoom = min(4.5, max(0.45, pinchStart * Float(g.scale)))
        default: camera.pinching = false
        }
    }

    /// 点一颗星：离手指最近的那颗（亮着的那类优先；暗下去的那些不认）
    func tap(at p: CGPoint, in size: CGSize) {
        let focus = input.focus.flatMap { GalaxyLayout.kinds.firstIndex(of: $0) }
        var best: (String, CGFloat)?
        var at = p
        for g in golden {
            guard let s = screen(GalaxyLayout.world(g.seat, orbit: orbit), size) else { continue }
            let d = hypot(s.x - p.x, s.y - p.y)
            if d < 32, d < (best?.1 ?? .infinity) { best = (g.id, d); at = s }
        }
        if best == nil {
            for s in seats where focus == nil || focus == s.cat {
                guard let q = screen(GalaxyLayout.world(s.seat, orbit: orbit), size) else { continue }
                let d = hypot(q.x - p.x, q.y - p.y)
                if d < 24, d < (best?.1 ?? .infinity) { best = (s.id, d); at = q }
            }
        }
        // 点到空的地方：收起卡片（镜头缩回去）
        onTapStar(best?.0 ?? "", at)
    }

    private func screen(_ world: SIMD3<Float>, _ size: CGSize) -> CGPoint? {
        let c = viewProj * SIMD4(world, 1)
        guard c.w > 0 else { return nil }
        return CGPoint(x: CGFloat((c.x / c.w + 1) / 2) * size.width, y: CGFloat((1 - c.y / c.w) / 2) * size.height)
    }

    // MARK: 摆星

    private func rebuild() {
        builtVersion = input.version
        // 先把要坐流星来的那几颗挑出来，落地之前不摆
        scheduleArrivals()
        var out: [GalaxySprite] = []
        out.reserveCapacity(12_000)
        var r = NebulaRandom(4242)
        let s = scale
        // 背景三层星星：远的小、暗，转的时候动得慢
        for layer in 0..<3 {
            for _ in 0..<260 {
                let z = r.next() * 2 - 1, a = r.next() * 2 * .pi, q = sqrt(1 - z * z)
                let b = Float(0.3 + r.next() * 0.7)
                out.append(GalaxySprite(posSize: SIMD4(Float(q * cos(a)), Float(z), Float(q * sin(a)), (0.7 + Float(layer) * 0.55) * s),
                                        color: SIMD4(0.86, 0.88, 1, b * (0.3 + Float(layer) * 0.22)),
                                        meta: SIMD4(UInt32(100 + layer), 3, UInt32(r.next() * 6000), 0)))
            }
        }
        // 星盘的尘和一层很淡的紫雾，跟记忆星一起绕着转
        for _ in 0..<4200 {
            let rr = 170 + pow(r.next(), 0.6) * 560
            out.append(GalaxySprite(posSize: SIMD4(Float(rr), Float(r.next() * 2 * .pi), Float(r.normal() * 14), 2.2),
                                    color: SIMD4(0.74, 0.7, 0.92, Float(0.05 + 0.12 * r.next())), meta: SIMD4(0, 0, 0, 255)))
        }
        for _ in 0..<260 {
            let rr = 200 + pow(r.next(), 0.7) * 480
            out.append(GalaxySprite(posSize: SIMD4(Float(rr), Float(r.next() * 2 * .pi), Float(r.normal() * 12), Float(90 + r.next() * 130)),
                                    color: SIMD4(0.56, 0.5, 0.8, 0.055), meta: SIMD4(0, 0, 0, 255)))
        }
        // 中间：一轮月亮，外面几圈淡淡的月光（11-27 她：「中间是发光的月球试试」）
        if let moon = NebulaPhoto.moon {
            let e = GalaxyLayout.core
            for (k, a) in [(1.15, 0.14), (1.75, 0.24), (2.7, 0.12), (4.2, 0.06)] as [(Float, Float)] {
                out.append(GalaxySprite(posSize: SIMD4(0, 0, 0, e * k), color: SIMD4(0.86, 0.9, 1, a), meta: SIMD4(1, 0, 0, 0)))
            }
            if coreTexture == nil { coreTexture = try? loader.newTexture(cgImage: moon.cgImage, options: [.SRGB: false, .generateMipmaps: true]) }
        }
        // 记忆星：一类一个颜色，散在四周
        seats = []; golden = []
        for (cat, kind) in GalaxyLayout.kinds.enumerated() {
            let c = GalaxyInk.rgb(kind)
            for m in input.members[kind] ?? [] where !pending.contains(m.id) {
                let p = GalaxyLayout.seat(m.id)
                let phase = UInt32(NebulaRandom.hash(m.id) % 6000)
                seats.append((m.id, p, cat))
                if m.recent || landed.contains(m.id) {
                    golden.append((m.id, p))
                    out.append(GalaxySprite(posSize: SIMD4(p, 15), color: SIMD4(GalaxyInk.fresh, 1), meta: SIMD4(0, 2, phase, 254)))
                } else {
                    out.append(GalaxySprite(posSize: SIMD4(p, m.bright ? 6.5 : 5), color: SIMD4(c, m.bright ? 0.95 : 0.7),
                                            meta: SIMD4(0, 1, phase, UInt32(cat + 1))))
                }
            }
        }
        if newTexture == nil { newTexture = textTexture("新", size: 13, color: UIColor(red: 1, green: 0.91, blue: 0.72, alpha: 1)) }
        staticCount = out.count
        staticSprites = out.isEmpty ? nil : device.makeBuffer(bytes: out, length: MemoryLayout<GalaxySprite>.stride * out.count)
    }

    /// 新记忆：还没送过的排上流星。1–3 条一颗接一颗，4 条以上一起来（流星雨）
    private func scheduleArrivals() {
        let known = Set(GalaxyLayout.kinds.flatMap { input.members[$0] ?? [] }.map(\.id))
        let todo = input.arrivals.filter { !scheduled.contains($0) && known.contains($0) }
        guard !todo.isEmpty else { return }
        let now = CACurrentMediaTime() - t0
        var r = NebulaRandom(77)
        let shower = todo.count >= 4
        for (n, id) in todo.enumerated() {
            scheduled.insert(id)
            if reduceMotion { landed.insert(id); continue }
            pending.insert(id)
            let start = now + 0.9 + (shower ? Double(n) * 0.16 + r.next() * 0.12 : Double(n) * 1.1)
            let offset = shower ? SIMD3<Float>(520 + Float(r.normal()) * 60, 700 + Float(r.normal()) * 60, -260)
                                : SIMD3<Float>(520, 700, -260)
            landings.append(Landing(id: id, seat: GalaxyLayout.seat(id), offset: offset, start: start))
        }
    }

    // MARK: 贴图

    private func textTexture(_ text: String, size: CGFloat, color: UIColor) -> (MTLTexture, SIMD2<Float>)? {
        let font = UIFont(name: "NotoSerifSC-Regular", size: size) ?? .systemFont(ofSize: size)
        let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let box = attr.size()
        let f = UIGraphicsImageRendererFormat(); f.scale = 3; f.opaque = false
        let img = UIGraphicsImageRenderer(size: box, format: f).image { _ in attr.draw(at: .zero) }
        guard let cg = img.cgImage, let t = try? loader.newTexture(cgImage: cg, options: [.SRGB: false]) else { return nil }
        return (t, SIMD2(Float(box.width), Float(box.height)))
    }

    // MARK: 每一帧

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let nowAbs = CACurrentMediaTime()
        let dt = Float(min(0.05, nowAbs - last)); last = nowAbs
        let now = nowAbs - t0
        scale = Float(view.contentScaleFactor)
        if !reduceMotion { orbit += dt / Float(GalaxyLayout.period) * 2 * .pi }
        if let seat = focusSeat, camera.focusPoint != nil { camera.focusPoint = lifted(GalaxyLayout.world(seat, orbit: orbit), zoom: camera.s.zoom) }
        camera.update(now: now, dt: dt, centers: [.zero])
        // 动的时候按屏幕最快的刷新率画（她的 14 Pro Max 是 120），停着就 60，省电
        let fps = camera.busy || !landings.isEmpty ? 120 : 60
        if view.preferredFramesPerSecond != fps { view.preferredFramesPerSecond = fps }

        let size = view.drawableSize
        let w = Float(max(1, size.width)), h = Float(max(1, size.height))
        let proj = GalaxyMath.perspective(fovy: 50 * .pi / 180, aspect: w / h, near: 5, far: 30_000)
        let eye = camera.eye
        let viewM = GalaxyMath.lookAt(eye: eye, center: camera.s.target)
        viewProj = proj * viewM
        projScale = proj.columns.1.y * h / 2
        // 0：中间那张照片永远面朝镜头；1：世界本身
        let f = normalize(camera.s.target - eye), side = normalize(cross(f, SIMD3(0, 1, 0))), up = cross(side, f)
        let regions: [simd_float4x4] = [
            simd_float4x4(columns: (SIMD4(side, 0), SIMD4(up, 0), SIMD4(f, 0), SIMD4(0, 0, 0, 1))),
            matrix_identity_float4x4,
        ]
        // 背景三层：远的那层只跟着转一点点，近的转得多
        let sky: [simd_float4x4] = [0.15, 0.35, 0.6].map { k -> simd_float4x4 in
            let y = camera.s.yaw * Float(k), p = camera.s.pitch * Float(k)
            let d = SIMD3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
            return proj * GalaxyMath.lookAt(eye: .zero, center: -d)
        }

        if builtVersion != input.version { rebuild() }

        // 流星落地
        var extra: [GalaxySprite] = []
        var streaks: [GalaxyStreak] = []
        let gold0 = SIMD4<Float>(1, 0.94, 0.8, 1), gold1 = SIMD4<Float>(1, 0.78, 0.47, 0)
        var flying: [Landing] = []
        for l in landings {
            let k = (now - l.start) / 2.0
            guard k >= 0 else { flying.append(l); continue }
            let kk = Float(min(1, k)), e = kk * kk * (3 - 2 * kk)
            let end = GalaxyLayout.world(l.seat, orbit: orbit), start = end + l.offset
            let head = start + (end - start) * e, tail = start + (end - start) * max(0, e - 0.22)
            streaks.append(GalaxyStreak(a: SIMD4(head, 5 * scale), b: SIMD4(tail, 0), ca: gold0, cb: gold1))
            extra.append(GalaxySprite(posSize: SIMD4(head, 10), color: SIMD4(1, 0.96, 0.85, 1), meta: SIMD4(1, 0, 0, 0)))
            if kk < 1 { flying.append(l); continue }
            // 落下来了：闪一圈，这颗变成金色的「新」星
            pending.remove(l.id); landed.insert(l.id)
            flashes.append((l.seat, now))
            builtVersion = -2
        }
        landings = flying
        // 新记忆落地：闪一圈，再炸开一小簇星屑往四周散（11-27 她要「新记忆出现」更有感觉）
        flashes.removeAll { now - $0.start > 1.4 }
        let f0 = normalize(camera.s.target - eye), side0 = normalize(cross(f0, SIMD3(0, 1, 0))), up0 = cross(side0, f0)
        for fl in flashes {
            let t = Float(now - fl.start), at = GalaxyLayout.world(fl.seat, orbit: orbit)
            if t < 0.7 {
                let k = t / 0.7
                extra.append(GalaxySprite(posSize: SIMD4(at, 10 + k * 70), color: SIMD4(1, 0.92, 0.74, (1 - k) * 0.9), meta: SIMD4(1, 0, 0, 0)))
            }
            let k = min(1, t / 1.4), ease = 1 - (1 - k) * (1 - k)
            for j in 0..<10 {
                let a = Float(j) / 10 * 2 * .pi + 0.3, reach = Float(40 + (j % 3) * 18)
                let p = at + (side0 * cos(a) + up0 * sin(a)) * reach * ease
                extra.append(GalaxySprite(posSize: SIMD4(p, 3.2), color: SIMD4(1, 0.93, 0.8, (1 - k) * 0.95), meta: SIMD4(1, 1, UInt32(j * 600), 0)))
            }
        }
        // 正开着的那颗：外面一圈光，一明一暗
        if let seat = focusSeat {
            let at = GalaxyLayout.world(seat, orbit: orbit), pulse = 0.5 + 0.5 * sin(Float(now) * 3)
            extra.append(GalaxySprite(posSize: SIMD4(at, 34 + pulse * 14), color: SIMD4(1, 0.93, 0.85, 0.3 + 0.3 * pulse), meta: SIMD4(1, 0, 0, 0)))
            extra.append(GalaxySprite(posSize: SIMD4(at, 12 + pulse * 3), color: SIMD4(1, 1, 1, 1), meta: SIMD4(1, 1, 0, 0)))
        }
        // 背景偶尔划过一颗白色小流星
        if !reduceMotion {
            if now > nextMeteor {
                var r = NebulaRandom(UInt32(truncatingIfNeeded: Int(now * 1000)))
                meteors.append((SIMD2(Float(r.next() * 1.4 - 0.2), Float(r.next() * 0.5 + 0.45)),
                                SIMD2(-Float(0.55 + r.next() * 0.5), -Float(0.35 + r.next() * 0.35)), 1))
                nextMeteor = now + 3 + r.next() * 5
            }
            for i in meteors.indices {
                meteors[i].p += meteors[i].v * dt
                meteors[i].life -= dt * 0.9
                let m = meteors[i]
                streaks.append(GalaxyStreak(a: SIMD4(m.p.x, m.p.y, 0, 1.6 * scale), b: SIMD4(m.p.x - m.v.x * 0.2, m.p.y - m.v.y * 0.2, 0, 1),
                                            ca: SIMD4(1, 1, 1, 0.8 * max(0, m.life)), cb: SIMD4(1, 1, 1, 0)))
            }
            meteors.removeAll { $0.life <= 0 }
        }

        guard let pass = view.currentRenderPassDescriptor, let drawableObj = view.currentDrawable,
              let cmd = queue.makeCommandBuffer(), let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        let focus = input.focus.flatMap { GalaxyLayout.kinds.firstIndex(of: $0) }.map(Float.init) ?? -1
        var u = GalaxyUniforms(viewProj: viewProj, view: viewM, proj: proj, viewport: SIMD2(w, h), time: Float(now),
                               projScale: projScale, orbit: orbit, focus: focus)
        enc.setVertexBytes(&u, length: MemoryLayout<GalaxyUniforms>.stride, index: 1)
        enc.setVertexBytes(regions, length: MemoryLayout<simd_float4x4>.stride * regions.count, index: 2)
        enc.setVertexBytes(sky, length: MemoryLayout<simd_float4x4>.stride * sky.count, index: 3)

        // 中间：月亮，很轻地一亮一暗，像在呼吸
        enc.setRenderPipelineState(quadPipe)
        enc.setFragmentSamplerState(sampler, index: 0)
        if let tex = coreTexture {
            let e = GalaxyLayout.core
            // 凑近了月亮会很大很亮，跟着拉近收一点光，别抢了那颗星
            let breathe: Float = (reduceMotion ? 1 : 0.92 + 0.08 * sin(Float(now) * 0.7)) * min(1, max(0.5, 1.4 / camera.s.zoom))
            let quads = [GalaxyQuad(center: SIMD4(0, 0, 0, e), tint: SIMD4(1, 1, 1, 0.82 * breathe), meta: SIMD4(0, 0, 0, 0), extra: .zero)]
            enc.setFragmentTexture(tex, index: 0)
            enc.setVertexBytes(quads, length: MemoryLayout<GalaxyQuad>.stride * quads.count, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: quads.count)
        }

        enc.setRenderPipelineState(spritePipe)
        if let buf = staticSprites, staticCount > 0 {
            enc.setVertexBuffer(buf, offset: 0, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: staticCount)
        }
        if !extra.isEmpty {
            enc.setVertexBytes(extra, length: MemoryLayout<GalaxySprite>.stride * extra.count, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: extra.count)
        }
        if !streaks.isEmpty {
            enc.setRenderPipelineState(streakPipe)
            enc.setVertexBytes(streaks, length: MemoryLayout<GalaxyStreak>.stride * streaks.count, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: streaks.count)
        }
        // 新记的那几颗头上写「新」
        if let (tex, size) = newTexture, !golden.isEmpty {
            enc.setRenderPipelineState(quadPipe)
            let half = size * 0.5 * scale
            let qs = golden.prefix(40).map { g in
                GalaxyQuad(center: SIMD4(GalaxyLayout.world(g.seat, orbit: orbit), 0), tint: SIMD4(1, 1, 1, 0.95), meta: SIMD4(1, 2, 0, 0),
                           extra: SIMD4(0, half.y + 10 * scale, half.x, half.y))
            }
            enc.setFragmentTexture(tex, index: 0)
            enc.setVertexBytes(qs, length: MemoryLayout<GalaxyQuad>.stride * qs.count, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: qs.count)
        }
        enc.endEncoding()
        cmd.present(drawableObj)
        cmd.commit()
    }
}

// MARK: - 放进 SwiftUI

struct GalaxyUniverseView: UIViewRepresentable {
    var input: GalaxyInput
    /// 正在看整片星河（进了一团的详情就停下来，不白画）
    var active: Bool
    /// 从一团里出来时加一：镜头飞回全景
    var homeRequest: Int
    var reduceMotion: Bool
    var onTapStar: (String, CGPoint) -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var renderer: GalaxyRenderer?
        var home = 0
        weak var view: MTKView?
        @objc func pan(_ g: UIPanGestureRecognizer) { if let v = view { renderer?.pan(g, in: v) } }
        @objc func pinch(_ g: UIPinchGestureRecognizer) { renderer?.pinch(g) }
        @objc func tap(_ g: UITapGestureRecognizer) { if let v = view { renderer?.tap(at: g.location(in: v), in: v.bounds.size) } }
        /// 左边缘 44 点留给「往右划退出去」
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard g is UIPanGestureRecognizer, let v = g.view else { return true }
            return g.location(in: v).x > SwipeBackToClose.edge
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            (g is UIPinchGestureRecognizer || other is UIPinchGestureRecognizer) && g.view === other.view
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let v = MTKView()
        v.colorPixelFormat = .bgra8Unorm
        v.clearColor = MTLClearColor(red: 5 / 255, green: 7 / 255, blue: 13 / 255, alpha: 1)
        v.framebufferOnly = true
        v.preferredFramesPerSecond = 60
        v.isOpaque = true
        let r = GalaxyRenderer(view: v)
        v.device = r?.device
        v.delegate = r
        context.coordinator.renderer = r
        context.coordinator.view = v
        context.coordinator.home = homeRequest
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        pinch.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        [pan, pinch, tap].forEach(v.addGestureRecognizer)
        return v
    }

    func updateUIView(_ v: MTKView, context: Context) {
        guard let r = context.coordinator.renderer else { return }
        r.reduceMotion = reduceMotion
        r.onTapStar = onTapStar
        r.update(input)
        v.isPaused = !active
        if context.coordinator.home != homeRequest {
            context.coordinator.home = homeRequest
            r.flyHome()
        }
    }
}
