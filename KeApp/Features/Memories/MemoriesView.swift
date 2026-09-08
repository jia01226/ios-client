import SwiftUI

struct MemoriesView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var review: MemoryReviewStore
    @State private var category = "全部"

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
                            Text("已收下的记忆").font(theme.font.sectionTitle)
                            Spacer()
                            Picker("类型", selection: $category) {
                                ForEach(["全部", "身体", "喜好", "约定", "生活", "关系"], id: \.self) { Text($0) }
                            }.pickerStyle(.menu)
                        }
                        let facts = review.archive.facts.filter { category == "全部" || $0.category == category }
                        if facts.isEmpty {
                            Text(review.archive.outbox.isEmpty ? "收下并同步的记忆会留在这里。" : "审核已存本机，同步后更新这里。")
                                .font(theme.font.reviewBody).foregroundStyle(theme.reviewSecondary)
                        }
                        ForEach(facts) { fact in
                            VStack(alignment: .leading, spacing: theme.metric.gapS) {
                                Text(fact.fact).font(theme.font.reviewBody)
                                if !fact.note.isEmpty {
                                    Text("你的备注 · \(fact.note)").font(theme.font.reviewCaption)
                                }
                                Text("\(fact.category) · \(fact.observed_at)")
                                    .font(theme.font.reviewCaption).foregroundStyle(theme.reviewSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, theme.metric.gapS)
                            Divider()
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
        .tint(theme.effectiveAccent)
        .task { await review.sync() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await review.sync() } }
        }
    }
}
