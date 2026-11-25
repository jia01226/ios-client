import Foundation

struct ShiftTemplate: Codable, Equatable, Identifiable {
    let id: ShiftDay.Kind
    var name: String
    var archived = false

    static func initial() -> [ShiftTemplate] {
        // 11-25 她定的四种：开会一般 8:30–12；「其他」时间不确定，柯会去问她
        [.init(id: .normal, name: "开会"), .init(id: .early, name: "早班"),
         .init(id: .deputy, name: "副班"), .init(id: .other, name: "其他")]
    }
}
