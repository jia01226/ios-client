import SwiftUI

// 112：聊天页的设置抽屉。聊天页往左划，从右边拉出四分之三宽的纸；左边露出一条变暗的聊天，点它或往右划就收回。
// 11-16 她：不要文绉绉的名字，简单明了；细线分割、组和组之间留白，不加框、不放小图标。
// 首页一列分组（模型 · 主动消息 · 聊天窗口 · 外观 · 工具），每行右边写着现在的值，点进去是那一页。

enum KeSettingsTab: String, CaseIterable, Identifiable {
    /// garden 是首页（名字沿用：聊天页、换窗挑选页都拿它回到首页）
    case garden, model, effort, visits, window, text, bubbles, paper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .garden: return "设置"
        case .model: return "模型"
        case .effort: return "思考深度"
        case .visits: return "主动消息"
        case .window: return "聊天窗口"
        case .text: return "字体与字号"
        case .bubbles: return "聊天气泡"
        case .paper: return "主题色"
        }
    }
}

/// 首页「工具」那组、还有几行，打开原来功能区的那些页，原来的功能一个不少。
enum KeDrawerTool {
    case search, dates, fonts, appearance, usage, all, workshop
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

/// 127：从聊天页往左拉出抽屉时手指每动一下的距离。单独放一个对象里，只有抽屉外框看着它：
/// 以前放在 ChatView 的 @State 里，拉一下整个聊天页（连同把整段记录重新切成时间线）就重画一遍。
@MainActor
final class KeDrawerPullState: ObservableObject {
    @Published var pull: CGFloat = 0
}

/// 127：抽屉里面那一大块只在开关、换页时才需要重算；外框跟着手动的时候不碰它。
private struct KeDrawerContentHost<Content: View>: View, Equatable {
    let key: AnyHashable
    let content: Content
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }
    var body: some View { content }
}

struct KeDrawerOverlay<Content: View>: View {
    @Binding var isOpen: Bool
    /// 从聊天页往左拉出来的距离（手还没松开时跟着手走）
    @ObservedObject var pullState: KeDrawerPullState
    /// 127：里面的内容什么时候需要重算（开关、换页）；其余时候拖动只挪外框
    let contentKey: AnyHashable
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(CamelliaPalette.storageKey) private var savedPalette = CamelliaPalette.defaultPalette.rawValue
    @State private var closingDrag: CGFloat = 0
    @State private var controlActive = false
    /// 127：抽屉停稳了才换成玻璃；拉出来、滑进滑出的路上是一张实心纸（不让模糊跟着每帧重采样底下的聊天）
    @State private var settled = false

    private var palette: CamelliaPalette { .resolve(savedPalette) }

    var body: some View {
        GeometryReader { geo in
            let width = (geo.size.width * 0.75).rounded()
            let pull = pullState.pull
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
                KeDrawerContentHost(key: contentKey, content: content())
                    .equatable()
                    .environment(\.keDrawerControlActive, $controlActive)
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    // 11-19 她：「退出设置的时候字会闪过」——以前一往右划就从玻璃一下子换成实心纸，背景一亮、字跟着一闪。
                    // 停稳以后一路是玻璃，收回去、滑出屏幕了才换回纸（拉出来的路上照旧是纸，不让模糊跟着每帧重算）
                    .background { panelBackground(glass: settled).ignoresSafeArea() }
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Ink.line.opacity(0.35))
                            .frame(width: 0.7)
                            .ignoresSafeArea()
                    }
                    // 127：原来整块抽屉挂一个半径 18 的 .shadow（要按里面所有字和图的轮廓每帧离屏算），
                    // 换成贴在左边的一条渐变，样子差不多，是静止的
                    .background(alignment: .leading) {
                        LinearGradient(colors: [.clear, Ink.primary.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 16)
                            .offset(x: -16)
                            .opacity(progress)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }
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
        .task(id: isOpen) {
            guard isOpen else {
                // 等收回的弹簧走完（0.38 秒）再换回纸
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 450))
                guard !Task.isCancelled else { return }
                settled = false
                return
            }
            // 弹簧 0.38 秒，等它停稳再换玻璃
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 450))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { settled = true }
        }
    }

    @ViewBuilder
    private func panelBackground(glass: Bool) -> some View {
        // 117：抽屉也是那块玻璃；上面字多，纸色垫厚一点
        ZStack {
            if glass {
                KeGlass(shape: Rectangle(), minPaper: 0.72, native: true)
                    .transition(.identity)
            }
            palette.paper.opacity(glass ? 0 : 1)
        }
        // 停稳后纸淡出、露出玻璃；一收回（或往右拖）立刻是整张纸，不跟着收回的弹簧慢慢变，免得半透一下
        .transaction(value: glass) { transaction in
            if !glass { transaction.animation = nil }
        }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if page == .garden {
                        KeSettingsHome(vm: vm, store: store, onPick: go, onOpenTool: onOpenTool, onStartPick: onStartPick)
                    } else {
                        Text(page.title)
                            .font(Ink.song(24))
                            .tracking(2)
                            .foregroundStyle(Ink.primary)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.bottom, 18)
                        pageContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .id(page)
            .frame(maxHeight: .infinity)
        }
        .task(id: isOpen) {
            guard isOpen else { return }
            // 127：等抽屉滑完再去读。读回来会让整个聊天页重画，赶在滑的路上就是一卡
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await store.loadWindow()
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .garden: EmptyView()
        case .model: KeModelPage(vm: vm)
        case .effort: KeEffortPage(store: store)
        case .visits: KeVisitsPage(store: store)
        case .window: KeWindowPage(store: store, onStartPick: onStartPick)
        case .text: KeTextPage(onOpenTool: onOpenTool)
        case .bubbles: KeBubblePage()
        case .paper: KePaperPage()
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
                    Text("设置")
                }
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(page == .garden ? 0 : 1)
            .disabled(page == .garden)
            .accessibilityLabel("回到设置")
            .accessibilityHidden(page == .garden)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("收起设置")
        }
        .font(.system(size: 13))
        .foregroundStyle(Ink.secondary)
        .padding(.leading, 15)
        .padding(.trailing, 6)
        .padding(.top, 4)
    }
}

