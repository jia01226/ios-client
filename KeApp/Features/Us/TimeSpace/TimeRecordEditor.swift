import SwiftUI

struct TimeRecordEditor: View {
    let line: ChatLine
    @Environment(\.dismiss) private var dismiss
    @State private var shift: String
    @State private var saving = false
    @State private var error: String?
    private let date: Date
    private let currentNote: String
    private let options = ["早班", "副班", "上夜", "下夜", "睡班", "早班+睡班", "早班+上夜"]
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    init(line: ChatLine, date: Date, currentShift: String?, currentNote: String = "") {
        self.line = line
        self.date = date
        self.currentNote = currentNote
        _shift = State(initialValue: Self.normalized(currentShift ?? ""))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("给 \(dateText) 排班")
                    .font(.custom("NotoSerifSC-Regular", size: 18, relativeTo: .headline))
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            shift = option
                        } label: {
                            Text(short(option))
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(shift == option ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08), in: Capsule())
                                .overlay(Capsule().stroke(shift == option ? Color.accentColor : Color.clear, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("shift-option-\(option)")
                        .accessibilityAddTraits(shift == option ? .isSelected : [])
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                if !shift.isEmpty {
                    Button("清除这天排班", role: .destructive) { Task { await save(clear: true) } }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(24)
            .navigationTitle("排班")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中" : "保存") { Task { await save(clear: false) } }
                        .disabled(saving || shift.isEmpty)
                }
            }
            .interactiveDismissDisabled(saving)
        }
        .presentationDetents([.height(390)])
        .presentationDragIndicator(.visible)
    }

    @MainActor private func save(clear: Bool) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        let api = APIClient(baseURL: line.apiBaseURL)
        do {
            if clear { try await api.deleteShift(date: dateKey) }
            else { try await api.setShift(date: dateKey, shift: shift, note: currentNote) }
            dismiss()
        } catch { self.error = "没有保存成功，请重试。" }
    }

    private var dateKey: String { formatted("yyyy-MM-dd") }
    private var dateText: String { formatted("M月d日") }
    private func formatted(_ template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = CompanionDate.calendar.timeZone
        formatter.dateFormat = template
        return formatter.string(from: date)
    }
    private func short(_ value: String) -> String { value.replacingOccurrences(of: "早班+", with: "早+") }
    private static func normalized(_ value: String) -> String {
        switch value {
        case "夜班": return "上夜"
        case "早班+夜班": return "早班+上夜"
        default: return value
        }
    }
}
