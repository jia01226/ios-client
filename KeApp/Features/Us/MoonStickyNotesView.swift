import SwiftUI

struct MoonStickyNotesView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: StickyNotesStore
    var showsEmptyPaper = true
    var drawerMode = false
    @State private var trayPage = 0
    @State private var selected: StickyNote?
    @State private var allOpen = false
    @State private var showsArchived = false
    private var featured: [StickyNote] { Array(store.all.prefix(2)) }

    var body: some View {
        Group {
            if drawerMode { drawerBody } else { remindersBody }
        }
        .buttonStyle(.plain).foregroundStyle(theme.pageColor.textPrimary)
        .sheet(item: Binding(get: { drawerMode ? nil : selected }, set: { selected = $0 })) { note in
            NavigationStack {
                noteReader(note)
                    .navigationTitle("柯留下的").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("放好") { selected = nil }.accessibilityIdentifier("note-reader-close")
                        }
                    }
            }.tint(theme.pageAccent)
        }
        .fullScreenCover(item: Binding(get: { drawerMode ? selected : nil }, set: { selected = $0 })) { note in
            VStack(spacing: NotesTheme.gap) {
                HStack {
                    Button("放回去") { selected = nil }
                        .frame(minHeight: NotesTheme.controlHeight)
                        .accessibilityIdentifier("drawer-note-put-back")
                    Spacer()
                }.font(Moonlight.serif(NotesTheme.titleSize)).foregroundStyle(theme.pageAccent)
                noteReader(note)
                    .background(paper, in: NotePaperShape())
                    .shadow(color: KeepsakeTheme.shadow.opacity(NotesTheme.shadowOpacity),
                            radius: NotesTheme.readerShadowRadius, y: NotesTheme.readerShadowOffset)
                    .accessibilityIdentifier("drawer-note-lifted")
            }.padding(NotesTheme.pageInset)
                .background(theme.pageBackground.ignoresSafeArea()).buttonStyle(.plain)
        }
        .sheet(isPresented: $allOpen) { notesList }
    }

    private var remindersBody: some View {
        VStack(alignment: .leading, spacing: NotesTheme.smallGap) {
            listHeader
            syncStatus
            if store.all.isEmpty && showsEmptyPaper {
                VStack(alignment: .leading, spacing: NotesTheme.smallGap) {
                    Text("a little note").font(Moonlight.script(NotesTheme.scriptSize)).foregroundStyle(theme.pageAccent)
                    Text("柯的小提醒会贴在这里。").font(Moonlight.serif(NotesTheme.bodySize))
                    Text("想说的话，去「玩」里的朋友圈写。")
                        .font(Moonlight.serif(NotesTheme.captionSize)).foregroundStyle(theme.pageColor.textSecondary)
                }.frame(maxWidth: .infinity, minHeight: NotesTheme.drawerCardMinHeight, alignment: .leading)
                    .padding(NotesTheme.inset).background(paper.opacity(NotesTheme.ruleOpacity), in: NotePaperShape())
                    .accessibilityIdentifier("notes-empty")
            } else {
                HStack(alignment: .top, spacing: NotesTheme.gap) {
                    ForEach(featured) { note in
                        noteCard(note).transition(archiveTransition)
                    }
                }
            }
            localArchiveStatus
        }
    }

    private var listHeader: some View {
        HStack(spacing: NotesTheme.compactGap) {
            Button("便利贴") { showsArchived = false; allOpen = true }
                .font(Moonlight.serif(NotesTheme.titleSize))
                .frame(minHeight: NotesTheme.controlHeight).accessibilityIdentifier("notes-all")
            Spacer()
            Button("已收起 · \(store.archived.count)") { showsArchived = true; allOpen = true }
                .font(Moonlight.serif(NotesTheme.captionSize))
                .frame(minHeight: NotesTheme.controlHeight).accessibilityIdentifier("notes-open-archive")
        }
    }

    private var localArchiveStatus: some View {
        Text(StickyNotesStore.archiveStatus)
            .font(Moonlight.serif(NotesTheme.captionSize)).foregroundStyle(theme.pageColor.textSecondary)
            .accessibilityIdentifier("notes-local-archive-status")
    }

    @ViewBuilder
    private var syncStatus: some View {
        if let status = store.status {
            VStack(alignment: .leading, spacing: NotesTheme.compactGap) {
                Text(status).foregroundStyle(theme.pageColor.textSecondary)
                Button("重新同步") { Task { await store.load() } }
                    .foregroundStyle(theme.pageAccent).frame(minHeight: NotesTheme.controlHeight)
                    .disabled(store.loading).accessibilityIdentifier("notes-retry")
            }.font(Moonlight.serif(NotesTheme.captionSize))
        }
    }

    private var notesList: some View {
        NavigationStack {
            VStack(spacing: NotesTheme.gap) {
                Picker("便利贴", selection: $showsArchived) {
                    Text("贴着的").tag(false)
                    Text("已收起").tag(true)
                }.pickerStyle(.segmented).accessibilityIdentifier("notes-list-filter")
                ScrollView {
                    LazyVStack(spacing: NotesTheme.gap) {
                        syncStatus
                        ForEach(showsArchived ? store.archived : store.all) { note in
                            VStack(alignment: .leading, spacing: NotesTheme.smallGap) {
                                Text("柯").font(Moonlight.serif(NotesTheme.authorSize)).foregroundStyle(theme.pageAccent)
                                Text(note.content).font(Moonlight.serif(NotesTheme.bodySize))
                                    .lineSpacing(NotesTheme.lineSpacing).textSelection(.enabled)
                                HStack {
                                    Spacer()
                                    if showsArchived {
                                        Button("放回去") { changeArchive { store.restore(note) } }
                                            .accessibilityIdentifier("note-restore-" + note.id)
                                    } else { acknowledgeButton(note) }
                                }.font(Moonlight.serif(NotesTheme.authorSize))
                                    .frame(minHeight: NotesTheme.controlHeight)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(NotesTheme.inset)
                                .background(paper, in: NotePaperShape())
                                .accessibilityElement(children: .contain).accessibilityIdentifier("note-" + note.id)
                                .transition(archiveTransition)
                        }
                        if (showsArchived ? store.archived : store.all).isEmpty {
                            Text(showsArchived ? "收起的提醒会留在这里，随时能放回去。" : "柯的小提醒会贴在这里。")
                                .font(Moonlight.serif(NotesTheme.bodySize)).foregroundStyle(theme.pageColor.textSecondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(showsArchived ? "notes-archive-list" : "notes-active-list")
                }.refreshable { await store.load() }
                localArchiveStatus
            }.padding(NotesTheme.pageInset).background(theme.pageBackground)
                .navigationTitle("便利贴").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("收好") { allOpen = false }.accessibilityIdentifier("notes-list-close")
                    }
                }
        }.tint(theme.pageAccent)
    }

    private var trayPageCount: Int { max(1, (store.all.count + 1) / 2) }
    private var drawerBody: some View {
        VStack(spacing: NotesTheme.smallGap) {
            listHeader
            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    Image("KeepsakeNotesInterior").resizable().scaledToFit()
                        .colorMultiply(KeepsakeTheme.artworkTint(night: theme.skin == .night))
                        .accessibilityHidden(true).allowsHitTesting(false)
                    if store.all.isEmpty {
                        Text("柯的小提醒会放在这里。")
                            .font(Moonlight.serif(NotesTheme.authorSize)).foregroundStyle(KeepsakeTheme.paperInk)
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
                                            .shadow(color: KeepsakeTheme.shadow.opacity(NotesTheme.shadowOpacity),
                                                    radius: NotesTheme.shadowRadius, y: NotesTheme.shadowOffset)
                                            .position(x: g.size.width * (pair.count == 1 ? 0.42 : (index == 0 ? 0.28 : 0.58)),
                                                      y: g.size.height * (pair.count == 1 ? 0.39 : (index == 0 ? 0.24 : 0.51)))
                                            .zIndex(Double(index))
                                            .transition(archiveTransition)
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
                HStack(spacing: NotesTheme.pageInset) {
                    Button { trayPage = max(0, trayPage - 1) } label: {
                        Image(systemName: "chevron.left").frame(width: NotesTheme.controlHeight, height: NotesTheme.controlHeight)
                    }.disabled(trayPage == 0).accessibilityLabel("前两张便利贴")
                    Text("\(trayPage + 1) / \(trayPageCount)").font(Moonlight.serif(NotesTheme.authorSize))
                    Button { trayPage = min(trayPageCount - 1, trayPage + 1) } label: {
                        Image(systemName: "chevron.right").frame(width: NotesTheme.controlHeight, height: NotesTheme.controlHeight)
                    }.disabled(trayPage == trayPageCount - 1).accessibilityLabel("后两张便利贴")
                }
            }
            localArchiveStatus
        }.onChange(of: store.all.count) { _, _ in trayPage = min(trayPage, trayPageCount - 1) }
    }

    private func noteReader(_ note: StickyNote) -> some View {
        VStack(alignment: .leading, spacing: NotesTheme.gap) {
            Text("little notes").font(Moonlight.script(NotesTheme.largeScriptSize))
                .foregroundStyle(drawerMode ? KeepsakeTheme.signature : theme.pageAccent)
            ScrollView {
                Text(note.content).font(Moonlight.serif(NotesTheme.readerSize)).lineSpacing(NotesTheme.lineSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    .accessibilityIdentifier(drawerMode ? "drawer-note-content" : "note-reader-content")
            }
            acknowledgeButton(note)
            localArchiveStatus
        }.foregroundStyle(drawerMode ? KeepsakeTheme.paperInk : theme.pageColor.textPrimary)
            .padding(NotesTheme.pageInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(drawerMode ? paper : theme.pageBackground)
    }

    private var paper: Color { theme.skin == .night && !drawerMode ? theme.pageColor.card : Moonlight.lavenderPaper }

    private func noteCard(_ note: StickyNote) -> some View {
        VStack(alignment: .leading, spacing: NotesTheme.smallGap) {
            Button { selected = note } label: {
                VStack(alignment: .leading, spacing: NotesTheme.smallGap) {
                    Text("柯").font(Moonlight.serif(NotesTheme.authorSize))
                        .foregroundStyle(drawerMode ? KeepsakeTheme.paperMutedInk : theme.pageColor.textSecondary)
                    Rectangle().fill(theme.pageAccent.opacity(NotesTheme.ruleOpacity))
                        .frame(width: NotesTheme.ruleWidth, height: NotesTheme.ruleHeight)
                    Text(note.content).font(Moonlight.serif(NotesTheme.bodySize)).lineSpacing(NotesTheme.lineSpacing)
                        .lineLimit(drawerMode ? 1 : 2).frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.accessibilityIdentifier("note-open-" + note.id)
            Spacer(minLength: 0)
            acknowledgeButton(note)
        }.frame(maxWidth: .infinity, minHeight: drawerMode ? NotesTheme.drawerCardMinHeight : NotesTheme.cardMinHeight,
                alignment: .topLeading)
            .padding(drawerMode ? NotesTheme.drawerCardInset : NotesTheme.cardInset)
            .background(paper.opacity(drawerMode ? 1 : NotesTheme.cardOpacity), in: NotePaperShape())
            .overlay(alignment: .bottomTrailing) {
                FoldCorner().fill(theme.pageAccent.opacity(NotesTheme.foldOpacity))
                    .frame(width: NotesTheme.foldSize, height: NotesTheme.foldSize).allowsHitTesting(false)
            }
            .foregroundStyle(drawerMode ? KeepsakeTheme.paperInk : theme.pageColor.textPrimary)
            .accessibilityElement(children: .contain).accessibilityIdentifier("note-" + note.id)
    }

    private func acknowledgeButton(_ note: StickyNote) -> some View {
        Button("知道啦") {
            selected = nil
            changeArchive { store.acknowledge(note) }
        }.font(Moonlight.serif(NotesTheme.authorSize)).foregroundStyle(theme.pageAccent)
            .frame(minHeight: NotesTheme.controlHeight)
            .accessibilityLabel("知道啦，收起这张便利贴")
            .accessibilityIdentifier("note-ack-" + note.id)
    }

    private var archiveTransition: AnyTransition {
        reduceMotion ? .identity : .asymmetric(insertion: .opacity, removal: .move(edge: .bottom).combined(with: .opacity))
    }
    private func changeArchive(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: NotesTheme.archiveDuration), change)
    }
}

private struct NotePaperShape: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: .zero); p.addLine(to: CGPoint(x: r.maxX, y: 0))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - NotesTheme.foldSize))
            p.addLine(to: CGPoint(x: r.maxX - NotesTheme.foldSize, y: r.maxY))
            p.addLine(to: CGPoint(x: 0, y: r.maxY)); p.closeSubpath()
        }
    }
}
private struct FoldCorner: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: r.maxX, y: 0)); p.addLine(to: CGPoint(x: 0, y: r.maxY)); p.closeSubpath() }
    }
}
