import SwiftUI

/// Fixed cabinet with separate notes/letters trays; the private bottom drawer never moves.
struct MoonDrawerView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let line: ChatLine
    @StateObject private var notes: StickyNotesStore
    @State private var contents = DrawerKeepsakes()
    @State private var loaded = false
    @State private var loading = false
    @State private var error: String?
    @State private var openness: CGFloat = 0
    @State private var notesOpenness: CGFloat = 0
    @State private var notesFocused = false
    @State private var reading: DrawerLetter?
    private var night: Bool { theme.skin == .night }
    private var isOpen: Bool { openness > 0.5 }
    private var notesOpen: Bool { notesOpenness > 0.5 }

    init(line: ChatLine) {
        self.line = line
        _notes = StateObject(wrappedValue: StickyNotesStore(api: APIClient(baseURL: line.apiBaseURL), scope: line.rawValue))
    }

    var body: some View {
        ZStack {
        ScrollView {
            VStack(spacing: 14) {
                Text("keepsakes").font(Moonlight.script(36))
                    .foregroundStyle(theme.pageAccent).padding(.top, 18)
                KeepsakeCabinetArtwork(openness: $openness, notesOpenness: $notesOpenness,
                                       visibleCount: contents.visibleCount, notesCount: notes.all.count,
                                       night: night, settle: settle, settleNotes: settleNotes)
                    .frame(maxWidth: 370).padding(.horizontal, 14)
                HStack(spacing: 36) {
                    drawerControl("便利贴", open: notesOpen, id: "drawer-notes-pull") { settleNotes(notesOpen ? 0 : 1) }
                    drawerControl("卷轴", open: isOpen, id: "drawer-pull") { settle(isOpen ? 0 : 1) }
                }
                HStack(spacing: 7) {
                    Image(systemName: "lock").font(.system(size: 11, weight: .light))
                    Text("最下面这一层，是柯的私藏。").font(Moonlight.serif(12))
                }.foregroundStyle(theme.pageColor.textSecondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("drawer-private-locked")
                    .accessibilityLabel("柯的私藏，下层始终锁着")
                Text("第一层记事，第二层收信。")
                    .font(Moonlight.serif(13)).foregroundStyle(theme.pageColor.textSecondary)
                    .padding(.top, 38).padding(.bottom, 36)
            }.frame(maxWidth: .infinity).padding(.bottom, 28)
        }
        .accessibilityHidden(notesFocused || isOpen).allowsHitTesting(!notesFocused && !isOpen)
            if isOpen {
                letterFocus
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.80, anchor: .top).combined(with: .opacity))
            }
            if notesFocused {
                StickyDrawerFocus(store: notes, night: night) { settleNotes(0) }
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.80, anchor: .top).combined(with: .opacity))
            }
        }
        .buttonStyle(.plain).tint(theme.pageAccent).scrollIndicators(.hidden)
        .task { await reload() }.refreshable { await reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reload() } }
        }
        .sheet(item: $reading) { letter in
            KeepsakeParchmentReader(letter: letter, night: night) { reading = nil }
                .environmentObject(theme).presentationDetents([.large])
        }
    }

    private func drawerControl(_ title: String, open: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(Moonlight.serif(16))
                Image(systemName: open ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .ultraLight))
            }.frame(minWidth: 88, minHeight: 44)
        }
        .accessibilityIdentifier(id).accessibilityValue(open ? "已拉开" : "已合上")
        .accessibilityHint("也可以拖动这一层的珍珠拉手")
    }

    private func reload() async {
        async let drawer: Void = load()
        async let stickyNotes: Void = notes.load()
        _ = await (drawer, stickyNotes)
    }

    private var letterFocus: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Text("letters").font(Moonlight.script(34)).foregroundStyle(theme.pageAccent)
                    Spacer()
                    Button { settle(0) } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 17, weight: .ultraLight)).frame(width: 44, height: 44)
                    }.accessibilityLabel("收好卷轴抽屉").accessibilityIdentifier("drawer-pull")
                        .accessibilityValue("已拉开")
                }
                GeometryReader { g in
                    ZStack(alignment: .topLeading) {
                        Image("KeepsakeNotesInterior").resizable().scaledToFit()
                            .colorMultiply(KeepsakeTheme.artworkTint(night: night))
                            .accessibilityHidden(true).allowsHitTesting(false)
                        ScrollView {
                            scrolls.padding(.vertical, 12)
                        }.scrollIndicators(.hidden)
                            .frame(width: g.size.width * 0.76, height: g.size.height * 0.70)
                            .position(x: g.size.width * 0.5, y: g.size.height * 0.46)
                            .accessibilityIdentifier("drawer-letter-interior")
                    }
                }.aspectRatio(1, contentMode: .fit)
                Text("点开一卷，读柯交给你的话。")
                    .font(Moonlight.serif(13)).foregroundStyle(theme.pageColor.textSecondary)
            }.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 28)
                .frame(maxWidth: 520).frame(maxWidth: .infinity)
        }.background(theme.pageBackground).scrollIndicators(.hidden)
            .accessibilityElement(children: .contain).accessibilityIdentifier("drawer-letter-focus")
            .refreshable { await load() }
    }

    private var scrolls: some View {
        VStack(spacing: 26) {
            if loading { ProgressView("正在看看柯留下了什么").font(Moonlight.serif(13)) }
            if let error {
                Button(error) { Task { await load() } }
                    .font(Moonlight.serif(13)).frame(minHeight: 44)
                    .accessibilityIdentifier("drawer-retry")
            }
            if loaded && contents.isEmpty {
                Text("柯还没有把卷纸放在这一层。")
                    .font(Moonlight.serif(14)).foregroundStyle(KeepsakeTheme.paperMutedInk)
                    .accessibilityIdentifier("drawer-empty")
            }
            ForEach(contents.letters) { letter in
                Button { reading = letter } label: {
                    VStack(spacing: 9) {
                        KeepsakeScrollArtwork(sealed: false, night: night)
                            .frame(maxWidth: 210).frame(height: 64).accessibilityHidden(true)
                        Text(letter.title.isEmpty ? "留给你的一封信" : letter.title)
                            .font(Moonlight.serif(17)).multilineTextAlignment(.center)
                        Text(DrawerDate.label(letter.createdAt)).font(Moonlight.serif(11))
                            .foregroundStyle(KeepsakeTheme.paperMutedInk)
                    }.frame(maxWidth: .infinity).contentShape(Rectangle())
                }
                .accessibilityIdentifier("drawer-letter-\(letter.id)")
                .accessibilityLabel("\(letter.title.isEmpty ? "留给你的一封信" : letter.title)，\(DrawerDate.label(letter.createdAt))")
                .accessibilityHint("展开这卷纸")
            }
            ForEach(contents.teasers) { teaser in
                VStack(spacing: 9) {
                    KeepsakeScrollArtwork(sealed: true, night: night)
                        .frame(maxWidth: 210).frame(height: 70).accessibilityHidden(true)
                    Text("还封着").font(Moonlight.serif(16))
                    if !teaser.text.isEmpty {
                        Text(teaser.text).font(Moonlight.serif(13))
                            .foregroundStyle(KeepsakeTheme.paperMutedInk).multilineTextAlignment(.center)
                    }
                }.frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("drawer-teaser-\(teaser.id)")
                    .accessibilityHint("蜡封还在，柯还没有公开这卷的全文")
            }
        }.padding(.horizontal, 10).foregroundStyle(KeepsakeTheme.paperInk)
    }

    private func settle(_ target: CGFloat) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.9)) {
            openness = target
            if target > 0.5 { notesOpenness = 0 }
        }
    }
    private func settleNotes(_ target: CGFloat) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.9)) {
            notesOpenness = target
            if target > 0.5 { openness = 0 }
            notesFocused = target > 0.5
        }
    }
    @MainActor private func load() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let remote = try await APIClient(baseURL: line.apiBaseURL).fetchDrawer()
            try Task.checkCancellation()
            let visible = DrawerKeepsakes(remote)
            contents = visible; loaded = true
            if let id = reading?.id { reading = visible.letters.first { $0.id == id } }
        } catch is CancellationError {
        } catch let failure as URLError where failure.code == .cancelled {
        } catch {
            self.error = "抽屉暂时没接上，点这里重试。"
        }
    }
}

