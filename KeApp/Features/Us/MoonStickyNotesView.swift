import SwiftUI

struct MoonStickyNotesView: View {
    @EnvironmentObject private var theme: Theme
    @ObservedObject var store: StickyNotesStore
    @State private var editor = false
    @State private var selected: StickyNote?
    @State private var text = ""
    @State private var allOpen = false
    @State private var editAfterList = false
    private var featured: [StickyNote] {
        let pair = [store.all.first { $0.author == .user }, store.all.first { $0.author == .ai }].compactMap { $0 }
        return pair.count == 2 ? pair : Array(store.all.prefix(2))
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 8) {
                Spacer()
                Button("便利贴") { allOpen = true }.font(Moonlight.serif(13))
                    .accessibilityIdentifier("notes-all")
                Button { selected = nil; text = ""; editor = true } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .ultraLight))
                        .frame(width: 34, height: 34).background(theme.pageAccent.opacity(0.6), in: Circle())
                }.frame(minWidth: 44, minHeight: 44).accessibilityLabel("写便利贴").accessibilityIdentifier("notes-add")
            }
            if store.all.isEmpty {
                Button { selected = nil; text = ""; editor = true } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("a little note").font(Moonlight.script(25)).foregroundStyle(theme.pageAccent)
                        Text("随手记一句，留在这里。").font(Moonlight.serif(16))
                    }.frame(maxWidth: .infinity, minHeight: 96, alignment: .leading).padding(20)
                        .background(paper(.user).opacity(0.55), in: NotePaperShape())
                }.accessibilityIdentifier("notes-empty")
            } else {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(featured.enumerated()), id: \.element.id) { index, note in
                        noteCard(note).padding(.top, index == 1 ? 8 : 0)
                    }
                }
            }
        }
        .buttonStyle(.plain).foregroundStyle(theme.pageColor.textPrimary)
        .sheet(isPresented: $editor) { editorView }
        .sheet(isPresented: $allOpen, onDismiss: { if editAfterList { editAfterList = false; editor = true } }) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        if let status = store.status { Text(status).font(Moonlight.serif(13)).foregroundStyle(theme.pageColor.textSecondary) }
                        ForEach(store.all) { note in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(note.author == .user ? "佳佳" : "柯").foregroundStyle(theme.pageAccent)
                                Text(note.content).textSelection(.enabled)
                                if store.isLocal(note) { Text("本机 · 待同步").font(Moonlight.serif(12)) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                                .background(paper(note.author), in: NotePaperShape())
                                .contentShape(Rectangle())
                                .onTapGesture { selected = note; text = note.content; editAfterList = true; allOpen = false }
                                .contextMenu {
                                    if note.author == .user {
                                        Button("编辑") { selected = note; text = note.content; editAfterList = true; allOpen = false }
                                        Button("删除", role: .destructive) { Task { await store.delete(note) } }
                                    }
                                }
                        }
                        if store.all.isEmpty { Text("这里还没有便利贴。") }
                    }.font(Moonlight.serif(17)).padding(24)
                }.background(theme.pageBackground).navigationTitle("便利贴").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("收好") { allOpen = false } } }
                    .refreshable { await store.load() }
            }.tint(theme.pageAccent)
        }
    }
    private func paper(_ author: StickyNote.Author) -> Color {
        theme.skin == .night ? theme.pageColor.card : (author == .user ? Moonlight.rosePaper : Moonlight.lavenderPaper)
    }
    private func noteCard(_ note: StickyNote) -> some View {
        Button {
            selected = note; text = note.content; editor = true
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                Text(note.author == .user ? "佳佳" : "柯").font(Moonlight.serif(14)).foregroundStyle(note.author == .user ? theme.pageAccent : theme.pageColor.textSecondary)
                Rectangle().fill(theme.pageAccent.opacity(0.55)).frame(width: 16, height: 0.5)
                Text(note.content).font(Moonlight.serif(19)).lineSpacing(5).lineLimit(3)
                if store.isLocal(note) { Text("本机 · 待同步").font(Moonlight.serif(10)).foregroundStyle(theme.pageColor.textSecondary) }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading).padding(18)
                .background(paper(note.author).opacity(0.76), in: NotePaperShape())
                .overlay(alignment: .bottomTrailing) {
                    FoldCorner().fill(theme.pageAccent.opacity(0.23)).frame(width: 16, height: 16)
                }
        }.accessibilityIdentifier("note-" + note.id)
    }
    private var editorView: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(selected?.author == .ai ? "柯留下的" : "写给自己").font(Moonlight.script(26))
                    .foregroundStyle(theme.pageAccent)
                if selected?.author == .ai {
                    ScrollView { Text(text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                } else {
                    TextEditor(text: $text).scrollContentBackground(.hidden).accessibilityIdentifier("note-editor")
                }
                if let status = store.status { Text(status).font(Moonlight.serif(12)).foregroundStyle(theme.pageColor.textSecondary) }
            }.font(Moonlight.serif(19)).padding(24).background(theme.pageBackground)
                .navigationTitle("便利贴").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("收起") { editor = false } }
                    if selected?.author != .ai {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("贴好") { Task { await store.save(text, editing: selected); editor = false } }
                                .disabled(store.saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityIdentifier("note-save")
                        }
                    }
                }
        }.tint(theme.pageAccent)
    }
}

private struct NotePaperShape: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: .zero); p.addLine(to: CGPoint(x: r.maxX, y: 0))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 16)); p.addLine(to: CGPoint(x: r.maxX - 16, y: r.maxY))
            p.addLine(to: CGPoint(x: 0, y: r.maxY)); p.closeSubpath()
        }
    }
}
private struct FoldCorner: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: r.maxX, y: 0)); p.addLine(to: CGPoint(x: 0, y: r.maxY)); p.closeSubpath() }
    }
}
