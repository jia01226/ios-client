import SwiftUI
import SceneKit
import CoreText

// 95：记忆页的「记忆星河」——3D 场景部分。
// 版式与 15 号花体沿用 GPT 的网页预览（Design/MemoryGalaxyPreview），厚度来自 Claude 的网页版：
// 银河在中间、偏暖；星云是悬在不同深度的雾，大多在银河后面；远处三层偏冷的星空。
// 镜头绕银河转，近快远慢。一颗带名字的亮星 = 柯亲手记的一条记忆；以前整理的是暗一层的小点；其余全是星尘。

struct GalaxyRandom {
    private var state: UInt32
    init(seed: UInt32) { state = seed }
    static func hash(_ text: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for byte in text.utf8 { h ^= UInt32(byte); h = h &* 16_777_619 }
        return h
    }
    mutating func next() -> Float {
        state = state &* 1_664_525 &+ 1_013_904_223
        return Float(state) / 4_294_967_296
    }
    mutating func normal() -> Float {
        let u = max(0.00001, next()), v = next()
        return sqrt(-2 * log(u)) * cos(v * 2 * .pi)
    }
}

// MARK: - 程序画的贴图（全是 CGImage，没有图片素材）

enum GalaxyArt {
    static let space = CGColorSpaceCreateDeviceRGB()
    static func context(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
    static func radial(_ ctx: CGContext, center: CGPoint, radius: CGFloat, stops: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)]) {
        let colors = stops.map { CGColor(red: $0.1, green: $0.2, blue: $0.3, alpha: $0.4) } as CFArray
        let locations = stops.map(\.0)
        guard let g = CGGradient(colorsSpace: space, colors: colors, locations: locations) else { return }
        ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }
    /// 记忆星：光晕加一道很淡的十字星芒
    static let star: CGImage? = {
        let s = 128, c = CGPoint(x: 64, y: 64)
        guard let ctx = context(s, s) else { return nil }
        radial(ctx, center: c, radius: 64, stops: [(0, 1, 1, 1, 1), (0.1, 1, 1, 1, 0.6), (0.32, 1, 1, 1, 0.12), (1, 1, 1, 1, 0)])
        ctx.setBlendMode(.plusLighter)
        for (sx, sy) in [(CGFloat(1), CGFloat(0.035)), (0.035, 1)] {
            ctx.saveGState()
            ctx.translateBy(x: 64, y: 64)
            ctx.scaleBy(x: sx, y: sy)
            radial(ctx, center: .zero, radius: 64, stops: [(0, 1, 1, 1, 0.4), (1, 1, 1, 1, 0)])
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }()
    static let glow: CGImage? = {
        guard let ctx = context(128, 128) else { return nil }
        radial(ctx, center: CGPoint(x: 64, y: 64), radius: 64, stops: [(0, 1, 1, 1, 1), (0.1, 1, 1, 1, 0.6), (0.32, 1, 1, 1, 0.12), (1, 1, 1, 1, 0)])
        return ctx.makeImage()
    }()
    static let ring: CGImage? = {
        guard let ctx = context(128, 128) else { return nil }
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: CGRect(x: 6, y: 6, width: 116, height: 116))
        return ctx.makeImage()
    }()
    /// 银河盘面下那层淡淡的暖光，把银河的形状托出来
    static let disk: CGImage? = {
        guard let ctx = context(512, 512) else { return nil }
        radial(ctx, center: CGPoint(x: 256, y: 256), radius: 256,
               stops: [(0, 1, 0.925, 0.84, 0.5), (0.35, 0.9, 0.84, 0.91, 0.16), (1, 0.78, 0.745, 0.9, 0)])
        return ctx.makeImage()
    }()
    static func cloud(seed: UInt32, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGImage? {
        let s = 256
        guard let ctx = context(s, s) else { return nil }
        var random = GalaxyRandom(seed: seed)
        for _ in 0..<22 {
            let p = CGPoint(x: CGFloat(s) / 2 + CGFloat(random.next() - 0.5) * CGFloat(s) * 0.5,
                            y: CGFloat(s) / 2 + CGFloat(random.next() - 0.5) * CGFloat(s) * 0.4)
            let a = 0.16 + CGFloat(random.next()) * 0.16
            radial(ctx, center: p, radius: CGFloat(s) * (0.12 + CGFloat(random.next()) * 0.3), stops: [(0, r, g, b, a), (1, r, g, b, 0)])
        }
        return ctx.makeImage()
    }
    /// 星星下面的名字。用系统苹方画成贴图，跟着星星一起飞。
    static func label(_ text: String) -> (CGImage, CGFloat)? {
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 30, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0.87, green: 0.83, blue: 0.92, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let w = Int(ceil(bounds.width)) + 24, h = 48
        guard let ctx = context(w, h) else { return nil }
        ctx.setShadow(offset: .zero, blur: 8, color: CGColor(red: 0.02, green: 0.027, blue: 0.05, alpha: 1))
        ctx.textPosition = CGPoint(x: 12 - bounds.minX, y: 14)
        CTLineDraw(line, ctx)
        guard let image = ctx.makeImage() else { return nil }
        return (image, CGFloat(w) / CGFloat(h))
    }
}

