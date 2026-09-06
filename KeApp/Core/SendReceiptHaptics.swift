import UIKit

struct SendReceiptFeedbackGate {
    private var acknowledged: Set<String> = []

    mutating func consume(clientID: String, serverID: Int?) -> Bool {
        guard let serverID, serverID > 0 else { return false }
        return acknowledged.insert(clientID).inserted
    }
}

@MainActor
final class SendReceiptHaptics {
    private var gate = SendReceiptFeedbackGate()
    private let generator = UIImpactFeedbackGenerator(style: .light)

    func prepare() { generator.prepare() }

    func acknowledge(clientID: String, serverID: Int?) {
        guard gate.consume(clientID: clientID, serverID: serverID),
              UIApplication.shared.applicationState == .active else { return }
        generator.impactOccurred(intensity: 0.6)
    }
}
