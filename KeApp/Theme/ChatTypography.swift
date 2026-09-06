import SwiftUI

struct ChatTypography: Identifiable {
    let id: String
    let title: String
    let postScriptName: String
    static let all: [ChatTypography] = [
        .init(id: "regular", title: "苹方 · 常规", postScriptName: "PingFangSC-Regular"),
        .init(id: "light", title: "苹方 · 轻体", postScriptName: "PingFangSC-Light"),
        .init(id: "serif", title: "Noto 宋体", postScriptName: "NotoSerifSC-Regular"),
        .init(id: "wenkai", title: "霞鹜文楷", postScriptName: "LXGWWenKai-Regular")
    ]
    func font(size: Double) -> Font { .custom(postScriptName, size: size, relativeTo: .body) }
}

struct WaitingShimmer: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let progress = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2) / 2.2
            Text("正在输入中")
                .font(.caption2)
                .foregroundStyle(color.opacity(0.5))
                .fixedSize()
                .overlay {
                    if !reduceMotion {
                        GeometryReader { geometry in
                            LinearGradient(colors: [.clear, color.opacity(0.95), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: geometry.size.width * 0.7)
                                .offset(x: geometry.size.width * (progress * 2 - 0.7))
                        }
                        .mask(Text("正在输入中").font(.caption2))
                        .allowsHitTesting(false)
                    }
                }
        }
        .accessibilityLabel("正在输入中")
    }
}
