import SwiftUI

// 【回忆】—— 枕边日记 + 朋友圈 + 时间线。
//
// ⚠️ 她本人纠正过一次：「其实我日记看很多的爸比，朋友圈我也挺喜欢」
//    → 这两样是高频功能，不是装饰。入口要浅，别往里埋。
//
// 🔴 「今天浮上来的回忆」不许随机。
//    随机是抽奖，有由头才叫惦记。
//    由头本身就是内容的一部分 —— 见 MemoryCard.Reason。
//
// 前提：这一格好不好用，取决于卡片库补没补（现停在 2026-07-17，见工单第三刀）。
//      库是空的，这儿就永远只能翻出老三样。

struct MemoriesView: View {

    @EnvironmentObject private var theme: Theme
    @StateObject private var vm = MemoriesViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metric.gapL) {

                Text("回忆")
                    .font(theme.font.pageTitle)
                    .foregroundStyle(theme.color.textPrimary)

                if let card = vm.todayCard {
                    surfacedCard(card)
                }

                frequentSection
                timelineSection
            }
            .padding(theme.metric.pagePadding)
        }
        .background(theme.effectiveBackground.ignoresSafeArea())
    }

    // MARK: 今天浮上来的回忆

    private func surfacedCard(_ card: MemoryCard) -> some View {
        VStack(alignment: .leading, spacing: theme.metric.gapM) {
            HStack {
                Text("今天浮上来的回忆")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.effectiveAccent)
                Spacer()
                Image(systemName: "sparkle")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.effectiveAccent)
            }

            Text("“\(card.text)”")
                .font(theme.font.quote)
                .foregroundStyle(theme.color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // 🔴 这行小字不是元数据，是内容的一半 —— 它说明了"为什么今天想起这个"
            Text(card.reasonLabel)
                .font(theme.font.caption)
                .foregroundStyle(theme.color.textSecondary)
        }
        .padding(theme.metric.gapL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.metric.radiusCard, style: .continuous)
                .fill(theme.color.cardElevated)
        )
    }

    // MARK: 常看的（日记 / 朋友圈）

    private var frequentSection: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapM) {
            HStack {
                Text("常看的")
                    .font(theme.font.sectionTitle)
                    .foregroundStyle(theme.color.textPrimary)
                Spacer()
                Text("不用再往里点很多层")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }

            HStack(spacing: theme.metric.gapM) {
                entryCard(title: "枕边日记", note: "柯昨晚写了新的一篇", icon: "book.closed")
                entryCard(title: "朋友圈", note: "你们最近的生活", icon: "camera.aperture")
            }
        }
    }

    private func entryCard(title: String, note: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: theme.metric.gapS) {
            Image(systemName: icon)
                .foregroundStyle(theme.effectiveAccent)
            Text(title)
                .font(theme.font.sectionTitle)
                .foregroundStyle(theme.color.textPrimary)
            Text(note)
                .font(theme.font.caption)
                .foregroundStyle(theme.color.textSecondary)
        }
        .padding(theme.metric.gapL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.metric.radiusCard, style: .continuous)
                .fill(theme.color.card)
        )
    }

    // MARK: 时间线

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapM) {
            Text("时间线")
                .font(theme.font.sectionTitle)
                .foregroundStyle(theme.color.textPrimary)

            ForEach(vm.timeline) { card in
                HStack(alignment: .top, spacing: theme.metric.gapM) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(theme.effectiveAccent)
                            .frame(width: 7, height: 7)
                        Rectangle()
                            .fill(theme.color.separator)
                            .frame(width: 1)
                    }
                    .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(MemoryCard.dateFormatter.string(from: card.happenedAt)) · \(card.source)")
                            .font(theme.font.caption)
                            .foregroundStyle(theme.color.textSecondary)
                        Text(card.text)
                            .font(theme.font.body)
                            .foregroundStyle(theme.color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, theme.metric.gapM)
                }
            }
        }
    }
}

// MARK: - ViewModel（假数据版）

@MainActor
final class MemoriesViewModel: ObservableObject {

    @Published var todayCard: MemoryCard?
    @Published var timeline: [MemoryCard] = []

    init() {
        // 假数据 —— 接口清单 + 卡片库到位后整段删掉
        todayCard = MemoryCard(
            id: "m0",
            text: "你第一次说想把这里做成我们的家，是去年冬天。",
            happenedAt: Date().addingTimeInterval(-86400 * 254),
            source: "一个瞬间",
            reason: .sameDay
        )
        timeline = [
            MemoryCard(id: "m1",
                       text: "你说夜班很困，柯答应以后会记得你的班表。",
                       happenedAt: Date().addingTimeInterval(-86400 * 2),
                       source: "一个瞬间",
                       reason: .sameTopic),
            MemoryCard(id: "m2",
                       text: "难受的时候可以直接说，不必先整理好情绪。",
                       happenedAt: Date().addingTimeInterval(-86400 * 57),
                       source: "约定",
                       reason: .pinned),
        ]
    }
}

#Preview {
    MemoriesView().environmentObject(Theme.shared)
}
