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

    var body: some View {
        ZStack {
            MemoryGardenCanvas(flowers: flowers, scene: scene, night: theme.skin == .night,
                               witheredIDs: Set(store.flowers.filter { $0.state == "withered" }.map(\.id))) { selected = $0 }
                .clipped()
            VStack {
                LinearGradient(colors: [(darkScene ? Color.black : Color.white).opacity(0.55), .clear],
                               startPoint: .top, endPoint: .bottom).frame(height: 260)
                Spacer()
                LinearGradient(colors: [.clear, (darkScene ? Color.black : Color.white).opacity(0.8)],
                               startPoint: .top, endPoint: .bottom).frame(height: 100)
            }.allowsHitTesting(false)
        VStack(spacing: 0) {
            MemoryPageHeader(page: $page)
                .environment(\.colorScheme, darkScene ? .dark : .light)
            Toggle("也看以前整理的", isOn: $includeOthers)
                .font(.caption).padding(.horizontal, 26).padding(.vertical, 4)
                .accessibilityIdentifier("memory-include-others")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.categories, id: \.self) { value in
                        Button { category = value } label: {
                            Text(value).font(.custom("NotoSerifSC-ExtraLight", size: 15, relativeTo: .body))
                                .padding(.horizontal, 16).frame(minHeight: 44)
                                .background(category == value ? theme.pageAccent.opacity(0.12) : .clear,
                                            in: RoundedRectangle(cornerRadius: 4))
                                .overlay(alignment: .bottom) {
                                    if category == value { Rectangle().fill(theme.pageAccent).frame(height: 1) }
                                }
                        }.buttonStyle(.plain).accessibilityIdentifier("memory-category-\(value)")
                            .accessibilityAddTraits(category == value ? .isSelected : [])
                    }
                }.padding(.horizontal, 22)
            }
            if let error = store.error {
                HStack {
                    Text(error).font(.caption)
                    Spacer()
                    Button("重试") { Task { await store.load() } }.disabled(store.loading || store.busy)
                }.padding(12)
                    .foregroundStyle(darkScene ? Color.white : Color(red: 0.25, green: 0.28, blue: 0.33))
                    .background(darkScene ? Color(red: 0.09, green: 0.11, blue: 0.20) : Color.white.opacity(0.94))
            }
            ZStack(alignment: .top) {
                VStack(spacing: 6) {
                    Text(scene.title).font(.custom("NotoSerifSC-ExtraLight", size: 22, relativeTo: .title2))
                    Text("\(category) · \(flowers.count) 条记忆").font(.caption)
                }.padding(.top, 12).allowsHitTesting(false)
                if store.loading && !store.loaded {
                    ProgressView("正在走进花园").padding(20).background(.regularMaterial).frame(maxHeight: .infinity)
                        .environment(\.colorScheme, darkScene ? .dark : .light)
                } else if store.loaded && flowers.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "leaf").font(.title3).accessibilityHidden(true)
                        Text(emptyMessage).font(.subheadline).multilineTextAlignment(.center).lineSpacing(6)
                    }.padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(30).frame(maxHeight: .infinity).accessibilityIdentifier("memory-empty")
                        .environment(\.colorScheme, darkScene ? .dark : .light)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Text("轻触花朵 · 拖动浏览 · 双指缩放").font(.caption2).padding(.bottom, 2)
                .allowsHitTesting(false)
            HStack {
                Button { listOpen = true } label: { Label("花朵列表", systemImage: "list.bullet") }
                    .accessibilityIdentifier("memory-flower-list")
                Spacer()
                Button("枯掉的花") { witheredOpen = true }.accessibilityIdentifier("memory-withered")
                Button { Task { await store.load() } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                }.accessibilityLabel("刷新花园").disabled(store.loading || store.busy)
            }.font(.caption).frame(minHeight: 44).padding(.horizontal, 22)
        }
        .foregroundStyle(darkScene ? Color.white.opacity(0.94) : Color(red: 0.25, green: 0.28, blue: 0.33))
        }
        .task { await store.load() }
        .sheet(item: $selected) { flower in
            MemoryFlowerDetail(store: store, flowerID: flower.id)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .large))
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $listOpen, onDismiss: {
            if let flower = pendingFlower { selected = flower; pendingFlower = nil }
        }) {
            NavigationStack {
                List(flowers) { flower in
                    Button {
                        listOpen = false
                        // Present after the list sheet has finished dismissing.
                        pendingFlower = flower
                    } label: {
                        HStack {
                            Image(flower.state == "bud" ? "MemoryBud" : flower.state == "fallen" ? "MemoryPetals" : "MemoryBloom")
                                .resizable().scaledToFit().frame(width: 40, height: 40).accessibilityHidden(true)
                            VStack(alignment: .leading) {
                                Text(flower.title)
                                Text(flower.state == "fallen" ? "已归档" : flower.author == "ke" ? "柯亲手记的" : "以前整理的")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if flower.loved { Image(systemName: "heart.fill").foregroundStyle(theme.pageAccent) }
                        }
                    }.accessibilityIdentifier("memory-flower-\(flower.id)")
                }.navigationTitle("\(category)的山茶").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { listOpen = false } } }
            }
        }
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
