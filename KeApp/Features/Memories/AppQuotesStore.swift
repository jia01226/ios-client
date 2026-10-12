import Foundation
import Combine

protocol AppQuotesAPI: Sendable {
    func appQuotes() async throws -> AppQuotePage
    func saveAppQuote(messageID: Int, note: String) async throws
    func removeAppQuote(id: Int) async throws
}
extension APIClient: AppQuotesAPI {}

@MainActor final class AppQuotesStore: ObservableObject {
    private static var stores: [URL: AppQuotesStore] = [:]
    static func shared(line: ChatLine) -> AppQuotesStore {
        if let store = stores[line.apiBaseURL] { return store }
        let store = AppQuotesStore(api: APIClient(baseURL: line.apiBaseURL))
        stores[line.apiBaseURL] = store
        return store
    }
    @Published private(set) var quotes: [AppQuote] = []
    @Published private(set) var loading = false
    @Published private(set) var saving = false
    @Published var error: String?
    private let api: any AppQuotesAPI
    init(api: any AppQuotesAPI) { self.api = api }
    func quote(messageID: Int?) -> AppQuote? { quotes.first { $0.message_id == messageID } }
    func load() async {
        guard !loading, !saving else { return }
        loading = true
        defer { loading = false }
        do { try await refresh(); error = nil }
        catch { self.error = "语录暂时没有同步成功，请重试。" }
    }
    private func refresh() async throws {
        quotes = try await api.appQuotes().quotes.sorted { ($0.created_at, $0.id) > ($1.created_at, $1.id) }
    }
    func save(message: Message, note: String) async -> Bool {
        guard message.canSaveQuote, let id = message.serverID, note.count <= 1000, !saving, !loading else { return false }
        saving = true
        defer { saving = false }
        do {
            try await api.saveAppQuote(messageID: id, note: note)
            do { try await refresh(); error = nil }
            catch { self.error = "已经收下，列表尚未刷新。请重新同步。" }
            return true
        } catch { self.error = "没有收进语录，请重试。"; return false }
    }
    @discardableResult func remove(_ quote: AppQuote) async -> Bool {
        guard !saving, !loading else { return false }
        saving = true
        defer { saving = false }
        do {
            try await api.removeAppQuote(id: quote.id)
            quotes.removeAll { $0.id == quote.id }
            error = nil
            return true
        } catch { self.error = "没有移出语录，原话仍保留着。请重试。"; return false }
    }
}

extension Message {
    var canSaveQuote: Bool { sender == .ke && serverID != nil && !isStreaming && deliveryState == .sent && !text.isEmpty }
}

struct QuoteOpenRequest: Identifiable, Equatable {
    let id = UUID()
    let messageID: Int
}
