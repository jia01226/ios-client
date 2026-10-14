import SwiftUI

struct MemoryTabView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject private var garden: MemoryGardenStore
    let line: ChatLine
    var onOpenQuote: (AppQuote) -> Void
    @State private var page = 0
    init(line: ChatLine, onOpenQuote: @escaping (AppQuote) -> Void) {
        self.line = line; self.onOpenQuote = onOpenQuote
        _garden = StateObject(wrappedValue: MemoryGardenStore(api: APIClient(baseURL: line.apiBaseURL)))
    }
    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-preview-flower-study") {
            ExpeditionMaterialStudy()
        } else if ProcessInfo.processInfo.arguments.contains("-preview-expedition") {
            MemoryExpeditionPreview()
        } else { standardBody }
        #else
        standardBody
        #endif
    }
    private var standardBody: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if page == 0 { MemoryGardenView(store: garden, page: $page) }
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
                Text("星图").tag(0)
                Text("语录").tag(1)
            }.pickerStyle(.segmented).accessibilityIdentifier("memory-pages")
        }.padding(.horizontal, 26).padding(.top, 6).padding(.bottom, 5)
    }
}

struct MemoryGardenView: View {
    @ObservedObject var store: MemoryGardenStore
    @Binding var page: Int
    @State private var includeOthers = false
    @State private var openID: String?
    @State private var dimmedOpen = false

    // 94：记忆页换成宇宙星图（MemoryStarMapView），喜欢、记错了、熄灭的星沿用花园的接口。
    // 96：版式换成 GPT 星河那套（记忆 + 15 号花体 + 小字），标题浮在星空上，不再垫色块；开关收进「⋯」。
    var body: some View {
        ZStack {
            MemoryStarMapView(store: store, includeOthers: $includeOthers,
                              onOpen: { openID = $0.id },
                              onLove: { flower in Task { await store.change(flower, action: "love") } }) { header }
            if store.loading && !store.loaded {
                ProgressView("正在点亮星星").padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else if store.loaded && store.visible(includeOthers: includeOthers).isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.title3).accessibilityHidden(true)
                    Text(emptyMessage).font(.subheadline).multilineTextAlignment(.center).lineSpacing(6)
                }.padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(30).accessibilityIdentifier("memory-empty")
            } else if let error = store.error, !store.loaded {
                VStack(spacing: 10) {
                    Text(error).font(.subheadline).multilineTextAlignment(.center)
                    Button("重试") { Task { await store.load() } }.disabled(store.loading || store.busy)
                }.padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(30)
            }
        }
        .environment(\.colorScheme, .dark)
        .background(Color(red: 0.02, green: 0.027, blue: 0.05).ignoresSafeArea())
        .foregroundStyle(Color.white.opacity(0.94))
        .task { await store.load() }
        .sheet(isPresented: Binding(get: { openID != nil }, set: { if !$0 { openID = nil } })) {
            if let openID { MemoryStarDetail(store: store, starID: openID) }
        }
        .sheet(isPresented: $dimmedOpen) {
            NavigationStack {
                List {
                    if let error = store.error { Text(error).foregroundStyle(.secondary) }
                    let dimmed = store.flowers.filter { $0.state == "withered" && (includeOthers || $0.author == "ke") }
                    if dimmed.isEmpty { Text("还没有熄灭的星。") }
                    ForEach(dimmed) { flower in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(flower.title)
                            Text(flower.body).font(.subheadline).foregroundStyle(.secondary)
                            Button("重新点亮") { Task { await store.change(flower, action: "revive") } }
                                .disabled(store.busy || store.loading)
                                .accessibilityIdentifier("memory-revive-\(flower.id)")
                        }.padding(.vertical, 8)
                    }
                }.navigationTitle("熄灭的星").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dimmedOpen = false } } }
            }
        }
    }
    private static let muted = Color(red: 0.72, green: 0.74, blue: 0.81)
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("记忆").font(.custom("NotoSerifSC-Regular", size: 28, relativeTo: .title)).tracking(3.4)
                Spacer()
                Button("语录") { page = 1 }
                    .font(.system(size: 13)).foregroundStyle(Self.muted)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("memory-quotes")
                Menu {
                    Toggle("以前整理的", isOn: $includeOthers)
                    Button("熄灭的星") { dimmedOpen = true }
                    Button("刷新") { Task { await store.load() } }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("星图设置")
                .accessibilityIdentifier("memory-menu")
                .padding(.trailing, -10)
            }
            Text("A small universe of us")
                .font(.custom("PinyonScript-Regular", size: 36, relativeTo: .largeTitle))
                .foregroundStyle(Color(red: 0.93, green: 0.93, blue: 0.95))
                .lineLimit(1).fixedSize()
                .transformEffect(CGAffineTransform(a: 0.9, b: 0, c: -0.287, d: 1, tx: 14, ty: 0))
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text("\(Self.monthName())的星河 · \(store.visible(includeOthers: includeOthers).count) 颗记忆")
                .font(.system(size: 12)).tracking(1.3).foregroundStyle(Self.muted)
                .shadow(color: .black.opacity(0.6), radius: 4)
        }
        .padding(.horizontal, 26).padding(.top, 6)
    }
    private static func monthName(_ date: Date = Date()) -> String {
        let m = Calendar.current.component(.month, from: date)
        return ["一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月"][max(0, min(11, m - 1))]
    }
    private var emptyMessage: String {
        if !includeOthers && !store.flowers.contains(where: { $0.author == "ke" && $0.isDrawable }) {
            return "柯还没开始点星星，他每天会自己记下你们的事"
        }
        return "这片天空还没有星星。"
    }
}