// MARK: - 点云

enum GalaxyPoints {
    struct Dot { var p: SIMD3<Float>; var c: SIMD3<Float> }
    /// 一批同样大小的点。SceneKit 的点是屏幕上的小方块，所以都压在 1–3 像素，看起来就是星点。
    static func node(_ dots: [Dot], size: CGFloat, minPx: CGFloat, maxPx: CGFloat) -> SCNNode {
        let vertices = dots.map { SCNVector3($0.p.x, $0.p.y, $0.p.z) }
        var colors: [Float] = []
        colors.reserveCapacity(dots.count * 3)
        for d in dots { colors.append(d.c.x); colors.append(d.c.y); colors.append(d.c.z) }
        let colorSource = SCNGeometrySource(data: Data(bytes: colors, count: colors.count * 4), semantic: .color,
                                            vectorCount: dots.count, usesFloatComponents: true, componentsPerVector: 3,
                                            bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let indices = (0..<UInt32(dots.count)).map { $0 }
        let element = SCNGeometryElement(data: Data(bytes: indices, count: indices.count * 4), primitiveType: .point,
                                         primitiveCount: dots.count, bytesPerIndex: 4)
        element.pointSize = size
        element.minimumPointScreenSpaceRadius = minPx
        element.maximumPointScreenSpaceRadius = maxPx
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), colorSource], elements: [element])
        geometry.firstMaterial = additive()
        return SCNNode(geometry: geometry)
    }
    static func additive(_ contents: Any? = nil) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        m.isDoubleSided = true
        if let contents { m.diffuse.contents = contents }
        return m
    }
}

// MARK: - 一颗记忆星

final class GalaxyStar {
    let id: String
    let category: String
    let base: Float
    let phase: Float
    let importance: Int
    let holder = SCNNode()     // 在银河盘面里的位置
    let facing = SCNNode()     // 永远面向镜头：星、光环、名字都挂在这里
    let glow: SCNNode
    let ring: SCNNode
    let label: SCNNode?
    var loved = false
    var hiddenUntil: Date?
    var revealAt: Date?
    var dimmed = false

