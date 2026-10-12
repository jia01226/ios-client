import SwiftUI
import UIKit

/// Deterministic placement is separate from rendering and API state.
/// One node == one memory ID. Never duplicate sprites to make the garden look fuller.
enum MemoryFlowerLayout {
    struct Node {
        let flower: MemoryFlower
        let frame: CGRect
    }
    static let size = CGSize(width: 1000, height: 1778)
    /// Art-direction entry point: normalized foliage regions, never extra flowers.
    /// The open path, water and courtyard paving are deliberately left unplanted.
    static func plantingRegions(for scene: MemoryScene) -> [CGRect] {
        switch scene {
        case .moon: [CGRect(x: 0.14, y: 0.52, width: 0.24, height: 0.29),
                     CGRect(x: 0.76, y: 0.57, width: 0.12, height: 0.28),
                     CGRect(x: 0.15, y: 0.30, width: 0.23, height: 0.11)]
        case .water: [CGRect(x: 0.14, y: 0.56, width: 0.16, height: 0.25),
                      CGRect(x: 0.67, y: 0.28, width: 0.20, height: 0.13)]
        case .castle: [CGRect(x: 0.14, y: 0.68, width: 0.31, height: 0.19),
                       CGRect(x: 0.79, y: 0.54, width: 0.10, height: 0.12)]
        case .courtyard: [CGRect(x: 0.67, y: 0.77, width: 0.21, height: 0.12),
                          CGRect(x: 0.14, y: 0.27, width: 0.20, height: 0.09)]
        case .glasshouse: [CGRect(x: 0.14, y: 0.76, width: 0.25, height: 0.14),
                           CGRect(x: 0.68, y: 0.64, width: 0.21, height: 0.09),
                           CGRect(x: 0.14, y: 0.48, width: 0.23, height: 0.06)]
        }
    }
    static func nodes(_ flowers: [MemoryFlower], scene: MemoryScene) -> [Node] {
        let ordered = flowers.sorted { $0.id < $1.id }
        let regions = plantingRegions(for: scene)
        return ordered.map { flower in
            let hash = flower.id.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
            let region = regions[Int(hash % UInt64(regions.count))]
            let u = CGFloat((hash >> 12) % 997) / 997
            let v = CGFloat((hash >> 32) % 991) / 991
            let x = flower.state == "fallen" ? 380 + u * 250 : (region.minX + u * region.width) * size.width
            let y = flower.state == "fallen" ? 1450 + CGFloat(hash % 45)
                : (region.minY + v * region.height) * size.height
            let densityScale = min(1, sqrt(18 / CGFloat(max(1, ordered.count))))
            let perspective: CGFloat = region.midY < 0.5 ? 0.8 : 1
            let diameter = 165 * densityScale * perspective * (0.62 + CGFloat(flower.importance) * 0.038)
            return Node(flower: flower, frame: CGRect(x: x - diameter / 2, y: y - diameter / 2,
                                                     width: diameter, height: diameter))
        }
    }
    struct Cluster {
        var nodes: [Node]
        var center: CGPoint {
            CGPoint(x: nodes.reduce(0) { $0 + $1.frame.midX } / CGFloat(nodes.count),
                    y: nodes.reduce(0) { $0 + $1.frame.midY } / CGFloat(nodes.count))
        }
        // Includes the representatives, count label and quiet space around them.
        var bounds: CGRect { CGRect(x: center.x - 72, y: center.y - 58, width: 144, height: 150) }
    }
    static func clusters(_ nodes: [Node]) -> [Cluster] {
        var groups = Dictionary(grouping: nodes) { "\(Int($0.frame.midX / 180))-\(Int($0.frame.midY / 180))" }
            .values.map { Cluster(nodes: $0) }.sorted { $0.nodes[0].flower.id < $1.nodes[0].flower.id }
        // Each merge reduces the group count. IDs remain unique and totals remain exact.
        var merged = true
        while merged {
            merged = false
            outer: for i in groups.indices {
                for j in groups.indices where j > i {
                    if groups[i].bounds.intersects(groups[j].bounds) {
                        groups[i].nodes += groups[j].nodes
                        groups.remove(at: j)
                        merged = true
                        break outer
                    }
                }
            }
        }
        return groups
    }
}

