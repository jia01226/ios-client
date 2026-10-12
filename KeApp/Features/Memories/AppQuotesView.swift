import SwiftUI

struct AppQuote: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    let message_id: Int
    let text: String
    let note: String
    let scene: String
    let created_at: String
}
struct AppQuotePage: Decodable, Sendable { let quotes: [AppQuote] }

struct AppQuoteSaveView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    let line: ChatLine
    let message: Message
    @ObservedObject private var store: AppQuotesStore
    @State private var note = ""
    init(line: ChatLine, message: Message) {
        self.line = line; self.message = message
        store = .shared(line: line)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("柯的原话") { Text(message.text).textSelection(.enabled) }
                Section {
                    TextField("写一点备注，也可以留空", text: $note, axis: .vertical)
                        .accessibilityIdentifier("quote-note")
                } footer: { Text("\(note.count) / 1000 字") }
                if let error = store.error { Text(error).foregroundStyle(.secondary) }
            }
            .navigationTitle("收进语录").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.saving ? "保存中" : "收下") {
                        Task { if await store.save(message: message, note: note) { dismiss() } }
                    }.disabled(store.saving || store.loading || note.count > 1000 || !message.canSaveQuote)
                        .accessibilityIdentifier("quote-save")
                }
            }
        }.tint(theme.pageAccent).interactiveDismissDisabled(store.saving)
    }
}

struct AppQuotesView: View {
    @EnvironmentObject private var theme: Theme
    @ObservedObject private var store: AppQuotesStore
    var onOpen: ((AppQuote) -> Void)?
    @State private var bedroomExpanded = false
    @State private var removing: AppQuote?
    init(line: ChatLine, onOpen: ((AppQuote) -> Void)? = nil) {
        store = .shared(line: line); self.onOpen = onOpen
    }
    var body: some View {
        List {
            Section {
                Text("长按柯已发完的消息，把喜欢的原话收在这里。")
                    .font(.subheadline).foregroundStyle(.secondary)
                if store.loading { ProgressView("正在同步语录") }
                if let error = store.error {
                    Text(error)
                    Button("重新同步") { Task { await store.load() } }
                }
            }.listRowBackground(Color.clear)
            Section("日常") {
                let daily = store.quotes.filter { $0.scene != "bedroom" }
                if daily.isEmpty && !store.loading { Text("收下的日常原话会留在这里。").foregroundStyle(.secondary) }
                ForEach(daily) { quote in paper(quote) }
            }
            Section {
                DisclosureGroup("床上", isExpanded: $bedroomExpanded) {
                    let privateQuotes = store.quotes.filter { $0.scene == "bedroom" }
                    if privateQuotes.isEmpty { Text("还没有收下的原话。").foregroundStyle(.secondary) }
                    ForEach(privateQuotes) { quote in paper(quote) }
                }.accessibilityIdentifier("quotes-bedroom")
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.pageBackground)
        .navigationTitle("语录").tint(theme.pageAccent)
        .task { await store.load() }.refreshable { await store.load() }
        .alert("从语录拿掉？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("取消", role: .cancel) { removing = nil }
            Button("拿掉", role: .destructive) {
                if let quote = removing { Task { await store.remove(quote) } }
                removing = nil
            }
        } message: { Text("只取消收藏，不会删除聊天中的原话。") }
    }
    private func paper(_ quote: AppQuote) -> some View {
        Button { onOpen?(quote) } label: {
            VStack(alignment: .leading, spacing: 14) {
                Text(quote.text).font(.custom("NotoSerifSC-ExtraLight", size: 17, relativeTo: .body)).lineSpacing(6)
                if !quote.note.isEmpty { Text(quote.note).font(.subheadline).foregroundStyle(.secondary) }
                HStack {
                    Text(quote.created_at).font(.caption)
                    Spacer()
                    if onOpen != nil { Image(systemName: "arrow.up.backward").accessibilityLabel("回到这条聊天") }
                }.foregroundStyle(.secondary)
            }.padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain)
            .accessibilityIdentifier("quote-\(quote.id)")
            .listRowBackground(theme.skin == .night ? Color.white.opacity(0.05) : Color(red: 0.98, green: 0.97, blue: 0.96))
            .swipeActions(allowsFullSwipe: false) {
                Button("移出语录", role: .destructive) { removing = quote }.disabled(store.saving)
            }
    }
}
