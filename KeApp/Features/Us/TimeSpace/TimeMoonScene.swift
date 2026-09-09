import SwiftUI
import SceneKit

enum TimeMoonFraming {
    static func layerTravel(progress: CGFloat, depth: CGFloat, reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 0 : min(1, max(0, progress)) * depth
    }
    static func frame(size: CGSize, bottomInset: CGFloat, progress: CGFloat) -> (center: CGPoint, diameter: CGFloat) {
        let p = min(1, max(0, progress))
        let travel = p * p * (3 - 2 * p)
        let initialDiameter = size.width * 1.65
        let diameter = initialDiameter + (size.height * 1.6 - initialDiameter) * p * p
        let initialY = size.height - bottomInset + initialDiameter * 0.30
        return (CGPoint(x: size.width / 2, y: initialY + (size.height / 2 - initialY) * travel), diameter)
    }
}

/// 月球保留实时几何；星云使用同一着色器预渲染的纹理。
struct TimeMoonScene: UIViewRepresentable {
    var progress: CGFloat
    var reduceMotion: Bool
    var active = true
    var showSatellite = true
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> TimeSceneView {
        let view = TimeSceneView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false
        view.isPlaying = false
        view.contentScaleFactor = 1.5
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        return view
    }

    static func dismantleUIView(_ view: TimeSceneView, coordinator: Coordinator) {
        view.isPlaying = false
        view.onLayout = nil
        view.scene = nil
    }

    func updateUIView(_ view: TimeSceneView, context: Context) {
        let coordinator = context.coordinator
        view.onLayout = { view in updateScene(view, coordinator: coordinator) }
        updateScene(view, coordinator: coordinator)
    }

    private func updateScene(_ view: TimeSceneView, coordinator: Coordinator) {
        let size = view.bounds.size
        guard size.width > 0, size.height > 0, active else { return }
        let p = min(1, max(0, progress))
        let input = FrameInput(size: size, progress: p, reduceMotion: reduceMotion,
                               showSatellite: showSatellite, topInset: topInset, bottomInset: bottomInset)
        guard input != coordinator.lastFrame else { return }
        coordinator.lastFrame = input
        let framing = TimeMoonFraming.frame(size: size, bottomInset: bottomInset, progress: p)
        let diameter = framing.diameter
        let centerY = framing.center.y
        let scale = Float(diameter / size.height * 2)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        coordinator.moon.scale = SCNVector3(scale, scale, scale)
        coordinator.moon.position = SCNVector3(0, Float((size.height / 2 - centerY) / size.height * 4), 0)
        coordinator.moon.eulerAngles = SCNVector3Zero
        // Orthographic projection keeps the circular body stable while framing changes.
        coordinator.camera.position.z = Float(20 + diameter / size.height * 4)
        let scene = coordinator
        (scene.starBackground.geometry as? SCNPlane)?.width = 4.2 * size.width / size.height
        scene.starBackground.position.y = Float(reduceMotion ? 0 : p * 0.28)
        scene.starBackground.scale = SCNVector3(1, 1.16, 1)
        scene.satellite.position = SCNVector3(Float((size.width / 2 - 82) / size.height * 4),
            Float(2 - (topInset + 86) / size.height * 4 + (reduceMotion ? 0 : p * 0.25)), 3)
        scene.satellite.opacity = showSatellite ? max(0, 1 - p * 3) : 0
        let fade = Float(max(0, 1 - p * 1.15))
        scene.farStars.position.y = Float(TimeMoonFraming.layerTravel(progress: p, depth: 0.10, reduceMotion: reduceMotion))
        scene.nearStars.position.y = Float(TimeMoonFraming.layerTravel(progress: p, depth: 0.85, reduceMotion: reduceMotion))
        let nearScale = Float(1 + TimeMoonFraming.layerTravel(progress: p, depth: 0.22, reduceMotion: reduceMotion))
        scene.nearStars.scale = SCNVector3(nearScale, nearScale, 1)
        scene.nearStars.opacity = CGFloat(fade)
        scene.farStars.opacity = CGFloat(fade)
        SCNTransaction.commit()
        view.setNeedsDisplay()
    }

    struct FrameInput: Equatable {
        let size: CGSize
        let progress: CGFloat
        let reduceMotion: Bool
        let showSatellite: Bool
        let topInset: CGFloat
        let bottomInset: CGFloat
    }

    final class TimeSceneView: SCNView {
        var onLayout: ((TimeSceneView) -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?(self)
        }
    }

    final class Coordinator {
        let scene = SCNScene()
        let camera = SCNNode()
        let moon = SCNNode(geometry: SCNSphere(radius: 1))
        let farStars = SCNNode()
        let nearStars = SCNNode()
        let satellite = SCNNode(geometry: SCNSphere(radius: 0.065))
        let starBackground = SCNNode(geometry: SCNPlane(width: 2, height: 4.2))
        var lastFrame: FrameInput?

