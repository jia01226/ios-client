import SwiftUI

struct PeriodQuickActions: View {
    @EnvironmentObject private var theme: Theme
    @ObservedObject var store: PeriodStore
    @State private var history = false
    var body: some View {
        VStack(alignment: .leading, spacing: JournalLayout.smallGap) {
            HStack {
                Button { history = true } label: { Label("经期", systemImage: "drop").font(theme.font.journalBody) }
                    .accessibilityIdentifier("period-history")
                Spacer()
                Button("来了") { Task { await store.start() } }.disabled(!store.canStart)
                    .accessibilityIdentifier("period-start")
                Button("走了") { Task { await store.finish() } }.disabled(!store.canEnd)
                    .accessibilityIdentifier("period-end")
            }
            .buttonStyle(.bordered).tint(theme.pageAccent)
            Text(store.summary).font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary)
            if let error = store.error {
                Button(error) { Task { await store.load() } }.font(theme.font.journalCaption)
            }
            if let status = store.status { Text(status).font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary) }
        }
        .sheet(isPresented: $history) { PeriodHistoryView(store: store) }
    }
}

/// Compact month-header controls retain direct start/end recording and the history sheet.
struct PeriodCalendarControls: View {
    @EnvironmentObject private var theme: Theme
    @ObservedObject var store: PeriodStore
    @State private var history = false
    var body: some View {
        HStack(spacing: 2) {
            Button { history = true } label: {
                Image(systemName: "drop").font(.system(size: 12, weight: .ultraLight)).frame(width: 44, height: 44)
            }.accessibilityLabel("经期记录").accessibilityValue(store.summary).accessibilityIdentifier("period-history")
            Button { Task { await store.start() } } label: { actionLabel("来了", available: store.canStart) }
                .disabled(!store.canStart).accessibilityIdentifier("period-start")
            Button { Task { await store.finish() } } label: { actionLabel("走了", available: store.canEnd) }
                .disabled(!store.canEnd).accessibilityIdentifier("period-end")
        }.buttonStyle(.plain).foregroundStyle(theme.pageAccent)
            .sheet(isPresented: $history) { PeriodHistoryView(store: store) }
    }
    private func actionLabel(_ title: String, available: Bool) -> some View {
        Text(title).font(Moonlight.serif(12)).frame(width: 42, height: 25)
            .overlay(Capsule().stroke(theme.pageAccent.opacity(available ? 0.6 : 0.25), lineWidth: 0.6))
            .opacity(available ? 1 : 0.45).frame(width: 44, height: 44).contentShape(Rectangle())
    }
}

private struct PeriodHistoryView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PeriodStore
    @State private var deleting: RemotePeriod?
    var body: some View {
        NavigationStack {
            List {
                if !store.pendingEnds.isEmpty {
                    Section {
                        Text("结束日期已保存在手机里，尚未同步给柯。")
                        Button("重试同步结束日期") { Task { await store.syncEnds() } }.disabled(store.saving)
                    }
                }
                if let status = store.status { Text(status) }
                if let error = store.error { Button(error) { Task { await store.load() } } }
                ForEach(store.records.sorted { $0.start_date > $1.start_date }) { record in
                    VStack(alignment: .leading, spacing: JournalLayout.smallGap) {
                        Text(record.start_date + " 来了")
                        if let end = store.pendingEnds[record.id] ?? record.end_date {
                            Text(end + (store.pendingEnds[record.id] == nil ? " 走了" : " 走了 · 待同步"))
                                .foregroundStyle(theme.pageColor.textSecondary)
                        }
                        if let note = record.note, !note.isEmpty { Text(note).font(theme.font.journalCaption) }
                    }.swipeActions { Button("删除记录", role: .destructive) { deleting = record } }
                }
                if store.loaded && store.records.isEmpty { Text("还没有经期记录。") }
            }
            .scrollContentBackground(.hidden).background(theme.pageBackground)
            .tint(theme.pageAccent).font(theme.font.journalBody)
            .navigationTitle("经期记录").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .refreshable { await store.load() }
            .confirmationDialog("删除这条经期记录？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                if let record = deleting { Button("删除记录", role: .destructive) { Task { await store.delete(record) }; deleting = nil } }
                Button("保留", role: .cancel) { deleting = nil }
            }
        }
    }
}