/// Cropping transparent sprite margins happens during layout; original source pixels stay intact.
private struct KeepsakeCutout: View {
    let name: String
    let crop: CGRect
    var body: some View {
        GeometryReader { g in
            Image(name).renderingMode(.original).resizable()
                .frame(width: g.size.width / crop.width, height: g.size.height / crop.height)
                .offset(x: -g.size.width * crop.minX / crop.width,
                        y: -g.size.height * crop.minY / crop.height)
        }.clipped().accessibilityHidden(true).allowsHitTesting(false)
    }
}

private struct KeepsakeCabinetArtwork: View {
    @Binding var openness: CGFloat
    @Binding var notesOpenness: CGFloat
    let visibleCount: Int
    let notesCount: Int
    let night: Bool
    let settle: (CGFloat) -> Void
    let settleNotes: (CGFloat) -> Void

    var body: some View {
        GeometryReader { g in
            let width = g.size.width
            ZStack(alignment: .topLeading) {
                Image("KeepsakeCabinet").renderingMode(.original).resizable()
                    .frame(width: width, height: width * 1276 / 1233)
                tray(width: width, notes: false)
                    .mask(DrawerAperture(top: 0.484, control: 0.550))
                tray(width: width, notes: true)
                    .mask(DrawerAperture(top: 0.275, control: 0.340))
                DrawerHandle(openness: $notesOpenness, width: width, title: "便利贴",
                             id: "drawer-notes-handle", settle: settleNotes)
                    .frame(width: width * 0.78, height: width * 0.15)
                    .position(x: width * 0.5, y: width * (0.394 + 0.073 * notesOpenness))
                DrawerHandle(openness: $openness, width: width, title: "卷轴",
                             id: "drawer-letter-handle", settle: settle)
                    .frame(width: width * 0.78, height: width * 0.15)
                    .position(x: width * 0.5, y: width * (0.61 + 0.073 * openness))
            }
            .colorMultiply(KeepsakeTheme.artworkTint(night: night))
            .offset(y: -width * 0.035)
            .frame(width: width, height: g.size.height, alignment: .top)
        }
        .aspectRatio(1 / 0.94, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawer-artwork")
    }

    private func tray(width: CGFloat, notes: Bool) -> some View {
        let progress = notes ? notesOpenness : openness
        return ZStack(alignment: .topLeading) {
            Image("KeepsakeUpperDrawer").renderingMode(.original).resizable()
            if notes {
                ForEach(0..<min(2, notesCount), id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(index == 0 ? Moonlight.rosePaper : Moonlight.lavenderPaper)
                        .frame(width: width * 0.34, height: width * 0.12)
                        .rotationEffect(.degrees(index == 0 ? -4 : 5))
                        .scaleEffect(x: 1, y: 0.30)
                        .position(x: width * (0.35 + CGFloat(index) * 0.15),
                                  y: width * (0.19 + CGFloat(index) * 0.022))
                }
            } else {
                ForEach(0..<min(3, visibleCount), id: \.self) { index in
                    KeepsakeCutout(name: "KeepsakeScroll",
                                   crop: CGRect(x: 0.016, y: 0.37, width: 0.968, height: 0.37))
                        .frame(width: width * 0.54, height: width * 0.13)
                        .scaleEffect(x: 1, y: 0.28)
                        .position(x: width * 0.42, y: width * (0.187 + CGFloat(index) * 0.028))
                }
            }
        }
        .frame(width: width * 0.84, height: width * 0.56)
        .offset(x: width * 0.08, y: width * ((notes ? 0.045 : 0.262) + 0.073 * progress))
        .frame(width: width, height: width * 1276 / 1233, alignment: .topLeading)
        .accessibilityHidden(true).allowsHitTesting(false)
    }
}

private struct DrawerHandle: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var openness: CGFloat
    let width: CGFloat
    let title: String
    let id: String
    let settle: (CGFloat) -> Void
    @State private var dragStart: CGFloat?

