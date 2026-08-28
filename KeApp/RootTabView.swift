import SwiftUI
import UIKit

// 底部四个 tab —— 她 2026-08-14 18:45 自己定的。
//
// 顺序也是她定的：我们 / 柯 / 玩 / 回忆
// 「不喜欢点开太多的 tag，划上划下的」→ 层级要浅，宁可横着多一格。
//
// ⚠️ 别自作主张加第五个。

struct RootTabView: View {

    @EnvironmentObject private var theme: Theme
    @State private var selection: Tab = .ke   // 默认落在聊天页
    @State private var keyboardIsVisible = false

    enum Tab: Hashable {
        case us, ke, play, memories
    }

    var body: some View {
        ZStack {
            AppAtmosphere()

            VStack(spacing: 0) {
                // 由系统 TabView 管四个顶层页面的生命周期和可见层级：已经访问过的
                // ChatView 会保留状态，同时只有当前页面参与命中测试和主要渲染。
                TabView(selection: $selection) {
                    UsView()
                        .tag(Tab.us)
                    ChatView()
                        .tag(Tab.ke)
                    PlayView()
                        .tag(Tab.play)
                    MemoriesView()
                        .tag(Tab.memories)
                }
                .toolbar(.hidden, for: .tabBar)

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
        .padding(.horizontal, theme.metric.pagePadding)
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
        Image(assetName)
            .resizable()
            .scaledToFit()
            .padding(1)
        .scaleEffect(selected ? 1 : 0.92)
        .animation(.easeOut(duration: 0.16), value: selected)
        .accessibilityHidden(true)
    }

    private var assetName: String {
        switch (tab, selected) {
        case (.us, false): return "NavUsIdle"
        case (.us, true): return "NavUsSelected"
        case (.ke, false): return "NavKeIdle"
        case (.ke, true): return "NavKeSelected"
        case (.play, false): return "NavPlayIdle"
        case (.play, true): return "NavPlaySelected"
        case (.memories, false): return "NavMemoryIdle"
        case (.memories, true): return "NavMemorySelected"
        }
    }
}

#Preview {
    RootTabView().environmentObject(Theme.shared)
}
