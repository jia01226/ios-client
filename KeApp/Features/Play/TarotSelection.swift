import Foundation

/// Keep opaque deal IDs in their original wire type, including older numeric IDs.
enum TarotDealID: Codable, Equatable, Sendable {
    case text(String)
    case number(Int)
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let text = try? value.decode(String.self) { self = .text(text) }
        else { self = .number(try value.decode(Int.self)) }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self { case .text(let id): try value.encode(id); case .number(let id): try value.encode(id) }
    }
}

struct TarotDeal: Decodable, Sendable {
    let deal_id: TarotDealID
    let deck_size: Int
    let spread: String
    let spread_name: String
    let positions: [String]
    var isValid: Bool {
        deck_size == 78 && positions.count == ["one": 1, "three": 3, "celtic": 10][spread]
            && positions.allSatisfy { !$0.isEmpty }
    }
}

struct TarotPickRequest: Encodable {
    let deal_id: TarotDealID
    let picks: [Int]
}

/// Selection order is the server's position order. Previewing never adds a pick.
struct TarotSelection: Equatable {
    let deckSize: Int
    let requiredCount: Int
    private(set) var picks: [Int] = []
    private(set) var preview: Int?
    private(set) var submitted = false
    var isFull: Bool { picks.count == requiredCount }

    mutating func tap(_ index: Int) {
        guard !submitted, !isFull, (0..<deckSize).contains(index), !picks.contains(index) else { return }
        if preview == index { picks.append(index); preview = nil }
        else { preview = index }
    }
    mutating func previewCard(_ index: Int) {
        guard !submitted, !isFull, (0..<deckSize).contains(index), !picks.contains(index) else { return }
        preview = index
    }
    mutating func returnCard(_ index: Int) {
        guard !submitted else { return }
        picks.removeAll { $0 == index }
        preview = nil
    }
    /// A timed-out POST may already have succeeded. Freeze the exact request for retries.
    mutating func freeze() -> Bool {
        guard isFull else { return false }
        submitted = true; preview = nil
        return true
    }
}