/// Native pan/pinch surface, one drawing view, no 600-view SwiftUI tree.
/// Flower list is also provided by the screen for accessible, exact selection.
struct MemoryGardenCanvas: UIViewRepresentable {
    let flowers: [MemoryFlower]
    let scene: MemoryScene
    let night: Bool
    var witheredIDs: Set<String> = []
    var onSelect: (MemoryFlower) -> Void
    func makeUIView(context: Context) -> GardenScrollView { GardenScrollView() }
    func updateUIView(_ view: GardenScrollView, context: Context) {
        view.configure(flowers: flowers, scene: scene, night: night, witheredIDs: witheredIDs, onSelect: onSelect)
    }
}

final class GardenScrollView: UIScrollView, UIScrollViewDelegate {
    private let garden = GardenDrawingView(frame: CGRect(origin: .zero, size: MemoryFlowerLayout.size))
    private var scene: MemoryScene?
    private var fittedWidth: CGFloat = 0
    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        addSubview(garden)
        contentSize = garden.bounds.size
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bouncesZoom = true
        accessibilityIdentifier = "memory-garden-canvas"
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        garden.addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(flowers: [MemoryFlower], scene: MemoryScene, night: Bool, witheredIDs: Set<String>, onSelect: @escaping (MemoryFlower) -> Void) {
        let sceneChanged = self.scene != scene
        self.scene = scene
        garden.onSelect = onSelect
        if sceneChanged || garden.flowers != flowers || garden.night != night {
            garden.configure(flowers: flowers, scene: scene, night: night, witheredIDs: witheredIDs, animate: !sceneChanged)
        }
        if sceneChanged { fittedWidth = 0; setNeedsLayout() }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, abs(fittedWidth - bounds.width) > 0.5 else { return }
        fittedWidth = bounds.width
        let fit = max(bounds.width / MemoryFlowerLayout.size.width, bounds.height / MemoryFlowerLayout.size.height)
        minimumZoomScale = fit
        maximumZoomScale = fit * 5
        setZoomScale(fit, animated: false)
        contentOffset = CGPoint(x: max(0, (contentSize.width - bounds.width) / 2), y: 0)
        garden.detailScale = 1
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { garden }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        garden.detailScale = scale / max(0.01, minimumZoomScale)
    }
    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: garden)
        if garden.isClustered {
            let rect = CGRect(x: point.x - bounds.width / (minimumZoomScale * 2.5) / 2,
                              y: point.y - bounds.height / (minimumZoomScale * 2.5) / 2,
                              width: bounds.width / (minimumZoomScale * 2.5),
                              height: bounds.height / (minimumZoomScale * 2.5))
            zoom(to: rect, animated: !UIAccessibility.isReduceMotionEnabled)
            return
        }
        let hitSize = 44 / zoomScale
        if let node = garden.nodes.filter({ $0.frame.insetBy(dx: -hitSize / 2, dy: -hitSize / 2).contains(point) })
            .min(by: { hypot($0.frame.midX - point.x, $0.frame.midY - point.y) < hypot($1.frame.midX - point.x, $1.frame.midY - point.y) }) {
            garden.onSelect?(node.flower)
        }
    }
}

