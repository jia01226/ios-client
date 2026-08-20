import SwiftUI

// 底部四个 tab —— 她 2026-08-14 18:45 自己定的。
//
// 顺序也是她定的：我们 / 柯 / 玩 / 回忆
// 「不喜欢点开太多的 tag，划上划下的」→ 层级要浅，宁可横着多一格。
//
// ⚠️ 别自作主张加第五个。

struct RootTabView: View {

    @EnvironmentObject private var theme: Theme
    @State private var selection: Tab = .ke   // 默认落在聊天页

    enum Tab: Hashable {
        case us, ke, play, memories
    }

    var body: some View {
        ZStack {
            AppAtmosphere()

            // 四个页面保持在稳定的视图树里。之前用 switch 会在切 Tab 时销毁
            // ChatView 及其 StateObject，重新进聊天就可能正好撞上历史请求/缓存竞态，
            // 出现整页空白，必须再切一次才能恢复。
            UsView()
                .tabLayer(isActive: selection == .us)
            ChatView()
                .tabLayer(isActive: selection == .ke)
            PlayView()
                .tabLayer(isActive: selection == .play)
            MemoriesView()
                .tabLayer(isActive: selection == .memories)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            crystalTabBar
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
        .background(CrystalSurface(cornerRadius: theme.metric.radiusDock, strength: 1.15))
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

private extension View {
    func tabLayer(isActive: Bool) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
            .zIndex(isActive ? 1 : 0)
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
