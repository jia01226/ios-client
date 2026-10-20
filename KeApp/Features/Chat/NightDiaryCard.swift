import SwiftUI

// 128：刚才那一回结束，柯写了一篇「夜里」，服务器在聊天里发一条「夜里日记 · 刚才那一回」，
// 带一个附件 {url: "ke-night://<id>", name: "<tag 或第一行>", kind: "night"}。
// 这里画成一张卡：上面一两行摘要（点一下翻开日记 › 夜里的那一篇），下面就地点评——
// 她说「我不想打字，很羞耻」：喜欢 / 一般 / 不喜欢点一下，「下回想要」每行点一个，「写一句」可有可无。
// 点评和日记页「夜里」那一栏是同一份数据（NightStore.shared），哪边点的另一边都看得到。

private struct KeNightStoreKey: EnvironmentKey {
    static let defaultValue: NightStore? = nil
}

extension EnvironmentValues {
    /// 128：聊天时间线的格子里拿得到的「夜里」数据；没有（截图、预览）就只画卡、不出点评
    var keNightStore: NightStore? {
        get { self[KeNightStoreKey.self] }
        set { self[KeNightStoreKey.self] = newValue }
    }
}

struct NightDiaryCard: View {
    let message: Message
    let attachment: ChatAttachment
    var onOpen: () -> Void
    @Environment(\.keNightStore) private var store

    var body: some View {
        if let store, let id = attachment.nightID {
            NightDiaryCardLive(store: store, id: id, title: Self.title(message), fallback: attachment.name, onOpen: onOpen)
        } else {
            NightDiaryCardFace(title: Self.title(message), excerpt: Self.fallbackExcerpt(attachment.name), onOpen: onOpen)
                .frame(maxWidth: Theme.shared.metric.bubbleMaxWidth, alignment: .leading)
                .background(NightCardSurface())
        }
    }

    /// 卡上那一行字：服务器那条的第一行（「夜里日记 · 刚才那一回」），没有就用这个
    static let defaultTitle = "夜里日记 · 刚才那一回"
    static func title(_ message: Message) -> String {
        let first = message.text.split(whereSeparator: \.isNewline).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return first.isEmpty ? defaultTitle : first
    }

    /// 摘要：这一篇的正文开头（压成一行，卡上最多两行）；还没拉到就先用附件名（tag 或第一行）
    static func excerpt(_ entry: RemoteNight?, fallback: String) -> String {
        if let entry {
            let text = NightText.preview(entry.content)
            if text != "……" { return text }
        }
        return fallbackExcerpt(fallback)
    }

    static func fallbackExcerpt(_ name: String) -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "点开看柯写的那一篇" : value
    }
}

/// 有数据的那张：拉那一篇、就地点评
private struct NightDiaryCardLive: View {
    @ObservedObject var store: NightStore
    let id: Int
    let title: String
    let fallback: String
    var onOpen: () -> Void
    @FocusState private var focused: Int?

    var body: some View {
        let entry = store.entry(id)
        VStack(alignment: .leading, spacing: 10) {
            NightDiaryCardFace(
                title: title,
                excerpt: NightDiaryCard.excerpt(entry, fallback: fallback),
                saving: store.saving.contains(id),
                onOpen: onOpen
            )
            if let entry {
                NightReviewControls(
                    entry: entry,
                    error: store.errors[id],
                    draft: Binding(get: { store.drafts[id] ?? "" }, set: { store.drafts[id] = $0 }),
                    editing: store.editing.contains(id),
                    prefsOpen: store.prefsOpen.contains(id),
                    focus: $focused,
                    onRate: { r in Task { await store.rate(id, r) } },
                    onPref: { pref, value in Task { await store.setPref(id, pref, value) } },
                    onTogglePrefs: {
                        if store.prefsOpen.contains(id) { store.prefsOpen.remove(id) } else { store.prefsOpen.insert(id) }
                    },
                    onEdit: {
                        store.startEditing(entry)
                        DispatchQueue.main.async { focused = id }
                    },
                    onSend: {
                        focused = nil
                        Task { await store.send(id) }
                    },
                    compact: true
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            } else if store.failed {
                Button { Task { await store.load() } } label: {
                    Text("没接上，点这里再试").font(Ink.song(13)).foregroundStyle(Ink.secondary)
                        .frame(maxWidth: .infinity, minHeight: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14).padding(.bottom, 10)
            }
        }
        .frame(maxWidth: Theme.shared.metric.bubbleMaxWidth, alignment: .leading)
        .background(NightCardSurface())
        .task(id: id) { await store.ensure(id) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("night-card-\(id)")
    }
}

/// 卡的上半截：小月亮、「夜里日记 · 刚才那一回」、一两行摘要、「点开看 ›」。整块点一下翻开那一篇
private struct NightDiaryCardFace: View {
    let title: String
    let excerpt: String
    var saving = false
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(Ink.meText)
                        .accessibilityHidden(true)
                    Text(title).font(Ink.song(13)).foregroundStyle(Ink.secondary).lineLimit(1)
                    Spacer(minLength: 4)
                    if saving { ProgressView().controlSize(.mini).tint(Ink.secondary) }
                    Text("点开看 ›").font(Ink.song(12.5)).foregroundStyle(Ink.accent)
                }
                // 两行的位置一直留着：那一篇拉回来以前和以后一样高，格子不变大小
                Text(excerpt)
                    .font(Ink.song(15.5))
                    .foregroundStyle(Ink.primary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)：\(excerpt)")
        .accessibilityHint("点开看这一篇")
        .accessibilityAddTraits(.isButton)
    }
}

/// 128：卡的底：和气泡一样平的一块（不描边、不加影子），纸色固定浅色，上面的墨色字永远看得清
private struct NightCardSurface: View {
    var body: some View {
        RoundedRectangle(cornerRadius: CGFloat(Theme.shared.bubbleCornerRadius), style: .continuous)
            .fill(Theme.shared.nightCardPaper)
            .allowsHitTesting(false)
    }
}
