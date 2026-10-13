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
                Text("花园").tag(0)
                Text("语录").tag(1)
            }.pickerStyle(.segmented).accessibilityIdentifier("memory-pages")
        }.padding(.horizontal, 26).padding(.top, 6).padding(.bottom, 5)
    }
}

struct MemoryGardenView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: MemoryGardenStore
    @Binding var page: Int
    @State private var includeOthers = false
    @State private var category = "约定"
    @State private var selected: MemoryFlower?
    @State private var listOpen = false
    @State private var witheredOpen = false
    private var flowers: [MemoryFlower] { store.visible(includeOthers: includeOthers, category: category) }
    private var scene: MemoryScene { .forCategory(category) }
    private var darkScene: Bool { theme.skin == .night || scene == .moon }

    // 92：正式花园换成 90 版的山茶探索（MemoryGardenExperience），接上真实记忆。
    // 旧的 MemoryGardenCanvas 不再出现在正式页面。
    @State private var correctingID: String?
    @State private var correctionNote = ""
    var body: some View {
        VStack(spacing: 0) {
            MemoryPageHeader(page: $page)
                .environment(\.colorScheme, .dark)
            HStack(spacing: 14) {
                Toggle("也看以前整理的", isOn: $includeOthers)
                    .toggleStyle(.switch).fixedSize()
                    .accessibilityIdentifier("memory-include-others")
                Spacer()
                Button("枯掉的花") { witheredOpen = true }.accessibilityIdentifier("memory-withered")
                Button { Task { await store.load() } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 36, height: 36)
                }.accessibilityLabel("刷新花园").disabled(store.loading || store.busy)
            }.font(.caption).padding(.horizontal, 22).padding(.bottom, 4)
            ZStack {
                MemoryGardenExperience(
                    flowers: store.visible(includeOthers: includeOthers),
                    categories: store.categories,
                    initialCategory: "约定",
                    night: theme.skin == .night,
                    isBusy: store.busy,
                    interactionError: store.error,
                    onLoveMemory: { id, _ in
                        guard let flower = store.flowers.first(where: { $0.id == id }) else { return }
                        Task { await store.change(flower, action: "love") }
                    },
                    onRequestCorrection: { id in correctionNote = ""; correctingID = id }
                )
                .id(includeOthers)
                if store.loading && !store.loaded {
                    ProgressView("正在走进花园").padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                } else if store.loaded && store.visible(includeOthers: includeOthers).isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "leaf").font(.title3).accessibilityHidden(true)
                        Text(emptyMessage).font(.subheadline).multilineTextAlignment(.center).lineSpacing(6)
                    }.padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(30).accessibilityIdentifier("memory-empty")
                } else if let error = store.error, !store.loaded {
                    VStack(spacing: 10) {
                        Text(error).font(.subheadline).multilineTextAlignment(.center)
                        Button("重试") { Task { await store.load() } }.disabled(store.loading || store.busy)
                    }.padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(30)
                }
            }
            .environment(\.colorScheme, .dark)
        }
        .background(Color(red: 0.06, green: 0.08, blue: 0.14).ignoresSafeArea())
        .foregroundStyle(Color.white.opacity(0.94))
        .task { await store.load() }
        .alert("这件事记错了吗？", isPresented: Binding(get: { correctingID != nil }, set: { if !$0 { correctingID = nil } })) {
            TextField("哪里错了，可以留空", text: $correctionNote)
            Button("取消", role: .cancel) { correctingID = nil }
            Button("确认记错了", role: .destructive) {
                guard let id = correctingID, let flower = store.flowers.first(where: { $0.id == id }) else { return }
                correctingID = nil
                Task { await store.change(flower, action: "wither", note: correctionNote) }
            }
        } message: { Text("会告诉柯不再记起这件事。点错了，可以从「枯掉的花」找回来。") }
        .sheet(isPresented: $witheredOpen) {
            NavigationStack {
                List {
                    if let error = store.error { Text(error).foregroundStyle(.secondary) }
                    let withered = store.flowers.filter { $0.state == "withered" && (includeOthers || $0.author == "ke") }
                    if withered.isEmpty { Text("这里还没有枯掉的花。") }
                    ForEach(withered) { flower in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(flower.title)
                            Text(flower.body).font(.subheadline).foregroundStyle(.secondary)
                            Button("找回来") { Task { await store.change(flower, action: "revive") } }
                                .disabled(store.busy || store.loading)
                                .accessibilityIdentifier("memory-revive-\(flower.id)")
                        }.padding(.vertical, 8)
                    }
                }.navigationTitle("枯掉的花").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { witheredOpen = false } } }
            }
        }
    }
    @State private var pendingFlower: MemoryFlower?
    private var emptyMessage: String {
        if !includeOthers && !store.flowers.contains(where: { $0.author == "ke" && $0.isDrawable }) {
            return "柯还没开始种花，他每天会自己记下你们的事"
        }
        return "这片花圃还没有记忆，先让月光落在这里。"
    }
}

private struct MemoryFlowerDetail: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: Theme
    @ObservedObject var store: MemoryGardenStore
    let flowerID: String
    @State private var correcting = false
    @State private var note = ""
    private var flower: MemoryFlower? { store.flowers.first { $0.id == flowerID } }
    var body: some View {
        NavigationStack {
            ScrollView {
                if let flower {
                    VStack(alignment: .leading, spacing: 18) {
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
                            Button(flower.loved ? "取消喜欢" : "这朵我很喜欢") {
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
            .alert("这件事记错了吗？", isPresented: $correcting) {
                TextField("哪里错了，可以留空", text: $note)
                Button("取消", role: .cancel) {}
                Button("确认记错了", role: .destructive) {
                    guard let flower else { return }
                    Task { if await store.change(flower, action: "wither", note: note) { dismiss() } }
                }
            } message: { Text("会告诉柯不再记起这件事。点错了，可以从「枯掉的花」找回来。") }
    }
}
