import SwiftUI

struct MemoriesView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var review: MemoryReviewStore
    @State private var category = "全部"
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
                        Text(review.line.title).font(theme.font.reviewCaption)
                            .foregroundStyle(theme.reviewSecondary)
                    }
                    NavigationLink {
                        MemoryReviewDeck(store: review)
                    } label: {
                        HStack(spacing: theme.metric.gapM) {
                            Image(systemName: "rectangle.on.rectangle.angled")
                            VStack(alignment: .leading, spacing: theme.metric.gapS) {
                                Text("一起核对记忆").font(theme.font.sectionTitle)
                                Text(review.hasLoaded || review.archive.storeID != nil
                                     ? "\(review.pending.count) 张待审 · \(review.deferred.count) 张暂缓"
                                     : "连接后查看待审卡片")
                                    .font(theme.font.reviewCaption)
                                    .foregroundStyle(theme.reviewSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(theme.metric.gapL)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.color.cardElevated, in: RoundedRectangle(cornerRadius: theme.metric.radiusCard))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("memory-review-entry")

                    NavigationLink {
                        KeMemoryLibraryView(line: review.line) {
                            Task { await review.sync() }
                        }
                    } label: {
                        HStack(spacing: theme.metric.gapM) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 20, weight: .medium))
                            VStack(alignment: .leading, spacing: theme.metric.gapS) {
                                Text("柯的记忆").font(theme.font.sectionTitle)
                                Text("他从共同聊天里记住的事与语录，不会替代你的原话。")
                                    .font(theme.font.reviewCaption)
                                    .foregroundStyle(theme.reviewSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(theme.reviewSecondary)
                        }
                        .frame(minHeight: theme.metric.touchTarget)
                    }
                    .accessibilityIdentifier("ke-memory-library-entry")
                    NavigationLink {
                        MemoryUsageView(line: review.line)
                    } label: {
                        Label("整理用量", systemImage: "chart.bar")
                            .font(theme.font.sectionTitle)
                            .frame(minHeight: theme.metric.touchTarget)
                    }
                    .accessibilityIdentifier("memory-usage-entry")

                    NavigationLink {
                        MemoryRetrievalView(line: review.line) {
                            Task { await review.sync() }
                        }
                    } label: {
                        Label("记忆怎么找的", systemImage: "magnifyingglass")
                            .font(theme.font.sectionTitle)
                            .frame(minHeight: theme.metric.touchTarget)
                    }
                    .accessibilityIdentifier("memory-retrieval-entry")

                    VStack(alignment: .leading, spacing: theme.metric.gapS) {
                        Text(review.syncLabel).font(theme.font.reviewCaption)
                        if let error = review.error {
                            Text(error).font(theme.font.reviewCaption)
                            Button("重试同步") { Task { await review.sync() } }
                                .frame(minHeight: theme.metric.touchTarget)
                        }
                    }
                    .foregroundStyle(theme.reviewSecondary)

                    VStack(alignment: .leading, spacing: theme.metric.gapM) {
                        HStack {
                            VStack(alignment: .leading, spacing: theme.metric.gapXS) {
                                Text("我的记忆库").font(theme.font.sectionTitle)
                                Text("你确认过的资料、经历与变化，随时可以核对和更正。")
                                    .font(theme.font.reviewCaption)
                                    .foregroundStyle(theme.reviewSecondary)
                            }
                            Spacer()
                            Picker("类型", selection: $category) {
                                ForEach(["全部", "身体用药", "安排", "关系约定", "喜好", "生活日常"], id: \.self) { Text($0) }
                            }.pickerStyle(.menu)
                        }
                        let facts = review.archive.facts.filter { category == "全部" || ($0.group ?? $0.category) == category }
                        if facts.isEmpty {
                            Text(review.archive.outbox.isEmpty ? "收下并同步的记忆会留在这里。" : "审核已存本机，同步后更新这里。")
                                .font(theme.font.reviewBody).foregroundStyle(theme.reviewSecondary)
                        }
                        let groupOrder = ["身体用药", "安排", "关系约定", "喜好", "生活日常"]
                        let layerRank = ["现行": 0, "长期": 1, "零碎": 2, "旧账": 3]
                        let grouped = Dictionary(grouping: facts) { $0.group ?? "生活日常" }
                        let names = groupOrder.filter { grouped[$0] != nil } + grouped.keys.filter { !groupOrder.contains($0) }.sorted()
                        ForEach(names, id: \.self) { name in
                            let items = (grouped[name] ?? []).sorted {
                                let a = ($0.changed_when != nil || !($0.history ?? []).isEmpty) ? 0 : 1
                                let b = ($1.changed_when != nil || !($1.history ?? []).isEmpty) ? 0 : 1
                                if a != b { return a < b }
                                return (layerRank[$0.layer ?? ""] ?? 9) < (layerRank[$1.layer ?? ""] ?? 9)
                            }
                            let changedCount = items.filter { $0.changed_when != nil || !($0.history ?? []).isEmpty }.count
                            Section {
                                factsList(items)
                            } header: {
                                HStack(spacing: theme.metric.gapS) {
                                    Text(name).font(theme.font.sectionTitle)
                                    Text("\(items.count)").font(theme.font.reviewCaption)
                                        .foregroundStyle(theme.reviewSecondary)
                                    if changedCount > 0 {
                                        Text("变过 \(changedCount)").font(theme.font.reviewCaption)
                                            .padding(.horizontal, theme.metric.gapS)
                                            .background(theme.effectiveAccent.opacity(0.16), in: Capsule())
                                    }
                                    Spacer()
                                }
                                .padding(.top, theme.metric.gapM)
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
    private func factsList(_ facts: [ReviewedFact]) -> some View {
                        ForEach(facts) { fact in
                            VStack(alignment: .leading, spacing: theme.metric.gapS) {
                                Text(fact.fact).font(theme.font.reviewBody)
                                if !fact.note.isEmpty {
                                    Text("你的备注 · \(fact.note)").font(theme.font.reviewCaption)
                                }
                                if let when = fact.changed_when { Text("变化时间 · \(when)").font(theme.font.reviewCaption) }
                                if let history = fact.history, !history.isEmpty {
                                    DisclosureGroup("以前的情况") {
                                        ForEach(history) { old in
                                            VStack(alignment: .leading, spacing: theme.metric.gapS) {
                                                Text(old.fact).font(theme.font.reviewBody)
                                                Text("历史记录 · \(old.observed_at)").font(theme.font.reviewCaption)
                                                if !old.note.isEmpty { Text(old.note).font(theme.font.reviewCaption) }
                                            }
                                        }
                                    }
                                }
                                if let card = fact.review_card {
                                    Button("以前是，现在变了") { review.prepareUpdate(card); updating = card }
                                        .frame(minHeight: theme.metric.touchTarget)
                                }
                                HStack(spacing: theme.metric.gapS) {
                                    if let layer = fact.layer {
                                        Text(layer).font(theme.font.reviewCaption)
                                            .padding(.horizontal, theme.metric.gapS)
                                            .background(theme.color.cardElevated, in: Capsule())
                                    }
                                    if fact.changed_when != nil || !(fact.history ?? []).isEmpty {
                                        Text("变过").font(theme.font.reviewCaption)
                                            .padding(.horizontal, theme.metric.gapS)
                                            .background(theme.effectiveAccent.opacity(0.16), in: Capsule())
                                    }
                                    Text(fact.observed_at)
                                        .font(theme.font.reviewCaption).foregroundStyle(theme.reviewSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, theme.metric.gapS)
                            Divider()
                        }
    }
}

/// 柯的“会想起什么”与用户事实库分开呈现，避免把角色的说话参考误认为用户资料。
private struct KeMemoryLibraryView: View {
    @EnvironmentObject private var theme: Theme
    let line: ChatLine
    let onChanged: () -> Void

    var body: some View {
        List {
            Section {
                Text("这里放的是柯在相处中会参考的共同聊天线索与被你收下的语录。它们不等同于你的事实资料；有不对的地方，请回到“我的记忆库”核对或更正。")
                    .font(theme.font.body)
                    .foregroundStyle(theme.color.textSecondary)
            } header: {
                Text("柯会想起的")
            }

            Section {
                NavigationLink {
                    AppQuotesView(line: line)
                } label: {
                    Label("柯味语录", systemImage: "quote.bubble")
                }

                NavigationLink {
                    MemoryRetrievalView(line: line) {
                        onChanged()
                    }
                } label: {
                    Label("他这次怎么找到记忆", systemImage: "magnifyingglass")
                }
            } footer: {
                Text("柯不会因为看过一段旧聊天，就把它当成你的新事实。")
            }
        }
        .navigationTitle("柯的记忆")
        .navigationBarTitleDisplayMode(.inline)
        .tint(theme.effectiveAccent)
    }
}
