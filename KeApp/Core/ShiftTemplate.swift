import Foundation

struct ShiftTemplate: Codable, Equatable, Identifiable {
    let id: ShiftDay.Kind
    var name: String
    var archived = false

    static func initial() -> [ShiftTemplate] {
        // 11-25 她定的四种：开会一般 8:30–12；「其他」时间不确定，柯会去问她
        // 顺序她定的：早班 / 副班 / 开会 / 其他
        [.init(id: .early, name: "早班"), .init(id: .deputy, name: "副班"),
         .init(id: .normal, name: "开会"), .init(id: .other, name: "其他")]
    }

    /// 本机存过的模板也按她定的顺序摆（旧版存的是开会在前）
    static func ordered(_ list: [ShiftTemplate]) -> [ShiftTemplate] {
        let rank: [ShiftDay.Kind] = initial().map(\.id)
        return list.enumerated().sorted { a, b in
            let ra = rank.firstIndex(of: a.element.id) ?? rank.count
            let rb = rank.firstIndex(of: b.element.id) ?? rank.count
            return ra == rb ? a.offset < b.offset : ra < rb
        }.map(\.element)
    }
}
