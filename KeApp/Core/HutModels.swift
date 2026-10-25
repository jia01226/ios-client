import Foundation
import Combine

struct HutID: Decodable, Hashable {
    let value: String
    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if let string = try? box.decode(String.self) { value = string }
        else { value = String(try box.decode(Int.self)) }
    }
}

struct HutOpenItem: Decodable, Identifiable {
    let id: HutID
    let text: String
    let since: String?
    let closed_at: String?
    let note: String?
}

struct HutMemory: Decodable {
    let kind: String?
    let text: String
    let date: String?
    let now: String?
    let hits: Int?
    let recalled_at: String?
}

struct HutFactCategory: Decodable {
    let category: String
    let count: Int
    let items: [HutMemory]
}

struct HutPhoto: Decodable {
    let caption: String
    let said: String?
    let date: String?
}

struct HutWeather: Decodable {
    let facts: Int
    let lines: Int
    let photos: Int
    let open_items: Int
    let recalled_this_week: Int
    let summary: String
}

struct HutLetter: Decodable, Identifiable {
    let id: HutID
    let text: String
    let created_at: String
    let status: String
    let reply: String?
    let replied_at: String?
}

struct RemoteHut: Decodable {
    let open_items: [HutOpenItem]
    let recently_closed: [HutOpenItem]
    let cairn: [HutMemory]
    let polaroids: [HutMemory]
    let fact_book: [HutFactCategory]
    let floe: HutMemory?
    let photos: [HutPhoto]
    let weather: HutWeather
    let letters: [HutLetter]
}

protocol HutAPI {
    func fetchHut() async throws -> RemoteHut
    func sendHutLetter(text: String) async throws
}
extension APIClient: HutAPI {}
