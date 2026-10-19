import Foundation
import EventSource

/// 125 修：只有注释行（`: keepalive`）的那一块。EventSource 自带的解析器把这种块整个丢掉，
/// App 就分不出「流健康、只是没话」和「连接已经悄悄断了」；这里留下一个空事件报「还连着」。
struct ChatSSEKeepAlive: EVEvent {
    var id: String? { nil }
    var event: String? { nil }
    var data: String? { nil }
    var other: [String: String]? { nil }
    var time: String? { nil }
}

/// 125 修：和 EventSource 自带的一样按空行切块、每块交给 ServerEvent.parse；
/// 多出来的只有一条：解析不出东西、但不是空的那块（注释行）报一个 ChatSSEKeepAlive。
/// 换行只认 LF 和 CRLF（和自带的一样）；CR 一律去掉——JSON 里的回车都是转义过的，不会是裸的 CR。
struct ChatSSEParser: EventParser {
    private var buffer = Data()
    private static let separator = Data([0x0A, 0x0A])

    mutating func parse(_ data: Data) -> [EVEvent] {
        buffer.append(contentsOf: data.lazy.filter { $0 != 0x0D })
        var events: [EVEvent] = []
        var start = buffer.startIndex
        while let range = buffer.range(of: Self.separator, in: start..<buffer.endIndex) {
            let block = Data(buffer[start..<range.lowerBound])
            start = range.upperBound
            if let event = ServerEvent.parse(from: block) {
                events.append(event)
            } else if !block.allSatisfy({ $0 == 0x0A }) {
                events.append(ChatSSEKeepAlive())
            }
        }
        if start != buffer.startIndex { buffer = Data(buffer[start..<buffer.endIndex]) }
        return events
    }
}
