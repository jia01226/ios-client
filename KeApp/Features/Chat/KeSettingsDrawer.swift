import SwiftUI

// 112：聊天页的「月隐」设置抽屉。照 10-16 她点头的网页样子做：
// 聊天页往左划，从右边拉出四分之三宽的纸；左边露出一条变暗的聊天，点它或往右划就收回。
// 四页：话笺（字体·气泡·模型）、来信（柯来找我）、素笺（四款纸色）、换窗（带着这一程）。

enum KeSettingsTab: String, CaseIterable, Identifiable {
    case garden, words, visits, paper, window

    static let tabs: [KeSettingsTab] = [.words, .visits, .paper, .window]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .garden: return "月隐"
        case .words: return "话笺"
        case .visits: return "来信"
        case .paper: return "素笺"
        case .window: return "换窗"
        }
    }

    /// 顶上居中的小字
    var caption: String {
        switch self {
        case .garden: return "设置"
        case .words: return "聊天"
        case .visits: return "柯来找我"
        case .paper: return "配色"
        case .window: return "留住这一程"
        }
    }

    /// 目录页名字下面那行
    var subtitle: String {
        switch self {
        case .garden: return "一枝收月色"
        case .words: return "字体 · 气泡 · 模型"
        case .visits: return "柯来找我"
        case .paper: return "四款纸色"
        case .window: return "带着这一程"
        }
    }

    var script: String {
        switch self {
        case .garden: return "Moonlit"
        case .words: return "Words between us"
        case .visits: return "A little closer"
        case .paper: return "Paper & light"
        case .window: return "A new window"
        }
    }
}

/// 话笺里「更多」能回到原来功能区的那些页，原来的功能一个不少。
enum KeDrawerTool {
    case search, dates, fonts, appearance, usage, all
}

// MARK: - 滑杆按住时别把横向拖动当成「收回抽屉」

private struct KeDrawerControlActiveKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var keDrawerControlActive: Binding<Bool> {
        get { self[KeDrawerControlActiveKey.self] }
        set { self[KeDrawerControlActiveKey.self] = newValue }
    }
}

enum KeDrawerMotion {
    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86)
    }
}

// MARK: - 外框：暗条 + 从右边滑进来的纸

struct KeDrawerOverlay<Content: View>: View {
    @Binding var isOpen: Bool
    /// 从聊天页往左拉出来的距离（手还没松开时跟着手走）
    let pull: CGFloat
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(CamelliaPalette.storageKey) private var savedPalette = CamelliaPalette.defaultPalette.rawValue
    @State private var closingDrag: CGFloat = 0
    @State private var controlActive = false

    private var palette: CamelliaPalette { .resolve(savedPalette) }

    var body: some View {
        GeometryReader { geo in
            let width = (geo.size.width * 0.75).rounded()
            let shown = isOpen ? max(0, width - closingDrag) : min(width, max(0, pull))
            let progress = width > 0 ? shown / width : 0
            ZStack(alignment: .trailing) {
                Ink.primary.opacity(0.22 * progress)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .allowsHitTesting(isOpen)
                    .accessibilityElement()
                    .accessibilityLabel("收起设置，回到聊天")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { close() }
                    .accessibilityHidden(!isOpen)

                // 一直留在层级里，只是推到屏幕外：这样收回时也有滑出去的动画。
                content()
                    .environment(\.keDrawerControlActive, $controlActive)
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .background { panelBackground.ignoresSafeArea() }
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Ink.line.opacity(0.35))
                            .frame(width: 0.7)
                            .ignoresSafeArea()
                    }
                    .shadow(color: Ink.primary.opacity(0.10 * progress), radius: 18, x: -6)
                    .offset(x: width - shown)
                    .allowsHitTesting(isOpen)
                    .accessibilityHidden(!isOpen)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityAction(.escape) { close() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .simultaneousGesture(closeGesture(width: width))
        }
        .onChange(of: isOpen) { _, open in
            if !open { controlActive = false }
        }
    }

    @ViewBuilder
    private var panelBackground: some View {
        // 117：抽屉也是那块玻璃；上面字多，纸色垫厚一点
        KeGlass(shape: Rectangle(), minPaper: 0.72)
    }

    /// 往右划收回。滑杆按着的时候不算。
    private func closeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard isOpen, !controlActive else { return }
                let dx = value.translation.width, dy = value.translation.height
                guard dx > 0, abs(dx) > abs(dy) * 1.2 else { return }
                closingDrag = dx
            }
            .onEnded { value in
                guard isOpen else { return }
                let shouldClose = !controlActive && closingDrag > 0
                    && (closingDrag > width * 0.32 || value.predictedEndTranslation.width > width * 0.7)
                withAnimation(KeDrawerMotion.animation(reduceMotion: reduceMotion)) {
                    closingDrag = 0
                    if shouldClose { isOpen = false }
                }
            }
    }

    private func close() {
        withAnimation(KeDrawerMotion.animation(reduceMotion: reduceMotion)) {
            closingDrag = 0
            isOpen = false
        }
    }
}

