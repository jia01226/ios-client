import Foundation


/// 只负责把服务端明确发出的 `split` 边界映射成本地消息。
///
/// 正文内容本身（标点、空行、长度）永远不参与切分判断；没有 `split` 就始终是一个气泡。
struct ChatReplyStreamAssembly: Sendable {
    let rootMessageID: String

    private(set) var localMessageIDs: [String]
    private(set) var currentMessageID: String
    private var startsNewMessageWithNextText = false

    init(rootMessageID: String) {
        self.rootMessageID = rootMessageID
        localMessageIDs = [rootMessageID]
        currentMessageID = rootMessageID
    }

    mutating func receiveSplit() {
        startsNewMessageWithNextText = true
    }

    /// 空的尾段不提前造气泡；真正收到下一段正文时才创建下一条本地消息。
    mutating func messageIDForIncomingText() -> (id: String, isNew: Bool) {
        guard startsNewMessageWithNextText else {
            return (currentMessageID, false)
        }
        startsNewMessageWithNextText = false
        let nextID = "\(rootMessageID)-part-\(localMessageIDs.count + 1)"
        localMessageIDs.append(nextID)
        currentMessageID = nextID
        return (nextID, true)
    }

    /// 新协议严格一一映射；老服务端或数量异常时只认仍受支持的“最后一条”旧字段，
    /// 随后的历史刷新会用 VPS 正式记录替换本地临时气泡，不在客户端猜剩余 id。
    func serverIDAssignments(
        assistantMessageIDs: [Int],
        legacyAssistantMessageID: Int?
    ) -> [(localMessageID: String, serverMessageID: Int)] {
        if assistantMessageIDs.count == localMessageIDs.count {
            return Array(zip(localMessageIDs, assistantMessageIDs)).map {
                (localMessageID: $0.0, serverMessageID: $0.1)
            }
        }
        guard let localMessageID = localMessageIDs.last,
              let serverMessageID = legacyAssistantMessageID else { return [] }
        return [(localMessageID: localMessageID, serverMessageID: serverMessageID)]
    }
}
