import SceneKit
import SwiftUI
import UIKit

/// 把横向月面纹理包在真正的球体上。`yaw` 不设边界，因此可以连续旋转 360°。
struct MoonSceneView: UIViewRepresentable, Animatable {
    var yaw: Double
    var pitch: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(yaw, pitch) }
        set {
            yaw = newValue.first
            pitch = newValue.second
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView(frame: .zero)
        let scene = SCNScene()

        sceneView.scene = scene
        sceneView.backgroundColor = .clear
        sceneView.isOpaque = false
        sceneView.isUserInteractionEnabled = false
        sceneView.allowsCameraControl = false
        sceneView.autoenablesDefaultLighting = false
        sceneView.antialiasingMode = .multisampling4X
        sceneView.preferredFramesPerSecond = 60
        sceneView.rendersContinuously = false

        let sphere = SCNSphere(radius: 1.02)
        sphere.segmentCount = 144

        let texture = UIImage(named: "MoonSurface")
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = texture
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .clamp
        material.diffuse.minificationFilter = .linear
        material.diffuse.magnificationFilter = .linear
        material.diffuse.mipFilter = .linear
        material.roughness.contents = 0.88
        material.metalness.contents = 0.02
        material.emission.contents = texture
        material.emission.intensity = 0.13
        sphere.firstMaterial = material

        let moonNode = SCNNode(geometry: sphere)
        context.coordinator.moonNode = moonNode
        scene.rootNode.addChildNode(moonNode)

        let camera = SCNCamera()
        camera.fieldOfView = 31
        camera.zNear = 0.1
        camera.zFar = 100
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 4.25)
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(white: 0.52, alpha: 1)
        ambient.intensity = 720
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let key = SCNLight()
        key.type = .directional
        key.color = UIColor(red: 1.0, green: 0.91, blue: 0.74, alpha: 1)
        key.intensity = 980
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.42, -0.72, 0)
        scene.rootNode.addChildNode(keyNode)

        applyRotation(to: moonNode)
        return sceneView
    }

    func updateUIView(_ sceneView: SCNView, context: Context) {
        guard let moonNode = context.coordinator.moonNode else { return }
        applyRotation(to: moonNode)
        sceneView.setNeedsDisplay()
    }

    private func applyRotation(to node: SCNNode) {
        let yawRotation = simd_quatf(
            angle: Float(yaw),
            axis: SIMD3<Float>(0, 1, 0)
        )
        let pitchRotation = simd_quatf(
            angle: Float(pitch),
            axis: SIMD3<Float>(1, 0, 0)
        )
        node.simdOrientation = yawRotation * pitchRotation
    }

    final class Coordinator {
        var moonNode: SCNNode?
    }
}
