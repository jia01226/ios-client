import SwiftUI
import UIKit

struct RootTabView: View {

    @EnvironmentObject private var theme: Theme
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var chatNotifications = ChatNotificationCoordinator.shared
    @State private var selection: Tab
    @State private var chatLine: ChatLine = .test1
    @State private var keyboardIsVisible = false
    @State private var chatSettingsOpen = false
    /// 112：在「我们」「柯的」从最右边往左划也能拉出设置；收起后回到原来那一页
    @State private var settingsReturnTab: Tab?
    @State private var quoteOpenRequest: QuoteOpenRequest?
    @State private var chatSendRequests: [ChatSendRequest] = []
    @AppStorage(CamelliaPalette.storageKey) private var camelliaPaletteValue = CamelliaPalette.defaultPalette.rawValue
    private var camelliaPalette: CamelliaPalette { .resolve(camelliaPaletteValue) }
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// 126：底栏实际多高（大字号时会长高）、Home 条那截多高
    @State private var dockHeight: CGFloat = 58
    @State private var safeBottom: CGFloat = 0
    /// 134：手指在底栏上滑到哪儿了（没在滑就是 nil）；滑过一格震一下
    @State private var dockDragX: CGFloat?
    @State private var dockTick = 0

    enum Tab: Hashable {
        // 佳佳 2026-10-06：原来「佳佳」那一格换成柯的抽屉——他自己的地方。
        case ke, us, memory, drawer
    }

    init() {
        let previewUs = ProcessInfo.processInfo.arguments.contains("-preview-us")
        _selection = State(initialValue: ProcessInfo.processInfo.arguments.contains("-preview-memory") ? .memory : (previewUs ? .us : .ke))
    }

    var body: some View {
        ZStack {
            AppAtmosphere()
                // 126：量一下底下 Home 条那一截有多高（不算键盘），底栏照设计稿离底边 max(10, 安全区)
                .background {
                    Color.clear.ignoresSafeArea(.keyboard)
                        .onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.bottom }) { safeBottom = $0 }
                }