private final class GardenDrawingView: UIView {
    private(set) var flowers: [MemoryFlower] = []
    private(set) var nodes: [MemoryFlowerLayout.Node] = []
    private(set) var night = false
    var onSelect: ((MemoryFlower) -> Void)?
    var detailScale: CGFloat = 1 { didSet { if oldValue != detailScale { setNeedsDisplay() } } }
    var isClustered: Bool { flowers.count > 100 && detailScale < 1.8 }
    private var backgroundArt: UIImage?
    private var sprites: [String: UIImage] = [:]
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        contentMode = .redraw
        for name in ["MemoryBloom", "MemoryBud", "MemoryPetals"] { sprites[name] = UIImage(named: name) }
        isAccessibilityElement = true
        accessibilityLabel = "山茶花园"
        accessibilityHint = "双指缩放、拖动浏览。也可以用下方的花朵列表选择记忆。"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(flowers: [MemoryFlower], scene: MemoryScene, night: Bool, witheredIDs: Set<String>, animate: Bool) {
        if animate && !UIAccessibility.isReduceMotionEnabled {
            let incomingIDs = Set(flowers.map(\.id))
            for node in nodes where !incomingIDs.contains(node.flower.id) && witheredIDs.contains(node.flower.id) {
                let fallen = CALayer()
                fallen.contents = sprites["MemoryPetals"]?.cgImage
                fallen.frame = node.frame
                layer.addSublayer(fallen)
                let animation = CABasicAnimation(keyPath: "position.y")
                animation.fromValue = node.frame.midY
                animation.toValue = node.frame.midY + 95
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0.7; fade.toValue = 0
                let group = CAAnimationGroup()
                group.animations = [animation, fade]; group.duration = 0.9
                group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                fallen.opacity = 0
                fallen.add(group, forKey: "wither")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { fallen.removeFromSuperlayer() }
            }
        }
        self.flowers = flowers; self.night = night
        nodes = MemoryFlowerLayout.nodes(flowers, scene: scene)
        backgroundArt = UIImage(named: scene.rawValue)
        accessibilityValue = "\(flowers.count) 条记忆"
        setNeedsDisplay()
    }
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1).setFill()
        ctx.fill(bounds)
        backgroundArt?.draw(in: bounds)
        if night {
            UIColor(red: 0.055, green: 0.075, blue: 0.18, alpha: 0.72).setFill()
            ctx.fill(bounds)
        }
        if isClustered {
            // Aggregate only real IDs; count label is the exact represented population.
            for cluster in MemoryFlowerLayout.clusters(nodes) {
                let group = cluster.nodes
                let x = cluster.center.x
                let y = cluster.center.y
                // Three representative real IDs at most; the label states the cluster total.
                let representatives = group.sorted {
                    if $0.flower.loved != $1.flower.loved { return $0.flower.loved }
                    return $0.flower.id < $1.flower.id
                }.prefix(3)
                for (index, node) in representatives.enumerated() {
                    let angle = CGFloat(index) * 2.4
                    let radius = CGFloat(index == 0 ? 0 : 24)
                    let diameter = 62 * (0.62 + CGFloat(node.flower.importance) * 0.038)
                    drawFlower(node.flower, in: CGRect(x: x + cos(angle) * radius - diameter / 2,
                                                       y: y + sin(angle) * radius - diameter / 2,
                                                       width: diameter, height: diameter), context: ctx)
                }
                let label = "\(group.count)条"
                label.draw(at: CGPoint(x: x - 30, y: y + 50), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 24, weight: .light),
                    .foregroundColor: night ? UIColor.white : UIColor.darkGray
                ])
            }
            return
        }
        for node in nodes where node.frame.intersects(rect) {
            drawFlower(node.flower, in: node.frame, context: ctx)
        }
    }
    /// Both zoom levels use the same semantic appearance. No decorative population.
    private func drawFlower(_ flower: MemoryFlower, in frame: CGRect, context ctx: CGContext) {
            let sprite = flower.state == "bud" ? "MemoryBud" : (flower.state == "fallen" ? "MemoryPetals" : "MemoryBloom")
            let tint: UIColor = flower.valence < 0.15
                ? UIColor(red: 0.52, green: 0.30, blue: 0.37, alpha: 1)
                : flower.valence > 0.6 ? UIColor(red: 0.94, green: 0.78, blue: 0.83, alpha: 1)
                : UIColor(red: 0.97, green: 0.95, blue: 0.95, alpha: 1)
            ctx.saveGState()
            ctx.setAlpha(flower.author == "ke" ? 1 : 0.48)
            if night || flower.loved {
                ctx.setShadow(offset: .zero, blur: flower.loved ? 12 : 4,
                              color: UIColor.white.withAlphaComponent(flower.loved ? 0.75 : 0.2).cgColor)
            } else {
                ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 5,
                              color: UIColor(red: 0.28, green: 0.30, blue: 0.38, alpha: 0.35).cgColor)
            }
            // Preserve petal shading; tint only within the sprite's alpha.
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            sprites[sprite]?.draw(in: frame)
            ctx.setBlendMode(.sourceAtop)
            ctx.setFillColor(tint.withAlphaComponent(flower.valence < 0.15 ? 0.78 : 0.45).cgColor)
            ctx.fill(frame)
            ctx.endTransparencyLayer()
            ctx.restoreGState()
            if flower.loved {
                ctx.setFillColor(UIColor(red: 1, green: 0.96, blue: 0.85, alpha: 0.9).cgColor)
                ctx.fillEllipse(in: CGRect(x: frame.midX - 2, y: frame.midY - 2, width: 4, height: 4))
            }
    }
}
