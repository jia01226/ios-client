import SwiftUI

struct TimeRecordEditor: View {
    let line: ChatLine
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var kind: TimeEventKind = .shift
    @State private var shift = ""
    @State private var note = ""
    @State private var saving = false
    @State private var error: String?
    @State private var operationID = UUID().uuidString

    init(line: ChatLine, date: Date) { self.line = line; _date = State(initialValue: date) }

    var body: some View {
        NavigationStack {
            Form {
                Picker("记录类型", selection: $kind) {
                    Text("排班").tag(TimeEventKind.shift)
                    Text("生理期开始").tag(TimeEventKind.period)
                    Text("亲密记录").tag(TimeEventKind.intimate)
                }
                DatePicker("日期", selection: $date, displayedComponents: .date)
                    .environment(\.timeZone, CompanionDate.calendar.timeZone)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                if kind == .shift { TextField("班次，例如早班", text: $shift) }
                TextField("备注", text: $note, axis: .vertical).lineLimit(3...8)
                if let error { Text(error) }
            }
            .navigationTitle("添加日期记录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中" : "保存") { Task { await save() } }
                        .disabled(saving || (kind == .shift && shift.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
            .interactiveDismissDisabled(saving)
        }
    }

    @MainActor private func save() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = CompanionDate.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let key = formatter.string(from: date)
        let api = APIClient(baseURL: line.apiBaseURL)
        do {
            switch kind {
            case .shift: try await api.setShift(date: key, shift: shift, note: note)
            case .period: try await api.addPeriod(startDate: key, note: note)
            case .intimate: try await api.savePrivateRecord(date: key, note: note, operationID: operationID)
            case .reminder: return
            }
            dismiss()
        } catch { self.error = "没有保存成功，内容已保留，请重试。" }
    }
}
