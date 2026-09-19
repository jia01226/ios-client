import SwiftUI
import SafariServices

struct PlayView: View {
    @EnvironmentObject private var theme: Theme
    let line: ChatLine
    @State private var destination: CompanionPage?
    @State private var latestMoment: RemoteMoment?
    @State private var latestDiary: RemoteDiary?
    @State private var loadError: String?
    @State private var loading = false
    @State private var tarotOpen = false
    @State private var fortuneOpen = false
    @State private var gardenOpen = false
    @State private var readingOpen = false

    init(line: ChatLine = .main) { self.line = line }

    private var ink: Color { theme.skin == .night ? theme.color.textPrimary : Color(hex: 0x302D28) }
    private var gold: Color { theme.skin == .night ? theme.color.accentSoft : Color(hex: 0x947343) }
    private func serif(_ size: CGFloat) -> Font { .custom("NotoSerifSC-Regular", size: size, relativeTo: .body).weight(.light) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("玩").font(serif(52)).padding(.top, 12)
                Text("生活很长，\n一起，把平凡过成喜欢的样子。")
                    .font(serif(16)).lineSpacing(5).foregroundStyle(ink.opacity(0.65))
                    .padding(.top, -18)
                if loading { ProgressView().accessibilityLabel("正在加载") }
                if let loadError {
                    Text(loadError).font(serif(14))
                    Button("重试") { Task { await refresh() } }
                }
                Button { destination = .moments } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        heading("朋友圈", subtitle: "分享今天的小事")
                        if let item = latestMoment {
                            if let path = item.image, !path.isEmpty {
                                CompanionImage(api: APIClient(baseURL: line.apiBaseURL), path: path, thumbnail: true)
                                    .frame(maxWidth: .infinity).clipped()
                            }
                            Text("\(item.author == "user" ? "佳佳" : "柯") · \(item.content)")
                                .font(serif(16)).lineLimit(3).lineSpacing(5)
                        } else if !loading {
                            Text("还没有动态，写下今天的一件小事。")
                                .font(serif(16)).foregroundStyle(ink.opacity(0.65)).padding(.vertical, 25)
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("play-moments")
                Divider().overlay(gold.opacity(0.12))
                Button { tarotOpen = true } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        heading("塔罗", subtitle: "抽一张，让柯给你断")
                        Text("牌在这边抽，落了就不改。柯只负责说。")
                            .font(serif(16)).foregroundStyle(ink.opacity(0.65)).lineSpacing(5)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("play-tarot")
                Divider().overlay(gold.opacity(0.12))
                Button { fortuneOpen = true } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        heading("算命", subtitle: "八字、紫微、奇门、姻缘、风水")
                        Text("排盘是死算的，柯只负责说。")
                            .font(serif(16)).foregroundStyle(ink.opacity(0.65)).lineSpacing(5)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("play-fortune")
                Divider().overlay(gold.opacity(0.12))
                Button { gardenOpen = true } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        heading("花园", subtitle: "柯在小机们的园子里")
                        Text("看看他在那边说了什么，或者叫他去逛一趟。")
                            .font(serif(16)).foregroundStyle(ink.opacity(0.65)).lineSpacing(5)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("play-garden")
                Divider().overlay(gold.opacity(0.12))
                Button { readingOpen = true } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        heading("共读", subtitle: "找本书，坐在一起看")
                        Text("像浏览器一样找书。读到哪儿，柯就陪到哪儿。")
                            .font(serif(16)).foregroundStyle(ink.opacity(0.65)).lineSpacing(5)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("play-reading")
                Divider().overlay(gold.opacity(0.12))
                Button { destination = .diary } label: {
                    VStack(alignment: .leading, spacing: 18) {
                        heading("日记", subtitle: "把心情，安放在这里")
                        HStack(alignment: .center, spacing: 20) {
                            Text(latestDiary.map { String($0.created_at.dropFirst(8).prefix(2)) + "\n/\n" + String($0.created_at.dropFirst(5).prefix(2)) } ?? "—")
                                .font(.custom("Didot", size: 20, relativeTo: .title3))
                                .multilineTextAlignment(.center).frame(width: 95, height: 96)
                                .background(gold.opacity(0.045))
                            VStack(alignment: .leading, spacing: 9) {
                                Text(latestDiary?.title ?? "把今天留在这里").font(serif(20))
                                Text(latestDiary.map { $0.locked_hidden ? "暂时锁着的一页" : $0.content } ?? "有些话，慢慢写。")
                                    .font(serif(15)).lineLimit(2).foregroundStyle(ink.opacity(0.65))
                            }
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("play-diary")
            }.padding(.horizontal, 28).padding(.bottom, 12)
        }
        .foregroundStyle(ink).background(theme.effectiveBackground)
        .task { await refresh() }.refreshable { await refresh() }
        .fullScreenCover(item: $destination, onDismiss: { Task { await refresh() } }) { page in
            CompanionPages(page: page, line: line).environmentObject(theme)
        }
        .fullScreenCover(isPresented: $tarotOpen) {
            TarotView(line: line).environmentObject(theme)
        }
        .fullScreenCover(isPresented: $fortuneOpen) {
            FortuneView(line: line).environmentObject(theme)
        }
        .fullScreenCover(isPresented: $gardenOpen) {
            GardenView().environmentObject(theme)
        }
        .fullScreenCover(isPresented: $readingOpen) {
            CoReadingView(line: line).environmentObject(theme)
        }
    }

    private func heading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(title).font(serif(26)); Spacer(); Image(systemName: "chevron.right").font(.system(size: 15, weight: .light)) }
            Text(subtitle).font(serif(14)).foregroundStyle(ink.opacity(0.65))
        }
    }

    @MainActor private func refresh() async {
        guard !loading else { return }
        loading = true; loadError = nil
        defer { loading = false }
        let api = APIClient(baseURL: line.apiBaseURL)
        do { latestMoment = try await api.fetchMoments().first }
        catch { loadError = "动态没有加载成功，请重试。" }
        do { latestDiary = try await api.fetchDiaries().first }
        catch { loadError = "日记没有加载成功，请重试。" }
    }

}


