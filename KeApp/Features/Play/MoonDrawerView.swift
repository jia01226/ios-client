import SwiftUI

/// 柯的抽屉：粉色的「月光宝盒」，里面放的是一卷卷欧式卷纸（佳佳 2026-10-08：
/// 「抽屉很奇怪 长得白的 要做成卷纸 欧洲那种 粉色抽屉 月光宝盒」）。
/// 之前的 SceneKit 漆柜在她手机上发白，这里全用 SwiftUI 平面手绘，颜色自己说了算。
struct MoonDrawerView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let line: ChatLine
    @State private var drawer: RemoteDrawer?
    @State private var error: String?
    @State private var loading = false
    @State private var openness: CGFloat = 0
    @State private var dragStart: CGFloat?
    @State private var reading: RemoteDrawer.Item?
    private var released: [RemoteDrawer.Item] { drawer?.outside.filter { $0.visibility == "released" } ?? [] }
    private var previews: [RemoteDrawer.Item] { drawer?.outside.filter { $0.visibility == "teaser" } ?? [] }
    private var night: Bool { theme.skin == .night }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("月光宝盒").font(Moonlight.serif(24))
                    Text("keepsakes").font(Moonlight.script(26)).foregroundStyle(theme.pageAccent)
                }.padding(.top, 10)
                MoonTreasureBox(openness: openness, night: night, hasScrolls: !released.isEmpty || !previews.isEmpty)
                    .frame(width: 300, height: 300)
                    .accessibilityHidden(true)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            if dragStart == nil { dragStart = openness }
                            openness = min(1, max(0, (dragStart ?? 0) + value.translation.height / 110))
                        }
                        .onEnded { value in
                            let target: CGFloat = openness + value.predictedEndTranslation.height / 500 > 0.5 ? 1 : 0
                            settle(target); dragStart = nil
                        })
                Button { settle(openness > 0.5 ? 0 : 1) } label: {
                    HStack(spacing: 10) {
                        MoonCrescent().fill(theme.pageAccent).frame(width: 13, height: 13)
                        Text(openness > 0.5 ? "轻轻推回去" : "拉开上面这一层").font(Moonlight.serif(17))
                        Image(systemName: openness > 0.5 ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .ultraLight))
                    }.frame(minHeight: 44)
                }.accessibilityIdentifier("drawer-pull").accessibilityValue(openness > 0.5 ? "已拉开" : "已合上")
                if openness > 0.5 {
                    VStack(spacing: 14) {
                        if loading { ProgressView("正在看看柯留下了什么") }
                        if let error { Button(error) { Task { await load() } }.font(Moonlight.serif(13)) }
                        if let drawer, drawer.outside.allSatisfy({ $0.visibility != "released" && $0.visibility != "teaser" }) {
                            Text("柯还没有把卷纸放在这一层。").font(Moonlight.serif(14))
                                .foregroundStyle(theme.pageColor.textSecondary)
                        }
                        ForEach(released) { item in
                            Button { reading = item } label: {
                                ScrollRoll(title: item.title, subtitle: Self.shortDate(item.created_at), sealed: false, night: night)
                            }.accessibilityIdentifier("drawer-letter-\(item.id)")
                                .accessibilityLabel("卷纸：\(item.title)")
                        }
                        ForEach(previews) { item in
                            VStack(spacing: 6) {
                                ScrollRoll(title: item.title, subtitle: "还封着", sealed: true, night: night)
                                if !item.teaser.isEmpty {
                                    Text(item.teaser).font(Moonlight.serif(13))
                                        .foregroundStyle(theme.pageColor.textSecondary)
                                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                                }
                            }
                        }
                    }.padding(.horizontal, 22).transition(.opacity.combined(with: .move(edge: .top)))
                }
                HStack(spacing: 8) {
                    Image(systemName: "lock").font(.system(size: 12, weight: .ultraLight))
                    Text("下面这一层，先留给柯。").font(Moonlight.serif(13))
                }.foregroundStyle(theme.pageColor.textSecondary).padding(.top, 10)
                    .accessibilityIdentifier("drawer-private-locked")
                Text("等他愿意，会亲手拿给你。").font(Moonlight.serif(12)).foregroundStyle(theme.pageColor.textSecondary)
            }.frame(maxWidth: .infinity).padding(.bottom, 28)
        }.buttonStyle(.plain).tint(theme.pageAccent).scrollIndicators(.hidden)
            .task { await load() }.refreshable { await load() }
            .sheet(item: $reading) { item in
                ParchmentReader(item: item, night: night) { reading = nil }
                    .environmentObject(theme)
            }
    }

    static func shortDate(_ raw: String) -> String {
        let day = String(raw.prefix(10))
        let parts = day.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return day }
        return "\(m)月\(d)日"
    }
    private func settle(_ target: CGFloat) {
        withAnimation(reduceMotion ? .linear(duration: 0.1) : .spring(response: 0.6, dampingFraction: 0.85)) { openness = target }
    }
    private func load() async {
        guard !loading else { return }; loading = true; error = nil
        defer { loading = false }
        do { drawer = try await APIClient(baseURL: line.apiBaseURL).fetchDrawer() }
        catch { self.error = "抽屉暂时没接上，点这里重试。" }
    }
}

