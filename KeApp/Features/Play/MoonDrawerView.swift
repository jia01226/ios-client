import SwiftUI
import SceneKit

struct MoonDrawerView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let line: ChatLine
    @State private var drawer: RemoteDrawer?
    @State private var error: String?
    @State private var loading = false
    @State private var openness: CGFloat = 0
    @State private var dragStart: CGFloat?
    @State private var reading: RemoteDrawer.Item?
    private var released: [RemoteDrawer.Item] { drawer?.outside.filter { $0.visibility == "released" } ?? [] }
    private var previews: [RemoteDrawer.Item] { drawer?.outside.filter { $0.visibility == "teaser" } ?? [] }
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("keepsakes").font(Moonlight.script(29)).foregroundStyle(theme.pageAccent).padding(.top, 12)
                LacquerDrawerScene(openness: openness, night: theme.skin == .night, hasLetter: !released.isEmpty)
                    .frame(height: 315).accessibilityHidden(true)
                    .overlay {
                        Color.clear.contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 8)
                                .onChanged { value in
                                    if dragStart == nil { dragStart = openness }
                                    openness = min(1, max(0, (dragStart ?? 0) + value.translation.height / 110))
                                }
                                .onEnded { value in
                                    let target: CGFloat = openness + value.predictedEndTranslation.height / 500 > 0.5 ? 1 : 0
                                    settle(target); dragStart = nil
                                })
                    }
                Button { settle(openness > 0.5 ? 0 : 1) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "moon").font(.system(size: 16, weight: .ultraLight))
                        Text(openness > 0.5 ? "轻轻推回去" : "拉开上面这一层").font(Moonlight.serif(17))
                        Image(systemName: openness > 0.5 ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .ultraLight))
                    }.frame(minHeight: 44)
                }.accessibilityIdentifier("drawer-pull").accessibilityValue(openness > 0.5 ? "已拉开" : "已合上")
                if openness > 0.5 {
                    VStack(alignment: .leading, spacing: 16) {
                        if loading { ProgressView("正在看看柯留下了什么") }
                        if let error { Button(error) { Task { await load() } }.font(Moonlight.serif(13)) }
                        if let drawer, drawer.outside.isEmpty { Text("柯还没有把东西放在这一层。").font(Moonlight.serif(14)) }
                        ForEach(released) { item in
                            Button { reading = item } label: {
                                HStack {
                                    Image(systemName: "envelope.open").font(.system(size: 19, weight: .ultraLight))
                                    Text(item.title).font(Moonlight.serif(17))
                                    Spacer(); Image(systemName: "chevron.right").font(.system(size: 10, weight: .ultraLight))
                                }.padding(.vertical, 10).contentShape(Rectangle())
                            }.accessibilityIdentifier("drawer-letter-\(item.id)")
                        }
                        ForEach(previews) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title).font(Moonlight.serif(16))
                                Text(item.teaser).font(Moonlight.serif(13)).foregroundStyle(theme.pageColor.textSecondary)
                            }
                        }
                    }.padding(.horizontal, 32).transition(.opacity)
                }
                HStack(spacing: 8) {
                    Image(systemName: "lock").font(.system(size: 12, weight: .ultraLight))
                    Text("下面这一层，先留给柯。").font(Moonlight.serif(13))
                }.foregroundStyle(theme.pageColor.textSecondary).padding(.top, 12)
                    .accessibilityIdentifier("drawer-private-locked")
                Text("等他愿意，会亲手拿给你。").font(Moonlight.serif(12)).foregroundStyle(theme.pageColor.textSecondary)
            }.frame(maxWidth: .infinity).padding(.bottom, 24)
        }.buttonStyle(.plain).tint(theme.pageAccent).scrollIndicators(.hidden)
            .task { await load() }.refreshable { await load() }
            .sheet(item: $reading) { item in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            Text(item.title).font(Moonlight.serif(28))
                            // Visibility is checked twice; private payloads can never become a reader.
                            if item.visibility == "released" { Text(item.content).font(Moonlight.serif(18)).lineSpacing(10).textSelection(.enabled) }
                            Text(item.created_at).font(Moonlight.serif(12)).foregroundStyle(theme.pageColor.textSecondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
                    }.background(theme.pageBackground).foregroundStyle(theme.pageColor.textPrimary)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("放回去") { reading = nil } } }
                }.tint(theme.pageAccent)
            }
    }
    private func settle(_ target: CGFloat) {
        withAnimation(reduceMotion ? .linear(duration: 0.1) : .spring(response: 0.6, dampingFraction: 0.85)) { openness = target }
    }
    private func load() async {
        guard !loading else { return }; loading = true; error = nil
        defer { loading = false }
        do { drawer = try await APIClient(baseURL: line.apiBaseURL).fetchDrawer() }
        catch { self.error = "抽屉暂时没接上，点这里重试。" }
    }
}