    init(flower: MemoryFlower, position: SCNVector3) {
        id = flower.id
        category = flower.category
        importance = flower.importance
        base = 0.22 + Float(flower.importance) * 0.024
        phase = Float(GalaxyRandom.hash(flower.id) % 1000) / 1000 * 6.28
        holder.position = position
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        facing.constraints = [billboard]
        holder.addChildNode(facing)

        let tint = [CGColor(red: 0.93, green: 0.91, blue: 0.98, alpha: 1), CGColor(red: 0.91, green: 0.91, blue: 0.99, alpha: 1),
                    CGColor(red: 0.95, green: 0.91, blue: 0.96, alpha: 1)][flower.importance % 3]
        let starPlane = SCNPlane(width: 1, height: 1)
        let mat = GalaxyPoints.additive(GalaxyArt.star)
        mat.multiply.contents = tint
        starPlane.firstMaterial = mat
        glow = SCNNode(geometry: starPlane)
        facing.addChildNode(glow)

        let ringPlane = SCNPlane(width: 1, height: 1)
        let ringMat = GalaxyPoints.additive(GalaxyArt.ring)
        ringMat.multiply.contents = CGColor(red: 0.91, green: 0.66, blue: 0.71, alpha: 1)
        ringPlane.firstMaterial = ringMat
        ring = SCNNode(geometry: ringPlane)
        ring.opacity = 0
        facing.addChildNode(ring)

        if let (image, aspect) = GalaxyArt.label(flower.title) {
            let h: CGFloat = 0.085
            let plane = SCNPlane(width: h * aspect, height: h)
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = image
            m.writesToDepthBuffer = false
            m.readsFromDepthBuffer = false
            m.isDoubleSided = true
            plane.firstMaterial = m
            let node = SCNNode(geometry: plane)
            node.position = SCNVector3(0, -0.15, 0)
            facing.addChildNode(node)
            label = node
        } else {
            label = nil
        }
        loved = flower.loved
    }
}

// MARK: - 整个世界：场景、镜头、手势、每一帧

final class GalaxyWorld: NSObject, SCNSceneRendererDelegate {
    struct Orbit { var az: Float; var el: Float; var dist: Float; var target: SIMD3<Float> }
    static let home = Orbit(az: 0, el: 0, dist: 5.6, target: .zero)
    static let galaxyScale: Float = 1.6

    let scene = SCNScene()
    let cameraNode = SCNNode()
    let galaxy = SCNNode()
    private let oldLayer = SCNNode()
    private let coreGlow: SCNNode
    private let selection: SCNNode

    private let lock = NSLock()
    private var cam = GalaxyWorld.home
    private var goal = GalaxyWorld.home
    private var velocity = SIMD2<Float>(0, 0)
    private var gestureBase: Orbit?
    private var dragOrigin: CGSize?
    private var pinchOrigin: CGFloat?
    private var stars: [String: GalaxyStar] = [:]
    private var olds: [(id: String, category: String, position: SCNVector3)] = []
    private var selectedID: String?
    private var category: String?
    private var start = Date()
    private weak var renderer: SCNSceneRenderer?
    var reduceMotion = false
    var showOthers = false { didSet { oldLayer.isHidden = !showOthers } }

    override init() {
        let core = SCNPlane(width: 1.5, height: 1.5)
        let coreMat = GalaxyPoints.additive(GalaxyArt.glow)
        coreMat.multiply.contents = CGColor(red: 1, green: 0.945, blue: 0.86, alpha: 1)
        core.firstMaterial = coreMat
        coreGlow = SCNNode(geometry: core)
        let ringPlane = SCNPlane(width: 1, height: 1)
        let ringMat = GalaxyPoints.additive(GalaxyArt.ring)
        ringMat.multiply.contents = CGColor(red: 0.94, green: 0.88, blue: 0.73, alpha: 1)
        ringPlane.firstMaterial = ringMat
        selection = SCNNode(geometry: ringPlane)
        selection.opacity = 0
        super.init()
        build()
    }

