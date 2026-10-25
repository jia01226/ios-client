import SwiftUI

// 136 她：「塔罗能不能做个历史记录，有时候我记不住我问了什么，点进去一下子没有了」。
// 牌桌右上「记录」：以前每一次抽的牌，问了什么、哪天、三张是什么；点进去看牌和牌义。
// 也是这次起，牌翻开以后桌子底下直接写每张的牌义（以前要等柯回了才知道）。

/// 服务器 /api/tarot/recent 的一行
struct TarotHistoryItem: Decodable, Identifiable, Sendable {
    let id: Int
    let question: String
    let spread: String
    let spread_name: String
    let cards: [TarotCard]
    let verdict: String?
    let created_at: String?

    var cast: TarotCast { TarotCast(id: id, question: question, spread: spread, spread_name: spread_name, cards: cards, objective: nil) }

    /// 「10月22日 11:31」
    var dateText: String {
        guard let raw = created_at, raw.count >= 16 else { return created_at ?? "" }
        let parts = raw.prefix(16).split(whereSeparator: { $0 == "-" || $0 == " " || $0 == "T" })
        guard parts.count >= 4, let m = Int(parts[1]), let d = Int(parts[2]) else { return String(raw.prefix(16)) }
        return "\(m)月\(d)日 \(parts[3])"
    }
    var cardLine: String {
        cards.map { $0.cn + ($0.reversed ? "（逆）" : "") }.joined(separator: " · ")
    }
}

/// 服务器的客观牌义（objective）拆成一张一行：「过去(根源/背景) · 圣杯二（正位）：相互吸引……」
enum TarotMeaning {
    struct Row: Equatable { let title: String; let meaning: String }

    static func rows(_ objective: String) -> (cards: [Row], summary: String) {
        var cards: [Row] = [], rest: [String] = []
        for raw in objective.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("问的是：") || line.hasPrefix("牌阵：") { continue }
            if line.contains(" · "), let colon = line.firstIndex(of: "：") {
                let title = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let meaning = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                cards.append(Row(title: title, meaning: meaning))
            } else {
                rest.append(line)
            }
        }
        return (cards, rest.joined(separator: "\n"))
    }
}

/// 一块写牌义的板子：牌桌下面和记录里都用它。点牌名看大牌
struct TarotMeaningPanel: View {
    let cast: TarotCast
    let objective: String
    var onCard: (TarotCard) -> Void

    var body: some View {
        let parsed = TarotMeaning.rows(objective)
        VStack(alignment: .leading, spacing: TarotTableStyle.gap) {
            Text("牌义").font(TarotTableStyle.caption).foregroundStyle(TarotTableStyle.muted)
            ForEach(Array(parsed.cards.enumerated()), id: \.offset) { index, row in
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        if cast.cards.indices.contains(index) { onCard(cast.cards[index]) }
                    } label: {
                        Text(row.title).font(TarotTableStyle.body).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityHint("点开大图")
                    Text(row.meaning).font(TarotTableStyle.caption).foregroundStyle(TarotTableStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !parsed.summary.isEmpty {
                Text(parsed.summary).font(TarotTableStyle.caption).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TarotTableStyle.gap)
        .background(TarotTableStyle.panel, in: RoundedRectangle(cornerRadius: TarotTableStyle.radius))
        .overlay {
            RoundedRectangle(cornerRadius: TarotTableStyle.radius)
                .stroke(TarotTableStyle.border, lineWidth: TarotTableStyle.hairline)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tarot-meanings")
    }
}

struct TarotHistoryView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    let api: APIClient
    @State private var items: [TarotHistoryItem]?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let items, items.isEmpty {
                    Text("还没有抽过牌").font(TarotTableStyle.body).foregroundStyle(TarotTableStyle.muted)
                } else if let items {
                    ScrollView {
                        LazyVStack(spacing: TarotTableStyle.gap) {
                            ForEach(items) { item in
                                NavigationLink(value: item.id) { row(item) }.buttonStyle(.plain)
                            }
                        }
                        .padding(TarotTableStyle.padding)
                    }
                    .refreshable { await load() }
                } else if failed {
                    Button("没接上，点这里再试") { Task { await load() } }.font(TarotTableStyle.body)
                } else {
                    ProgressView().tint(TarotTableStyle.ink)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("抽过的牌")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("关上")
                }
            }
            .navigationDestination(for: Int.self) { id in
                if let item = items?.first(where: { $0.id == id }) {
                    TarotHistoryDetail(item: item, api: api).environmentObject(theme)
                }
            }
            .background(TarotTableStyle.cloth.ignoresSafeArea())
        }
        .foregroundStyle(TarotTableStyle.ink)
        .tint(TarotTableStyle.ink)
        .preferredColorScheme(.dark)
        .task { if items == nil { await load() } }
    }

    private func row(_ item: TarotHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(item.dateText).font(TarotTableStyle.caption).foregroundStyle(TarotTableStyle.muted)
                Spacer()
                Text(item.spread_name).font(TarotTableStyle.caption).foregroundStyle(TarotTableStyle.muted)
            }
            Text(item.question.isEmpty ? (item.spread == TarotSpread.night ? "夜里" : "没写问题") : item.question)
                .font(TarotTableStyle.body).multilineTextAlignment(.leading).lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.cardLine).font(TarotTableStyle.caption).foregroundStyle(TarotTableStyle.muted).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TarotTableStyle.gap)
        .background(TarotTableStyle.panel, in: RoundedRectangle(cornerRadius: TarotTableStyle.radius))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        do {
            items = try await api.tarotHistory()
            failed = false
        } catch is CancellationError {
        } catch {
            if items == nil { failed = true }
        }
    }
}

private struct TarotHistoryDetail: View {
    @EnvironmentObject private var theme: Theme
    let item: TarotHistoryItem
    let api: APIClient
    @State private var objective: String?
    @State private var inspected: TarotCard?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TarotTableStyle.padding) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.dateText + " · " + item.spread_name).font(TarotTableStyle.caption).foregroundStyle(TarotTableStyle.muted)
                    Text(item.question.isEmpty ? "没写问题" : item.question).font(TarotTableStyle.title)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ChatImageGroup(attachments: item.cast.chatAttachments, trailing: false) { index in
                    if item.cards.indices.contains(index) { inspected = item.cards[index] }
                }
                if let objective, !objective.isEmpty {
                    TarotMeaningPanel(cast: item.cast, objective: objective) { inspected = $0 }
                } else if item.spread == TarotSpread.night {
                    ForEach(item.cards) { card in
                        if let night = card.night, !night.summary.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(night.displayLabel) · \(card.cn)").font(TarotTableStyle.body)
                                Text(night.summary).font(TarotTableStyle.caption).foregroundStyle(TarotTableStyle.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if let verdict = item.verdict?.trimmingCharacters(in: .whitespacesAndNewlines), !verdict.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("后来").font(TarotTableStyle.caption).foregroundStyle(TarotTableStyle.muted)
                        Text(verdict).font(TarotTableStyle.body).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(TarotTableStyle.padding)
        }
        .background(TarotTableStyle.cloth.ignoresSafeArea())
        .navigationTitle("那一次")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $inspected) { card in
            TarotCardInspector(cards: item.cards, initialCard: card, api: api).environmentObject(theme)
                .swipeBackToClose { inspected = nil }
        }
        .task {
            guard objective == nil, item.spread != TarotSpread.night else { return }
            objective = (try? await api.tarotCast(id: item.id))?.objective
        }
    }
}
