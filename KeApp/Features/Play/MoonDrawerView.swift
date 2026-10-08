import SwiftUI

/// Illustrated fixed cabinet + independently moving upper tray. The lower drawer never moves.
struct MoonDrawerView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let line: ChatLine
    @State private var contents = DrawerKeepsakes()
    @State private var loaded = false
    @State private var loading = false
    @State private var error: String?
    @State private var openness: CGFloat = 0
    @State private var reading: DrawerLetter?
    private var night: Bool { theme.skin == .night }
    private var isOpen: Bool { openness > 0.5 }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 3) {
                    Text("月光宝盒").font(Moonlight.serif(24))
                    Text("keepsakes").font(Moonlight.script(31)).foregroundStyle(theme.pageAccent)
                }.padding(.top, 14)
                KeepsakeCabinetArtwork(openness: $openness, visibleCount: contents.visibleCount,
                                       night: night, settle: settle)
                    .frame(maxWidth: 370).padding(.horizontal, 14)
                Button { settle(isOpen ? 0 : 1) } label: {
                    HStack(spacing: 12) {
                        Text(isOpen ? "轻轻推回去" : "拉开上面这一层").font(Moonlight.serif(16))
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .ultraLight))
                    }.frame(minHeight: 44)
                }
                .accessibilityIdentifier("drawer-pull")
                .accessibilityValue(isOpen ? "已拉开" : "已合上")
                .accessibilityHint("也可以拖动上层抽屉的珍珠丝带拉手")
                HStack(spacing: 7) {
                    Image(systemName: "lock").font(.system(size: 11, weight: .light))
                    Text("下面这一层，是柯的私藏。").font(Moonlight.serif(12))
                }.foregroundStyle(theme.pageColor.textSecondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("drawer-private-locked")
                    .accessibilityLabel("柯的私藏，下层始终锁着")
                if isOpen {
                    scrolls.padding(.top, 16).transition(.opacity)
                } else {
                    Text("轻轻拉开，看看他留给你的话。")
                        .font(Moonlight.serif(13)).foregroundStyle(theme.pageColor.textSecondary)
                        .padding(.top, 38).padding(.bottom, 36)
                }
            }.frame(maxWidth: .infinity).padding(.bottom, 28)
        }
        .buttonStyle(.plain).tint(theme.pageAccent).scrollIndicators(.hidden)
        .task { await load() }.refreshable { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
        .sheet(item: $reading) { letter in
            KeepsakeParchmentReader(letter: letter, night: night) { reading = nil }
                .environmentObject(theme).presentationDetents([.large])
        }
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
                    .font(Moonlight.serif(14)).foregroundStyle(theme.pageColor.textSecondary)
                    .accessibilityIdentifier("drawer-empty")
            }
            ForEach(contents.letters) { letter in
                Button { reading = letter } label: {
                    VStack(spacing: 9) {
                        KeepsakeScrollArtwork(sealed: false, night: night)
                            .frame(width: 248, height: 78).accessibilityHidden(true)
                        Text(letter.title.isEmpty ? "留给你的一封信" : letter.title)
                            .font(Moonlight.serif(17)).multilineTextAlignment(.center)
                        Text(DrawerDate.label(letter.createdAt)).font(Moonlight.serif(11))
                            .foregroundStyle(theme.pageColor.textSecondary)
                    }.frame(maxWidth: .infinity).contentShape(Rectangle())
                }
                .accessibilityIdentifier("drawer-letter-\(letter.id)")
                .accessibilityLabel("\(letter.title.isEmpty ? "留给你的一封信" : letter.title)，\(DrawerDate.label(letter.createdAt))")
                .accessibilityHint("展开这卷纸")
            }
            ForEach(contents.teasers) { teaser in
                VStack(spacing: 9) {
                    KeepsakeScrollArtwork(sealed: true, night: night)
                        .frame(width: 248, height: 88).accessibilityHidden(true)
                    Text("还封着").font(Moonlight.serif(16))
                    if !teaser.text.isEmpty {
                        Text(teaser.text).font(Moonlight.serif(13))
                            .foregroundStyle(theme.pageColor.textSecondary).multilineTextAlignment(.center)
                    }
                }.frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("drawer-teaser-\(teaser.id)")
                    .accessibilityHint("蜡封还在，柯还没有公开这卷的全文")
            }
        }.padding(.horizontal, 28)
    }

    private func settle(_ target: CGFloat) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.9)) {
            openness = target
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var openness: CGFloat
    let visibleCount: Int
    let night: Bool
    let settle: (CGFloat) -> Void
    @State private var dragStart: CGFloat?
    var body: some View {
        GeometryReader { g in
            let width = g.size.width
            ZStack(alignment: .topLeading) {
                Image("KeepsakeCabinet").renderingMode(.original).resizable()
                    .frame(width: width, height: width)
                movingTray(width: width)
                    .mask(DrawerAperture())
                // The illustration itself has no private-content hit target.
                Rectangle().fill(.clear)
                    .frame(width: width * 0.78, height: width * 0.24)
                    .contentShape(Rectangle())
                    .position(x: width * 0.5, y: width * (0.46 + 0.085 * openness))
                    .highPriorityGesture(DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            if dragStart == nil { dragStart = openness }
                            let next = DrawerTravel.progress(start: dragStart ?? openness,
                                                             translation: value.translation.height,
                                                             distance: width * 0.28)
                            // Reduce Motion keeps explicit open/closed states without a moving scene.
                            if !reduceMotion { openness = next }
                        }
                        .onEnded { value in
                            settle(DrawerTravel.target(start: dragStart ?? openness,
                                                       predictedTranslation: value.predictedEndTranslation.height,
                                                       distance: width * 0.28))
                            dragStart = nil
                        })
                    .onTapGesture { settle(openness > 0.5 ? 0 : 1) }
            }
            .colorMultiply(KeepsakeTheme.artworkTint(night: night))
            .offset(y: -width * 0.12)
            .frame(width: width, height: g.size.height, alignment: .top)
        }
        .aspectRatio(1 / 0.74, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("月光宝盒，上层可拉开，下层为柯的私藏")
        .accessibilityValue(openness > 0.5 ? "上层已拉开" : "上层已合上")
        .accessibilityIdentifier("drawer-artwork")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: settle(1)
            case .decrement: settle(0)
            @unknown default: break
            }
        }
    }

    private func movingTray(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image("KeepsakeUpperDrawer").renderingMode(.original).resizable()
            ForEach(0..<min(3, visibleCount), id: \.self) { index in
                KeepsakeCutout(name: "KeepsakeScroll",
                               crop: CGRect(x: 0.016, y: 0.37, width: 0.968, height: 0.37))
                    .frame(width: width * 0.24, height: width * 0.06)
                    .rotationEffect(.degrees(84))
                    .scaleEffect(x: 1, y: 0.53)
                    .position(x: width * (0.25 + CGFloat(index) * 0.17), y: width * 0.185)
            }
        }
        .frame(width: width * 0.84, height: width * 0.54)
        .offset(x: width * 0.08, y: width * (0.145 + 0.085 * openness))
        .frame(width: width, height: width, alignment: .topLeading)
    }
}

/// The fixed curved cornice occludes the rear of the translated tray while it slides in.
private struct DrawerAperture: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.width * 0.357))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: rect.width * 0.357),
                          control: CGPoint(x: rect.midX, y: rect.width * 0.445))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
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