    private func build() {
        scene.background.contents = CGColor(red: 0.02, green: 0.027, blue: 0.05, alpha: 1)
        let camera = SCNCamera()
        camera.fieldOfView = 58
        camera.zNear = 0.05
        camera.zFar = 600
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        var random = GalaxyRandom(seed: 20_261_014)
        // 远处三层星空：偏冷，越远越暗越小
        func shell(_ n: Int, _ r0: Float, _ r1: Float, _ bright: Float, size: CGFloat, maxPx: CGFloat) {
            var dots: [GalaxyPoints.Dot] = []
            for _ in 0..<n {
                let u = random.next() * 2 - 1, a = random.next() * 2 * .pi, r = r0 + random.next() * (r1 - r0), q = sqrt(1 - u * u)
                let t = random.next()
                let c: SIMD3<Float> = t < 0.1 ? [0.95, 0.88, 0.9] : (t < 0.4 ? [0.76, 0.82, 1] : [0.86, 0.9, 1])
                let b = bright * (0.35 + random.next() * 0.65)
                dots.append(.init(p: [cos(a) * q * r, u * r, sin(a) * q * r], c: c * b))
            }
            scene.rootNode.addChildNode(GalaxyPoints.node(dots, size: size, minPx: 0.5, maxPx: maxPx))
        }
        shell(2600, 140, 180, 0.6, size: 0.5, maxPx: 1.2)
        shell(1400, 70, 95, 0.7, size: 0.35, maxPx: 1.6)
        shell(500, 30, 45, 0.85, size: 0.2, maxPx: 2.2)
        // 远处一条斜着的细银河带
        var band: [GalaxyPoints.Dot] = []
        for _ in 0..<5000 {
            let x = (random.next() - 0.5) * 260
            let b = 0.12 + random.next() * 0.3
            band.append(.init(p: [x, random.normal() * 7 + x * 0.35, -110 - random.next() * 20], c: [0.92 * b, 0.9 * b, b]))
        }
        scene.rootNode.addChildNode(GalaxyPoints.node(band, size: 0.4, minPx: 0.5, maxPx: 1.4))

        // 星云：大多在银河后面，前面只留两团很淡的
        let nebulae: [(CGFloat, CGFloat, CGFloat, SCNVector3, CGFloat, CGFloat)] = [
            (112, 94, 150, SCNVector3(-3.2, 1.6, -2.6), 6.5, 0.55), (62, 80, 140, SCNVector3(3.4, -1.2, -3.4), 7, 0.6),
            (140, 86, 118, SCNVector3(2, 2.6, -3.2), 4.2, 0.34), (70, 86, 130, SCNVector3(-2.6, -2.4, -2.2), 4.6, 0.3),
            (120, 100, 160, SCNVector3(0.4, -0.3, -5.5), 9, 0.45), (150, 96, 126, SCNVector3(-1.6, 1.2, 1.4), 2.4, 0.1),
            (80, 100, 150, SCNVector3(2.8, 0.8, 1.2), 2.8, 0.1), (200, 190, 230, SCNVector3(0, 0, -60), 70, 0.18)
        ]
        for (i, n) in nebulae.enumerated() {
            let plane = SCNPlane(width: n.4 * 1.5, height: n.4)
            plane.firstMaterial = GalaxyPoints.additive(GalaxyArt.cloud(seed: UInt32(31 + i * 7), n.0 / 255, n.1 / 255, n.2 / 255))
            let node = SCNNode(geometry: plane)
            node.position = n.3
            node.opacity = n.5
            node.constraints = [SCNBillboardConstraint()]
            scene.rootNode.addChildNode(node)
        }

        // 银河：两条旋臂，中心最亮，偏暖白，盘面有厚度
        galaxy.eulerAngles = SCNVector3(-1.08, 0, -0.19)
        scene.rootNode.addChildNode(galaxy)
        let gs = Self.galaxyScale
        var core: [GalaxyPoints.Dot] = [], arms: [GalaxyPoints.Dot] = []
        let n = 14_000
        for i in 0..<n {
            var r: Float, a: Float, z: Float
            if i < Int(Float(n) * 0.22) {
                r = pow(random.next(), 1.1) * 0.34; a = random.next() * 2 * .pi; z = random.normal() * 0.14 * max(0.25, 1 - r * 2)
            } else {
                r = 0.13 + pow(random.next(), 0.8) * 1.12
                let arm = Float(i % 2), scatter = random.normal() * (0.065 + 0.08 * r) * (i % 5 == 0 ? 2.5 : 1)
                a = arm * .pi + r * 5.2 + 0.19 * sin(r * 14 + arm) + scatter / max(0.18, r)
                if i % 7 == 0 { a += 0.45 + random.normal() * 0.24 }
                r += random.normal() * 0.035
                z = random.normal() * (0.045 + r * 0.065) + 0.04 * sin(a * 3 + r * 8)
                if i % 8 == 0 { z += random.normal() * 0.13 }
            }
            let lane = pow(max(0, cos(a * 2 - r * 10 + 0.5)), 10)
            let cloud = 0.72 + 0.28 * sin(a * 7 + r * 23) * sin(a * 3 - r * 17)
            var b = (0.2 + random.next() * 0.42) * cloud * (1 - 0.84 * lane) * min(1, (1.4 - r) * 2.5) * 1.12
            b *= r < 0.3 ? (0.75 + r * 1.2) : 1
            b = max(0, b)
            let warm = max(0, 1 - r * 2.6), pink: Float = random.next() < 0.07 ? 0.5 : 0
            let c: SIMD3<Float> = [(1 + 0.04 * pink) * b, (0.95 + 0.03 * warm - 0.1 * pink) * b, (0.88 - 0.12 * warm + 0.02 * pink) * b]
            let dot = GalaxyPoints.Dot(p: [cos(a) * r * gs, sin(a) * r * gs, z * gs], c: c)
            if r < 0.3 { core.append(dot) } else { arms.append(dot) }
        }
        galaxy.addChildNode(GalaxyPoints.node(arms, size: 0.02, minPx: 0.6, maxPx: 2.4))
        galaxy.addChildNode(GalaxyPoints.node(core, size: 0.022, minPx: 0.7, maxPx: 2.6))
        let diskPlane = SCNPlane(width: 4.4, height: 4.4)
        diskPlane.firstMaterial = GalaxyPoints.additive(GalaxyArt.disk)
        let disk = SCNNode(geometry: diskPlane)
        disk.opacity = 0.55
        galaxy.addChildNode(disk)
        coreGlow.constraints = [SCNBillboardConstraint()]
        coreGlow.opacity = 0.38
        galaxy.addChildNode(coreGlow)
        selection.constraints = [SCNBillboardConstraint()]
        galaxy.addChildNode(selection)
        oldLayer.isHidden = true
        galaxy.addChildNode(oldLayer)
        placeCamera(cam)
    }