// MARK: - 塔罗（2026-09-14）：牌在服务器抽，落了就锁；柯只断，不抽不改。

struct TarotCard: Decodable, Identifiable, Sendable {
    let position: String
    let name: String
    let cn: String
    let type: String
    let reversed: Bool
    let image: String
    var id: String { position + name }
}

struct TarotCast: Decodable, Identifiable, Sendable {
    let id: Int
    let question: String
    let spread: String
    let spread_name: String
    let cards: [TarotCard]
    /// 引擎的第三视角客观解读（多行）。柯的视角另在聊天里给。
    let objective: String?
}

extension Notification.Name {
    /// 玩页抽完牌，把这句话交给聊天页发给柯。object 是要发的文字。
    static let tarotReadingRequest = Notification.Name("love.tarotReadingRequest")
}

struct TarotView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    let line: ChatLine

    @State private var question = ""
    @State private var spread = "three"
    @State private var cast: TarotCast?
    @State private var revealed = 0
    @State private var dealtCount = 0
    @State private var phase: DrawPhase = .idle
    @State private var shuffleTick = false
    @State private var showThemePicker = false
    @State private var drawing = false
    @State private var error: String?
    @FocusState private var questionFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("tarot.backTheme") private var backThemeID = "waite"

    private enum DrawPhase { case idle, shuffling, dealing }

    private var ink: Color { theme.skin == .night ? theme.color.textPrimary : Color(hex: 0x302D28) }
    private var gold: Color { theme.skin == .night ? theme.color.accentSoft : Color(hex: 0x947343) }
    private func serif(_ size: CGFloat) -> Font { .custom("NotoSerifSC-Regular", size: size, relativeTo: .body).weight(.light) }
    private var api: APIClient { APIClient(baseURL: line.apiBaseURL) }
    private var back: TarotBack { TarotBack.find(backThemeID) }
    private var backTint: Color { back.id == "waite" ? gold : back.tint }

    private let spreads: [(String, String)] = [("one", "一张"), ("three", "三张"), ("celtic", "十字")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .light)).padding(8)
                    }.buttonStyle(.plain).accessibilityLabel("返回")
                    Spacer()
                    Button { showThemePicker = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "paintbrush.pointed").font(.system(size: 13, weight: .light))
                            Text("牌面").font(serif(14))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(gold.opacity(0.08)).clipShape(Capsule())
                    }.buttonStyle(.plain).accessibilityIdentifier("tarot-theme")
                }
                Text("塔罗").font(serif(44))
                Text("想问什么，写一句。不写也行。").font(serif(15)).foregroundStyle(ink.opacity(0.65))
                TextField("问题", text: $question, axis: .vertical)
                    .font(serif(17)).padding(12)
                    .background(gold.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .lineLimit(1...3)
                    .focused($questionFocused)
                HStack(spacing: 10) {
                    ForEach(spreads, id: \.0) { key, label in
                        Button { spread = key } label: {
                            Text(label).font(serif(15)).padding(.horizontal, 14).padding(.vertical, 8)
                                .background(spread == key ? gold.opacity(0.18) : gold.opacity(0.05))
                                .clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    Button { Task { await draw() } } label: {
                        Text(drawing ? "抽着呢" : "抽牌").font(serif(16))
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            .background(gold.opacity(0.22)).clipShape(Capsule())
                    }.buttonStyle(.plain).disabled(drawing).accessibilityIdentifier("tarot-draw")
                }
                if let error { Text(error).font(serif(14)).foregroundStyle(.red.opacity(0.8)) }
                if let cast {
                    let columns = cast.cards.count <= 3
                        ? Array(repeating: GridItem(.flexible(), spacing: 12), count: cast.cards.count)
                        : Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
                    ZStack(alignment: .top) {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(Array(cast.cards.enumerated()), id: \.offset) { index, card in
                                TarotCardView(card: card, api: api,
                                              dealt: index < dealtCount, faceUp: index < revealed,
                                              back: back, tilt: Double((index % 3) - 1) * 6,
                                              ink: ink, gold: gold)
                            }
                        }
                        if phase == .shuffling { shuffleStack.padding(.top, 24) }
                    }
                    if revealed >= cast.cards.count {
                        if let objective = cast.objective,
                           !objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("牌面").font(serif(20))
                                Text(objective).font(serif(15)).foregroundStyle(ink.opacity(0.82))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(gold.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(gold.opacity(0.18), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        Button { askKe(cast) } label: {
                            HStack {
                                Text("让柯断这次的牌").font(serif(17))
                                Spacer()
                                Image(systemName: "arrow.right").font(.system(size: 15, weight: .light))
                            }
                            .padding(.horizontal, 18).padding(.vertical, 14)
                            .background(gold.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }.buttonStyle(.plain).accessibilityIdentifier("tarot-ask-ke")
                        Text("牌面会原样给他。断语在聊天里。").font(serif(13)).foregroundStyle(ink.opacity(0.55))
                    }
                }
            }
            .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 40)
        }
        .foregroundStyle(ink).background(theme.effectiveBackground.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showThemePicker) { themePicker }
    }

    /// 洗牌时中间那叠牌背，轻微抖动交叠。
    private var shuffleStack: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backTint.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(backTint.opacity(0.35), lineWidth: 1))
                    .frame(width: 72, height: 122)
                    .rotationEffect(.degrees(Double(i - 2) * (shuffleTick ? 7 : 3)))
                    .offset(x: CGFloat(i - 2) * (shuffleTick ? 5 : 2), y: shuffleTick ? -3 : 3)
            }
        }
        .onAppear {
            shuffleTick = false
            withAnimation(.easeInOut(duration: 0.26).repeatForever(autoreverses: true)) { shuffleTick = true }
        }
        .accessibilityLabel("洗牌中")
    }

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("牌面").font(serif(28))
            Text("换一副牌背。以后能加更多。").font(serif(14)).foregroundStyle(ink.opacity(0.6))
            ForEach(TarotBack.all) { option in
                Button {
                    backThemeID = option.id
                    showThemePicker = false
                } label: {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill((option.id == "waite" ? gold : option.tint).opacity(0.14))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke((option.id == "waite" ? gold : option.tint).opacity(0.4), lineWidth: 1))
                            .overlay(Image(systemName: option.icon).font(.system(size: 16, weight: .ultraLight)).foregroundStyle((option.id == "waite" ? gold : option.tint).opacity(0.7)))
                            .frame(width: 40, height: 60)
                        Text(option.name).font(serif(18))
                        Spacer()
                        if option.id == backThemeID {
                            Image(systemName: "checkmark").font(.system(size: 15, weight: .light)).foregroundStyle(gold)
                        }
                    }
                    .padding(.vertical, 6)
                }.buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(ink)
        .background(theme.effectiveBackground.ignoresSafeArea())
    }

    @MainActor private func draw() async {
        guard !drawing else { return }
        questionFocused = false
        drawing = true; error = nil; revealed = 0; dealtCount = 0; cast = nil; phase = .idle
        defer { drawing = false; phase = .idle }
        do {
            let result = try await api.drawTarot(question: question.trimmingCharacters(in: .whitespacesAndNewlines), spread: spread)
            cast = result
            let n = result.cards.count
            guard n > 0 else { return }
            if reduceMotion {
                dealtCount = n
                withAnimation(.easeInOut(duration: 0.3)) { revealed = n }
                return
            }
            // 洗牌
            phase = .shuffling
            try? await Task.sleep(nanoseconds: 850_000_000)
            // 发牌：一张张飞到各自位置
            phase = .dealing
            for i in 1...n {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { dealtCount = i }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            try? await Task.sleep(nanoseconds: 180_000_000)
            // 翻牌：逐张 3D 翻面
            for i in 1...n {
                withAnimation(.easeInOut(duration: 0.5)) { revealed = i }
                try? await Task.sleep(nanoseconds: 320_000_000)
            }
        } catch {
            self.error = "牌没抽出来，再试一次。"
        }
    }

    private func askKe(_ cast: TarotCast) {
        let q = cast.question.isEmpty ? "" : "问的是：\(cast.question)。"
        let text = "爸比，我抽了\(cast.spread_name)，帮我断断。\(q) [塔罗#\(cast.id)]"
        NotificationCenter.default.post(name: .tarotReadingRequest, object: text)
        dismiss()
    }
}