// MARK: - 颜色（宝盒和卷纸自己的，不跟页面主题走，免得又发白）

private enum BoxInk {
    static func body(_ night: Bool) -> [Color] {
        night ? [Color(hex: 0x8A5E6B), Color(hex: 0x5E3C48)] : [Color(hex: 0xF4C9D2), Color(hex: 0xE3A3B1)]
    }
    static func lid(_ night: Bool) -> [Color] {
        night ? [Color(hex: 0x9C6B79), Color(hex: 0x6F4855)] : [Color(hex: 0xF8D7DE), Color(hex: 0xEBB3C0)]
    }
    static func inside(_ night: Bool) -> Color { night ? Color(hex: 0x3E2730) : Color(hex: 0xB9707F) }
    static func trim(_ night: Bool) -> Color { night ? Color(hex: 0xC9A27A) : Color(hex: 0xD8AE7E) }
    static func trimLight(_ night: Bool) -> Color { night ? Color(hex: 0xE6CBA4) : Color(hex: 0xF3DDB8) }
    static let parchment = [Color(hex: 0xFBF1DE), Color(hex: 0xF1DFC0)]
    static let parchmentEdge = Color(hex: 0xC9A97E)
    static let rod = [Color(hex: 0xE9C99A), Color(hex: 0xB98A55)]
    static let ink = Color(hex: 0x5B4636)
    static let ribbon = Color(hex: 0xD98C9D)
    static let wax = Color(hex: 0xB5566C)
}

// MARK: - 月光宝盒

private struct MoonTreasureBox: View, Animatable {
    var openness: CGFloat
    let night: Bool
    let hasScrolls: Bool
    var animatableData: CGFloat { get { openness } set { openness = newValue } }

    var body: some View {
        let w: CGFloat = 260
        ZStack(alignment: .top) {
            // 盖子：拱顶 + 月牙
            LidShape()
                .fill(LinearGradient(colors: BoxInk.lid(night), startPoint: .top, endPoint: .bottom))
                .overlay(LidShape().stroke(BoxInk.trim(night), lineWidth: 1.6))
                .frame(width: w + 16, height: 62)
                .overlay(alignment: .center) {
                    HStack(spacing: 10) {
                        Sparkle().fill(BoxInk.trimLight(night)).frame(width: 7, height: 7)
                        MoonCrescent().fill(BoxInk.trimLight(night)).frame(width: 22, height: 22)
                        Sparkle().fill(BoxInk.trimLight(night)).frame(width: 7, height: 7)
                    }.offset(y: 6)
                }
            // 盒身
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: BoxInk.body(night), startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(BoxInk.trim(night), lineWidth: 1.6))
                .frame(width: w, height: 196)
                .offset(y: 58)
            // 上层抽屉拉开后露出来的里面，和探出头的卷纸
            DrawerCavity(night: night, hasScrolls: hasScrolls, openness: openness)
                .frame(width: w - 28, height: 78)
                .offset(y: 70)
                .opacity(Double(min(1, openness * 1.6)))
            // 上层抽屉面：往外（往下）拉
            DrawerFront(night: night, locked: false)
                .frame(width: w - 24, height: 80)
                .scaleEffect(1 + 0.07 * openness)
                .offset(y: 70 + 58 * openness)
                .shadow(color: .black.opacity(0.18 * Double(openness)), radius: 10 * openness, y: 6 * openness)
                .zIndex(2)
            // 下层抽屉：一直锁着
            DrawerFront(night: night, locked: true)
                .frame(width: w - 24, height: 80)
                .offset(y: 162)
                .zIndex(openness > 0.05 ? 0 : 1)
            // 小脚
            HStack {
                BoxFoot(color: BoxInk.trim(night))
                Spacer()
                BoxFoot(color: BoxInk.trim(night))
            }.frame(width: w - 30).offset(y: 252)
        }
        .frame(width: 300, height: 300, alignment: .top)
    }
}