    var body: some View {
        Rectangle().fill(.clear).contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 6)
                .onChanged { value in
                    if dragStart == nil { dragStart = openness }
                    if !reduceMotion {
                        openness = DrawerTravel.progress(start: dragStart ?? openness,
                                                         translation: value.translation.height,
                                                         distance: width * 0.28)
                    }
                }
                .onEnded { value in
                    settle(DrawerTravel.target(start: dragStart ?? openness,
                                               predictedTranslation: value.predictedEndTranslation.height,
                                               distance: width * 0.28))
                    dragStart = nil
                })
            .onTapGesture { settle(openness > 0.5 ? 0 : 1) }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(id).accessibilityLabel(title + "抽屉的珍珠拉手")
            .accessibilityValue(openness > 0.5 ? "已拉开" : "已合上")
            .accessibilityAddTraits(.isButton)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: settle(1)
                case .decrement: settle(0)
                @unknown default: break
                }
            }
    }
}

/// Each fixed curved rim hides the part of its tray still inside the cabinet.
private struct DrawerAperture: Shape {
    let top: CGFloat
    let control: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.width * top))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: rect.width * top),
                          control: CGPoint(x: rect.midX, y: rect.width * control))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Opening the first drawer brings its tray and the real notes forward into a focused scene.
private struct StickyDrawerFocus: View {
    @EnvironmentObject private var theme: Theme
    @ObservedObject var store: StickyNotesStore
    let night: Bool
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack {
                    Text("便利贴").font(Moonlight.serif(20)).foregroundStyle(theme.pageColor.textPrimary)
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 17, weight: .ultraLight)).frame(width: 44, height: 44)
                    }.accessibilityLabel("收好便利贴抽屉").accessibilityIdentifier("drawer-notes-close")
                }
                MoonStickyNotesView(store: store, showsEmptyPaper: false, drawerMode: true)
                if let status = store.status {
                    Text(status).font(Moonlight.serif(12)).foregroundStyle(theme.pageColor.textSecondary)
                }
                if store.loading { ProgressView().tint(theme.pageAccent) }
            }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 32)
                .frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden).background(theme.pageBackground)
        .buttonStyle(.plain).foregroundStyle(theme.pageColor.textPrimary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawer-notes-focus")
        .refreshable { await store.load() }
    }
}