        init() {
            scene.background.contents = UIColor(red: 0.94, green: 0.92, blue: 0.89, alpha: 1)
            let sky = SCNMaterial()
            sky.lightingModel = .constant
            sky.diffuse.contents = UIImage(named: "time-nebula-baked") ?? UIImage()
            sky.diffuse.mipFilter = .linear
            sky.isDoubleSided = true
            starBackground.geometry?.firstMaterial = sky
            starBackground.position.z = -20
            scene.rootNode.addChildNode(starBackground)
            camera.camera = SCNCamera()
            camera.camera?.usesOrthographicProjection = true
            camera.camera?.orthographicScale = 2
            camera.camera?.zFar = 100
            camera.camera?.wantsHDR = false
            camera.position = SCNVector3(0, 0, 25)
            scene.rootNode.addChildNode(camera)
            (moon.geometry as? SCNSphere)?.segmentCount = 96
            let material = SCNMaterial()
            material.diffuse.contents = UIImage(named: "time-moon-albedo")
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
            material.diffuse.contentsTransform = SCNMatrix4MakeScale(4, 4, 1)
            material.diffuse.magnificationFilter = .linear
            material.diffuse.mipFilter = .linear
            material.shaderModifiers = [.surface: "_surface.diffuse.rgb = mix(_surface.diffuse.rgb, float3(1.0, 0.985, 0.96), 0.25);"]
            material.lightingModel = .blinn
            material.specular.contents = UIColor(white: 0.35, alpha: 1)
            material.shininess = 0.28
            material.emission.contents = UIColor(white: 0.025, alpha: 1)
            moon.geometry?.firstMaterial = material
            scene.rootNode.addChildNode(moon)
            let atmosphere = SCNNode(geometry: SCNSphere(radius: 1.012))
            (atmosphere.geometry as? SCNSphere)?.segmentCount = 64
            let air = SCNMaterial()
            air.lightingModel = .constant
            air.diffuse.contents = UIColor.white
            air.writesToDepthBuffer = false
            air.shaderModifiers = [.fragment: TimeNebulaVolume.atmosphere]
            atmosphere.geometry?.firstMaterial = air
            moon.addChildNode(atmosphere)
            let silver = SCNMaterial()
            silver.lightingModel = .constant
            silver.diffuse.contents = UIImage(named: "time-silver-reference")
            silver.specular.contents = UIColor(white: 0.18, alpha: 1)
            silver.shininess = 0.2
            silver.shaderModifiers = [.geometry: """
            #pragma body
            _geometry.texcoords[0] = float2(0.491 + _geometry.position.x / 0.13 * 0.785,
                                           0.492 - _geometry.position.y / 0.13 * 0.785);
            """]
            (satellite.geometry as? SCNSphere)?.segmentCount = 32
            satellite.geometry?.firstMaterial = silver
            satellite.categoryBitMask = 2
            scene.rootNode.addChildNode(satellite)
            let silverFill = SCNNode()
            silverFill.light = SCNLight()
            silverFill.light?.type = .ambient
            silverFill.light?.intensity = 45
            silverFill.light?.categoryBitMask = 2
            scene.rootNode.addChildNode(silverFill)
            let silverKey = SCNNode()
            silverKey.light = SCNLight()
            silverKey.light?.type = .omni
            silverKey.light?.intensity = 650
            silverKey.light?.categoryBitMask = 2
            silverKey.position = SCNVector3(-5, 4, 4)
            scene.rootNode.addChildNode(silverKey)
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 680
            ambient.light?.categoryBitMask = 1
            ambient.light?.color = UIColor.white
            scene.rootNode.addChildNode(ambient)
            let light = SCNNode()
            light.light = SCNLight()
            light.light?.type = .omni
            light.light?.intensity = 370
            light.light?.categoryBitMask = 1
            light.position = SCNVector3(-8, 6, 8)
            scene.rootNode.addChildNode(light)
            configureSpaceLayers()
        }

        private func configureSpaceLayers() {
            // Background stars sit behind the lunar body; a few soft points sit nearer the camera.
            farStars.position.z = -14
            nearStars.position.z = 10
            scene.rootNode.addChildNode(farStars)
            scene.rootNode.addChildNode(nearStars)
            for index in 0..<65 {
                let node = SCNNode(geometry: SCNSphere(radius: index.isMultiple(of: 17) ? 0.0025 : 0.0012))
                (node.geometry as? SCNSphere)?.segmentCount = 6
                let material = SCNMaterial()
                material.lightingModel = .constant
                material.diffuse.contents = UIColor(white: 1, alpha: 0.65)
                node.geometry?.firstMaterial = material
                let x = Float((index * 97 + 17) % 251) / 250 * 2 - 1
                let y = Float((index * 151 + 13) % 257) / 256 * 4.8 - 2.4
                node.position = SCNVector3(x, y, Float(index % 11) * 0.7)
                farStars.addChildNode(node)
            }
            for (x, y, radius) in [(-0.82, 0.82, 0.004), (0.73, 1.15, 0.0055), (0.84, -0.30, 0.007), (-0.70, -1.35, 0.0045)] {
                let node = SCNNode(geometry: SCNSphere(radius: radius))
                (node.geometry as? SCNSphere)?.segmentCount = 8
                let material = SCNMaterial()
                material.lightingModel = .constant
                material.diffuse.contents = UIColor(red: 1, green: 0.98, blue: 0.92, alpha: 0.65)
                node.geometry?.firstMaterial = material
                node.position = SCNVector3(x, y, -radius * 180)
                nearStars.addChildNode(node)
            }
        }
    }
}