// MARK: - 抽屉里面

struct KeSettingsDrawer: View {
    let isOpen: Bool
    @ObservedObject var vm: ChatViewModel
    @ObservedObject var store: KeWindowStore
    @Binding var page: KeSettingsTab
    let onClose: () -> Void
    let onOpenTool: (KeDrawerTool) -> Void
    let onStartPick: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs
            Group {
                if page == .garden {
                    KeDrawerGarden { go($0) }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(page.title)
                                .font(Ink.song(26))
                                .tracking(3)
                                .foregroundStyle(Ink.primary)
                                .accessibilityAddTraits(.isHeader)
                            Text(page.script)
                                .font(Ink.script(20))
                                .foregroundStyle(Ink.secondary)
                                .padding(.bottom, 14)
                            pageContent
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 36)
                    }
                    .scrollIndicators(.hidden)
                    .id(page)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .task(id: isOpen) {
            guard isOpen else { return }
            await store.loadWindow()
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .garden: EmptyView()
        case .words: KeWordsPage(vm: vm, store: store, onOpenTool: onOpenTool)
        case .visits: KeVisitsPage(store: store)
        case .paper: KePaperPage()
        case .window: KeWindowPage(store: store, onStartPick: onStartPick)
        }
    }

    private func go(_ next: KeSettingsTab) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { page = next }
    }

    private var header: some View {
        HStack {
            Button { go(.garden) } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 12))
                    Text("目录")
                }
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(page == .garden ? 0 : 1)
            .disabled(page == .garden)
            .accessibilityLabel("回到目录")
            .accessibilityHidden(page == .garden)

            Spacer()
            Text(page.caption)
            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("收起设置抽屉")
        }
        .font(.system(size: 12))
        .foregroundStyle(Ink.secondary)
        .padding(.leading, 15)
        .padding(.trailing, 6)
        .padding(.top, 4)
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(KeSettingsTab.tabs) { tab in
                Button { go(tab) } label: {
                    Text(tab.title)
                        .font(Ink.song(14))
                        .foregroundStyle(page == tab ? Ink.primary : Ink.secondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(page == tab ? Ink.accent : Color.clear)
                                .frame(height: 1)
                                .padding(.horizontal, 10)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(page == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.line.opacity(0.35)).frame(height: 0.6)
        }
    }
}

// MARK: - 目录：月亮、藤蔓、四个名字

