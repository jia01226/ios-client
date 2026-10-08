import SwiftUI
import WebKit

private enum DuelLoadState { case loading, ready, unavailable }

struct DuelView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    @State private var state = DuelLoadState.loading
    @State private var reloadID = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            DuelWebView(state: $state, reloadID: reloadID).ignoresSafeArea()
            if state != .ready {
                VStack(spacing: 22) {
                    Text("双弈").font(Moonlight.serif(42))
                    if state == .loading {
                        ProgressView("正在打开棋盘").tint(theme.pageAccent)
                    } else {
                        Text("棋盘暂时没接上。")
                            .font(Moonlight.serif(18)).accessibilityIdentifier("duel-unavailable")
                        Button("再试一次") { state = .loading; reloadID += 1 }
                            .font(Moonlight.serif(17)).frame(minWidth: 100, minHeight: 44)
                            .foregroundStyle(theme.pageAccent).accessibilityIdentifier("duel-retry")
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.pageBackground).foregroundStyle(theme.pageColor.textPrimary)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .light))
                    .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
            }.buttonStyle(.plain).foregroundStyle(theme.pageColor.textPrimary)
                .padding(.leading, 14).padding(.top, 8)
                .accessibilityLabel("关闭棋盘").accessibilityIdentifier("duel-close")
        }.buttonStyle(.plain)
    }
}

private struct DuelWebView: UIViewRepresentable {
    @Binding var state: DuelLoadState
    let reloadID: Int
    private var url: URL {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-test-companion") {
            return URL(string: "ke-duel-preview://room/unavailable")!
        }
        #endif
        return URL(string: "https://jiagude.love/duel/")!
    }
    func makeCoordinator() -> Coordinator { Coordinator(state: $state) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-test-companion") {
            configuration.setURLSchemeHandler(DuelUnavailableFixture(), forURLScheme: "ke-duel-preview")
        }
        #endif
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.scrollView.contentInsetAdjustmentBehavior = .never
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.state = $state
        guard context.coordinator.lastReload != reloadID else { return }
        context.coordinator.lastReload = reloadID
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            view.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) { view.load(request) }
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading(); view.navigationDelegate = nil
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var state: Binding<DuelLoadState>
        var lastReload: Int?
        init(state: Binding<DuelLoadState>) { self.state = state }
        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if response.isForMainFrame, let http = response.response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                state.wrappedValue = .unavailable; decisionHandler(.cancel)
            } else { decisionHandler(.allow) }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { state.wrappedValue = .ready }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { state.wrappedValue = .unavailable }
        private func failed(_ error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { state.wrappedValue = .unavailable }
        }
    }
}

#if DEBUG
/// Exercise the real WKWebView failure path; never substitute a fake successful chess screen.
private final class DuelUnavailableFixture: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        // WebKit strips HTTP status from custom-scheme responses. Use a genuine
        // navigation error here; HTTP status handling is exercised by real HTTPS.
        urlSchemeTask.didFailWithError(URLError(.cannotConnectToHost))
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
#endif
