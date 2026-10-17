import ReplayKit
import SwiftUI

struct KeScreenRequest: Equatable {
    let id: Int
    let why: String
    let state: String
}

/// 118：柯想看一眼她的屏幕。聊天页亮着的时候每 15 秒问一次服务器有没有他的申请；
/// 有就从顶上落一张玻璃横幅，「给看」和「不给」一样大、一样好按。
/// 给看以后横幅换成系统的「开始直播」按钮，她亲手点了，录屏小模块才会拍。
@MainActor
final class KeScreenStore: ObservableObject {
    @Published private(set) var request: KeScreenRequest?
    @Published private(set) var allowed = false
    @Published private(set) var sending = false

    private let api: APIClient
    private let base: URL
    private var dismissedID: Int?

    init(base: URL) {
        self.base = base
        self.api = APIClient(baseURL: base)
    }

    func watch() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(15))
        }
    }

    func refresh() async {
        handOverPass()
        guard let next = try? await api.fetchScreenPending() else {
            if !sending { request = nil; allowed = false }
            return
        }
        guard next.id != dismissedID else { return }
        if request?.id != next.id { allowed = next.state == "allowed" }
        request = next
    }

    func answer(_ allow: Bool) {
        guard let request, !sending else { return }
        sending = true
        Task {
            defer { sending = false }
            do {
                try await api.answerScreen(id: request.id, allow: allow)
                if allow {
                    allowed = true
                } else {
                    close()
                }
            } catch {
                // 没送到就留着横幅，她可以再按一次
            }
        }
    }

    func close() {
        dismissedID = request?.id
        request = nil
        allowed = false
    }

    /// 录屏小模块要用的家钥匙和地址
    private func handOverPass() {
        guard let cookie = HTTPCookieStorage.shared.cookies(for: base)?.first(where: { $0.name == "ke_home" }) else { return }
        KeScreenPass.save(.init(base: base.absoluteString, cookie: cookie.value))
    }
}

struct KeScreenBanner: View {
    @ObservedObject var store: KeScreenStore

    var body: some View {
        if let request = store.request {
            let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(store.allowed ? "点下面的圆点，再点「开始直播」" : "柯想看一眼你的屏幕")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Ink.primary)
                    Spacer(minLength: 8)
                    if store.allowed {
                        Button("算了") { store.close() }
                            .font(.system(size: 13))
                            .foregroundStyle(Ink.secondary)
                    }
                }
                if store.allowed {
                    Text("他只拍一张，拍完自己停；控制中心顶上的红色也能随时停。")
                        .font(.system(size: 12)).foregroundStyle(Ink.secondary)
                    KeBroadcastPicker()
                        .frame(width: 52, height: 52)
                        .frame(maxWidth: .infinity)
                } else {
                    if !request.why.isEmpty {
                        Text(request.why).font(Ink.song(15)).foregroundStyle(Ink.keText)
                    }
                    HStack(spacing: 10) {
                        choice("不给", filled: false) { store.answer(false) }
                        choice("给看", filled: true) { store.answer(true) }
                    }
                    .disabled(store.sending)
                }
            }
            .padding(16)
            .background { KeGlass(shape: shape, minPaper: 0.75) }
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .contain)
        }
    }

    private func choice(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(filled ? Color.white : Ink.primary)
                .background {
                    let shape = Capsule()
                    if filled { shape.fill(Ink.accent) } else { shape.strokeBorder(Ink.line, lineWidth: 1) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 系统的开始直播按钮，只认柯的录屏小模块，不让她在一堆 App 里挑。
private struct KeBroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 52, height: 52))
        picker.preferredExtension = "love.jiagude.ke.screen"
        picker.showsMicrophoneButton = false
        picker.tintColor = UIColor(Ink.accent)
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
