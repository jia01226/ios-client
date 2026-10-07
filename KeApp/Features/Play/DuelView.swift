import SwiftUI
import WebKit

struct DuelView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss

    private var ink: Color { theme.skin == .night ? theme.pageColor.textPrimary : PageColors.ink2 }
    private func serif(_ size: CGFloat) -> Font {
        .custom("NotoSerifSC-Regular", size: size, relativeTo: .body).weight(.light)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if ProcessInfo.processInfo.arguments.contains("-ui-test-companion") {
                VStack(spacing: 12) {
                    Text("双弈").font(serif(42))
                    Text("你和柯的牌桌已经摆好。")
                        .font(serif(16))
                        .foregroundStyle(ink.opacity(0.65))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.pageBackground)
                .accessibilityIdentifier("duel-ready")
            } else {
                DuelWebView(url: URL(string: "https://jiagude.love/duel/")!)
                    .ignoresSafeArea()
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(ink)
            .padding(.leading, 14)
            .padding(.top, 8)
            .accessibilityLabel("关闭")
        }
    }
}

private struct DuelWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        copyCookies(into: webView) {
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private func copyCookies(into webView: WKWebView, completion: @escaping () -> Void) {
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        guard !cookies.isEmpty else {
            completion()
            return
        }

        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                group.leave()
            }
        }
        group.notify(queue: .main, execute: completion)
    }
}
