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
        TabView(selection: $selection) {

            UsView()
                .tabItem { Label("我们", systemImage: "calendar.badge.clock") }
                .tag(Tab.us)

            ChatView()
                .tabItem { Label("柯", systemImage: "bubble.left.and.heart.fill") }
                .tag(Tab.ke)

            PlayView()
                .tabItem { Label("玩", systemImage: "sparkles") }
                .tag(Tab.play)

            MemoriesView()
                .tabItem { Label("回忆", systemImage: "bookmark.fill") }
                .tag(Tab.memories)
        }
        .background(theme.effectiveBackground.ignoresSafeArea())
    }
}

#Preview {
    RootTabView().environmentObject(Theme.shared)
}