private struct DrawerFront: View {
    let night: Bool
    let locked: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: BoxInk.lid(night), startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 8).stroke(BoxInk.trim(night), lineWidth: 1.2)
            RoundedRectangle(cornerRadius: 5).stroke(BoxInk.trimLight(night).opacity(0.8), lineWidth: 0.7)
                .padding(7)
            if locked {
                VStack(spacing: 3) {
                    Circle().stroke(BoxInk.trim(night), lineWidth: 1.4).frame(width: 13, height: 13)
                    Capsule().fill(BoxInk.trim(night)).frame(width: 3, height: 9)
                }
            } else {
                MoonCrescent().fill(BoxInk.trimLight(night))
                    .overlay(MoonCrescent().stroke(BoxInk.trim(night), lineWidth: 0.8))
                    .frame(width: 26, height: 26)
            }
        }
    }
}

private struct DrawerCavity: View {
    let night: Bool
    let hasScrolls: Bool
    let openness: CGFloat
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 6).fill(BoxInk.inside(night))
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [.black.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
            if hasScrolls {
                HStack(alignment: .bottom, spacing: 14) {
                    MiniScroll().frame(width: 30, height: 52).rotationEffect(.degrees(-8))
                    MiniScroll().frame(width: 30, height: 62)
                    MiniScroll().frame(width: 30, height: 48).rotationEffect(.degrees(7))
                }
                .offset(y: 26 - 34 * openness)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// 竖着放在宝盒里的小卷纸：中间一卷纸，上下两头木轴，腰上一根粉丝带。
private struct MiniScroll: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: BoxInk.parchment, startPoint: .leading, endPoint: .trailing))
                .padding(.vertical, 5)
            VStack {
                Capsule().fill(LinearGradient(colors: BoxInk.rod, startPoint: .top, endPoint: .bottom)).frame(height: 7)
                Spacer()
                Capsule().fill(LinearGradient(colors: BoxInk.rod, startPoint: .top, endPoint: .bottom)).frame(height: 7)
            }
            Rectangle().fill(BoxInk.ribbon).frame(height: 4)
        }
    }
}

private struct LidShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let base = rect.maxY
        p.move(to: CGPoint(x: rect.minX + 6, y: base))
        p.addLine(to: CGPoint(x: rect.minX + 6, y: rect.minY + rect.height * 0.55))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - 6, y: rect.minY + rect.height * 0.55),
                       control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.35))
        p.addLine(to: CGPoint(x: rect.maxX - 6, y: base))
        p.addQuadCurve(to: CGPoint(x: rect.minX + 6, y: base), control: CGPoint(x: rect.midX, y: base + 4))
        p.closeSubpath()
        return p
    }
}

private struct BoxFoot: View {
    let color: Color
    var body: some View {
        UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 9, bottomTrailingRadius: 9, topTrailingRadius: 2)
            .fill(color).frame(width: 22, height: 14)
    }
}

private struct Sparkle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        p.move(to: CGPoint(x: c.x, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: rect.maxY), control: c)
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: rect.minY), control: c)
        return p
    }
}

// MARK: - 卷纸（列表里横着放的一卷）

