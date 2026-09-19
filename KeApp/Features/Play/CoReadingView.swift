import SwiftUI
import WebKit

struct WebReadingComment: Decodable, Sendable {
    let author: String
    let content: String
}

struct CoReadingPage: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var url: String
    var progress: Double
    var updatedAt: Date
}

struct CoReadingNote: Codable, Identifiable, Equatable {
    let id: UUID
    let pageID: UUID
    let author: String
    let content: String
    let excerpt: String
    let createdAt: Date
}

@MainActor
final class CoReadingStore: ObservableObject {
    @Published private(set) var pages: [CoReadingPage] = []
    @Published private(set) var notes: [CoReadingNote] = []

    private let pagesKey = "coreading.pages.v1"
    private let notesKey = "coreading.notes.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: pagesKey),
           let decoded = try? decoder.decode([CoReadingPage].self, from: data) {
            pages = decoded.sorted { $0.updatedAt > $1.updatedAt }
        }
        if let data = defaults.data(forKey: notesKey),
           let decoded = try? decoder.decode([CoReadingNote].self, from: data) {
            notes = decoded.sorted { $0.createdAt > $1.createdAt }
        }
    }

    @discardableResult
    func savePage(title: String, url: String, progress: Double) -> CoReadingPage {
        if let index = pages.firstIndex(where: { $0.url == url }) {
            pages[index].title = title
            pages[index].progress = progress
            pages[index].updatedAt = Date()
            persist()
            return pages[index]
        }
        let page = CoReadingPage(
            id: UUID(), title: title, url: url,
            progress: min(max(progress, 0), 1), updatedAt: Date()
        )
        pages.insert(page, at: 0)
        persist()
        return page
    }

    func update(_ id: UUID, title: String, url: String, progress: Double) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[index].title = title
        pages[index].url = url
        pages[index].progress = min(max(progress, 0), 1)
        pages[index].updatedAt = Date()
        pages.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    func remove(_ page: CoReadingPage) {
        pages.removeAll { $0.id == page.id }
        notes.removeAll { $0.pageID == page.id }
        persist()
    }

    func addNote(pageID: UUID, author: String, content: String, excerpt: String) {
        notes.insert(CoReadingNote(
            id: UUID(), pageID: pageID, author: author, content: content,
            excerpt: excerpt, createdAt: Date()
        ), at: 0)
        persist()
    }

    func notes(for pageID: UUID) -> [CoReadingNote] {
        notes.filter { $0.pageID == pageID }
    }

    private func persist() {
        if let data = try? encoder.encode(pages) { defaults.set(data, forKey: pagesKey) }
        if let data = try? encoder.encode(notes) { defaults.set(data, forKey: notesKey) }
    }
}

fileprivate struct ReadingContext {
    let title: String
    let url: String
    let excerpt: String
    let progress: Double
}