struct KeDrawerGarden: View {
    let onPick: (KeSettingsTab) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = max(geo.size.height, 480)
            ZStack(alignment: .topLeading) {
                // 藤蔓和两朵花先合在一起再一起变淡，交叠处不会透出接缝。
                ZStack(alignment: .topLeading) {
                    art("KeSettingsVine", w: w, h: h, x: 0.30, y: 0.22, width: 0.47, height: 0.76)
                    art("KeCamelliaDiary", w: w, h: h, x: 0.45, y: 0.49, width: 0.16, height: 0.16 * w / h)
                    art("KeCamelliaDiary", w: w, h: h, x: 0.42, y: 0.80, width: 0.16, height: 0.16 * w / h)
                }
                .compositingGroup()
                .opacity(0.64)

                art("KeSettingsMoon", w: w, h: h, x: 0.18, y: 0.01, width: 0.40, height: 0.35)
                    .opacity(0.62)

                ZStack {
                    Image("KeCamelliaWingLeft").resizable().scaledToFit()
                    Image("KeCamelliaWingRight").resizable().scaledToFit()
                    Image("KeCamelliaBody").resizable().scaledToFit()
                }
                .frame(width: 42, height: 42)
                .rotationEffect(.degrees(-16))
                .saturation(0.5)
                .opacity(0.5)
                .offset(x: w * 0.33, y: h * 0.67)
                .accessibilityHidden(true)

                title
                    .frame(width: w * 0.91, alignment: .trailing)
                    .offset(y: h * 0.12)

                link(.words, leading: true).offset(x: w * 0.08, y: h * 0.32)
                link(.visits, leading: true).offset(x: w * 0.08, y: h * 0.57)
                link(.paper, leading: false)
                    .frame(width: w * 0.93, alignment: .trailing)
                    .offset(y: h * 0.48)
                link(.window, leading: false)
                    .frame(width: w * 0.93, alignment: .trailing)
                    .offset(y: h * 0.77)

                Text("点名字进入 · 向右划收回")
                    .font(.system(size: 10))
                    .foregroundStyle(Ink.secondary)
                    .offset(x: w * 0.08, y: h - 30)
            }
            .frame(width: w, height: h, alignment: .topLeading)
        }
        .clipped()
    }

    private func art(_ name: String, w: CGFloat, h: CGFloat, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .saturation(0.5)
            .frame(width: w * width, height: h * height)
            .offset(x: w * x, y: h * y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// 「月隐」竖着写，左边一行小字「一枝收月色」带一条细线。
    private var title: some View {
        HStack(alignment: .top, spacing: 13) {
            vertical("一枝收月色", size: 11, spacing: 3)
                .padding(.trailing, 6)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Ink.line).frame(width: 0.7)
                }
                .foregroundStyle(Ink.secondary)
            vertical("月隐", size: 32, spacing: 8)
                .foregroundStyle(Ink.primary)
                .padding(.top, 24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("月隐，一枝收月色")
        .accessibilityAddTraits(.isHeader)
    }

    private func vertical(_ text: String, size: CGFloat, spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, char in
                Text(String(char)).font(Ink.song(size))
            }
        }
    }

    private func link(_ page: KeSettingsTab, leading: Bool) -> some View {
        Button { onPick(page) } label: {
            HStack(alignment: .top, spacing: 6) {
                if !leading { stroke }
                VStack(alignment: .leading, spacing: 3) {
                    Text(page.title)
                        .font(Ink.song(24))
                        .tracking(3)
                        .foregroundStyle(Ink.primary)
                    Text(page.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.secondary)
                }
                if leading { stroke }
            }
            .frame(minHeight: 62, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(page.title)，\(page.subtitle)")
    }

    private var stroke: some View {
        Rectangle()
            .fill(Ink.line.opacity(0.55))
            .frame(width: 24, height: 0.7)
            .padding(.top, 17)
    }
}

// MARK: - 素笺：四款纸色

struct KePaperPage: View {
    @AppStorage(CamelliaPalette.storageKey) private var savedPalette = CamelliaPalette.defaultPalette.rawValue
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(CamelliaPalette.allCases) { palette in
                    let selected = CamelliaPalette.resolve(savedPalette) == palette
                    Button { savedPalette = palette.rawValue } label: {
                        VStack(alignment: .leading) {
                            Text(palette.label)
                                .font(Ink.song(18))
                                .foregroundStyle(Ink.primary)
                            Spacer(minLength: 18)
                            Text(palette.rawValue.capitalized)
                                .font(Ink.script(16))
                                .foregroundStyle(Ink.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
                        .background(palette.paper, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(selected ? Ink.accent : Ink.line, lineWidth: selected ? 1.6 : 0.8)
                        }
                        .overlay(alignment: .topTrailing) {
                            if selected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Ink.accent)
                                    .padding(10)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(palette.label)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            KeGlassPicker()
            Text("把喜欢的纸色，铺进每一个角落。")
                .font(Ink.song(15))
                .foregroundStyle(Ink.primary)
            KeDrawerHint("点一款，【我们】、抽屉和这里的纸一起换色。")
        }
    }
}

// MARK: - 小零件

struct KeDrawerHint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Ink.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct KeDrawerSectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Ink.song(17))
            .foregroundStyle(Ink.primary)
            .padding(.top, 10)
            .accessibilityAddTraits(.isHeader)
    }
}

struct KeDrawerSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    let valueText: String
    @Environment(\.keDrawerControlActive) private var controlActive

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText).monospacedDigit()
            }
            .font(.system(size: 13))
            .foregroundStyle(Ink.secondary)
            Group {
                if let step {
                    Slider(value: $value, in: range, step: step, onEditingChanged: { controlActive.wrappedValue = $0 })
                } else {
                    Slider(value: $value, in: range, onEditingChanged: { controlActive.wrappedValue = $0 })
                }
            }
            .tint(Ink.accent)
            .accessibilityLabel(title)
            .accessibilityValue(valueText)
        }
    }
}

/// 抽屉里的两种按钮：描边的、实心的。
struct KeDrawerButtonStyle: ButtonStyle {
    var solid = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Ink.song(15))
            .foregroundStyle(solid ? CamelliaPalette.white.paper : Ink.primary)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(solid ? Ink.accent : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Ink.accent.opacity(solid ? 0 : 0.7), lineWidth: 0.8)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .contentShape(Rectangle())
    }
}

// MARK: - 电话还没接上：一张小卡

struct KeCallPlaceholderCard: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CamelliaPalette.storageKey) private var savedPalette = CamelliaPalette.defaultPalette.rawValue

    var body: some View {
        VStack(spacing: 12) {
            Text("电话功能准备中")
                .font(Ink.song(20))
                .foregroundStyle(Ink.primary)
                .accessibilityAddTraits(.isHeader)
            Text("One day, hear your voice.")
                .font(Ink.script(22))
                .foregroundStyle(Ink.secondary)
            Text("以后可以在这里和柯打电话。现在还没接上，不会拨出去。")
                .font(.system(size: 14))
                .foregroundStyle(Ink.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("知道了") { dismiss() }
                .buttonStyle(KeDrawerButtonStyle(solid: true))
                .padding(.top, 6)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CamelliaPalette.resolve(savedPalette).paper.ignoresSafeArea())
    }
}