// MARK: - 首页：柯 + 五组

struct KeSettingsHome: View {
    @EnvironmentObject private var theme: Theme
    @ObservedObject var vm: ChatViewModel
    @ObservedObject var store: KeWindowStore
    let onPick: (KeSettingsTab) -> Void
    let onOpenTool: (KeDrawerTool) -> Void
    let onStartPick: () -> Void

    @AppStorage(CamelliaPalette.storageKey) private var savedPalette = CamelliaPalette.defaultPalette.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("设置")
                .font(Ink.song(26))
                .tracking(3)
                .foregroundStyle(Ink.primary)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 14)

            profile

            KeSettingsGroup("模型") {
                KeSettingsRow(title: "模型", value: modelName, id: "settings-row-model") { onPick(.model) }
                KeSettingsRow(title: "额度", value: quota?.compactRemainingText,
                              valueTint: quota?.isRunningLow == true ? Ink.negative : nil,
                              id: "settings-row-quota") { onOpenTool(.usage) }
                KeSettingsRow(title: "思考深度", value: store.settings?.effortLevel?.title,
                              last: true, id: "settings-row-effort") { onPick(.effort) }
            }

            KeSettingsGroup("主动消息") {
                if let settings = store.settings {
                    KeSettingsToggleRow(title: "柯会主动找我", isOn: Binding(
                        get: { store.settings?.proactiveOn ?? settings.proactiveOn },
                        set: { store.change(\.proactiveOn, to: $0, key: "proactive_on", wire: $0) }
                    ))
                }
                KeSettingsRow(title: "免打扰时段", value: store.settings.map { quiet($0.quietWeekday) },
                              id: "settings-row-quiet") { onPick(.visits) }
                KeSettingsRow(title: "夜间消息间隔", value: store.settings.map { "\($0.nightGap) 分钟" },
                              id: "settings-row-night-gap") { onPick(.visits) }
                KeSettingsRow(title: "小红书分享", value: store.settings.map { $0.xhsPerDay == 0 ? "不分享" : "每天 \($0.xhsPerDay) 次" },
                              last: true, id: "settings-row-xhs") { onPick(.visits) }
            }

            KeSettingsGroup("聊天窗口") {
                KeSettingsRow(title: "窗口用量", value: windowUsage, progress: windowFill,
                              id: "settings-row-window") { onPick(.window) }
                KeSettingsRow(title: "清理窗口", id: "settings-row-wash") { onPick(.window) }
                KeSettingsRow(title: "换新窗口", id: "settings-row-rotate", action: onStartPick)
                KeSettingsRow(title: "已固定的对话", value: store.window.map { "\($0.pins.count) 段" },
                              last: true, id: "settings-row-pins") { onPick(.window) }
            }

            KeSettingsGroup("外观") {
                KeSettingsRow(title: "主题色", value: CamelliaPalette.resolve(savedPalette).label,
                              id: "settings-row-paper") { onPick(.paper) }
                KeSettingsRow(title: "字体与字号", value: "\(Int(theme.chatFontSize))",
                              id: "settings-row-text") { onPick(.text) }
                KeSettingsRow(title: "聊天气泡", id: "settings-row-bubbles") { onPick(.bubbles) }
                KeSettingsRow(title: "聊天背景", last: true, id: "settings-row-wallpaper") { onOpenTool(.appearance) }
            }

            KeSettingsGroup("工具") {
                KeSettingsRow(title: "搜索聊天记录", id: "settings-row-search") { onOpenTool(.search) }
                // 11-17 她：「工坊和这个用不上，更多聊天工具是重合的」——两行都拿掉
                KeSettingsRow(title: "按日期查找", last: true, id: "settings-row-dates") { onOpenTool(.dates) }
            }

            Text("向右划收回")
                .font(.system(size: 11))
                .foregroundStyle(Ink.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
        }
        .task { await vm.loadModelSettings() }
        .task { await store.loadSettings() }
    }

    /// 柯：头像、名字、现在用的哪个模型。点进去换模型。
    private var profile: some View {
        Button { onPick(.model) } label: {
            HStack(spacing: 14) {
                Text("柯")
                    .font(Ink.song(22))
                    .foregroundStyle(Ink.accent)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Ink.accent.opacity(0.09)))
                VStack(alignment: .leading, spacing: 4) {
                    Text("柯")
                        .font(Ink.song(20))
                        .foregroundStyle(Ink.primary)
                    Text(modelName ?? "还没读到模型")
                        .font(Ink.latin(12))
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                KeSettingsChevron()
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { KeSettingsLine() }
        .accessibilityIdentifier("settings-profile")
    }

    private var selectedOption: ChatModelOption? {
        vm.modelOptions.first { $0.id == vm.selectedModel }
    }

    private var modelName: String? {
        selectedOption?.displayName ?? vm.selectedModel
    }

    /// 现在用的这个号还剩多少；用的不是 Claude（没额度可看）就空着
    private var quota: ChatModelQuotaGroup? {
        guard let option = selectedOption else { return nil }
        let group = ChatModelSection.normalizedGroup(option.family ?? option.group ?? option.provider ?? "")
        return vm.modelQuotaCatalog?.groups.first { ChatModelSection.normalizedGroup($0.id) == group }
    }

    private var windowUsage: String? {
        store.window.map { "\(KeWindowFormat.wan($0.contextTokens)) / \(KeWindowFormat.wan($0.rotateAt))" }
    }

    private var windowFill: Double? {
        store.window.map { min(1, Double($0.contextTokens) / Double(max($0.rotateAt, 1))) }
    }

    /// 「23:00-08:30」写成「23:00 – 08:30」
    private func quiet(_ range: String) -> String {
        KeQuietRange(range).map { _ in range.replacingOccurrences(of: "-", with: " – ") } ?? range
    }
}

