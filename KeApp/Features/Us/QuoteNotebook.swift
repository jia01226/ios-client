import SwiftUI
import CryptoKit

struct NotebookPage: Identifiable, Codable, Equatable {
    let id: String
    let text: String
    let speaker: String
    let spokenAt: Date
    var mood: String
}

@MainActor
final class QuoteNotebook: ObservableObject {
    static let shared = QuoteNotebook()
    @Published private(set) var pages: [NotebookPage]
    private let defaults: UserDefaults
    private let key = "us.quote-notebook.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pages = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([NotebookPage].self, from: $0) } ?? []
    }

    func collect(_ message: Message, text: String? = nil) {
        let quote = text ?? message.text
        let digest = SHA256.hash(data: Data(quote.utf8)).map { String(format: "%02x", $0) }.joined()
        let id = message.id + ":" + digest
        guard !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !pages.contains(where: { $0.id == id }) else { return }
        pages.insert(NotebookPage(id: id, text: quote,
                                  speaker: message.sender == .ke ? "柯" : "佳佳",
                                  spokenAt: message.time, mood: ""), at: 0)
        persist()
    }

    func writeMood(_ mood: String, for id: String) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[index].mood = mood
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pages) else { return }
        defaults.set(data, forKey: key)
    }
}

struct QuoteNotebookView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var notebook = QuoteNotebook.shared

    var body: some View {
        Group {
            if notebook.pages.isEmpty {
                ContentUnavailableView("还没有收进来的话", systemImage: "book.closed",
                                       description: Text("长按聊天里的话，选“收进本子”。这里一页收一句。"))
            } else {
                TabView {
                    ForEach(notebook.pages) { page in
                        ScrollView {
                            VStack(alignment: .leading, spacing: theme.metric.gapL) {
                                Text(page.text).font(theme.font.journalQuote).textSelection(.enabled)
                                Text("\(page.speaker) · \(page.spokenAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary)
                                Divider().overlay(theme.pageColor.separator)
                                TextField("留一行心情…", text: Binding(
                                    get: { notebook.pages.first(where: { $0.id == page.id })?.mood ?? "" },
                                    set: { notebook.writeMood($0, for: page.id) }
                                ), axis: .vertical)
                                .font(theme.font.journalBody)
                            }
                            .padding(theme.metric.pagePadding)
                        }
                        .tag(page.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }
        }
        .foregroundStyle(theme.pageColor.textPrimary)
        .background(theme.pageBackground.ignoresSafeArea())
        .navigationTitle("小本子")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("返回") { dismiss() } } }
    }
}
