import SwiftUI

// 120：她想在聊天里直接问柯要锁着的日记，不用再去 柯的 → 日记 → 锁着 → 点开 → 去找柯要。
// 聊天页「+」里多一格「锁着的日记」，拉出这张单子：只列现在还锁着的，新的在上面；
// 点一篇就替她把日记里「去找柯要」那句发出去（不用改字），单子收起，人还在聊天里。
// 拉法、哪篇算锁着，都和日记页同一套（KeDiaryListView.fetchKeEntries / isLocked）。

struct LockedDiarySheet: View {
    let line: ChatLine
    var onAsk: (RemoteDiary) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CamelliaPalette.storageKey) private var savedPalette = CamelliaPalette.defaultPalette.rawValue
    @State private var entries: [RemoteDiary] = []
    @State private var loading = true
    @State private var failed = false
    /// 连点两篇只发第一句
    @State private var asked = false
    private var paper: Color { CamelliaPalette.resolve(savedPalette).paper }
    private var locked: [RemoteDiary] { entries.filter(KeDiaryListView.isLocked) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Ink.line.opacity(0.6)).frame(height: 0.7).padding(.horizontal, 26)
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.top, 14)
        .foregroundStyle(Ink.primary)
        .background(paper.ignoresSafeArea())
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("锁着的日记").font(Ink.song(20)).tracking(2)
                    .accessibilityAddTraits(.isHeader)
                Text("点一篇，替你去找柯要").font(Ink.song(13)).foregroundStyle(Ink.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .light))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(Ink.secondary)
            .accessibilityLabel("收起").accessibilityIdentifier("locked-diary-close")
        }
        .padding(.leading, 26).padding(.trailing, 14).padding(.bottom, 10)
    }

    @ViewBuilder private var content: some View {
        if loading && entries.isEmpty {
            VStack(spacing: 10) {
                ProgressView().tint(Ink.secondary)
                Text("正在翻日记…").font(Ink.song(14)).foregroundStyle(Ink.secondary)
            }
            .padding(.top, 36)
        } else if failed {
            Button { Task { await load() } } label: {
                Text("日记暂时没接上，点这里再试一次").font(Ink.song(14))
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .overlay(Capsule().stroke(Ink.line, lineWidth: 0.8))
            }
            .buttonStyle(.plain).padding(.top, 30)
            .accessibilityIdentifier("locked-diary-retry")
        } else if locked.isEmpty {
            Text("现在没有锁着的日记。").font(Ink.song(15)).foregroundStyle(Ink.secondary)
                .padding(.top, 36)
                .accessibilityIdentifier("locked-diary-empty")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(locked.enumerated()), id: \.element.id) { i, entry in
                        if i > 0 { Rectangle().fill(Ink.line.opacity(0.4)).frame(height: 0.5) }
                        row(entry)
                    }
                }
                .padding(.horizontal, 26).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(_ entry: RemoteDiary) -> some View {
        Button {
            guard !asked else { return }
            asked = true
            onAsk(entry)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(Ink.meText)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title.isEmpty ? "这一页" : entry.title).font(Ink.song(17)).lineLimit(1)
                    Text(Self.dateLine(entry.created_at)).font(Ink.song(12.5)).foregroundStyle(Ink.secondary)
                }
                Spacer(minLength: 8)
                Text("去要").font(Ink.song(13)).foregroundStyle(Ink.meText)
                    .padding(.horizontal, 10).frame(minHeight: 28)
                    .background(Capsule().fill(Ink.meFill))
            }
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(asked)
        .accessibilityLabel("\(entry.title.isEmpty ? "这一页" : entry.title)，\(Self.dateLine(entry.created_at))")
        .accessibilityHint("替你发一句话问柯要这篇")
    }

    /// 「10月12日 · 周日 · 21:30」，不是今年的写上年份
    static func dateLine(_ at: String) -> String {
        let day = String(at.prefix(10))
        return [KeDiaryListView.shortDate(at), KeDiaryListView.weekday(day), KeDiaryListView.time(at)]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// 和日记页一样：先摆上次看过的，后台再拉一遍
    private func load() async {
        if !KeDiaryListView.cache.isEmpty { entries = KeDiaryListView.cache; loading = false }
        else { loading = true }
        failed = false
        defer { loading = false }
        do {
            entries = try await KeDiaryListView.fetchKeEntries(line: line)
        } catch { if entries.isEmpty { failed = true } }
    }
}