// MARK: - 首页的零件：一组、一行、细线

struct KeSettingsGroup<Rows: View>: View {
    let title: String
    let rows: Rows

    init(_ title: String, @ViewBuilder rows: () -> Rows) {
        self.title = title
        self.rows = rows()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Ink.song(12))
                .tracking(2)
                .foregroundStyle(Ink.secondary)
                .padding(.top, 30)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            rows
        }
    }
}

/// 一行：名字 · 现在的值 · 小箭头。最后一行不画线，靠下面的留白收住。
struct KeSettingsRow: View {
    let title: String
    var value: String?
    var valueTint: Color?
    /// 窗口用量那行底下的一条细进度
    var progress: Double?
    var last = false
    var id: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(Ink.song(15))
                        .foregroundStyle(Ink.primary)
                    Spacer(minLength: 8)
                    if let value {
                        Text(value)
                            .font(Ink.latin(13))
                            .monospacedDigit()
                            .foregroundStyle(valueTint ?? Ink.secondary)
                            .lineLimit(1)
                    }
                    KeSettingsChevron()
                }
                if let progress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Ink.track)
                            Capsule().fill(Ink.accent.opacity(0.7)).frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 2)
                    .padding(.trailing, 18)
                    .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 13)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { if !last { KeSettingsLine() } }
        .accessibilityIdentifier(id ?? "settings-row-\(title)")
    }
}

struct KeSettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var last = false

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(Ink.song(15))
                .foregroundStyle(Ink.primary)
        }
        .tint(Ink.accent)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) { if !last { KeSettingsLine() } }
    }
}

struct KeSettingsLine: View {
    var body: some View {
        Rectangle()
            .fill(Ink.line.opacity(0.35))
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

struct KeSettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .light))
            .foregroundStyle(Ink.secondary.opacity(0.7))
            .accessibilityHidden(true)
    }
}

// MARK: - 主题色：五款纸色

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
            KeDrawerHint("点一款，【我们】、设置和这里的纸一起换色。")
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
