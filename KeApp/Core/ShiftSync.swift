import Foundation

protocol ShiftAPI: Sendable {
    func fetchShifts() async throws -> [RemoteShift]
    func setShift(date: String, shift: String, note: String) async throws
    func deleteShift(date: String) async throws
}

extension APIClient: ShiftAPI {}

struct PendingShiftChange: Codable, Equatable {
    let revision: UUID
    let shift: String?
    let note: String
    init(shift: String?, note: String = "") {
        revision = UUID(); self.shift = shift; self.note = note
    }
}

/// Human-readable times travel through the existing shift-note API and enter Ke's context.
enum ShiftNote {
    private static let prefix = "上班时间："
    static func encode(plan: ShiftPlan?, note: String?, dayOverride: Bool = false) -> String {
        var lines: [String] = []
        if let plan {
            lines.append(prefix + plan.timeSummary)
            lines.append(dayOverride ? "范围：当天单独调整" : "范围：班次默认时间")
            lines.append("时间按手机当地时区（\(TimeZone.current.identifier)），以本条记录为准。")
        }
        if let note, !note.isEmpty { lines.append("备注：" + note) }
        return lines.joined(separator: "\n")
    }
    static func plan(from note: String) -> ShiftPlan? {
        guard let line = note.components(separatedBy: "\n").first, line.hasPrefix(prefix) else { return nil }
        let pairs = String(line.dropFirst(prefix.count)).components(separatedBy: "、")
        guard (1...2).contains(pairs.count) else { return nil }
        var periods: [ShiftPeriod] = []
        for pair in pairs {
            let clocks = pair.components(separatedBy: "-")
            guard clocks.count == 2 else { return nil }
            let times = clocks.compactMap { clock -> Int? in
                let fields = clock.components(separatedBy: ":")
                guard fields.count == 2, let h = Int(fields[0]), let m = Int(fields[1]),
                      (0..<24).contains(h), (0..<60).contains(m) else { return nil }
                return h * 60 + m
            }
            guard times.count == 2 else { return nil }
            periods.append(ShiftPeriod(startMinutes: times[0], endMinutes: times[1]))
        }
        let plan = ShiftPlan(periods: periods)
        return plan.resolve(on: .now) == nil ? nil : plan
    }
    static func userNote(from note: String) -> String? {
        guard note.hasPrefix(prefix) else { return note.isEmpty ? nil : note }
        guard let range = note.range(of: "\n备注：") else { return nil }
        return String(note[range.upperBound...])
    }
}
