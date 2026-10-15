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
    @State private var quoteOpenRequest: QuoteOpenRequest?
    @State private var chatSendRequests: [ChatSendRequest] = []
    @AppStorage(CamelliaPalette.storageKey) private var camelliaPaletteValue = CamelliaPalette.defaultPalette.rawValue
    private var camelliaPalette: CamelliaPalette { .resolve(camelliaPaletteValue) }

    enum Tab: Hashable {
        // 佳佳 2026-10-06：原来「佳佳」那一格换成柯的抽屉——他自己的地方。
        case ke, us, play, memory, drawer
    }

    init() {
        let previewUs = ProcessInfo.processInfo.arguments.contains("-preview-us")
        _selection = State(initialValue: ProcessInfo.processInfo.arguments.contains("-preview-memory") ? .memory : (previewUs ? .us : .ke))
    }

    var body: some View {
        ZStack {
            AppAtmosphere()

            VStack(spacing: 0) {
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

                if !keyboardIsVisible && !chatSettingsOpen {
                    Group {
                        // 记忆页永远是夜：底栏跟着用夜里的玻璃
                        // 101：底栏先做最简单的三个字，正式样子等 GPT 设计
                        simpleTabBar
                    }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("root-tab-bar")
                }
            }
            .background {
                if selection == .drawer || selection == .us {
                    camelliaPalette.paper.ignoresSafeArea()
                } else if selection != .ke {
                    theme.pageBackground.ignoresSafeArea()
                }
            }
        }
        .preferredColorScheme(selection == .drawer || selection == .us || theme.skin != .night ? .light : .dark)
        .task {
            // 107：星河的星云、银河两张大图第一次用时现画会卡一下，先在后台画好
            Task.detached(priority: .utility) { _ = GalaxyArt.nebula; _ = GalaxyArt.galaxy; _ = GalaxyArt.glow }
            if chatNotifications.openRequest != nil { selection = .ke }
            await chatNotifications.clearBadgeIfActive()
        }
        .onChange(of: chatNotifications.openRequest) { _, _ in selection = .ke }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await chatNotifications.clearBadgeIfActive() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chatSettingsVisibility)) { notification in
            chatSettingsOpen = notification.object as? Bool ?? false
        }
        .onReceive(NotificationCenter.default.publisher(for: .tarotReadingRequest)) { notification in
            selection = .ke
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
        case .play:
            PlayView(line: chatLine).id(chatLine)
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

    /// 柯 · 我们 · 柯的：三个字，当前那页下面一个小圆点。
    private var simpleTabBar: some View {
        HStack(spacing: 0) {
            ForEach([(Tab.ke, "柯"), (Tab.us, "我们"), (Tab.drawer, "柯的")], id: \.1) { tab, label in
                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = tab } } label: {
                    VStack(spacing: 5) {
                        Text(label).font(.custom("NotoSerifSC-Light", size: 14)).tracking(2.4)
                        Circle().fill(selection == tab ? Ink.accent : Color.clear).frame(width: 4.5, height: 4.5)
                    }
                    .foregroundStyle(selection == tab ? Ink.primary : Ink.secondary)
                    .frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
                .accessibilityIdentifier("tab-\(tab)")
            }
        }
        .padding(.horizontal, 18).padding(.top, 6)
        .background(selection == .ke ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(camelliaPalette.paper))
        .overlay(alignment: .top) { Rectangle().fill(Ink.line.opacity(0.6)).frame(height: 0.5).padding(.horizontal, 18) }
    }

    private var journalTabBar: some View {
        HStack(spacing: 0) {
            journalTab(.ke, label: "柯", symbol: "bubble.left")
            journalTab(.us, label: "我们", symbol: "heart")
            journalTab(.play, label: "玩", symbol: "gamecontroller")
            journalTab(.memory, label: "记忆", symbol: "camera.macro")
            journalTab(.drawer, label: "柯的", symbol: "archivebox")
        }
        .padding(.horizontal, 12).padding(.top, 9).padding(.bottom, 3)
        .background(selection == .drawer ? camelliaPalette.paper : theme.pageBackground.opacity(0.96))
        .overlay(alignment: .top) { Rectangle().fill(theme.pageColor.separator.opacity(0.55)).frame(height: 0.5) }
    }
    private func journalTab(_ tab: Tab, label: String, symbol: String) -> some View {
        Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { selection = tab } } label: {
            VStack(spacing: 5) {
                Image(systemName: tab == selection && tab != .memory ? symbol + ".fill" : symbol)
                    .font(.system(size: 18, weight: .ultraLight)).frame(height: 22)
                    .symbolEffect(.bounce, value: tab != .memory && selection == tab)
                Text(label).font(.custom("NotoSerifSC-ExtraLight", size: 11))
            }
            .foregroundStyle(selection == .drawer
                ? (tab == selection ? CamelliaPalette.ink : CamelliaPalette.secondaryInk)
                : (tab == selection ? theme.pageAccent : theme.pageColor.textSecondary))
            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("tab-\(tab)")
    }

    private var crystalTabBar: some View {
        HStack(spacing: 0) {
            tabButton(.ke, label: "柯")
            tabButton(.us, label: "我们")
            tabButton(.play, label: "玩")
            tabButton(.memory, label: "记忆")
            tabButton(.drawer, label: "柯的")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(FloatingGlassSurface(cornerRadius: theme.metric.radiusDock))
        .padding(.horizontal, theme.metric.pagePadding)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private func tabButton(_ tab: Tab, label: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { selection = tab }
        } label: {
            VStack(spacing: 1) {
                Image(systemName: symbol(for: tab))
                    .font(.system(size: 23, weight: .light))
                    .symbolEffect(.bounce, value: selection == tab)
                    .frame(width: 42, height: 30)
                Text(label)
                    .font(.caption2.weight(selection == tab ? .semibold : .regular))
            }
            .foregroundStyle(selection == tab ? (selection == .ke ? theme.effectiveAccent : theme.pageAccent) : (selection == .ke ? theme.color.textSecondary : theme.pageColor.textSecondary))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(selection == tab ? theme.color.textPrimary.opacity(0.055) : Color.clear, in: Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab-\(tab)")
    }
    private func symbol(for tab: Tab) -> String {
        switch tab {
        case .us: return selection == tab ? "heart.fill" : "heart"
        case .ke: return "bubble.left.and.bubble.right.fill"
        case .play: return selection == tab ? "gamecontroller.fill" : "gamecontroller"
        case .drawer: return selection == tab ? "archivebox.fill" : "archivebox"
        case .memory: return "camera.macro"
        }
    }

}

#Preview {
    RootTabView().environmentObject(Theme.shared)
}


extension Notification.Name {
    static let chatSettingsVisibility = Notification.Name("love.chatSettingsVisibility")
}

/// Retained by the root while chat connects, logs in, or switches between tabs.
struct ChatSendRequest: Identifiable, Equatable {
    let id = UUID()
    let line: ChatLine
    let text: String
}