/// Separate 3D tray node moves inside a stationary two-tier cabinet; no felt textures.
private struct LacquerDrawerScene: UIViewRepresentable, Animatable {
    var openness: CGFloat
    var night: Bool
    var hasLetter: Bool
    var animatableData: CGFloat { get { openness } set { openness = newValue } }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = Moonlight.clear
        view.isOpaque = false; view.antialiasingMode = .multisampling4X
        view.scene = buildScene(night: night, hasLetter: hasLetter)
        view.allowsCameraControl = false; view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        let signature = "\(night)-\(hasLetter)"
        if view.scene?.rootNode.name != signature { view.scene = buildScene(night: night, hasLetter: hasLetter) }
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        view.scene?.rootNode.childNode(withName: "upper-tray", recursively: true)?.position.z = Float(openness * 1.05)
        SCNTransaction.commit()
    }
    private func buildScene(night: Bool, hasLetter: Bool) -> SCNScene {
        let scene = SCNScene(); scene.rootNode.name = "\(night)-\(hasLetter)"
        func material(_ color: UIColor, roughness: CGFloat = 0.3, metal: CGFloat = 0.08) -> SCNMaterial {
            let m = SCNMaterial(); m.diffuse.contents = color; m.lightingModel = .physicallyBased
            m.roughness.contents = roughness; m.metalness.contents = metal; return m
        }
        let lacquer = material(night ? UIColor(Palette.night.cardElevated) : Moonlight.lacquer)
        let inside = material(night ? UIColor(Palette.night.card) : Moonlight.lacquerInside, roughness: 0.55)
        let pearl = material(night ? UIColor(Palette.night.accentSoft) : Moonlight.pearlMetal, roughness: 0.2, metal: 0.45)
        let paper = material(night ? UIColor(Palette.night.textSecondary) : Moonlight.paper, roughness: 0.8)
        func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ at: SCNVector3, _ m: SCNMaterial, parent: SCNNode? = nil, radius: CGFloat = 0.045) {
            let g = SCNBox(width: w, height: h, length: d, chamferRadius: min(radius, min(w, min(h,d)) / 3))
            g.materials = [m]; let n = SCNNode(geometry: g); n.position = at; (parent ?? scene.rootNode).addChildNode(n)
        }
        // Shell, shelf and feet are kept fixed as the upper tray slides forward.
        box(3.3, 0.16, 1.95, SCNVector3(0, 2.1, 0), lacquer)
        box(3.3, 0.16, 1.95, SCNVector3(0, 0.1, 0), lacquer)
        box(0.14, 1.94, 1.88, SCNVector3(-1.56, 1.1, 0), lacquer)
        box(0.14, 1.94, 1.88, SCNVector3(1.56, 1.1, 0), lacquer)
        box(3.05, 1.94, 0.13, SCNVector3(0, 1.1, -0.89), lacquer)
        box(3.1, 0.09, 1.84, SCNVector3(0, 1.07, 0), lacquer)
        for x: Float in [-1.32, 1.32] { box(0.19, 0.23, 0.3, SCNVector3(x, -0.06, 0.62), pearl) }
        func tray(y: Float, name: String) -> SCNNode {
            let t = SCNNode(); t.name = name; t.position.y = y; scene.rootNode.addChildNode(t)
            box(2.99, 0.82, 0.13, SCNVector3(0, 0, 0.94), lacquer, parent: t)
            box(2.84, 0.07, 1.72, SCNVector3(0, -0.37, 0), inside, parent: t)
            for x: Float in [-1.39, 1.39] { box(0.08, 0.67, 1.7, SCNVector3(x, -0.02, 0), lacquer, parent: t) }
            box(2.8, 0.67, 0.07, SCNVector3(0, -0.02, -0.82), lacquer, parent: t)
            let path = UIBezierPath(cgPath: MoonCrescent().path(in: CGRect(x: 0, y: 0, width: 0.32, height: 0.32)).cgPath)
            let moon = SCNShape(path: path, extrusionDepth: 0.05); moon.chamferRadius = 0.012; moon.materials = [pearl]
            let pull = SCNNode(geometry: moon); pull.position = SCNVector3(-0.16, 0.12, 1.04); pull.eulerAngles.x = .pi
            t.addChildNode(pull)
            return t
        }
        let top = tray(y: 1.58, name: "upper-tray")
        let bottom = tray(y: 0.58, name: "locked-tray")
        // Lower tray is never populated with private material and has no open operation.
        box(0.15, 0.14, 0.07, SCNVector3(0, -0.13, 1.09), pearl, parent: bottom, radius: 0.025)
        let loop = SCNTorus(ringRadius: 0.052, pipeRadius: 0.013); loop.materials = [pearl]
        let lock = SCNNode(geometry: loop); lock.eulerAngles.x = .pi / 2; lock.position = SCNVector3(0, -0.04, 1.09); bottom.addChildNode(lock)
        if hasLetter {
            box(1.5, 0.025, 1.02, SCNVector3(-0.1, -0.3, 0.1), paper, parent: top, radius: 0.01)
            box(0.92, 0.03, 0.65, SCNVector3(0.25, -0.265, 0.2), paper, parent: top, radius: 0.01)
        }
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 2.25; camera.position = SCNVector3(3.6, 3.15, 7.0)
        camera.look(at: SCNVector3(0, 1.0, 0.25)); scene.rootNode.addChildNode(camera)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.color = Moonlight.light; ambient.light?.intensity = night ? 220 : 470; scene.rootNode.addChildNode(ambient)
        let light = SCNNode(); light.light = SCNLight(); light.light?.type = .omni
        light.light?.color = Moonlight.light; light.light?.intensity = night ? 430 : 1050
        light.position = SCNVector3(-3, 6, 5); scene.rootNode.addChildNode(light)
        return scene
    }
}
