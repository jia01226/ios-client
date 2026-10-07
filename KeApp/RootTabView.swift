import SwiftUI
import UIKit

struct RootTabView: View {

    @EnvironmentObject private var theme: Theme
    @State private var selection: Tab
    @State private var chatLine: ChatLine = .test1
    @State private var keyboardIsVisible = false
    @State private var chatSettingsOpen = false

    enum Tab: Hashable {
        // 佳佳 2026-10-06：原来「佳佳」那一格换成柯的抽屉——他自己的地方。
        case ke, us, play, drawer
    }

    init() {
        let previewUs = ProcessInfo.processInfo.arguments.contains("-preview-us")
        _selection = State(initialValue: previewUs ? .us : .ke)
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
                    ChatView(line: chatLine, selectedLine: $chatLine)
                        .id(chatLine)
                        .opacity(selection == .ke ? 1 : 0)
                        .allowsHitTesting(selection == .ke)
                        .accessibilityHidden(selection != .ke)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !keyboardIsVisible && !chatSettingsOpen {
                    Group {
                        if theme.skin == .day && selection != .ke { journalTabBar } else { crystalTabBar }
                    }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("root-tab-bar")
                }
            }
            .background {
                if selection != .ke {
                    theme.pageBackground.ignoresSafeArea()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chatSettingsVisibility)) { notification in
            chatSettingsOpen = notification.object as? Bool ?? false
        }
        .onReceive(NotificationCenter.default.publisher(for: .tarotReadingRequest)) { notification in
            selection = .ke
            guard let text = notification.object as? String, !text.isEmpty else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .chatSendRequest, object: text)
            }
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
            UsView(line: chatLine).id(chatLine)
        case .ke:
            Color.clear.allowsHitTesting(false)
        case .play:
            PlayView(line: chatLine).id(chatLine)
        case .drawer:
            KeSpaceView(line: chatLine).id(chatLine)
        }
    }

    private var journalTabBar: some View {
        HStack(spacing: 0) {
            journalTab(.ke, label: "柯", symbol: "bubble.left")
            journalTab(.us, label: "我们", symbol: "heart")
            journalTab(.play, label: "玩", symbol: "gamecontroller")
            journalTab(.drawer, label: "柯的", symbol: "archivebox")
        }
        .padding(.horizontal, 12).padding(.top, 9).padding(.bottom, 3)
        .background(theme.pageBackground.opacity(0.96))
        .overlay(alignment: .top) { Rectangle().fill(theme.pageColor.separator.opacity(0.55)).frame(height: 0.5) }
    }
    private func journalTab(_ tab: Tab, label: String, symbol: String) -> some View {
        Button { selection = tab } label: {
            VStack(spacing: 5) {
                Image(systemName: tab == selection ? symbol + ".fill" : symbol)
                    .font(.system(size: 18, weight: .ultraLight)).frame(height: 22)
                Text(label).font(.custom("NotoSerifSC-ExtraLight", size: 11))
            }
            .foregroundStyle(tab == selection ? theme.pageAccent : theme.pageColor.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("tab-\(tab)")
    }

    private var crystalTabBar: some View {
        HStack(spacing: 0) {
            tabButton(.ke, label: "柯")
            tabButton(.us, label: "我们")
            tabButton(.play, label: "玩")
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
            selection = tab
        } label: {
            VStack(spacing: 1) {
                Image(systemName: symbol(for: tab))
                    .font(.system(size: 23, weight: .medium))
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
        case .us: return "moon.stars.fill"
        case .ke: return "bubble.left.and.bubble.right.fill"
        case .play: return "sparkles"
        case .drawer: return "archivebox.fill"
        }
    }

}

#Preview {
    RootTabView().environmentObject(Theme.shared)
}


extension Notification.Name {
    static let chatSettingsVisibility = Notification.Name("love.chatSettingsVisibility")
    static let chatSendRequest = Notification.Name("love.chatSendRequest")
}