    // MARK: 记忆 → 星

    /// 位置只看记忆 ID：新记一条不会把旧的星挪走。柯记的落在旋臂上，以前整理的散在盘面里。
    static func position(for id: String, ke: Bool) -> SCNVector3 {
        var random = GalaxyRandom(seed: GalaxyRandom.hash(id))
        let gs = galaxyScale
        if ke {
            let r = 0.25 + 0.75 * sqrt(random.next())
            let arm: Float = random.next() < 0.5 ? 0 : 1
            let a = arm * .pi + r * 5.2 + (random.next() - 0.5) * 0.5
            return SCNVector3(cos(a) * r * gs, sin(a) * r * gs, (random.next() - 0.5) * 0.08 * gs + 0.06)
        }
        let r = 0.2 + pow(random.next(), 0.7) * 0.85, a = random.next() * 2 * .pi
        return SCNVector3(cos(a) * r * gs, sin(a) * r * gs, random.normal() * 0.05 * gs)
    }

    func sync(ke flowers: [MemoryFlower], others: [MemoryFlower]) {
        lock.lock(); defer { lock.unlock() }
        let wanted = Set(flowers.map(\.id))
        for (id, star) in stars where !wanted.contains(id) { star.holder.removeFromParentNode(); stars[id] = nil }
        for flower in flowers {
            if let star = stars[flower.id] { star.loved = flower.loved; continue }
            let star = GalaxyStar(flower: flower, position: Self.position(for: flower.id, ke: true))
            stars[flower.id] = star
            galaxy.addChildNode(star.holder)
        }
        if selectedID.map({ !wanted.contains($0) }) == true { selectedID = nil }
        olds = others.map { ($0.id, $0.category, Self.position(for: $0.id, ke: false)) }
        oldLayer.childNodes.forEach { $0.removeFromParentNode() }
        if !olds.isEmpty {
            let dots = olds.map { GalaxyPoints.Dot(p: [Float($0.position.x), Float($0.position.y), Float($0.position.z)], c: [0.62, 0.6, 0.72]) }
            oldLayer.addChildNode(GalaxyPoints.node(dots, size: 0.03, minPx: 1.2, maxPx: 2.6))
        }
    }