private struct ScrollRoll: View {
    let title: String
    let subtitle: String
    let sealed: Bool
    let night: Bool
    var body: some View {
        HStack(spacing: 0) {
            RollEnd()
            ZStack {
                Rectangle()
                    .fill(LinearGradient(colors: BoxInk.parchment, startPoint: .top, endPoint: .bottom))
                    .overlay(LinearGradient(colors: [BoxInk.parchmentEdge.opacity(0.35), .clear, .clear, BoxInk.parchmentEdge.opacity(0.35)],
                                            startPoint: .top, endPoint: .bottom))
                VStack(spacing: 3) {
                    Text(title).font(Moonlight.serif(16)).foregroundStyle(BoxInk.ink).lineLimit(1)
                    Text(subtitle).font(Moonlight.serif(11)).foregroundStyle(BoxInk.ink.opacity(0.65))
                }.padding(.horizontal, 30)
                HStack {
                    Spacer()
                    if sealed {
                        ZStack {
                            Circle().fill(BoxInk.wax).frame(width: 26, height: 26)
                            MoonCrescent().fill(Color(hex: 0xF6D9DF)).frame(width: 12, height: 12)
                        }.padding(.trailing, 10)
                    } else {
                        Rectangle().fill(BoxInk.ribbon.opacity(0.9)).frame(width: 5).padding(.trailing, 22)
                    }
                }
            }.frame(height: 58)
            RollEnd()
        }
        .frame(maxWidth: 320)
        .shadow(color: .black.opacity(night ? 0.35 : 0.12), radius: 6, y: 3)
        .contentShape(Rectangle())
    }
}

/// 卷起来的那一头：一卷纸筒，外面露出木轴两端的小圆头。
private struct RollEnd: View {
    var body: some View {
        ZStack {
            Capsule().fill(LinearGradient(colors: [Color(hex: 0xEAD3AE), Color(hex: 0xFBF1DE), Color(hex: 0xDCC09A)],
                                          startPoint: .leading, endPoint: .trailing))
                .frame(width: 16, height: 66)
            VStack {
                Circle().fill(LinearGradient(colors: BoxInk.rod, startPoint: .top, endPoint: .bottom)).frame(width: 12, height: 12)
                Spacer()
                Circle().fill(LinearGradient(colors: BoxInk.rod, startPoint: .top, endPoint: .bottom)).frame(width: 12, height: 12)
            }.frame(height: 78)
        }.frame(width: 16, height: 78)
    }
}

// MARK: - 展开读：上下两根木轴，中间羊皮纸一点点放下来

private struct ParchmentReader: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: RemoteDrawer.Item
    let night: Bool
    let close: () -> Void
    @State private var unrolled = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ReaderRod()
                    VStack(alignment: .leading, spacing: 22) {
                        Text(item.title).font(Moonlight.serif(26)).foregroundStyle(BoxInk.ink)
                        // 只有 released 才有正文；私藏的不可能走到这里。
                        if item.visibility == "released" {
                            Text(item.content).font(Moonlight.serif(18)).lineSpacing(10)
                                .foregroundStyle(BoxInk.ink).textSelection(.enabled)
                        }
                        HStack {
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("— 柯").font(Moonlight.script(26)).foregroundStyle(BoxInk.wax)
                                Text(MoonDrawerView.shortDate(item.created_at)).font(Moonlight.serif(12))
                                    .foregroundStyle(BoxInk.ink.opacity(0.6))
                            }
                        }
                    }
                    .padding(.horizontal, 30).padding(.vertical, 34)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(colors: BoxInk.parchment, startPoint: .top, endPoint: .bottom)
                            .overlay(LinearGradient(colors: [BoxInk.parchmentEdge.opacity(0.28), .clear, .clear, BoxInk.parchmentEdge.opacity(0.28)],
                                                    startPoint: .leading, endPoint: .trailing))
                    )
                    .padding(.horizontal, 14)
                    .scaleEffect(x: 1, y: unrolled ? 1 : 0.04, anchor: .top)
                    .opacity(unrolled ? 1 : 0.4)
                    ReaderRod()
                }
                .padding(.horizontal, 18).padding(.vertical, 24)
            }
            .background(theme.pageBackground.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("卷起来放回去") { close() } } }
        }
        .tint(theme.pageAccent)
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.1) : .easeOut(duration: 0.9)) { unrolled = true }
        }
    }
}

private struct ReaderRod: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle().fill(LinearGradient(colors: BoxInk.rod, startPoint: .top, endPoint: .bottom)).frame(width: 18, height: 18)
            Capsule().fill(LinearGradient(colors: [Color(hex: 0xEAD3AE), Color(hex: 0xFBF1DE), Color(hex: 0xD9BC94)],
                                          startPoint: .top, endPoint: .bottom))
                .frame(height: 20)
            Circle().fill(LinearGradient(colors: BoxInk.rod, startPoint: .top, endPoint: .bottom)).frame(width: 18, height: 18)
        }
        .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
    }
}