            // 126：页面铺满到屏幕底；底栏、月牙都浮在上面，不再占一截矩形。
            // 不使用系统 TabView，避免 iOS 17 留下透明、可命中的系统栏。
            // 聊天页始终留在层级内以保留当前窗口状态；其它页面按需加载，
            // 风铃和月球动画不会在后台继续运行。
            ZStack {
                selectedNonChatPage
                ChatView(line: chatLine, selectedLine: $chatLine, quoteOpenRequest: $quoteOpenRequest, sendRequests: $chatSendRequests)
                    .id(chatLine)
                    .opacity(selection == .ke ? 1 : 0)
                    .allowsHitTesting(selection == .ke)
                    .accessibilityHidden(selection != .ke)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 127：打开设置抽屉时底栏收起，但聊天的输入栏和记录的留白不跟着往下挪——
            // 以前抽屉一开，输入胶囊下移、时间线重算留白并重新落到最新，正好压在抽屉滑出来的那几帧上
            .environment(\.floatingDockInset, keyboardIsVisible ? 0 : dockInset)
            .overlay(alignment: .trailing) {
                if selection != .ke && !chatSettingsOpen {
                    Color.clear
                        .frame(width: KeDrawerEdge.width)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 12)
                                .onEnded { value in
                                    guard value.translation.width < -40,
                                          abs(value.translation.width) > abs(value.translation.height) else { return }
                                    openSettingsFromHome()
                                }
                        )
                        .accessibilityHidden(true)
                }
            }
            // 126：「我们」「柯的」顶上不要大标题，只留右上一枚小月牙——点了和从右边划、聊天里点三个点是同一个设置抽屉
            .overlay(alignment: .topTrailing) {
                if (selection == .us || selection == .drawer) && !chatSettingsOpen {
                    HomeSettingsMoon(action: openSettingsFromHome)
                        .padding(.trailing, theme.metric.chromeHeaderInset - 4)
                        .padding(.top, 2)
                }
            }
            .background {
                if selection == .drawer || selection == .us {
                    camelliaPalette.paper.ignoresSafeArea()
                } else if selection != .ke {
                    theme.pageBackground.ignoresSafeArea()
                }
            }

            if showsDock {
                // 记忆页永远是夜：底栏跟着用夜里的玻璃
                // 101：底栏先做最简单的三个字；126：浮起来的圆角玻璃胶囊
                simpleTabBar
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("root-tab-bar")
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    // 键盘收起的那一下底栏就回到底边，不骑在正在往下走的键盘上
                    .ignoresSafeArea(.keyboard)
            }
        }
        .preferredColorScheme(selection == .drawer || selection == .us || theme.skin != .night ? .light : .dark)
        .task {
            // 130：记忆的六团星云先在后台备好（画过的从手机里读），点进记忆不用等（旧星河的图不再用，不画了）
            NebulaArt.prewarm()
            if chatNotifications.openRequest != nil { selection = .ke }
            await chatNotifications.clearBadgeIfActive()
        }
        .onChange(of: chatNotifications.openRequest) { _, _ in selection = .ke }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await chatNotifications.clearBadgeIfActive() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chatSettingsVisibility)) { notification in
            chatSettingsOpen = notification.object as? Bool ?? false
            if !chatSettingsOpen, let back = settingsReturnTab {
                settingsReturnTab = nil
                selection = back
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tarotReadingRequest)) { notification in
            selection = .ke
            // 136：塔罗交给柯时带着那几张牌（只画在她的气泡上，不随消息发）
            if let handoff = notification.object as? ChatHandoff, !handoff.text.isEmpty {
                chatSendRequests.append(ChatSendRequest(line: chatLine, text: handoff.text, attachments: handoff.attachments))
                return
            }
            guard let text = notification.object as? String, !text.isEmpty else { return }
            chatSendRequests.append(ChatSendRequest(line: chatLine, text: text))
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillChangeFrameNotification
            )
        ) { notification in
            guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                as? CGRect else { return }
            keyboardIsVisible = endFrame.minY < UIScreen.main.bounds.maxY - 1
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardDidHideNotification
            )
        ) { _ in
            keyboardIsVisible = false
        }
    }

    @ViewBuilder
    private var selectedNonChatPage: some View {
        switch selection {
        case .us:
            UsPondView(line: chatLine).id(chatLine)
        case .ke:
            Color.clear.allowsHitTesting(false)
        case .drawer:
            KeSpaceView(line: chatLine) { quote in
                selection = .ke
                quoteOpenRequest = QuoteOpenRequest(messageID: quote.message_id)
            }.id(chatLine)
        case .memory:
            MemoryTabView(line: chatLine) { quote in
                selection = .ke
                quoteOpenRequest = QuoteOpenRequest(messageID: quote.message_id)
            }.id(chatLine)
        }
    }

    // MARK: 126 浮起来的底栏

    private var showsDock: Bool { !keyboardIsVisible && !chatSettingsOpen }
    /// 底栏离安全区底边还要多垫多少：有 Home 条的机器贴着安全区，没有的离屏幕底 10
    private var dockBottomPadding: CGFloat { max(0, theme.metric.chromeDockMinBottom - safeBottom) }
    /// 页面底下要让出来的高度（从安全区底边算起）：底栏 + 和内容之间的一点空
    private var dockInset: CGFloat { dockBottomPadding + dockHeight + theme.metric.chromeGap }

    private func openSettingsFromHome() {
        settingsReturnTab = selection
        selection = .ke
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .openKeSettings, object: nil)
        }
    }

    /// 柯 · 我们 · 柯的：三个字（宋体 14、字距 2.4），当前那页垫一层亮。整条是一块圆角玻璃，浮在页面上。
    /// 134 她：「底下 tab 切换能不能像苹果一样划过去，不是点击的那种」——照 iOS 26 的底栏：
    /// 手指按在底栏上左右滑，那块亮跟着手指走（稍微放大一点，像个放大镜），滑过一格轻轻震一下，松手就到那一页。点也照样能点。
    private static let dockTabs: [(Tab, String)] = [(.ke, "柯"), (.us, "我们"), (.drawer, "柯的")]
    private var simpleTabBar: some View {
        let tabs = Self.dockTabs
        let current = tabs.firstIndex { $0.0 == selection } ?? 0
        return GeometryReader { geo in
            let w = geo.size.width / CGFloat(tabs.count)
            // 手指在哪一格（滑的时候），不滑就是当前页
            let hover = dockDragX.map { min(tabs.count - 1, max(0, Int($0 / max(1, w)))) } ?? current
            let pillX = dockDragX.map { min(max($0, w / 2), geo.size.width - w / 2) } ?? (CGFloat(current) + 0.5) * w
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: theme.metric.chromeDockItemRadius, style: .continuous)
                    .fill(reduceTransparency ? Ink.accent.opacity(0.08) : Ink.dockSelection)
                    .frame(width: w - 3, height: geo.size.height)
                    .scaleEffect(dockDragX == nil ? 1 : 1.08)
                    .position(x: pillX, y: geo.size.height / 2)
                    .animation(dockDragX == nil ? .spring(response: 0.35, dampingFraction: 0.8) : .interactiveSpring(response: 0.18, dampingFraction: 0.86), value: pillX)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dockDragX == nil)
                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { index, item in
                        let lit = index == hover
                        Text(item.1).font(theme.font.dockLabel).tracking(theme.font.dockTracking)
                            .foregroundStyle(lit ? Ink.primary : Ink.secondary)
                            .frame(width: w, height: geo.size.height)
                            .accessibilityElement()
                            .accessibilityLabel(item.1)
                            .accessibilityAddTraits(item.0 == selection ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = item.0 } }
                            .accessibilityIdentifier("tab-\(item.0)")
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { v in
                        let moved = abs(v.translation.width) > 6 || abs(v.translation.height) > 6
                        guard moved || dockDragX != nil else { return }
                        let old = dockDragX.map { min(tabs.count - 1, max(0, Int($0 / max(1, w)))) }
                        dockDragX = v.location.x
                        let now = min(tabs.count - 1, max(0, Int(v.location.x / max(1, w))))
                        if old != nil, old != now { dockTick += 1 }
                    }
                    .onEnded { v in
                        let index = min(tabs.count - 1, max(0, Int(v.location.x / max(1, w))))
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selection = tabs[index].0
                            dockDragX = nil
                        }
                    }
            )
        }
        .frame(height: theme.metric.chromeDockHeight - 2 * theme.metric.chromeDockPadding)
        .sensoryFeedback(.selection, trigger: dockTick)
        .padding(theme.metric.chromeDockPadding)
        // 117：三个页面的底栏都是同一块液态玻璃（素笺里能选纸感/轻玻璃/浮光）；126：只画在圆角里，外面不铺底
        .background {
            KeGlass(shape: RoundedRectangle(cornerRadius: theme.metric.chromeDockRadius, style: .continuous), minPaper: 0.2)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { dockHeight = $0 }
        .padding(.horizontal, theme.metric.chromeDockInset)
        .padding(.bottom, dockBottomPadding)
    }

}