private struct MemoryStarDetail: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: Theme
    @ObservedObject var store: MemoryGardenStore
    let starID: String
    @State private var correcting = false
    @State private var note = ""
    private var flower: MemoryFlower? { store.flowers.first { $0.id == starID } }
    var body: some View {
        NavigationStack {
            ScrollView {
                if let flower {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(flower.author == "ke" ? "柯亲手记下 · \(flower.category)" : "以前整理的 · \(flower.category)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(flower.title).font(.custom("NotoSerifSC-ExtraLight", size: 23, relativeTo: .title2))
                        Text(flower.body).font(.body).lineSpacing(7).textSelection(.enabled)
                        ForEach(Array(flower.quotes.prefix(3).enumerated()), id: \.offset) { _, quote in
                            Text(quote).font(.body).lineSpacing(5).textSelection(.enabled)
                                .padding(.leading, 14)
                                .overlay(alignment: .leading) { Rectangle().fill(theme.pageAccent.opacity(0.4)).frame(width: 2) }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("发生于 \(flower.occurred_at ?? "日期未记录")")
                            Text("写下于 \(flower.written_at ?? "日期未记录")")
                        }.font(.caption).foregroundStyle(.secondary)
                        if let error = store.error { Text(error).font(.subheadline).foregroundStyle(.secondary) }
                        HStack {
                            Button("记错了") { correcting = true }.frame(minHeight: 44).accessibilityIdentifier("memory-correct")
                            Spacer()
                            Button(flower.loved ? "♥ 喜欢着" : "♡ 这颗我很喜欢") {
                                Task { await store.change(flower, action: "love") }
                            }.frame(minHeight: 44).accessibilityIdentifier("memory-love")
                        }.frame(minHeight: 44).disabled(store.busy || store.loading)
                    }.padding(24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("收好") { dismiss() } }
            }
        }.tint(theme.pageAccent)
            .presentationDetents([.medium, .large])
            .alert("这件事记错了吗？", isPresented: $correcting) {
                TextField("哪里错了，可以留空", text: $note)
                Button("取消", role: .cancel) {}
                Button("确认记错了", role: .destructive) {
                    guard let flower else { return }
                    Task { if await store.change(flower, action: "wither", note: note) { dismiss() } }
                }
            } message: { Text("会告诉柯不再记起这件事。这颗星会熄灭，点错了可以从「熄灭的星」重新点亮。") }
    }
}