private struct KeepsakeScrollArtwork: View {
    let sealed: Bool
    let night: Bool
    var body: some View {
        ZStack {
            KeepsakeCutout(name: "KeepsakeScroll",
                           crop: CGRect(x: 0.016, y: 0.37, width: 0.968, height: 0.37))
                .frame(height: 64)
            if sealed {
                KeepsakeCutout(name: "KeepsakeWax",
                               crop: CGRect(x: 0.21, y: 0.12, width: 0.62, height: 0.80))
                    .frame(width: 48, height: 62).offset(y: 9)
            }
        }.colorMultiply(KeepsakeTheme.artworkTint(night: night))
    }
}

private struct KeepsakeParchmentReader: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let letter: DrawerLetter
    let night: Bool
    let close: () -> Void
    @State private var progress: CGFloat = 0
    @State private var measuredHeight: CGFloat = 0
    @State private var beganOpening = false
    @State private var closing = false
    @State private var closeTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: -3) {
                    rod
                    letterPaper
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: LetterHeight.self, value: g.size.height)
                        })
                        .frame(height: max(3, measuredHeight * progress), alignment: .top)
                        .clipped()
                        .accessibilityHidden(progress < 0.98)
                    rod
                }.padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 44)
                    .frame(maxWidth: 540)
                    .frame(maxWidth: .infinity)
            }
            .background(theme.pageBackground.ignoresSafeArea())
            .navigationTitle("柯留下的话").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("卷起来放回去", action: rollUp)
                        .font(Moonlight.serif(14)).disabled(closing)
                        .accessibilityIdentifier("drawer-reader-close")
                }
            }
        }
        .tint(theme.pageAccent).interactiveDismissDisabled()
        .onPreferenceChange(LetterHeight.self) { height in
            guard height > 0 else { return }
            measuredHeight = height
            if !beganOpening {
                beganOpening = true
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.75)) { progress = 1 }
            }
        }
        .onDisappear { closeTask?.cancel() }
    }

    private var letterPaper: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(letter.title.isEmpty ? "留给你的一封信" : letter.title)
                .font(Moonlight.serif(25))
            Text(letter.content).font(Moonlight.serif(18)).lineSpacing(11)
                .textSelection(.enabled).accessibilityIdentifier("drawer-reader-content")
            VStack(alignment: .trailing, spacing: 7) {
                Text("柯").font(Moonlight.serif(23)).foregroundStyle(KeepsakeTheme.signature)
                Text(DrawerDate.label(letter.createdAt)).font(Moonlight.serif(12))
                    .foregroundStyle(KeepsakeTheme.paperMutedInk)
            }.frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 18)
        }
        .foregroundStyle(KeepsakeTheme.paperInk)
        .padding(.horizontal, 34).padding(.vertical, 42)
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
        .background {
            KeepsakeCutout(name: "KeepsakePaper",
                           crop: CGRect(x: 0.035, y: 0.027, width: 0.935, height: 0.947))
                .colorMultiply(KeepsakeTheme.paperTint(night: night))
        }
        .padding(.horizontal, 17)
    }
    private var rod: some View {
        KeepsakeCutout(name: "KeepsakeRod",
                       crop: CGRect(x: 0.025, y: 0.41, width: 0.95, height: 0.18))
            .frame(height: 34).colorMultiply(KeepsakeTheme.paperTint(night: night))
    }
    private func rollUp() {
        guard !closing else { return }
        closing = true
        if reduceMotion { close(); return }
        withAnimation(.easeInOut(duration: 0.5)) { progress = 0 }
        closeTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(520)) } catch { return }
            guard !Task.isCancelled else { return }
            close()
        }
    }
}

private struct LetterHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
