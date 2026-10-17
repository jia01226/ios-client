import CoreImage
import ReplayKit

/// 118：她点了「给看」、又亲手点了系统的开始直播，这个小模块才跑。
/// 每秒问一次服务器「现在要看吗」；被叫到就拍一张（缩到 640 宽的 JPEG）传上去，传完自己停。
/// 前 3 秒不拍（那会儿还是系统的倒计时 / 控制中心），最多跑 30 秒。内存上限 50MB，所以只留一个 CIContext、不攒帧。
final class SampleHandler: RPBroadcastSampleHandler {
    private let queue = DispatchQueue(label: "love.jiagude.ke.screen")
    private let context = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
    private var pass: KeScreenPass.Pass?
    private var timer: DispatchSourceTimer?
    private var startedAt = Date()
    private var wantID: Int?
    private var busy = false
    private var finished = false
    private var asking = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard let pass = KeScreenPass.load() else {
            stop("打开一下柯的 App 再试")
            return
        }
        queue.sync {
            self.pass = pass
            self.startedAt = Date()
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    override func broadcastFinished() {
        timer?.cancel()
        timer = nil
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        queue.sync {
            guard let id = wantID, !busy, !finished,
                  Date().timeIntervalSince(startedAt) >= 3,
                  let pixels = CMSampleBufferGetImageBuffer(sampleBuffer),
                  let jpeg = encode(pixels) else { return }
            busy = true
            upload(jpeg, id: id)
        }
    }

    // MARK: - 在 queue 上跑

    private func tick() {
        if finished { return }
        if Date().timeIntervalSince(startedAt) > 30 {
            stop("这次没看成，柯那边没在等")
            return
        }
        guard wantID == nil, !asking, let pass, let url = URL(string: pass.base + "/api/screen/beckon") else { return }
        asking = true
        URLSession.shared.dataTask(with: request(url, pass: pass)) { [weak self] data, _, _ in
            guard let self else { return }
            self.queue.async {
                self.asking = false
                guard let data,
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["take"] as? Bool == true,
                      let id = object["id"] as? Int else { return }
                self.wantID = id
            }
        }.resume()
    }

    private func encode(_ pixels: CVPixelBuffer) -> Data? {
        autoreleasepool {
            var image = CIImage(cvPixelBuffer: pixels)
            let width = image.extent.width
            if width > 640 {
                let scale = 640 / width
                image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
            guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            return context.jpegRepresentation(
                of: image, colorSpace: space,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.6]
            )
        }
    }

    private func upload(_ jpeg: Data, id: Int) {
        guard let pass, let url = URL(string: pass.base + "/api/screen/frame?id=\(id)") else { return }
        var req = request(url, pass: pass)
        req.httpMethod = "POST"
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        URLSession.shared.uploadTask(with: req, from: jpeg) { [weak self] _, response, _ in
            guard let self else { return }
            self.queue.async {
                let ok = (response as? HTTPURLResponse)?.statusCode == 200
                if ok {
                    self.stop("柯看过了")
                } else {
                    self.busy = false
                    self.wantID = nil
                }
            }
        }.resume()
    }

    private func request(_ url: URL, pass: KeScreenPass.Pass) -> URLRequest {
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("ke_home=\(pass.cookie)", forHTTPHeaderField: "Cookie")
        return req
    }

    private func stop(_ why: String) {
        finished = true
        timer?.cancel()
        timer = nil
        finishBroadcastWithError(NSError(domain: "love.jiagude.ke.screen", code: 0,
                                         userInfo: [NSLocalizedDescriptionKey: why]))
    }
}
