import SwiftUI

/// 11-06 她要一扇「完全独立的聊天页」：跟长窗分开，不混在一起。
/// 这页钉死一扇窗（试穿窗 = 会话 13），记录、模型都是它自己的；关掉就回到原来那页，两边不互相顶。
struct KeTrialChatPage: View {
    let sessionID: Int
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var line: ChatLine = .test1
    @State private var quoteOpenRequest: QuoteOpenRequest?
    @State private var sendRequests: [ChatSendRequest] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            ChatView(
                line: .test1,
                selectedLine: $line,
                quoteOpenRequest: $quoteOpenRequest,
                sendRequests: $sendRequests,
                pinnedSession: sessionID
            )
            .environment(\.floatingDockInset, 0)

            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.down")
                    Text(title)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Ink.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(.ultraThinMaterial))
            }
            .padding(.leading, 14)
            .padding(.top, 10)
            .accessibilityLabel("收起这扇窗")
        }
    }
}
