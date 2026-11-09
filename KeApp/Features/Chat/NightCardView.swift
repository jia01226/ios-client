import SwiftUI

struct NightCardView: View {
    @EnvironmentObject private var theme: Theme
    let entryID: Int
    @State private var rating: String = ""
    @State private var prefs: [String: String] = [:]
    @State private var comment: String = ""
    @State private var submitted = false
    @State private var submitting = false

    private struct PrefOption: Identifiable {
        let value: String
        let text: String
        var id: String { value }
    }

    private struct PrefRow: Identifiable {
        let key: String
        let label: String
        let options: [PrefOption]
        var id: String { key }
    }

    private static let prefRows: [PrefRow] = [
        PrefRow(key: "pace", label: "节奏", options: [
            PrefOption(value: "slower", text: "再慢一点"),
            PrefOption(value: "ok", text: "刚好"),
            PrefOption(value: "faster", text: "再快一点"),
        ]),
        PrefRow(key: "force", label: "力度", options: [
            PrefOption(value: "lighter", text: "再轻一点"),
            PrefOption(value: "ok", text: "刚好"),
            PrefOption(value: "harder", text: "再重一点"),
        ]),
        PrefRow(key: "talk", label: "骚话", options: [
            PrefOption(value: "more", text: "再多一点"),
            PrefOption(value: "ok", text: "刚好"),
            PrefOption(value: "less", text: "少一点"),
        ]),
        PrefRow(key: "foreplay", label: "前戏", options: [
            PrefOption(value: "longer", text: "再长一点"),
            PrefOption(value: "ok", text: "刚好"),
            PrefOption(value: "skip", text: "直接来"),
        ]),
        PrefRow(key: "length", label: "时长", options: [
            PrefOption(value: "longer", text: "再久一点"),
            PrefOption(value: "ok", text: "刚好"),
            PrefOption(value: "shorter", text: "短一点"),
        ]),
        PrefRow(key: "after", label: "事后", options: [
            PrefOption(value: "cuddle", text: "多抱一会儿"),
            PrefOption(value: "ok", text: "刚好"),
        ]),
    ]

    var body: some View {
        if submitted {
            submittedView
        } else {
            cardContent
        }
    }

    private var submittedView: some View {
        HStack(spacing: theme.metric.gapS) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(theme.effectiveAccent)
            Text("已收到")
                .font(theme.font.caption)
                .foregroundStyle(theme.color.textSecondary)
        }
        .padding(.vertical, theme.metric.gapS)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapM) {
            Text("夜里日记")
                .font(theme.font.sectionTitle)
                .foregroundStyle(theme.color.textPrimary)

            ratingRow

            prefsSection

            commentField

            submitButton
        }
        .padding(theme.metric.bubbleHorizontalPadding)
    }

    private var ratingRow: some View {
        HStack(spacing: theme.metric.gapS) {
            ratingButton(value: "love", label: "喜欢", icon: "heart.fill")
            ratingButton(value: "ok", label: "一般", icon: "hand.thumbsup")
            ratingButton(value: "meh", label: "不喜欢", icon: "hand.thumbsdown")
        }
    }

    private func ratingButton(value: String, label: String, icon: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                rating = rating == value ? "" : value
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
            }
            .font(theme.font.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: theme.metric.radiusChip, style: .continuous)
                    .fill(rating == value
                          ? theme.effectiveAccent.opacity(0.18)
                          : theme.color.card.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.metric.radiusChip, style: .continuous)
                    .stroke(rating == value
                            ? theme.effectiveAccent.opacity(0.4)
                            : theme.color.separator, lineWidth: 0.6)
            )
            .foregroundStyle(rating == value
                             ? theme.effectiveAccent
                             : theme.color.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private var prefsSection: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapS) {
            Text("下回想要")
                .font(theme.font.caption)
                .foregroundStyle(theme.color.textSecondary)

            ForEach(Self.prefRows) { row in
                prefRow(row)
            }
        }
    }

    private func prefRow(_ row: PrefRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.label)
                .font(.system(size: 11))
                .foregroundStyle(theme.color.textSecondary.opacity(0.7))

            HStack(spacing: 6) {
                ForEach(row.options) { option in
                    prefChip(
                        key: row.key,
                        value: option.value,
                        text: option.text
                    )
                }
            }
        }
    }

    private func prefChip(key: String, value: String, text: String) -> some View {
        let selected = prefs[key] == value
        return Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                if selected {
                    prefs.removeValue(forKey: key)
                } else {
                    prefs[key] = value
                }
            }
        } label: {
            Text(text)
                .font(.system(size: 12))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected
                              ? theme.effectiveAccent.opacity(0.15)
                              : theme.color.card.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(selected
                                ? theme.effectiveAccent.opacity(0.35)
                                : theme.color.separator.opacity(0.5), lineWidth: 0.5)
                )
                .foregroundStyle(selected
                                 ? theme.effectiveAccent
                                 : theme.color.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private var commentField: some View {
        TextField("备注", text: $comment, axis: .vertical)
            .font(theme.font.caption)
            .lineLimit(1...3)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.color.card.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.color.separator.opacity(0.5), lineWidth: 0.5)
            )
    }

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            HStack(spacing: 6) {
                if submitting {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(theme.color.textOnAccent)
                } else {
                    Text("提交")
                }
            }
            .font(theme.font.caption)
            .foregroundStyle(theme.color.textOnAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: theme.metric.radiusChip, style: .continuous)
                    .fill(hasContent
                          ? theme.effectiveAccent
                          : theme.effectiveAccent.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasContent || submitting)
    }

    private var hasContent: Bool {
        !rating.isEmpty || !prefs.isEmpty || !comment.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submit() {
        guard hasContent, !submitting else { return }
        submitting = true
        Task {
            do {
                try await APIClient.shared.nightComment(
                    entryID: entryID,
                    rating: rating,
                    comment: comment.trimmingCharacters(in: .whitespacesAndNewlines),
                    prefs: prefs
                )
                await MainActor.run {
                    withAnimation { submitted = true }
                }
            } catch {
                await MainActor.run { submitting = false }
            }
        }
    }
}