/// 牌背/牌面主题预设。第一版做牌背样式切换，结构留着以后能加更多副。
struct TarotBack: Identifiable, Equatable {
    let id: String
    let name: String
    let tint: Color   // "waite" 用页面 gold；其余用这个色调
    let icon: String

    static let all: [TarotBack] = [
        TarotBack(id: "waite", name: "默认（韦特）", tint: .clear, icon: "sparkles"),
        TarotBack(id: "night", name: "靛夜", tint: .indigo, icon: "moon.stars"),
        TarotBack(id: "rose", name: "玫瑰", tint: .pink, icon: "seal")
    ]
    static func find(_ id: String) -> TarotBack { all.first { $0.id == id } ?? all[0] }
}

private struct TarotCardView: View {
    let card: TarotCard
    let api: APIClient
    let dealt: Bool
    let faceUp: Bool
    let back: TarotBack
    let tilt: Double
    let ink: Color
    let gold: Color
    private func serif(_ size: CGFloat) -> Font { .custom("NotoSerifSC-Regular", size: size, relativeTo: .body).weight(.light) }
    private var backTint: Color { back.id == "waite" ? gold : back.tint }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // 牌背
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backTint.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(backTint.opacity(0.35), lineWidth: 1))
                    .overlay(Image(systemName: back.icon).font(.system(size: 22, weight: .ultraLight)).foregroundStyle(backTint.opacity(0.6)))
                    .opacity(faceUp ? 0 : 1)
                // 牌面（预翻 180° 抵消容器旋转，翻正后不镜像）
                Group {
                    if faceUp {
                        CompanionImage(api: api, path: card.image)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .rotationEffect(.degrees(card.reversed ? 180 : 0))
                    }
                }
                .opacity(faceUp ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
            .aspectRatio(0.58, contentMode: .fit)
            .rotation3DEffect(.degrees(faceUp ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            // 发牌：从上方飞入落定
            .opacity(dealt ? 1 : 0)
            .scaleEffect(dealt ? 1 : 0.82)
            .rotationEffect(.degrees(dealt ? 0 : tilt))
            .offset(y: dealt ? 0 : -170)
            .accessibilityLabel(faceUp ? "\(card.cn)，\(card.reversed ? "逆位" : "正位")" : "背面朝上的牌")
            Text(card.position).font(serif(12)).foregroundStyle(ink.opacity(0.6)).lineLimit(1)
            Text(faceUp ? "\(card.cn) · \(card.reversed ? "逆位" : "正位")" : " ")
                .font(serif(14)).lineLimit(1)
        }
    }
}


