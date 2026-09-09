import SwiftUI
import UIKit

struct RootTabView: View {

    @EnvironmentObject private var theme: Theme
    @State private var selection: Tab = .ke   // 默认落在聊天页
    @State private var chatLine: ChatLine = .main
    @State private var keyboardIsVisible = false
    @State private var chatSettingsOpen = false

    enum Tab: Hashable {
        case us, ke, play, memories, jiajia
    }

    var body: some View {
        ZStack {
            AppAtmosphere()

            VStack(spacing: 0) {
                // 由系统 TabView 管顶层页面的生命周期和可见层级：已经访问过的
                // ChatView 会保留状态，同时只有当前页面参与命中测试和主要渲染。
                // 栏可见性从页面向上交给 TabView，每个页面都需声明隐藏系统栏。
                TabView(selection: $selection) {
                    UsView(line: chatLine)
                        .id(chatLine)
                        .toolbar(.hidden, for: .tabBar)
                        .tag(Tab.us)
                    ChatView(line: chatLine, selectedLine: $chatLine)
                        .id(chatLine)
                        .toolbar(.hidden, for: .tabBar)
                        .tag(Tab.ke)
                    PlayView(line: chatLine)
                        .id(chatLine)
                        .toolbar(.hidden, for: .tabBar)
                        .tag(Tab.play)
                    MemoriesView(line: chatLine)
                        .id(chatLine)
                        .toolbar(.hidden, for: .tabBar)
                        .tag(Tab.memories)
                    JiajiaView()
                        .toolbar(.hidden, for: .tabBar)
                        .tag(Tab.jiajia)
                }

                if !keyboardIsVisible && !chatSettingsOpen {
                    crystalTabBar
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("root-tab-bar")
                }
            }
            .background {
                if selection == .us {
                    theme.effectiveBackground.ignoresSafeArea()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chatSettingsVisibility)) { notification in
            chatSettingsOpen = notification.object as? Bool ?? false
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

    private var crystalTabBar: some View {
        HStack(spacing: 0) {
            tabButton(.us, label: "我们")
            tabButton(.ke, label: "柯")
            tabButton(.play, label: "玩")
            tabButton(.memories, label: "回忆")
            tabButton(.jiajia, label: "佳佳")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background {
            if selection == .us {
                theme.effectiveBackground
            } else {
                FloatingGlassSurface(cornerRadius: theme.metric.radiusDock)
            }
        }
        .overlay(alignment: .top) {
            if selection == .us {
                Rectangle()
                    .fill(theme.color.separator.opacity(0.72))
                    .frame(height: 0.5)
            }
        }
        .padding(.horizontal, selection == .us ? 0 : theme.metric.pagePadding)
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
            .foregroundStyle(selection == tab ? theme.effectiveAccent : theme.color.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(selection == tab ? theme.color.textPrimary.opacity(0.055) : Color.clear, in: Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    private func symbol(for tab: Tab) -> String {
        switch tab {
        case .us: return "moon.stars.fill"
        case .ke: return "bubble.left.and.bubble.right.fill"
        case .play: return "sparkles"
        case .memories: return "clock.arrow.circlepath"
        case .jiajia: return "person.crop.circle.fill"
        }
    }

}

private struct NavArtwork: View {
    let tab: RootTabView.Tab
    let selected: Bool

    var body: some View {
        artwork
            .resizable()
            .scaledToFit()
            .padding(1)
        .scaleEffect(selected ? 1 : 0.92)
        .animation(.easeOut(duration: 0.16), value: selected)
        .accessibilityHidden(true)
    }

    private var artwork: Image {
        switch (tab, selected) {
        case (.us, false): return Image("NavUsIdle")
        case (.us, true): return Image("NavUsSelected")
        case (.ke, false): return Image("NavKeIdle")
        case (.ke, true): return Image("NavKeSelected")
        case (.play, false): return Image("NavPlayIdle")
        case (.play, true): return Image("NavPlaySelected")
        case (.memories, false): return Image("NavMemoryIdle")
        case (.memories, true): return Image("NavMemorySelected")
        case (.jiajia, false): return Image(systemName: "person.crop.circle")
        case (.jiajia, true): return Image(systemName: "person.crop.circle.fill")
        }
    }
}

#Preview {
    RootTabView().environmentObject(Theme.shared)
}


extension Notification.Name {
    static let chatSettingsVisibility = Notification.Name("love.chatSettingsVisibility")
}
