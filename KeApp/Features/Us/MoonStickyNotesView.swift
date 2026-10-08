import SwiftUI

struct MoonStickyNotesView: View {
    @EnvironmentObject private var theme: Theme
    @ObservedObject var store: StickyNotesStore
    var showsEmptyPaper = true
    var drawerMode = false
    @State private var trayPage = 0
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
        Group {
        if drawerMode { drawerBody } else {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if theme.skin != .day { Spacer() }
                Button("便利贴") { allOpen = true }.font(Moonlight.serif(theme.skin == .day ? 17 : 13))
                    .accessibilityIdentifier("notes-all")
                Button { selected = nil; text = ""; editor = true } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .ultraLight))
                        .frame(width: 34, height: 34).background(theme.pageAccent.opacity(0.6), in: Circle())
                }.frame(minWidth: 44, minHeight: 44).accessibilityLabel("写便利贴").accessibilityIdentifier("notes-add")
                if theme.skin == .day { Spacer() }
            }
            if store.all.isEmpty && showsEmptyPaper {
                Button { selected = nil; text = ""; editor = true } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("a little note").font(Moonlight.script(25)).foregroundStyle(theme.pageAccent)
                        Text("随手记一句，留在这里。").font(Moonlight.serif(16))
                    }.frame(maxWidth: .infinity, minHeight: 96, alignment: .leading).padding(20)
                        .background(paper(.user).opacity(0.55), in: NotePaperShape())
                }.accessibilityIdentifier("notes-empty")
            } else {
                HStack(alignment: .top, spacing: theme.skin == .day ? 20 : 14) {
                    ForEach(Array(featured.enumerated()), id: \.element.id) { index, note in
                        noteCard(note).padding(.top, index == 1 ? 8 : 0)
                    }
                }
            }
        }
        }
        }
        .buttonStyle(.plain).foregroundStyle(theme.pageColor.textPrimary)
        .sheet(isPresented: Binding(get: { editor && !drawerMode }, set: { editor = $0 })) { editorView }
        .fullScreenCover(isPresented: Binding(get: { editor && drawerMode }, set: { editor = $0 })) { drawerPaperReader }
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
    private var trayPageCount: Int { max(1, (store.all.count + 1) / 2) }
    private var drawerBody: some View {
        VStack(spacing: 12) {
            HStack {
                Text("little notes").font(Moonlight.script(32)).foregroundStyle(theme.pageAccent)
                Spacer()
                Button { selected = nil; text = ""; editor = true } label: {
                    Image(systemName: "plus").font(.system(size: 21, weight: .ultraLight)).frame(width: 44, height: 44)
                }.accessibilityLabel("写便利贴").accessibilityIdentifier("notes-add")
            }
            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    Image("KeepsakeNotesInterior").resizable().scaledToFit()
                        .colorMultiply(KeepsakeTheme.artworkTint(night: theme.skin == .night))
                        .accessibilityHidden(true).allowsHitTesting(false)
                    if store.all.isEmpty {
                        Text("还没有纸条，点右上角写一张。")
                            .font(Moonlight.serif(14)).foregroundStyle(KeepsakeTheme.paperInk)
                            .frame(width: g.size.width * 0.70, height: g.size.height * 0.38)
                            .position(x: g.size.width * 0.5, y: g.size.height * 0.48)
                            .accessibilityIdentifier("drawer-notes-empty")
                    } else {
                        TabView(selection: $trayPage) {
                            ForEach(0..<trayPageCount, id: \.self) { page in
                                let pair = Array(store.all.dropFirst(page * 2).prefix(2))
                                ZStack(alignment: .topLeading) {
                                    ForEach(Array(pair.enumerated()), id: \.element.id) { index, note in
                                        noteCard(note)
                                            .frame(width: g.size.width * 0.43, height: g.size.height * 0.42)
                                            .rotationEffect(.degrees(index == 0 ? -7 : 6))
                                            .shadow(color: KeepsakeTheme.shadow.opacity(0.14), radius: 3, y: 3)
                                            .position(x: g.size.width * (pair.count == 1 ? 0.42 : (index == 0 ? 0.28 : 0.58)),
                                                      y: g.size.height * (pair.count == 1 ? 0.39 : (index == 0 ? 0.24 : 0.51)))
                                            .zIndex(Double(index))
                                    }
                                }.frame(width: g.size.width * 0.84, height: g.size.height * 0.78).tag(page)
                            }
                        }.tabViewStyle(.page(indexDisplayMode: .never))
                            .frame(width: g.size.width * 0.84, height: g.size.height * 0.78)
                            .position(x: g.size.width * 0.5, y: g.size.height * 0.49)
                    }
                }
            }.aspectRatio(1, contentMode: .fit)
                .accessibilityElement(children: .contain).accessibilityIdentifier("drawer-notes-interior")
            if trayPageCount > 1 {
                HStack(spacing: 24) {
                    Button { trayPage = max(0, trayPage - 1) } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    }.disabled(trayPage == 0).accessibilityLabel("前两张便利贴")
                    Text("\(trayPage + 1) / \(trayPageCount)").font(Moonlight.serif(14))
                    Button { trayPage = min(trayPageCount - 1, trayPage + 1) } label: {
                        Image(systemName: "chevron.right").frame(width: 44, height: 44)
                    }.disabled(trayPage == trayPageCount - 1).accessibilityLabel("后两张便利贴")
                }
            }
            Text("点一张纸条，拿起来看。")
                .font(Moonlight.serif(13)).foregroundStyle(theme.pageColor.textSecondary)
        }.onChange(of: store.all.count) { _, _ in trayPage = min(trayPage, trayPageCount - 1) }
    }

    private var drawerPaperReader: some View {
        VStack(spacing: 22) {
            HStack {
                Button("放回去") { editor = false }.frame(minWidth: 60, minHeight: 44)
                    .accessibilityIdentifier("drawer-note-put-back")
                Spacer()
                if selected?.author != .ai {
                    Button("贴好") { Task { await store.save(text, editing: selected); editor = false } }
                        .frame(minWidth: 60, minHeight: 44)
                        .disabled(store.saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("note-save")
                }
            }.font(Moonlight.serif(17)).foregroundStyle(theme.pageAccent)
            VStack(alignment: .leading, spacing: 22) {
                Text("little notes").font(Moonlight.script(34)).foregroundStyle(KeepsakeTheme.signature)
                Text(selected?.author == .ai ? "柯留下的" : "佳佳的便利贴").font(Moonlight.serif(15))
                if selected?.author == .ai {
                    ScrollView { Text(text).font(Moonlight.serif(22)).lineSpacing(10)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        .accessibilityIdentifier("drawer-note-content") }
                } else {
                    TextEditor(text: $text).font(Moonlight.serif(22)).scrollContentBackground(.hidden)
                        .accessibilityIdentifier("note-editor")
                }
                if let status = store.status {
                    Text(status).font(Moonlight.serif(12))
                }
            }.foregroundStyle(KeepsakeTheme.paperInk).padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(paper(selected?.author ?? .user), in: NotePaperShape())
                .overlay(alignment: .bottomTrailing) { FoldCorner().fill(theme.pageAccent.opacity(0.23)).frame(width: 16, height: 16) }
                .shadow(color: KeepsakeTheme.shadow.opacity(0.12), radius: 18, y: 8)
                .accessibilityElement(children: .contain).accessibilityIdentifier("drawer-note-lifted")
        }.padding(.horizontal, 26).padding(.top, 12).padding(.bottom, 35)
            .background(theme.pageBackground.ignoresSafeArea()).buttonStyle(.plain)
    }

    private func paper(_ author: StickyNote.Author) -> Color {
        theme.skin == .night && !drawerMode ? theme.pageColor.card : (author == .user ? Moonlight.rosePaper : Moonlight.lavenderPaper)
    }
    private func noteCard(_ note: StickyNote) -> some View {
        Button {
            selected = note; text = note.content; editor = true
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                Text(note.author == .user ? "佳佳" : "柯").font(Moonlight.serif(14)).foregroundStyle(drawerMode ? (note.author == .user ? KeepsakeTheme.signature : KeepsakeTheme.paperMutedInk) : (note.author == .user ? theme.pageAccent : theme.pageColor.textSecondary))
                Rectangle().fill(theme.pageAccent.opacity(0.55)).frame(width: 16, height: 0.5)
                Text(note.content).font(Moonlight.serif(drawerMode ? 15 : 17)).lineSpacing(4).lineLimit(2)
                if store.isLocal(note) { Text("本机 · 待同步").font(Moonlight.serif(10)).foregroundStyle(theme.pageColor.textSecondary) }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, minHeight: drawerMode ? 88 : (theme.skin == .day ? 128 : 95), alignment: .topLeading).padding(drawerMode ? 12 : 16)
                .background(paper(note.author).opacity(drawerMode ? 1 : 0.76), in: NotePaperShape())
                .overlay(alignment: .bottomTrailing) {
                    FoldCorner().fill(theme.pageAccent.opacity(0.23)).frame(width: 16, height: 16)
                }
        }.foregroundStyle(drawerMode ? KeepsakeTheme.paperInk : theme.pageColor.textPrimary)
            .accessibilityIdentifier("note-" + note.id)
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
