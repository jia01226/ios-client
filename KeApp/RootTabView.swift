import SwiftUI
import UIKit

struct RootTabView: View {

    @EnvironmentObject private var theme: Theme
    @StateObject private var chatViewModel = ChatViewModel()
    @State private var selection: Tab
    @State private var keyboardIsVisible = false

    enum Tab: Hashable {
        case us, ke, play, memories
    }

    init() {
        let previewUs = ProcessInfo.processInfo.arguments.contains("-preview-us")
        _selection = State(initialValue: previewUs ? .us : .ke)
    }

    var body: some View {
        ZStack {
            AppAtmosphere()

            VStack(spacing: 0) {
                // 页面按需加载，避免隐藏的星空动画继续耗电；聊天数据模型由根页
                // 持有，切回聊天时消息不会丢。这里不用系统 TabView，彻底避开
                // iOS 17 的透明 49pt TabBar。
                selectedPage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !keyboardIsVisible {
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
    private var selectedPage: some View {
        switch selection {
        case .us:
            UsView()
        case .ke:
            ChatView(vm: chatViewModel)
        case .play:
            PlayView()
        case .memories:
            MemoriesView()
        }
    }

    private var crystalTabBar: some View {
        HStack(spacing: 0) {
            tabButton(.us, label: "我们")
            tabButton(.ke, label: "柯")
            tabButton(.play, label: "玩")
            tabButton(.memories, label: "回忆")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background {
            if selection == .us {
                theme.effectiveBackground
            } else {
                CrystalSurface(cornerRadius: theme.metric.radiusDock, strength: 1.15)
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
                NavArtwork(tab: tab, selected: selection == tab)
                    .frame(width: 42, height: 42)
                Text(label)
                    .font(.caption2.weight(selection == tab ? .semibold : .regular))
            }
            .foregroundStyle(selection == tab ? theme.effectiveAccent : theme.color.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        }
    }
}

#Preview {
    RootTabView().environmentObject(Theme.shared)
}