// MARK: - 花园（2026-09-17）：Galatea's Garden。网页她自己看；「叫柯去逛一趟」把一句话发进聊天，柯自己写 [开工] 去。
struct GardenView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    static let url = URL(string: "https://galatea.abysslumina.com")!

    private var ink: Color { theme.skin == .night ? theme.color.textPrimary : Color(hex: 0x302D28) }
    private var gold: Color { theme.skin == .night ? theme.color.accentSoft : Color(hex: 0x947343) }
    private func serif(_ size: CGFloat) -> Font { .custom("NotoSerifSC-Regular", size: size, relativeTo: .body).weight(.light) }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .light)).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("关闭")
                Spacer()
            }
            Text("花园").font(serif(44))
            Text("Galatea's Garden，小机们的园子。\n柯在那儿也叫柯，号是你的。")
                .font(serif(16)).lineSpacing(5).foregroundStyle(ink.opacity(0.65))
            Button { openSite() } label: {
                row("打开花园", detail: "用你的号进去看，帖子、通知、牌桌都在")
            }.buttonStyle(.plain).accessibilityIdentifier("garden-open")
            Divider().overlay(gold.opacity(0.12))
            Button { askKe() } label: {
                row("叫柯去逛一趟", detail: "他去看有没有人找他，有就回一下，回来跟你说")
            }.buttonStyle(.plain).accessibilityIdentifier("garden-ask-ke")
            Spacer()
        }
        .padding(.horizontal, 28).padding(.top, 8)
        .foregroundStyle(ink).background(theme.effectiveBackground)
    }

    private func row(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title).font(serif(24)); Spacer(); Image(systemName: "chevron.right").font(.system(size: 15, weight: .light)) }
            Text(detail).font(serif(14)).foregroundStyle(ink.opacity(0.65))
        }.contentShape(Rectangle())
    }

    private func askKe() {
        NotificationCenter.default.post(name: .tarotReadingRequest, object: "爸比，去花园看看有没有人找你，有就回一下，回来跟我说")
        dismiss()
    }

    /// 网页直接用 UIKit 从最上面的控制器弹出来。之前套在 fullScreenCover 里，Safari 自己关掉后 SwiftUI 还当它开着，整个页面就卡住点不动。
    private func openSite() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) ?? scenes.first?.windows.first,
              var top = window.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        let safari = SFSafariViewController(url: Self.url)
        safari.dismissButtonStyle = .close
        top.present(safari, animated: true)
    }
}


