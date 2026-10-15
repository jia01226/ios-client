import Foundation
import Combine

/// The only source of drawable flowers. Background artwork must contain no flowers.
struct MemoryFlower: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let body: String
    let quotes: [String]
    let occurred_at: String?
    let written_at: String?
    let category: String
    let importance: Int
    let valence: Double
    let last_recalled_at: String?
    let recall_count: Int
    var state: String
    let author: String
    var loved: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, body, quotes, occurred_at, written_at, category, importance, valence
        case last_recalled_at, recall_count, state, author, loved
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let string = try? c.decode(String.self, forKey: .id) { id = string }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
        title = try c.decode(String.self, forKey: .title)
        body = try c.decode(String.self, forKey: .body)
        quotes = try c.decodeIfPresent([String].self, forKey: .quotes) ?? []
        occurred_at = try c.decodeIfPresent(String.self, forKey: .occurred_at)
        written_at = try c.decodeIfPresent(String.self, forKey: .written_at)
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "未分类"
        importance = min(10, max(1, try c.decodeIfPresent(Int.self, forKey: .importance) ?? 1))
        valence = min(1, max(0, try c.decodeIfPresent(Double.self, forKey: .valence) ?? 0.5))
        last_recalled_at = try c.decodeIfPresent(String.self, forKey: .last_recalled_at)
        recall_count = try c.decodeIfPresent(Int.self, forKey: .recall_count) ?? 0
        state = try c.decode(String.self, forKey: .state)
        author = try c.decode(String.self, forKey: .author)
        loved = try c.decodeIfPresent(Bool.self, forKey: .loved) ?? false
    }
    var isDrawable: Bool { ["bloom", "bud", "fallen"].contains(state) }
}

struct MemoryGardenPage: Decodable, Sendable {
    let categories: [String]
    let flowers: [MemoryFlower]
}

enum MemoryScene: String, CaseIterable {
    case moon = "MemoryMoon", water = "MemoryWater", castle = "MemoryCastle"
    case courtyard = "MemoryCourtyard", glasshouse = "MemoryGlasshouse"
    static func forCategory(_ category: String) -> Self {
        switch category {
        case "约定": .moon
        case "关系", "恋爱": .water
        case "生活": .castle
        case "身体", "医疗": .courtyard
        case "喜好": .glasshouse
        default: .courtyard
        }
    }
    var title: String {
        switch self {
        case .moon: "月下山茶"
        case .water: "水边山茶"
        case .castle: "山茶城堡"
        case .courtyard: "山茶庭院"
        case .glasshouse: "玻璃花房"
        }
    }
}

protocol MemoryGardenAPI: Sendable {
    func memoryGarden() async throws -> MemoryGardenPage
    func changeMemoryFlower(id: String, action: String, note: String?, loved: Bool?) async throws
}
extension APIClient: MemoryGardenAPI {}

@MainActor final class MemoryGardenStore: ObservableObject {
    @Published private(set) var flowers: [MemoryFlower] = []
    @Published private(set) var categories = ["约定", "关系", "生活", "身体", "喜好"]
    @Published private(set) var loading = false
    @Published private(set) var loaded = false
    @Published private(set) var busy = false
    @Published var error: String?
    private let api: any MemoryGardenAPI
    /// 107：点开记忆不再转圈——上次拿到的先摆上，后台再刷新
    private static var cache: (flowers: [MemoryFlower], categories: [String])?
    init(api: any MemoryGardenAPI) {
        self.api = api
        if let c = Self.cache { flowers = c.flowers; categories = c.categories; loaded = true }
    }

    func visible(includeOthers: Bool, category: String? = nil) -> [MemoryFlower] {
        flowers.filter { $0.isDrawable && (includeOthers || $0.author == "ke") && (category == nil || $0.category == category) }
    }
    func load() async {
        guard !loading, !busy else { return }
        loading = true
        defer { loading = false }
        do { try await refresh(); error = nil }
        catch { self.error = "花园暂时没有同步成功。请重试，已有内容不会被清空。" }
    }
    private func refresh() async throws {
        let page = try await api.memoryGarden()
        // Duplicate IDs cannot create extra flowers or ambiguous tap targets.
        var seen = Set<String>()
        flowers = page.flowers.filter { seen.insert($0.id).inserted }
        var categorySeen = Set<String>()
        categories = (["约定", "关系", "生活", "身体", "喜好"] + page.categories + flowers.map(\.category))
            .filter { categorySeen.insert($0).inserted }
        loaded = true
        Self.cache = (flowers, categories)
    }
    @discardableResult func change(_ flower: MemoryFlower, action: String, note: String? = nil) async -> Bool {
        guard !busy, !loading else { return false }
        busy = true
        defer { busy = false }
        do {
            try await api.changeMemoryFlower(id: flower.id, action: action, note: note,
                                             loved: action == "love" ? !flower.loved : nil)
            // Only change local presentation after the server accepted the operation.
            if let index = flowers.firstIndex(where: { $0.id == flower.id }) {
                if action == "wither" { flowers[index].state = "withered" }
                if action == "love" { flowers[index].loved.toggle() }
            }
            do { try await refresh(); error = nil }
            catch { self.error = "操作已保存，花园还没刷新成功。请稍后重试。" }
            return true
        } catch {
            self.error = "没有保存成功，花还保持原样。请重试。"
            return false
        }
    }
}