@MainActor
final class ReadingBrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var title = ""
    @Published var url = ""
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    let webView: WKWebView

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.isElementFullscreenEnabled = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .interactive
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
    }

    func loadPreviewForUITest() {
        webView.loadHTMLString("""
        <html><head><meta name='viewport' content='width=device-width'><title>共读试读页</title></head>
        <body style='font:20px -apple-system;padding:28px;line-height:1.8'>
        <h1>共读试读页</h1><p>风从窗边经过，她把书翻到下一页，等身边的人说一句话。</p>
        </body></html>
        """, baseURL: URL(string: "https://example.com/book"))
    }

    fileprivate func snapshot() async -> ReadingContext? {
        let script = """
        (() => {
          const selected = (window.getSelection && window.getSelection().toString() || '').trim();
          const center = document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2);
          const block = center && center.closest ? center.closest('p, article, section, main, div') : null;
          let visible = (block && block.innerText || '').trim();
          if (visible.length < 40) visible = (document.querySelector('article, main')?.innerText || document.body?.innerText || '').trim();
          const text = (selected || visible).replace(/\\s+/g, ' ').slice(0, 4000);
          const maxScroll = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
          return { title: document.title || '', url: location.href, excerpt: text, progress: Math.max(0, Math.min(1, window.scrollY / maxScroll)) };
        })()
        """
        guard let value = try? await webView.evaluateJavaScript(script),
              let object = value as? [String: Any],
              let url = object["url"] as? String,
              url.hasPrefix("http") else { return nil }
        return ReadingContext(
            title: (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            url: url,
            excerpt: (object["excerpt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            progress: (object["progress"] as? NSNumber)?.doubleValue ?? 0
        )
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        refreshState(webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        refreshState(webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        refreshState(webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        refreshState(webView)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let target = navigationAction.request.url { load(target) }
        return nil
    }

    private func refreshState(_ webView: WKWebView) {
        title = webView.title ?? ""
        url = webView.url?.absoluteString ?? ""
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}

private struct ReadingWebView: UIViewRepresentable {
    @ObservedObject var model: ReadingBrowserModel
    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct CoReadingView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let line: ChatLine

    @StateObject private var store = CoReadingStore()
    @StateObject private var browser = ReadingBrowserModel()
    @State private var query = ""
    @State private var browserOpen = false
    @State private var joinedPageID: UUID?
    @State private var bubble: WebReadingComment?
    @State private var commentLoading = false
    @State private var errorText: String?
    @State private var showingNotes = false
    @State private var spontaneousTask: Task<Void, Never>?
    @State private var lastSpontaneousAt: Date?

    private var api: APIClient { APIClient(baseURL: line.apiBaseURL) }
    private var ink: Color { theme.color.textPrimary }
    private var accent: Color { theme.color.accent }

    var body: some View {
        NavigationStack {
            Group {
                if browserOpen { browserPage } else { libraryPage }
            }
            .background(theme.effectiveBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(browserOpen ? "书架" : "关闭") {
                        if browserOpen { saveProgressAndCloseBrowser() } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(browserOpen ? (browser.title.isEmpty ? "共读" : browser.title) : "共读书房")
                        .font(.custom("NotoSerifSC-Regular", size: 17)).lineLimit(1)
                }
                if browserOpen {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("留言") { showingNotes = true }
                            .disabled(joinedPageID == nil)
                    }
                }
            }
        }
        .sheet(isPresented: $showingNotes) { notesSheet }
        .alert("这一页暂时读不到", isPresented: Binding(
            get: { errorText != nil }, set: { if !$0 { errorText = nil } }
        )) { Button("知道了", role: .cancel) {} } message: { Text(errorText ?? "") }
        .onDisappear { spontaneousTask?.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveProgress() }
        }
    }

    private var libraryPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("找一本想看的书")
                        .font(.custom("NotoSerifSC-Regular", size: 34))
                    Text("像浏览器一样找。打开正文后，再叫柯坐过来。")
                        .font(.custom("NotoSerifSC-Regular", size: 15))
                        .foregroundStyle(ink.opacity(0.62))
                }

                HStack(spacing: 10) {
                    TextField("书名、作者或直接粘贴网址", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit(search)
                        .padding(.horizontal, 16).frame(height: 50)
                        .background(theme.color.card, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("coreading-search-field")
                    Button(action: search) {
                        Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .medium))
                            .frame(width: 50, height: 50).background(accent, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.white)
                    }
                    .accessibilityIdentifier("coreading-search")
                }

                if store.pages.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "books.vertical").font(.system(size: 34, weight: .ultraLight))
                        Text("书架还是空的")
                        Text("搜到能看的正文后，点“开始共读”。")
                            .font(.footnote).foregroundStyle(ink.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 48)
                    .foregroundStyle(ink.opacity(0.68))
                } else {
                    Text("我们的书架").font(.custom("NotoSerifSC-Regular", size: 22))
                    ForEach(store.pages) { page in
                        Button { open(page) } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Text(page.title).font(.custom("NotoSerifSC-Regular", size: 18)).lineLimit(2)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption)
                                }
                                ProgressView(value: page.progress).tint(accent)
                                HStack {
                                    Text(URL(string: page.url)?.host ?? page.url).lineLimit(1)
                                    Spacer()
                                    Text("(Int(page.progress * 100))%")
                                }
                                .font(.caption).foregroundStyle(ink.opacity(0.5))
                            }
                            .padding(16).background(theme.color.card, in: RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("从书架移除", role: .destructive) { store.remove(page) } }
                    }
                }
            }
            .padding(24)
        }
        .foregroundStyle(ink)
    }

    private var browserPage: some View {
        ZStack(alignment: .bottom) {
            ReadingWebView(model: browser)
                .ignoresSafeArea(edges: .bottom)
            if browser.isLoading {
                ProgressView().padding(10).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 78)
            }
            if let bubble {
                keBubble(bubble)
                    .padding(.horizontal, 16).padding(.bottom, 82)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            browserToolbar
        }
        .onChange(of: browser.url) { _, _ in
            bubble = nil
            scheduleSpontaneousComment()
        }
    }

    private var browserToolbar: some View {
        HStack(spacing: 9) {
            Button { browser.webView.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!browser.canGoBack)
            Button { browser.webView.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!browser.canGoForward)
            Button { browser.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
            Spacer()
            if joinedPageID == nil {
                Button("开始共读") { joinCurrentPage() }
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityIdentifier("coreading-join")
            } else {
                Button(commentLoading ? "柯在看" : "问柯") { requestComment(spontaneous: false) }
                    .disabled(commentLoading)
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityIdentifier("coreading-ask-ke")
            }
        }
        .font(.system(size: 17, weight: .medium))
        .padding(.horizontal, 16).frame(height: 64)
        .background(.ultraThinMaterial)
    }

    private func keBubble(_ comment: WebReadingComment) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(comment.author).font(.caption.weight(.semibold)).foregroundStyle(accent)
                Text("在页边写了一句").font(.caption).foregroundStyle(ink.opacity(0.5))
                Spacer()
                Button { withAnimation { bubble = nil } } label: { Image(systemName: "xmark").font(.caption) }
            }
            Text(comment.content).font(.custom("NotoSerifSC-Regular", size: 16)).lineSpacing(4)
        }
        .padding(15).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .accessibilityIdentifier("coreading-ke-bubble")
    }

    private var notesSheet: some View {
        NavigationStack {
            List {
                if let id = joinedPageID {
                    ForEach(store.notes(for: id)) { note in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(note.author).font(.caption.weight(.semibold)).foregroundStyle(accent)
                            Text(note.content)
                            if !note.excerpt.isEmpty {
                                Text(note.excerpt).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }.padding(.vertical, 5)
                    }
                }
            }
            .navigationTitle("页边留言")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showingNotes = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func search() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let direct = URL(string: trimmed).flatMap { ["http", "https"].contains($0.scheme ?? "") ? $0 : nil }
        let target = direct ?? URL(string: "https://cn.bing.com/search?q=" +
            (trimmed + " 在线阅读").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        joinedPageID = nil
        browserOpen = true
        if ProcessInfo.processInfo.arguments.contains("-ui-test-coreading") {
            browser.loadPreviewForUITest()
        } else {
            browser.load(target)
        }
    }

    private func open(_ page: CoReadingPage) {
        guard let url = URL(string: page.url) else { return }
        joinedPageID = page.id
        browserOpen = true
        browser.load(url)
    }

    private func joinCurrentPage() {
        Task {
            guard let context = await browser.snapshot(), !isSearchPage(context.url) else {
                errorText = "先从搜索结果打开书的正文，再点开始共读。"
                return
            }
            let page = store.savePage(
                title: context.title.isEmpty ? "没有标题的这一页" : context.title,
                url: context.url, progress: context.progress
            )
            joinedPageID = page.id
            scheduleSpontaneousComment()
        }
    }

    private func requestComment(spontaneous: Bool) {
        guard !commentLoading, let pageID = joinedPageID else { return }
        commentLoading = true
        Task {
            defer { commentLoading = false }
            guard let context = await browser.snapshot(), context.excerpt.count >= 12 else {
                if !spontaneous { errorText = "这一页暂时抓不到正文。可以选中一段文字后再问柯。" }
                return
            }
            store.update(pageID, title: context.title, url: context.url, progress: context.progress)
            do {
                let comment = try await api.annotateWebReading(
                    title: context.title, url: context.url, excerpt: context.excerpt
                )
                store.addNote(pageID: pageID, author: comment.author, content: comment.content, excerpt: String(context.excerpt.prefix(180)))
                withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) { bubble = comment }
            } catch {
                if !spontaneous { errorText = "柯刚才没接上这一页，再点一次就好。" }
            }
        }
    }

    private func scheduleSpontaneousComment() {
        spontaneousTask?.cancel()
        guard joinedPageID != nil, !isSearchPage(browser.url) else { return }
        if let lastSpontaneousAt, Date().timeIntervalSince(lastSpontaneousAt) < 180 { return }
        spontaneousTask = Task {
            try? await Task.sleep(for: .seconds(22))
            guard !Task.isCancelled, joinedPageID != nil else { return }
            lastSpontaneousAt = Date()
            requestComment(spontaneous: true)
        }
    }

    private func saveProgress() {
        guard let id = joinedPageID else { return }
        Task {
            if let context = await browser.snapshot() {
                store.update(id, title: context.title, url: context.url, progress: context.progress)
            }
        }
    }

    private func saveProgressAndCloseBrowser() {
        spontaneousTask?.cancel()
        Task {
            if let id = joinedPageID, let context = await browser.snapshot() {
                store.update(id, title: context.title, url: context.url, progress: context.progress)
            }
            browserOpen = false
            joinedPageID = nil
            bubble = nil
        }
    }

    private func isSearchPage(_ raw: String) -> Bool {
        guard let host = URL(string: raw)?.host?.lowercased() else { return true }
        return host.contains("bing.com") || host.contains("baidu.com") || host.contains("google.")
    }
}
