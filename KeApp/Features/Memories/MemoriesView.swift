import SwiftUI

struct MemoriesView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var review: MemoryReviewStore
    @State private var category = MemoryShelf.all
    @State private var updating: ReviewCard?

    init(line: ChatLine = .main) {
        _review = StateObject(wrappedValue: MemoryReviewStore.make(line: line))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metric.gapXL) {
                    HStack {
                        Text("回忆").font(theme.font.pageTitle)
                        Spacer()
                        Menu {
                            NavigationLink("柯味语录") { AppQuotesView(line: review.line) }
                                .accessibilityIdentifier("app-quotes-entry")
                            NavigationLink("整理用量") { MemoryUsageView(line: review.line) }
                                .accessibilityIdentifier("memory-usage-entry")
                            NavigationLink("记忆怎么找的") {
                                MemoryRetrievalView(line: review.line) {
                                    Task { await review.sync() }
                                }
                            }
                            .accessibilityIdentifier("memory-retrieval-entry")
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(theme.font.menuIcon)
                                .frame(width: theme.metric.touchTarget, height: theme.metric.touchTarget)
                                .background(theme.color.cardElevated, in: Circle())
                        }
                        .accessibilityLabel("更多回忆工具")
                    }

                    featuredMemory

                    HStack(spacing: theme.metric.gapS) {
                        NavigationLink {
                            MemoryReviewDeck(store: review)
                        } label: {
                            memoryShortcut(
                                title: "一起核对",
                                subtitle: review.hasLoaded || review.archive.storeID != nil
                                    ? "\(review.pending.count) 张待审"
                                    : "看看待审卡片",
                                icon: "rectangle.on.rectangle.angled"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("memory-review-entry")

                        NavigationLink {
                            ArchiveHistoryView(line: review.line)
                        } label: {
                            memoryShortcut(title: "找一段话", subtitle: "搜索我们的回忆", icon: "magnifyingglass")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("archive-search-entry")

                        NavigationLink {
                            ArchiveHistoryView(line: review.line)
                        } label: {
                            memoryShortcut(title: "最初聊天", subtitle: "回到开始那天", icon: "clock.arrow.circlepath")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("archive-history-entry")
                    }

                    if review.error != nil || !review.hasLoaded || review.isSyncing {
                        HStack(spacing: theme.metric.gapS) {
                            Image(systemName: review.isSyncing ? "arrow.triangle.2.circlepath" : "wifi.exclamationmark")
                            Text(syncSummary).lineLimit(1)
                            Spacer(minLength: 0)
                            if !review.isSyncing {
                                Button("重试") { Task { await review.sync() } }
                            }
                        }
                        .font(theme.font.reviewCaption)
                        .foregroundStyle(theme.reviewSecondary)
                        .padding(.horizontal, theme.metric.gapM)
                        .padding(.vertical, theme.metric.gapS)
                        .background(theme.color.cardElevated, in: Capsule())
                    }

                    VStack(alignment: .leading, spacing: theme.metric.gapM) {
                        HStack {
                            Text("我们收下的").font(theme.font.sectionTitle)
                            Spacer()
                            Picker("类型", selection: $category) {
                                ForEach(MemoryShelf.allCases) { Text($0.title).tag($0) }
                            }.pickerStyle(.menu)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: theme.metric.gapS) {
                                ForEach(MemoryShelf.visibleCases) { shelf in
                                    Button(shelf.title) { category = shelf }
                                        .font(theme.font.reviewCaption)
                                        .foregroundStyle(category == shelf ? theme.color.textOnAccent : theme.color.textPrimary)
                                        .padding(.horizontal, theme.metric.gapM)
                                        .frame(minHeight: 34)
                                        .background(category == shelf ? theme.effectiveAccent : theme.color.cardElevated, in: Capsule())
                                }
                            }
                        }
                        let facts = filteredFacts
                        if facts.isEmpty {
                            emptyShelf
                        } else {
                            ForEach(facts) { fact in
                                memoryFactCard(fact)
                            }
                        }
                    }
                }
                .foregroundStyle(theme.color.textPrimary)
                .padding(theme.metric.pagePadding)
            }
            .background(theme.color.bg)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await review.sync() }
        }
        .sheet(item: $updating) { card in ReviewNoteEditor(store: review, card: card) }
        .tint(theme.effectiveAccent)
        .task { await review.sync() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await review.sync() } }
        }
    }

    @ViewBuilder
    private var featuredMemory: some View {
        let fact = review.archive.facts.first
        VStack(alignment: .leading, spacing: theme.metric.gapM) {
            HStack {
                Text(fact == nil ? "今天想起" : "最近收下").font(theme.font.sectionTitle)
                    .foregroundStyle(theme.effectiveAccent)
                Spacer()
                Image(systemName: "sparkles")
                    .foregroundStyle(theme.effectiveAccent.opacity(0.58))
            }
            Text(fact?.fact ?? "等我们收下一些回忆，柯会在有由头的时候，替你翻出一页。")
                .font(theme.font.quote)
                .lineSpacing(5)
            Divider().overlay(theme.color.separator)
            Text(fact.map { "柯主动想起 · \($0.observed_at)" } ?? "不是随机抽一张，是想起了才翻出来")
                .font(theme.font.reviewCaption)
                .foregroundStyle(theme.reviewSecondary)
        }
        .padding(theme.metric.gapL)
        .background(theme.color.cardElevated, in: RoundedRectangle(cornerRadius: theme.metric.radiusCard))
    }

    private func memoryShortcut(title: String, subtitle: String, icon: String) -> some View {
        VStack(spacing: theme.metric.gapS) {
            Image(systemName: icon)
                .font(.system(size: 23, weight: .regular))
                .foregroundStyle(theme.effectiveAccent)
            Text(title).font(theme.font.sectionTitle).lineLimit(1)
            Text(subtitle)
                .font(theme.font.reviewCaption)
                .foregroundStyle(theme.reviewSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 112)
        .padding(.horizontal, theme.metric.gapXS)
        .background(theme.color.card, in: RoundedRectangle(cornerRadius: theme.metric.radiusCard))
    }

    private var filteredFacts: [ReviewedFact] {
        review.archive.facts.filter { category == .all || MemoryShelf(fact: $0) == category }
    }

    private var syncSummary: String {
        if review.isSyncing { return "正在把回忆收好" }
        if !review.archive.outbox.isEmpty { return "已保留本机内容，联网后同步" }
        return "暂时没连上，已保留本机内容"
    }

    private var emptyShelf: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapS) {
            Image(systemName: category.icon)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(theme.effectiveAccent)
            Text(category == .all ? "这里会慢慢装满" : "“\(category.title)”还没有收进来的记忆")
                .font(theme.font.sectionTitle)
            Text("核对并收下的内容会留在这里，不会因为暂时断线消失。")
                .font(theme.font.reviewBody)
                .foregroundStyle(theme.reviewSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.metric.gapL)
        .background(theme.color.card, in: RoundedRectangle(cornerRadius: theme.metric.radiusCard))
    }

    @ViewBuilder
    private func memoryFactCard(_ fact: ReviewedFact) -> some View {
        let shelf = MemoryShelf(fact: fact)
        VStack(alignment: .leading, spacing: theme.metric.gapM) {
            Label(shelf.title, systemImage: shelf.icon)
                .font(theme.font.reviewCaption)
                .foregroundStyle(theme.effectiveAccent)
                .padding(.horizontal, theme.metric.gapS)
                .padding(.vertical, theme.metric.gapXS)
                .background(theme.effectiveAccent.opacity(0.11), in: Capsule())
            Text(fact.fact).font(theme.font.reviewBody).lineSpacing(3)
            if !fact.note.isEmpty {
                Text("你的备注 · \(fact.note)")
                    .font(theme.font.reviewCaption)
                    .foregroundStyle(theme.reviewSecondary)
            }
            if let history = fact.history, !history.isEmpty {
                DisclosureGroup("以前的情况") {
                    ForEach(history) { old in
                        Text(old.fact).font(theme.font.reviewBody)
                        Text(old.observed_at).font(theme.font.reviewCaption).foregroundStyle(theme.reviewSecondary)
                    }
                }
            }
            HStack {
                Text(fact.observed_at).font(theme.font.reviewCaption).foregroundStyle(theme.reviewSecondary)
                Spacer()
                if let card = fact.review_card {
                    Button("情况变了") { review.prepareUpdate(card); updating = card }
                        .font(theme.font.reviewCaption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.metric.gapL)
        .background(theme.color.card, in: RoundedRectangle(cornerRadius: theme.metric.radiusCard))
    }
}

private enum MemoryShelf: String, CaseIterable, Identifiable {
    case all, medicine, preference, life, relationship

    static let visibleCases: [MemoryShelf] = [.all, .medicine, .preference, .life, .relationship]
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "全部"
        case .medicine: return "我的药"
        case .preference: return "我的喜好"
        case .life: return "生活"
        case .relationship: return "关系"
        }
    }
    var icon: String {
        switch self {
        case .all: return "sparkles"
        case .medicine: return "cross.case"
        case .preference: return "heart"
        case .life: return "cup.and.saucer"
        case .relationship: return "person.2"
        }
    }

    init(fact: ReviewedFact) {
        switch fact.group ?? fact.category {
        case "身体用药": self = .medicine
        case "喜好": self = .preference
        case "关系约定": self = .relationship
        default: self = .life
        }
    }
}

