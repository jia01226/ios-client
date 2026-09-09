import SwiftUI

struct AppQuote: Decodable, Identifiable, Sendable {
    let id: Int
    let message_id: Int
    let text: String
    let note: String
    let scene: String
    let created_at: String
}
struct AppQuotePage: Decodable, Sendable { let quotes: [AppQuote] }

struct AppQuoteSaveView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    let line: ChatLine
    let message: Message
    @State private var note = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("选中的回复") {
                    Text(message.text).font(theme.font.body).textSelection(.enabled)
                }
                Section {
                    TextField("哪里像柯？可以留空", text: $note, axis: .vertical)
                        .font(theme.font.body)
                } footer: {
                    Text("保存到\(line.title)的 App 柯味语录，连同前文作为说话方式的参考。")
                }
                if let error { Text(error).font(theme.font.caption) }
            }
            .navigationTitle("收进 App 柯味语录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中" : "收下") {
                        guard let id = message.serverID else { return }
                        saving = true
                        Task {
                            do {
                                try await APIClient(baseURL: line.apiBaseURL).saveAppQuote(messageID: id, note: note)
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                            saving = false
                        }
                    }.disabled(saving || note.count > 1000)
                }
            }
        }
        .tint(theme.effectiveAccent)
        .interactiveDismissDisabled(saving)
    }
}

struct AppQuotesView: View {
    @EnvironmentObject private var theme: Theme
    let line: ChatLine
    @State private var quotes: [AppQuote] = []
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        List {
            Section {
                Text("在聊天里长按你喜欢的回复，选择“收进 App 柯味语录”。")
                    .font(theme.font.body)
                Text("\(line.title) · 已收下 \(quotes.count) 条")
                    .font(theme.font.caption)
            }
            if loading { ProgressView() }
            if let error {
                Text(error)
                Button("重试") { Task { await load() } }
            }
            ForEach(quotes) { quote in
                VStack(alignment: .leading, spacing: theme.metric.gapS) {
                    Text(quote.text).font(theme.font.body).textSelection(.enabled)
                    if !quote.note.isEmpty { Text(quote.note).font(theme.font.caption) }
                    Text(quote.created_at).font(theme.font.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
                .swipeActions {
                    Button("移出语录", role: .destructive) {
                        Task {
                            do {
                                try await APIClient(baseURL: line.apiBaseURL).removeAppQuote(id: quote.id)
                                await load()
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                }
            }
        }
        .navigationTitle("App 柯味语录")
        .tint(theme.effectiveAccent)
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        do {
            quotes = try await APIClient(baseURL: line.apiBaseURL).appQuotes().quotes
            error = nil
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}
