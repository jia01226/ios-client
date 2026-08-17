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

            TabView(selection: $selection) {
                UsView().tag(Tab.us)
                ChatView().tag(Tab.ke)
                PlayView().tag(Tab.play)
                MemoriesView().tag(Tab.memories)
            }
            .toolbar(.hidden, for: .tabBar)
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
            withAnimation(.easeOut(duration: 0.18)) { selection = tab }
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
        Group {
            switch tab {
            case .us:
                sprite("UsNavSheet", size: CGSize(width: 93, height: 93), x: -26, y: selected ? -48 : -1)
            case .ke:
                sprite("KePlayNavSheet", size: CGSize(width: 134, height: 89), x: -24, y: selected ? -45 : -2)
            case .play:
                sprite("KePlayNavSheet", size: CGSize(width: 134, height: 89), x: -76, y: selected ? -45 : -2)
            case .memories:
                Image(selected ? "MemoryOpen" : "MemoryClosed")
                    .resizable()
                    .scaledToFit()
                    .padding(1)
            }
        }
        .scaleEffect(selected ? 1 : 0.92)
        .animation(.easeOut(duration: 0.16), value: selected)
        .accessibilityHidden(true)
    }

    private func sprite(_ name: String, size: CGSize, x: CGFloat, y: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image(name)
                .resizable()
                .frame(width: size.width, height: size.height)
                .offset(x: x, y: y)
        }
        .frame(width: 42, height: 42, alignment: .topLeading)
        .clipped()
    }
}

#Preview {
    RootTabView().environmentObject(Theme.shared)
}