private struct ArchiveHistoryView: View {
    @EnvironmentObject private var theme: Theme
    let line: ChatLine
    @State private var messages: [ArchivedChatMessage] = []
    @State private var query = ""
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                ContentUnavailableView(
                    "旧聊天没有打开",
                    systemImage: "exclamationmark.bubble",
                    description: Text(error)
                )
                Button("再试一次") { Task { await load(reset: true) } }
            } else if messages.isEmpty && !loading {
                ContentUnavailableView("还没有找到旧聊天", systemImage: "clock.arrow.circlepath")
            } else {
                ForEach(messages) { message in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(message.author == "user" ? "佳佳" : "柯")
                                .font(theme.font.reviewCaption)
                            Spacer()
                            Text(message.created_at)
                                .font(theme.font.reviewCaption)
                                .foregroundStyle(theme.reviewSecondary)
                        }
                        Text(message.content)
                            .font(theme.font.reviewBody)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 5)
                }
                if !messages.isEmpty && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(loading ? "正在往前翻…" : "再往前翻") {
                        Task { await load(reset: false) }
                    }
                    .disabled(loading)
                }
            }
        }
        .navigationTitle("最初的聊天")
        .searchable(text: $query, prompt: "搜索旧聊天")
        .task { await load(reset: true) }
        .onSubmit(of: .search) { Task { await load(reset: true) } }
        .refreshable { await load(reset: true) }
        .overlay { if loading && messages.isEmpty { ProgressView("正在翻旧记录…") } }
    }

    @MainActor
    private func load(reset: Bool) async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let beforeID = reset || !value.isEmpty ? nil : messages.first?.id
            let rows = try await APIClient(baseURL: line.apiBaseURL)
                .fetchArchivedMessages(query: value, beforeID: beforeID)
            messages = reset || !value.isEmpty ? rows : rows + messages
        } catch {
            self.error = "记录仍在服务器，连接没有接稳。"
        }
    }
}
