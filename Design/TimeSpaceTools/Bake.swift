import AppKit
import SceneKit
import Metal

@main struct Bake {
    static func main() throws {
        let device = MTLCreateSystemDefaultDevice()!
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
        let sky = SCNMaterial()
        sky.lightingModel = .constant
        sky.diffuse.contents = NSColor.white
        sky.shaderModifiers = [.fragment: TimeNebulaVolume.fragment]
        sky.setValue(Float(0), forKey: "u_travel")
        sky.setValue(Float(0), forKey: "u_motion")
        sky.setValue(Float(0.5), forKey: "u_aspect")
        plane.firstMaterial = sky
        let node = SCNNode(geometry: plane)
        node.position.z = -20
        scene.rootNode.addChildNode(node)
        renderer.scene = scene
        renderer.pointOfView = camera
        let size = CGSize(width: 768, height: 1536)
        let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .none)
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: 645, height: 1275, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        let target = device.makeTexture(descriptor: descriptor)!
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let queue = device.makeCommandQueue()!
        for mode in ["volume", "baked"] {
            if mode == "baked" {
                let cached = SCNMaterial()
                cached.lightingModel = .constant
                cached.diffuse.contents = image
                plane.firstMaterial = cached
                SCNTransaction.flush()
            }
            var milliseconds: [Double] = []
            for index in 0..<24 {
                let command = queue.makeCommandBuffer()!
                renderer.render(atTime: Double(index) / 60, viewport: CGRect(x: 0, y: 0, width: 645, height: 1275), commandBuffer: command, passDescriptor: pass)
                command.commit()
                command.waitUntilCompleted()
                if index > 3 { milliseconds.append((command.gpuEndTime - command.gpuStartTime) * 1000) }
            }
            milliseconds.sort()
            print("\(device.name) \(mode): median \(milliseconds[milliseconds.count / 2]) ms, max \(milliseconds.last!) ms")
        }
    }
}
