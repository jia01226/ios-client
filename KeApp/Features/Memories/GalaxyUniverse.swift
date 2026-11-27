import MetalKit
import SwiftUI
import UIKit
import simd

// MARK: - 11-27 新星河（整片宇宙）
// 她和我对着效果图改了八版定下来的样子（记在 memory-galaxy-redesign）：
// 「说好的」在正中像太阳，另外七团各走一条轨道、等分着排、整片一起慢慢转，轨道有一点高低；
// 背景三层星星（远的动得慢）、一条紫色的银河星盘；偶尔划过白色小流星；
// 新记忆是一颗金色流星，划进它那一团，落下闪一下变成「新」星。1–3 条一颗接一颗，4 条以上流星雨。
// 旧的那页是 CPU 一笔一笔画的（她说卡），这里全部交给显卡。点一团：镜头跟着它飞进去，再进那一团的详情页。

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
    var arts: [NebulaKind: NebulaArt] = [:]
    var members: [NebulaKind: [GalaxyMember]] = [:]
    /// 这次打开才看到的新记忆（按时间先后）：一颗颗流星送进去
    var arrivals: [String] = []
    /// 外面的东西变了就加一，这边才重新摆星
    var version = 0
}

enum GalaxyLayout {
    /// 0 是中心「说好的」；1…7 由里到外（效果图第八版：亲密时刻、他学会的、以后的家她嫌远，拉近了）
    static let order: [(kind: NebulaKind, orbit: Float)] = [
        (.whirlpool, 0), (.andromeda, 240), (.pleiades, 292), (.orion, 344),
        (.heart, 372), (.lessons, 400), (.sombrero, 428), (.horsehead, 552),
    ]
    /// 整片转一圈要多久（秒）。一起转，不会转着转着挤到一边
    static let period: Double = 240
    static let bandRegion = 8
    static let worldRegion = 9
    /// 星云的画在世界里的半边长
    static func extent(_ i: Int) -> Float { i == 0 ? 185 : 92 }
    static func index(of kind: NebulaKind) -> Int? { order.firstIndex { $0.kind == kind } }
    static func center(_ i: Int, spin: Double) -> SIMD3<Float> {
        guard i > 0 else { return .zero }
        let r = order[i].orbit
        let a = Double(i - 1) * 2 * .pi / 7 + spin
        let lift = Float(i % 2 == 1 ? 1 : -1) * Float(25 + i * 4)
        return SIMD3(Float(cos(a)) * r, lift * Float(sin(2 * a)), Float(sin(a)) * r)
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
        var made: NebulaPhoto?
        if kind != .lessons, let path = Bundle.main.path(forResource: "nebula-\(kind.rawValue)", ofType: "jpg"),
           let cg = UIImage(contentsOfFile: path)?.cgImage { made = NebulaPhoto(cg) }
        cache[kind] = made
        return made
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
    照片都来自维基共享资源，裁剪、调暗了天空、边缘做了渐隐。
    """
}

// MARK: 镜头

struct GalaxyCameraState {
    var yaw: Float
    var pitch: Float
    var zoom: Float
    var target: SIMD3<Float>
    static let home = GalaxyCameraState(yaw: 0.3, pitch: 0.85, zoom: 1, target: .zero)
}

final class GalaxyCamera {
    var s = GalaxyCameraState.home
    var vYaw: Float = 0, vPitch: Float = 0
    var dragging = false
    var pinching = false
    /// 跟着哪一团（它在公转，镜头跟着走）
    var follow: Int?
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
        }
        s.pitch = min(1.45, max(-1.2, s.pitch))
        s.zoom = min(4.5, max(0.45, s.zoom))
    }

    var eye: SIMD3<Float> {
        let d = 1850 / s.zoom
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
    /// 能不能进这一团（亲密时刻锁着就不飞，外面问她要不要打开）
    var canEnter: (NebulaKind) -> Bool = { _ in true }
    var onEnter: (NebulaKind) -> Void = { _ in }
    var onTapStar: (String) -> Void = { _ in }

    private var input = GalaxyInput()
    private var builtVersion = -1
    private var staticSprites: MTLBuffer?
    private var staticCount = 0
    /// 七条轨道的淡圈（效果图里有，第一版漏了）
    private var rings: MTLBuffer?
    private var ringCount = 0
    private var artTextures: [Int: MTLTexture] = [:]
    /// 哪几团用的是真照片（照片自己有星有尘，不再撒画出来的星尘）
    private var photoRegions: Set<Int> = []
    private var labelTextures: [Int: (MTLTexture, SIMD2<Float>)] = [:]
    private var newTexture: (MTLTexture, SIMD2<Float>)?
    /// 金色的那些（这几天新记的、刚落下的）：点得到、头上写「新」
    private var golden: [(id: String, region: Int, local: SIMD3<Float>)] = []

    private let t0 = CACurrentMediaTime()
    private var last = CACurrentMediaTime()
    private var spin = 0.0
    private var regions = [simd_float4x4](repeating: matrix_identity_float4x4, count: 10)
    private var centers = [SIMD3<Float>](repeating: .zero, count: 8)
    private var viewProj = matrix_identity_float4x4
    private var projScale: Float = 1
    private var drawable = CGSize(width: 1, height: 1)
    private var scale: Float = 3

    private struct Landing { let id: String; let region: Int; let local: SIMD3<Float>; let offset: SIMD3<Float>; let start: Double }
    private var landings: [Landing] = []
    private var scheduled: Set<String> = []
    private var pending: Set<String> = []
    private var landed: Set<String> = []
    private var flashes: [(region: Int, local: SIMD3<Float>, start: Double)] = []
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
        if new.version != builtVersion { builtVersion = -2 }   // 下一帧重摆
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

    func tap(at p: CGPoint, in size: CGSize) {
        guard !camera.flying else { return }
        // 金色的星先认（手指 30 点以内）
        var best: (String, CGFloat)?
        for g in golden {
            guard let s = screen(regions[g.region] * SIMD4(g.local, 1), size) else { continue }
            let d = hypot(s.x - p.x, s.y - p.y)
            if d < 30, d < (best?.1 ?? .infinity) { best = (g.id, d) }
        }
        if let id = best?.0 { onTapStar(id); return }
        var near: (Int, CGFloat)?
        for i in 0..<GalaxyLayout.order.count {
            let world = SIMD4(centers[i], 1)
            guard let s = screen(world, size), let r = screenRadius(world, extent: GalaxyLayout.extent(i), size) else { continue }
            let d = hypot(s.x - p.x, s.y - p.y) / max(24, r * 0.75)
            if d < 1, d < (near?.1 ?? .infinity) { near = (i, d) }
        }
        guard let i = near?.0 else { return }
        let kind = GalaxyLayout.order[i].kind
        guard canEnter(kind) else { return }
        // 镜头跟着这一团飞过去，凑近了再进详情（她要的「飞进去」，不是换一页）
        camera.follow = i
        var to = camera.s
        to.zoom = i == 0 ? 2.2 : 3.4
        camera.flyTo(to, duration: reduceMotion ? 0.01 : 0.85, now: CACurrentMediaTime() - t0) { [weak self] in
            self?.onEnter(kind)
        }
    }

    private func screen(_ world: SIMD4<Float>, _ size: CGSize) -> CGPoint? {
        let c = viewProj * world
        guard c.w > 0 else { return nil }
        return CGPoint(x: CGFloat((c.x / c.w + 1) / 2) * size.width, y: CGFloat((1 - c.y / c.w) / 2) * size.height)
    }
    private func screenRadius(_ world: SIMD4<Float>, extent: Float, _ size: CGSize) -> CGFloat? {
        let c = viewProj * world
        guard c.w > 0 else { return nil }
        return CGFloat(extent * projScale / c.w / scale)
    }

    // MARK: 摆星

    private func group(_ i: Int) -> NebulaGroup? { NebulaGroup.all.first { $0.kind == GalaxyLayout.order[i].kind } }

    /// 盘面坐标 (u, v, z) → 这一团里的本地坐标：中间那团平躺在盘面上，别的面朝镜头
    private func local(_ i: Int, _ p: SIMD3<Double>) -> SIMD3<Float> {
        let e = GalaxyLayout.extent(i)
        let u = Float(p.x), v = Float(p.y), z = Float(p.z)
        return i == 0 ? SIMD3(u * e, -z * e * 0.6, v * e) : SIMD3(u * e, -v * e, z * e * 0.6)
    }

    /// 这颗记忆星在这一团里的盘面坐标：有照片照照片的亮处，没有照原来画的
    private func seat(_ g: NebulaGroup, _ id: String) -> SIMD3<Double>? {
        if let photo = NebulaPhoto.of(g.kind) { return photo.seat(for: id) }
        return input.arts[g.kind]?.seat(for: id, thickness: g.thickness)
    }

    private func rebuild() {
        builtVersion = input.version
        // 先把要坐流星来的那几颗挑出来，落地之前不摆
        scheduleArrivals()
        var out: [GalaxySprite] = []
        out.reserveCapacity(24_000)
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
        // 银河星盘：星尘 + 一层淡紫的光雾，绕着中心一起转
        let band = UInt32(GalaxyLayout.bandRegion)
        // 11-27 她看了说「买家秀」：星盘太淡、背景发空。星尘加密加亮，光雾加厚
        for _ in 0..<4200 {
            let a = r.next() * 2 * .pi, rr = 120 + pow(r.next(), 0.6) * 500
            out.append(GalaxySprite(posSize: SIMD4(Float(cos(a) * rr), Float(r.normal() * 20), Float(sin(a) * rr), 2.4),
                                    color: SIMD4(0.74, 0.7, 0.92, Float(0.07 + 0.16 * r.next())), meta: SIMD4(band, 0, 0, 0)))
        }
        for _ in 0..<300 {
            let a = r.next() * 2 * .pi, rr = 150 + pow(r.next(), 0.7) * 460
            out.append(GalaxySprite(posSize: SIMD4(Float(cos(a) * rr), Float(r.normal() * 18), Float(sin(a) * rr), Float(90 + r.next() * 130)),
                                    color: SIMD4(0.56, 0.5, 0.8, 0.075), meta: SIMD4(band, 0, 0, 0)))
        }
        golden = []
        for i in 0..<GalaxyLayout.order.count {
            guard let g = group(i) else { continue }
            let e = GalaxyLayout.extent(i), reg = UInt32(i)
            if let photo = NebulaPhoto.of(g.kind) {
                photoRegions.insert(i)
                // 照片本身就有云有星；只照着照片的颜色铺一层很淡的大光雾，让它跟宇宙融在一起、有一点厚
                var puffs = 0, tries = 0
                while puffs < 80 && tries < 4000 {
                    tries += 1
                    let u = r.next() * 1.6 - 0.8, v = r.next() * 1.6 - 0.8, b = photo.brightness(u, v)
                    guard r.next() < b * 2.2 else { continue }
                    puffs += 1
                    let c = simd_min(photo.color(u, v) * 1.6, SIMD3(repeating: 1))
                    out.append(GalaxySprite(posSize: SIMD4(local(i, SIMD3(u, v, r.normal() * 0.3)), e * Float(0.22 + r.next() * 0.3)),
                                            color: SIMD4(c, 0.035), meta: SIMD4(reg, 0, 0, 0)))
                }
                for m in input.members[g.kind] ?? [] where !pending.contains(m.id) {
                    let p = local(i, photo.seat(for: m.id))
                    let phase = UInt32(NebulaRandom.hash(m.id) % 6000)
                    if m.recent || landed.contains(m.id) {
                        golden.append((m.id, i, p))
                        out.append(GalaxySprite(posSize: SIMD4(p, e * 0.11), color: SIMD4(1, 0.9, 0.68, 1), meta: SIMD4(reg, 2, phase, 0)))
                    } else {
                        out.append(GalaxySprite(posSize: SIMD4(p, e * (m.bright ? 0.03 : 0.022)), color: SIMD4(1, 0.97, 0.92, m.bright ? 0.7 : 0.4),
                                                meta: SIMD4(reg, 1, phase, 0)))
                    }
                }
                if artTextures[i] == nil {
                    artTextures[i] = try? loader.newTexture(cgImage: photo.cgImage, options: [.SRGB: false, .generateMipmaps: true])
                }
                if labelTextures[i] == nil, let t = labelTexture(g.name, g.astro) { labelTextures[i] = t }
                continue
            }
            guard let art = input.arts[g.kind] else { continue }
            // 云气：照这团画的亮处撒几百团又大又淡的光，云才厚（她：「云层太单薄」）
            var gas = 0, tries = 0
            while gas < 300 && tries < 9000 {
                tries += 1
                let u = r.next() * 1.8 - 0.9, v = r.next() * 1.8 - 0.9, b = art.brightness(u, v)
                guard r.next() < b * 1.1 else { continue }
                gas += 1
                let second = r.next() < 0.3
                let color = second ? GalaxyMath.rgb(g.hue + 32, 55, 64, Float(0.02 + 0.02 * b)) : GalaxyMath.rgb(g.hue, 48, 62, Float(0.02 + 0.02 * b))
                out.append(GalaxySprite(posSize: SIMD4(local(i, SIMD3(u, v, r.normal() * 0.25)), e * Float(0.18 + r.next() * 0.26)),
                                        color: color, meta: SIMD4(reg, 0, 0, 0)))
            }
            let alphas: [Float] = [0.16, 0.26, 0.38, 0.52]
            for (level, points) in art.dust.enumerated() {
                let c = GalaxyMath.rgb(g.hue, 30, 84, alphas[level] * 0.3)
                for p in points { out.append(GalaxySprite(posSize: SIMD4(local(i, p), e * 0.016), color: c, meta: SIMD4(reg, 0, 0, 0))) }
            }
            for m in input.members[g.kind] ?? [] where !pending.contains(m.id) {
                let p = local(i, art.seat(for: m.id, thickness: g.thickness))
                let phase = UInt32(NebulaRandom.hash(m.id) % 6000)
                if m.recent || landed.contains(m.id) {
                    golden.append((m.id, i, p))
                    out.append(GalaxySprite(posSize: SIMD4(p, e * 0.12), color: SIMD4(1, 0.9, 0.68, 1), meta: SIMD4(reg, 2, phase, 0)))
                } else {
                    out.append(GalaxySprite(posSize: SIMD4(p, e * (m.bright ? 0.042 : 0.032)),
                                            color: GalaxyMath.rgb(g.hue, 40, m.bright ? 92 : 84, m.bright ? 0.75 : 0.45),
                                            meta: SIMD4(reg, 1, phase, 0)))
                }
            }
            if artTextures[i] == nil {
                artTextures[i] = try? loader.newTexture(cgImage: art.cgImage, options: [.SRGB: false, .generateMipmaps: true])
            }
            if labelTextures[i] == nil, let t = labelTexture(g.name, g.astro) { labelTextures[i] = t }
        }
        if newTexture == nil { newTexture = textTexture("新", size: 13, color: UIColor(red: 1, green: 0.91, blue: 0.72, alpha: 1)) }
        if rings == nil {
            var segs: [GalaxyStreak] = []
            let c = SIMD4<Float>(0.8, 0.78, 0.95, 0.16)
            for i in 1..<GalaxyLayout.order.count {
                let n = 160
                func at(_ k: Int) -> SIMD3<Float> { GalaxyLayout.center(i, spin: Double(k) / Double(n) * 2 * .pi - Double(i - 1) * 2 * .pi / 7) }
                for k in 0..<n { segs.append(GalaxyStreak(a: SIMD4(at(k), 1.1 * s), b: SIMD4(at(k + 1), 0), ca: c, cb: c)) }
            }
            ringCount = segs.count
            rings = device.makeBuffer(bytes: segs, length: MemoryLayout<GalaxyStreak>.stride * segs.count)
        }
        staticCount = out.count
        staticSprites = out.isEmpty ? nil : device.makeBuffer(bytes: out, length: MemoryLayout<GalaxySprite>.stride * out.count)
    }

    /// 新记忆：还没送过的排上流星。1–3 条一颗接一颗，4 条以上一起来（流星雨）
    private func scheduleArrivals() {
        let todo = input.arrivals.filter { !scheduled.contains($0) }
        guard !todo.isEmpty else { return }
        let now = CACurrentMediaTime() - t0
        var r = NebulaRandom(77)
        let shower = todo.count >= 4
        var placed = 0
        for id in todo {
            guard let (i, g) = (0..<GalaxyLayout.order.count).lazy.compactMap({ i -> (Int, NebulaGroup)? in
                guard let g = self.group(i), self.input.members[g.kind]?.contains(where: { $0.id == id }) == true else { return nil }
                return (i, g)
            }).first, let spot = seat(g, id) else { continue }
            scheduled.insert(id)
            if reduceMotion { landed.insert(id); continue }
            pending.insert(id)
            let start = now + 0.9 + (shower ? Double(placed) * 0.16 + r.next() * 0.12 : Double(placed) * 1.1)
            let offset = shower ? SIMD3<Float>(520 + Float(r.normal()) * 60, 700 + Float(r.normal()) * 60, -260)
                                : SIMD3<Float>(520, 700, -260)
            landings.append(Landing(id: id, region: i, local: local(i, spot), offset: offset, start: start))
            placed += 1
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

    private func labelTexture(_ name: String, _ astro: String) -> (MTLTexture, SIMD2<Float>)? {
        let nameFont = UIFont(name: "NotoSerifSC-Regular", size: 16) ?? .systemFont(ofSize: 16)
        let a = NSAttributedString(string: name, attributes: [.font: nameFont, .kern: 1.3, .foregroundColor: UIColor(white: 0.95, alpha: 1)])
        let b = NSAttributedString(string: astro, attributes: [.font: UIFont.systemFont(ofSize: 9.5), .kern: 0.8,
                                                                .foregroundColor: UIColor(red: 0.72, green: 0.74, blue: 0.81, alpha: 1)])
        let sa = a.size(), sb = b.size()
        let box = CGSize(width: ceil(max(sa.width, sb.width)) + 4, height: ceil(sa.height + sb.height) + 2)
        let f = UIGraphicsImageRendererFormat(); f.scale = 3; f.opaque = false
        let img = UIGraphicsImageRenderer(size: box, format: f).image { _ in
            a.draw(at: CGPoint(x: (box.width - sa.width) / 2, y: 0))
            b.draw(at: CGPoint(x: (box.width - sb.width) / 2, y: sa.height + 1))
        }
        guard let cg = img.cgImage, let t = try? loader.newTexture(cgImage: cg, options: [.SRGB: false]) else { return nil }
        return (t, SIMD2(Float(box.width), Float(box.height)))
    }

    // MARK: 每一帧

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { drawable = size }

    func draw(in view: MTKView) {
        let nowAbs = CACurrentMediaTime()
        let dt = Float(min(0.05, nowAbs - last)); last = nowAbs
        let now = nowAbs - t0
        scale = Float(view.contentScaleFactor)
        drawable = view.drawableSize
        if !reduceMotion { spin += Double(dt) / GalaxyLayout.period * 2 * .pi }
        for i in 0..<8 { centers[i] = GalaxyLayout.center(i, spin: spin) }
        camera.update(now: now, dt: dt, centers: centers)
        // 动的时候按屏幕最快的刷新率画（她的 14 Pro Max 是 120），停着就 60，省电
        let fps = camera.busy || !landings.isEmpty ? 120 : 60
        if view.preferredFramesPerSecond != fps { view.preferredFramesPerSecond = fps }

        let w = Float(max(1, drawable.width)), h = Float(max(1, drawable.height))
        let proj = GalaxyMath.perspective(fovy: 50 * .pi / 180, aspect: w / h, near: 5, far: 30_000)
        let eye = camera.eye
        let viewM = GalaxyMath.lookAt(eye: eye, center: camera.s.target)
        viewProj = proj * viewM
        projScale = proj.columns.1.y * h / 2
        // 每一团的坐标系：中间那团平躺着慢慢自转；别的面朝镜头、跟着公转走
        let f = normalize(camera.s.target - eye), side = normalize(cross(f, SIMD3(0, 1, 0))), up = cross(side, f)
        var m0 = GalaxyMath.rotationY(Float(spin * 1.6)); m0.columns.3 = SIMD4(0, 0, 0, 1)
        regions[0] = m0
        for i in 1..<8 {
            regions[i] = simd_float4x4(columns: (SIMD4(side, 0), SIMD4(up, 0), SIMD4(f, 0), SIMD4(centers[i], 1)))
        }
        regions[GalaxyLayout.bandRegion] = GalaxyMath.rotationY(Float(spin))
        regions[GalaxyLayout.worldRegion] = matrix_identity_float4x4
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
            let end4 = regions[l.region] * SIMD4(l.local, 1)
            let end = SIMD3(end4.x, end4.y, end4.z), start = end + l.offset
            let head = start + (end - start) * e, tail = start + (end - start) * max(0, e - 0.22)
            streaks.append(GalaxyStreak(a: SIMD4(head, 5 * scale), b: SIMD4(tail, 0), ca: gold0, cb: gold1))
            extra.append(GalaxySprite(posSize: SIMD4(head, 10), color: SIMD4(1, 0.96, 0.85, 1), meta: SIMD4(UInt32(GalaxyLayout.worldRegion), 0, 0, 0)))
            if kk < 1 { flying.append(l); continue }
            // 落下来了：闪一圈，这颗变成金色的「新」星
            pending.remove(l.id); landed.insert(l.id)
            flashes.append((l.region, l.local, now))
            builtVersion = -2
        }
        landings = flying
        flashes.removeAll { now - $0.start > 0.7 }
        for fl in flashes {
            let k = Float((now - fl.start) / 0.7)
            extra.append(GalaxySprite(posSize: SIMD4(fl.local, 10 + k * 70), color: SIMD4(1, 0.92, 0.74, (1 - k) * 0.9),
                                      meta: SIMD4(UInt32(fl.region), 0, 0, 0)))
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
        var u = GalaxyUniforms(viewProj: viewProj, view: viewM, proj: proj, viewport: SIMD2(w, h), time: Float(now), projScale: projScale)
        enc.setVertexBytes(&u, length: MemoryLayout<GalaxyUniforms>.stride, index: 1)
        enc.setVertexBytes(regions, length: MemoryLayout<simd_float4x4>.stride * regions.count, index: 2)
        enc.setVertexBytes(sky, length: MemoryLayout<simd_float4x4>.stride * sky.count, index: 3)

        // 星云的画：两层，第二层大一点、转一点、淡一点，云就有了厚度
        enc.setRenderPipelineState(quadPipe)
        enc.setFragmentSamplerState(sampler, index: 0)
        for i in 0..<8 {
            guard let tex = artTextures[i] else { continue }
            let e = GalaxyLayout.extent(i)
            // 真照片：原样贴，外面再叠一层放大的、很淡的光晕；画出来的那团（北斗）照旧
            let photoQuads: [GalaxyQuad]? = !photoRegions.contains(i) ? nil : (i == 0
                ? [GalaxyQuad(center: SIMD4(0, 0, 0, e), tint: SIMD4(1, 1, 1, 0.95), meta: SIMD4(0, 1, 0, 0), extra: .zero),
                   GalaxyQuad(center: SIMD4(0, 4, 0, e * 1.3), tint: SIMD4(1, 1, 1, 0.14), meta: SIMD4(0, 1, 0, 0), extra: .zero)]
                : [GalaxyQuad(center: SIMD4(0, 0, 0, e), tint: SIMD4(1, 1, 1, 0.95), meta: SIMD4(UInt32(i), 0, 0, 0), extra: .zero),
                   GalaxyQuad(center: SIMD4(0, 0, 8, e * 1.35), tint: SIMD4(1, 1, 1, 0.12), meta: SIMD4(UInt32(i), 0, 0, 0), extra: SIMD4(0.3, 0, 0, 0))])
            let quads: [GalaxyQuad] = photoQuads ?? (i == 0
                ? [GalaxyQuad(center: SIMD4(0, 0, 0, e), tint: SIMD4(1, 1, 1, 0.8), meta: SIMD4(0, 1, 1, 0), extra: .zero),
                   GalaxyQuad(center: SIMD4(0, 5, 0, e * 1.15), tint: SIMD4(1, 1, 1, 0.22), meta: SIMD4(0, 1, 1, 0), extra: .zero)]
                : [GalaxyQuad(center: SIMD4(0, 0, 0, e), tint: SIMD4(1, 1, 1, 0.55), meta: SIMD4(UInt32(i), 0, 1, 0), extra: .zero),
                   GalaxyQuad(center: SIMD4(0, 0, 6, e * 1.3), tint: SIMD4(1, 1, 1, 0.2), meta: SIMD4(UInt32(i), 0, 1, 0), extra: SIMD4(0.4, 0, 0, 0))])
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
        enc.setRenderPipelineState(streakPipe)
        if let rings, ringCount > 0 {
            enc.setVertexBuffer(rings, offset: 0, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: ringCount)
        }
        if !streaks.isEmpty {
            enc.setVertexBytes(streaks, length: MemoryLayout<GalaxyStreak>.stride * streaks.count, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: streaks.count)
        }

        // 名字：在每一团下面，近的亮、远的淡；镜头凑近一团时别的名字收起来
        enc.setRenderPipelineState(quadPipe)
        for i in 0..<8 {
            guard let (tex, size) = labelTextures[i] else { continue }
            let c = viewProj * SIMD4(centers[i], 1)
            guard c.w > 0 else { continue }
            let depth = min(1, max(0, (c.w - 700) / 1400))
            var alpha = 1 - 0.45 * depth
            if let follow = camera.follow, follow != i { alpha *= 0.25 }
            let radiusPx = GalaxyLayout.extent(i) * projScale / c.w
            let half = size * 0.5 * scale
            let q = [GalaxyQuad(center: SIMD4(centers[i], 0), tint: SIMD4(1, 1, 1, alpha), meta: SIMD4(UInt32(GalaxyLayout.worldRegion), 2, 0, 0),
                                extra: SIMD4(0, -(radiusPx * 0.72 + half.y + 6 * scale), half.x, half.y))]
            enc.setFragmentTexture(tex, index: 0)
            enc.setVertexBytes(q, length: MemoryLayout<GalaxyQuad>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: 1)
        }
        if let (tex, size) = newTexture, !golden.isEmpty {
            let half = size * 0.5 * scale
            let qs = golden.prefix(40).map { g in
                GalaxyQuad(center: SIMD4(g.local, 0), tint: SIMD4(1, 1, 1, 0.95), meta: SIMD4(UInt32(g.region), 2, 0, 0),
                           extra: SIMD4(0, half.y + 9 * scale, half.x, half.y))
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
    var canEnter: (NebulaKind) -> Bool
    var onEnter: (NebulaKind) -> Void
    var onTapStar: (String) -> Void

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
        r.canEnter = canEnter
        r.onEnter = onEnter
        r.onTapStar = onTapStar
        r.update(input)
        v.isPaused = !active
        if context.coordinator.home != homeRequest {
            context.coordinator.home = homeRequest
            r.flyHome()
        }
    }
}
