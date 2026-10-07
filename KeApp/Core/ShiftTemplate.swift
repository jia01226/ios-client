import Foundation

struct ShiftTemplate: Codable, Equatable, Identifiable {
    let id: ShiftDay.Kind
    var name: String
    var archived = false

    static func initial() -> [ShiftTemplate] {
        [.init(id: .normal, name: "正常班"), .init(id: .early, name: "早班"),
         .init(id: .deputy, name: "副班"), .init(id: .other, name: "其他")]
    }
}