    // MARK: 镜头

    private func placeCamera(_ o: Orbit) {
        let ce = cos(o.el)
        cameraNode.simdPosition = o.target + SIMD3(sin(o.az) * ce * o.dist, sin(o.el) * o.dist, cos(o.az) * ce * o.dist)
        cameraNode.simdLook(at: o.target)
    }
    private func clamp(_ o: inout Orbit) {
        o.el = min(0.75, max(-0.55, o.el)); o.dist = min(9, max(2.2, o.dist))
    }
    func drag(_ translation: CGSize) {
        lock.lock(); defer { lock.unlock() }
        if gestureBase == nil { gestureBase = goal; pinchOrigin = nil }
        if dragOrigin == nil { dragOrigin = translation }
        guard var o = gestureBase, let origin = dragOrigin else { return }
        let s = 0.0055 * min(1.4, o.dist / 5.6)
        o.az -= Float(translation.width - origin.width) * s
        o.el += Float(translation.height - origin.height) * s * 0.8
        clamp(&o)
        goal.az = o.az; goal.el = o.el; cam.az = o.az; cam.el = o.el
        velocity = .zero
    }
    func pinch(_ magnification: CGFloat) {
        lock.lock(); defer { lock.unlock() }
        if gestureBase == nil { gestureBase = goal; dragOrigin = nil }
        if pinchOrigin == nil { pinchOrigin = magnification }
        guard let base = gestureBase, let origin = pinchOrigin else { return }
        goal.dist = min(9, max(2.2, base.dist * Float(origin / max(0.05, magnification))))
    }
    /// 松手后按手指的速度再转一段
    func endGesture(fling: CGSize = .zero) {
        lock.lock(); defer { lock.unlock() }
        gestureBase = nil; dragOrigin = nil; pinchOrigin = nil
        guard !reduceMotion else { return }
        let s = 0.0055 * min(1.4, goal.dist / 5.6)
        velocity = SIMD2(-Float(fling.width) * s * 0.035, Float(fling.height) * s * 0.028)
    }
    func goHome() {
        lock.lock(); defer { lock.unlock() }
        goal = Self.home; velocity = .zero; selectedID = nil
    }

    // MARK: 选择与分类

    func worldPosition(of id: String) -> SIMD3<Float>? {
        stars[id]?.holder.simdWorldPosition
    }
    func select(_ id: String?) {
        lock.lock(); defer { lock.unlock() }
        selectedID = id
        velocity = .zero
        if let id, let p = stars[id]?.holder.simdWorldPosition {
            goal.target = p; goal.dist = 2.6
        } else {
            goal.target = .zero; goal.dist = max(goal.dist, 4.6)
        }
    }
    func filter(_ category: String?) {
        lock.lock(); defer { lock.unlock() }
        self.category = category
        selectedID = nil
        let inside = stars.values.filter { category == nil || $0.category == category }
        if category != nil, !inside.isEmpty {
            goal.target = inside.map { $0.holder.simdWorldPosition }.reduce(.zero, +) / Float(inside.count)
            goal.dist = 3.6
        } else {
            goal.target = .zero; goal.dist = Self.home.dist
        }
    }
    /// 新记忆：先藏着，流星落到它那儿再亮起来
    func hide(_ id: String, until date: Date) {
        lock.lock(); defer { lock.unlock() }
        stars[id]?.hiddenUntil = date
    }

