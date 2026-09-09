import XCTest
import SceneKit
import Metal
@testable import KeApp

final class TimeRenderingPerformanceTests: XCTestCase {
    @MainActor func testCachedNebulaReducesGPUFrameCost() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("Metal is unavailable")
        }
        let renderer = SCNRenderer(device: device, options: nil)
        let scene = SCNScene()
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera!.usesOrthographicProjection = true
        camera.camera!.orthographicScale = 2
        camera.camera!.wantsHDR = false
        camera.position.z = 25
        scene.rootNode.addChildNode(camera)
        let plane = SCNPlane(width: 2.1, height: 4.2)
        let node = SCNNode(geometry: plane)
        node.position.z = -20
        scene.rootNode.addChildNode(node)
        renderer.scene = scene
        renderer.pointOfView = camera
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: 645, height: 1275, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        var medians: [Double] = []
        for cached in [false, true] {
            let material = SCNMaterial()
            material.lightingModel = .constant
            if cached {
                material.diffuse.contents = try XCTUnwrap(UIImage(named: "time-nebula-baked"))
            } else {
                material.diffuse.contents = UIColor.white
                material.shaderModifiers = [.fragment: TimeNebulaVolume.fragment]
                material.setValue(Float(0), forKey: "u_travel")
                material.setValue(Float(0), forKey: "u_motion")
                material.setValue(Float(0.5), forKey: "u_aspect")
            }
            plane.firstMaterial = material
            SCNTransaction.flush()
            var durations: [Double] = []
            for index in 0..<12 {
                let command = try XCTUnwrap(queue.makeCommandBuffer())
                renderer.render(atTime: Double(index) / 60,
                    viewport: CGRect(x: 0, y: 0, width: 645, height: 1275),
                    commandBuffer: command, passDescriptor: pass)
                command.commit()
                command.waitUntilCompleted()
                XCTAssertNil(command.error)
                if index >= 4 { durations.append((command.gpuEndTime - command.gpuStartTime) * 1000) }
            }
            medians.append(durations.sorted()[durations.count / 2])
        }
        guard medians.allSatisfy({ $0 > 0 }) else { throw XCTSkip("GPU timestamps unavailable") }
        let result = "\(device.name): nebula GPU median \(medians[0]) ms -> \(medians[1]) ms; 645x1275 pixels"
        print(result)
        let attachment = XCTAttachment(string: result)
        attachment.name = "nebula-gpu-comparison"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertLessThan(medians[1], medians[0] * 0.5)
    }
}