#Preview {
    RootTabView().environmentObject(Theme.shared)
}


/// 126：「我们」「柯的」右上角那枚小月牙，打开设置抽屉
struct HomeSettingsMoon: View {
    @EnvironmentObject private var theme: Theme
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "moon")
                .font(.system(size: theme.metric.homeMoonSize, weight: .light))
                .foregroundStyle(Ink.primary)
                .frame(width: theme.metric.touchTarget, height: theme.metric.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开设置")
        .accessibilityIdentifier("home-settings-moon")
    }
}

/// 126：页面底下被浮着的底栏盖住的那一截（从安全区底边算起）。键盘起来、设置打开时底栏收起，就是 0。
private struct FloatingDockInsetKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues {
    var floatingDockInset: CGFloat {
        get { self[FloatingDockInsetKey.self] }
        set { self[FloatingDockInsetKey.self] = newValue }
    }
}

extension Notification.Name {
    static let chatSettingsVisibility = Notification.Name("love.chatSettingsVisibility")
    static let openKeSettings = Notification.Name("love.openKeSettings")
}

/// Retained by the root while chat connects, logs in, or switches between tabs.
struct ChatSendRequest: Identifiable, Equatable {
    let id = UUID()
    let line: ChatLine
    let text: String
    var attachments: [ChatAttachment] = []
}

/// 别的页交给聊天发的一句话，外加只画在她气泡上的附件
struct ChatHandoff {
    let text: String
    let attachments: [ChatAttachment]
}