    /// 点到哪颗。柯记的亮星优先；打开了「以前整理的」才去找暗星。
    func hit(_ point: CGPoint) -> (id: String, ke: Bool)? {
        guard let renderer else { return nil }
        lock.lock(); let list = Array(stars.values); let oldList = showOthers ? olds : []; let cat = category; lock.unlock()
        var best: (String, CGFloat)?
        for star in list where cat == nil || star.category == cat {
            if let until = star.hiddenUntil, until > Date() { continue }
            let p = renderer.projectPoint(star.holder.worldPosition)
            guard p.z > 0, p.z < 1 else { continue }
            let d = hypot(CGFloat(p.x) - point.x, CGFloat(p.y) - point.y)
            if d < 32, d < (best?.1 ?? .infinity) { best = (star.id, d) }
        }
        if let best { return (best.0, true) }
        var old: (String, CGFloat)?
        for o in oldList where cat == nil || o.category == cat {
            let p = renderer.projectPoint(galaxy.convertPosition(o.position, to: nil))
            guard p.z > 0, p.z < 1 else { continue }
            let d = hypot(CGFloat(p.x) - point.x, CGFloat(p.y) - point.y)
            if d < 22, d < (old?.1 ?? .infinity) { old = (o.id, d) }
        }
        return old.map { ($0.0, false) }
    }
    func screenPoint(of id: String) -> CGPoint? {
        guard let renderer, let star = stars[id] else { return nil }
        let p = renderer.projectPoint(star.holder.worldPosition)
        return CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
    }

    // MARK: 每一帧（SceneKit 渲染线程）

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        self.renderer = renderer
        lock.lock(); defer { lock.unlock() }
        let t = Float(Date().timeIntervalSince(start)), now = Date()
        if gestureBase == nil {
            goal.az += velocity.x; goal.el += velocity.y
            velocity *= 0.93
            if !reduceMotion, selectedID == nil, abs(velocity.x) < 0.0001 { goal.az += 0.00035 }
        }
        clamp(&goal)
        let k: Float = reduceMotion ? 1 : 0.07
        cam.az += (goal.az - cam.az) * k; cam.el += (goal.el - cam.el) * k; cam.dist += (goal.dist - cam.dist) * k
        cam.target += (goal.target - cam.target) * k
        placeCamera(cam)
        coreGlow.opacity = CGFloat(0.38 + (reduceMotion ? 0 : 0.05 * sin(t * 0.7)))
        let labelAlpha = CGFloat(max(0, min(1, (7.5 - cam.dist) / 1.2)))
        for star in stars.values {
            let inside = category == nil || star.category == category
            var alpha: Float = inside ? 0.62 : 0.12
            let pulse: Float = reduceMotion ? 1
                : 0.79 + 0.16 * sin(t * (0.83 + Float(star.importance) * 0.037) + star.phase)
                  + 0.27 * exp(-pow((fmod(t + star.phase * 2.73, 17) / 17 - 0.5) / 0.026, 2))
            var scale = star.base * pulse
            if let until = star.hiddenUntil {
                let p = Float(now.timeIntervalSince(until) / 1.4)
                if p < 0 { alpha = 0 } else if p >= 1 { star.hiddenUntil = nil } else { alpha *= p; scale *= 1 + (1 - p) * 2.5 }
            }
            star.glow.opacity = CGFloat(alpha)
            star.glow.scale = SCNVector3(scale, scale, 1)
            star.ring.opacity = star.loved ? CGFloat(alpha * 0.55) : 0
            let ringScale = star.base * 1.15 + (reduceMotion ? 0 : sin(t * 1.6) * 0.015)
            star.ring.scale = SCNVector3(ringScale, ringScale, 1)
            star.label?.opacity = alpha > 0.3 ? labelAlpha * (star.id == selectedID ? 1 : 0.85) : 0
        }
        if let id = selectedID, let star = stars[id] {
            selection.position = star.holder.position
            let s = star.base * 1.5
            selection.scale = SCNVector3(s, s, 1)
            selection.opacity = 0.9
        } else {
            selection.opacity = 0
        }
    }
}
