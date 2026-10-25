import SwiftUI

struct MemoryTabView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject private var garden: MemoryGardenStore
    let line: ChatLine
    var onOpenQuote: (AppQuote) -> Void
    var onClose: (() -> Void)?
    @State private var page = 0
    init(line: ChatLine, onOpenQuote: @escaping (AppQuote) -> Void, onClose: (() -> Void)? = nil) {
        self.line = line; self.onOpenQuote = onOpenQuote; self.onClose = onClose
        _garden = StateObject(wrappedValue: MemoryGardenStore(api: APIClient(baseURL: line.apiBaseURL)))
    }
    var body: some View { standardBody }
    private var standardBody: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if page == 0 { MemoryGardenView(store: garden, page: $page, onClose: onClose) }
                else {
                    MemoryPageHeader(page: $page)
                    AppQuotesView(line: line, onOpen: onOpenQuote)
                }
            }.background(theme.pageBackground).foregroundStyle(theme.pageColor.textPrimary)
                .toolbar(.hidden, for: .navigationBar)
        }.tint(theme.pageAccent)
    }
}

private struct MemoryPageHeader: View {
    @Binding var page: Int
    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Les souvenirs").font(.custom("Allura-Regular", size: 32, relativeTo: .title))
                Text("记忆").font(.custom("NotoSerifSC-ExtraLight", size: 13, relativeTo: .caption))
            }
            Picker("记忆", selection: $page) {
                Text("星河").tag(0)
                Text("语录").tag(1)
            }.pickerStyle(.segmented).accessibilityIdentifier("memory-pages")
        }.padding(.horizontal, 26).padding(.top, 6).padding(.bottom, 5)
    }
}

// 97：记忆页是「记忆星河」（MemoryGalaxyView，2D 自算投影，每颗都点得到）。喜欢、记错了、熄灭的星沿用花园的接口。
// 129：换成六团星云（MemoryNebulaView）。
struct MemoryGardenView: View {
    @ObservedObject var store: MemoryGardenStore
    @Binding var page: Int
    var onClose: (() -> Void)?
    var body: some View { MemoryNebulaView(store: store, page: $page, onClose: onClose) }
}