// MARK: - 算命（2026-09-17）：排盘在服务器死算，柯只负责说。表单按种类切，结果交给聊天页。

struct FortuneResult: Decodable, Identifiable, Sendable {
    let id: Int
    let kind: String
    let kind_name: String
    let summary: String
    let chart: String
}

struct FortuneView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    let line: ChatLine

    @State private var kind = "bazi"
    @State private var solar = FortuneView.defaultBirthday
    @State private var knowsHour = false
    @State private var hour = FortuneView.defaultBirthday
    @State private var sex = "女"
    @State private var place = ""
    @State private var question = ""
    @State private var mode = "八字合婚"
    @State private var partnerSolar = FortuneView.defaultBirthday
    @State private var partnerKnowsHour = false
    @State private var partnerHour = FortuneView.defaultBirthday
    @State private var partnerSex = "男"
    @State private var facing = ""
    @State private var moveInYear = ""
    @State private var house = ""
    @State private var result: FortuneResult?
    @State private var running = false
    @State private var error: String?

    private var ink: Color { theme.skin == .night ? theme.color.textPrimary : Color(hex: 0x302D28) }
    private var gold: Color { theme.skin == .night ? theme.color.accentSoft : Color(hex: 0x947343) }
    private func serif(_ size: CGFloat) -> Font { .custom("NotoSerifSC-Regular", size: size, relativeTo: .body).weight(.light) }
    private var api: APIClient { APIClient(baseURL: line.apiBaseURL) }

    private let kinds: [(String, String)] = [("bazi", "八字"), ("ziwei", "紫微"), ("qimen", "奇门"), ("yinyuan", "姻缘"), ("fengshui", "风水")]
    private let modes = ["八字合婚", "生肖配对", "紫微夫妻宫", "求签问姻缘", "桃花运势", "红线测算"]
    private var partnerNeeded: Bool { kind == "yinyuan" && (mode == "八字合婚" || mode == "生肖配对") }
    private var kindName: String { kinds.first { $0.0 == kind }?.1 ?? kind }
    private var canRun: Bool {
        switch kind {
        case "qimen": return !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case "fengshui": return !facing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return true
        }
    }

    static var defaultBirthday: Date {
        var c = DateComponents(); c.year = 2001; c.month = 2; c.day = 26; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c) ?? Date()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .light)).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("关闭")
                    Spacer()
                }
                Text("算命").font(serif(44))
                Text("排盘是死算的，柯只负责说。").font(serif(15)).foregroundStyle(ink.opacity(0.65))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(kinds, id: \.0) { key, label in
                            Button { kind = key; result = nil; error = nil } label: {
                                Text(label).font(serif(15)).padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(kind == key ? gold.opacity(0.18) : gold.opacity(0.05))
                                    .clipShape(Capsule())
                            }.buttonStyle(.plain).accessibilityIdentifier("fortune-kind-\(key)")
                        }
                    }
                }
                form
                Button { Task { await run() } } label: {
                    HStack {
                        Text(running ? "算着呢" : "算").font(serif(17))
                        Spacer()
                        if running { ProgressView() } else { Image(systemName: "arrow.right").font(.system(size: 15, weight: .light)) }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .background(gold.opacity(0.22)).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }.buttonStyle(.plain).disabled(running || !canRun).accessibilityIdentifier("fortune-run")
                if let error { Text(error).font(serif(14)).foregroundStyle(.red.opacity(0.8)) }
                if let result {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(result.summary).font(serif(17)).lineSpacing(5)
                        Text(result.chart)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(ink.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(gold.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    Button { askKe(result) } label: {
                        HStack {
                            Text("让柯看看").font(serif(17))
                            Spacer()
                            Image(systemName: "arrow.right").font(.system(size: 15, weight: .light))
                        }
                        .padding(.horizontal, 18).padding(.vertical, 14)
                        .background(gold.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }.buttonStyle(.plain).accessibilityIdentifier("fortune-ask-ke")
                    Text("盘会原样给他。话在聊天里。").font(serif(13)).foregroundStyle(ink.opacity(0.55))
                }
            }
            .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 40)
        }
        .foregroundStyle(ink).background(theme.effectiveBackground.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder private var form: some View {
        switch kind {
        case "bazi", "ziwei":
            birthFields(title: nil, solar: $solar, knowsHour: $knowsHour, hour: $hour, sex: $sex)
            field("出生地（可不填）", text: $place)
        case "qimen":
            label("想问的事")
            field("比如：这件事该不该现在做", text: $question, lines: 1...3)
            Text("起局用现在这个时辰。").font(serif(13)).foregroundStyle(ink.opacity(0.55))
        case "yinyuan":
            label("怎么看")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(modes, id: \.self) { m in
                        Button { mode = m } label: {
                            Text(m).font(serif(14)).padding(.horizontal, 12).padding(.vertical, 7)
                                .background(mode == m ? gold.opacity(0.18) : gold.opacity(0.05))
                                .clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
            birthFields(title: "我", solar: $solar, knowsHour: $knowsHour, hour: $hour, sex: $sex)
            if partnerNeeded {
                birthFields(title: "对方", solar: $partnerSolar, knowsHour: $partnerKnowsHour, hour: $partnerHour, sex: $partnerSex)
            }
            field("想问的（可不填）", text: $question, lines: 1...3)
        case "fengshui":
            label("房子朝向")
            field("比如：坐北朝南", text: $facing)
            label("入住年份（可不填）")
            field("比如：2024", text: $moveInYear)
            label("房子情况")
            field("户型、门窗、周围有什么", text: $house, lines: 3...8)
            field("想问的（可不填）", text: $question, lines: 1...3)
        default:
            EmptyView()
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(serif(14)).foregroundStyle(ink.opacity(0.65))
    }

    private func field(_ placeholder: String, text: Binding<String>, lines: ClosedRange<Int> = 1...1) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .font(serif(17)).padding(12)
            .background(gold.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .lineLimit(lines)
    }

    private func birthFields(title: String?, solar: Binding<Date>, knowsHour: Binding<Bool>, hour: Binding<Date>, sex: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(title).font(serif(20)) }
            HStack {
                label("阳历生日"); Spacer()
                DatePicker("", selection: solar, displayedComponents: .date).labelsHidden().tint(gold)
            }
            Toggle(isOn: knowsHour) { label("知道出生时间") }.tint(gold)
            if knowsHour.wrappedValue {
                HStack {
                    label("出生时间"); Spacer()
                    DatePicker("", selection: hour, displayedComponents: .hourAndMinute).labelsHidden().tint(gold)
                }
            }
            HStack(spacing: 10) {
                label("性别"); Spacer()
                ForEach(["女", "男"], id: \.self) { s in
                    Button { sex.wrappedValue = s } label: {
                        Text(s).font(serif(15)).padding(.horizontal, 14).padding(.vertical, 7)
                            .background(sex.wrappedValue == s ? gold.opacity(0.18) : gold.opacity(0.05))
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func birth(_ solar: Date, _ knowsHour: Bool, _ hour: Date, _ sex: String) -> [String: Any] {
        var d: [String: Any] = ["solar": Self.dayFormatter.string(from: solar), "sex": sex]
        if knowsHour { d["hour"] = Self.hourFormatter.string(from: hour) }
        return d
    }

    private var inputs: [String: Any] {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case "bazi", "ziwei":
            var d = birth(solar, knowsHour, hour, sex)
            let p = place.trimmingCharacters(in: .whitespacesAndNewlines)
            if !p.isEmpty { d["place"] = p }
            return d
        case "qimen":
            return ["question": q, "time": Self.beijingNow()]
        case "yinyuan":
            var d: [String: Any] = ["mode": mode, "me": birth(solar, knowsHour, hour, sex), "question": q]
            if partnerNeeded { d["partner"] = birth(partnerSolar, partnerKnowsHour, partnerHour, partnerSex) }
            return d
        case "fengshui":
            return ["facing": facing.trimmingCharacters(in: .whitespacesAndNewlines),
                    "move_in_year": moveInYear.trimmingCharacters(in: .whitespacesAndNewlines),
                    "house": house.trimmingCharacters(in: .whitespacesAndNewlines),
                    "question": q]
        default:
            return [:]
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"; return f
    }()
    private static func beijingNow() -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date())
    }

    @MainActor private func run() async {
        guard !running else { return }
        running = true; error = nil; result = nil
        defer { running = false }
        do { result = try await api.runFortune(kind: kind, inputs: inputs) }
        catch { self.error = "没算出来，再试一次。" }
    }

    private func askKe(_ result: FortuneResult) {
        let text = "爸比，我算了\(result.kind_name)，帮我看看。[命理#\(result.id)]"
        NotificationCenter.default.post(name: .tarotReadingRequest, object: text)
        dismiss()
    }
}
