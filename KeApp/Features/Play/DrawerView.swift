import SwiftUI

struct RemoteDrawer: Decodable, Sendable {
    let sealed: Bool
    let outside: [Item]
    struct Item: Decodable, Identifiable, Sendable {
        let id: Int
        let title: String
        let teaser: String
        let content: String
        let visibility: String
        let created_at: String
    }
}

struct DrawerView: View {
    let line: ChatLine
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    @State private var drawer: RemoteDrawer?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error); Button("重试") { Task { await load() } } }
                if let drawer {
                    ForEach(drawer.outside) { item in
                        Section(item.title) {
                            Text(item.visibility == "released" ? item.content : item.teaser)
                            Text(item.created_at).font(theme.font.caption)
                        }
                    }
                    if drawer.outside.isEmpty { Text("柯还没有放东西在外面。") }
                    if drawer.sealed { Text("还有一些，他暂时留给自己。") }
                } else if error == nil { ProgressView("正在打开") }
            }
            .scrollContentBackground(.hidden)
            .background(theme.effectiveBackground)
            .tint(theme.effectiveAccent)
            .navigationTitle("抽屉")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .task { await load() }
            .refreshable { await load() }
        }
    }
    @MainActor private func load() async {
        do { drawer = try await APIClient(baseURL: line.apiBaseURL).fetchDrawer(); error = nil }
        catch { self.error = "没有打开成功，请重试。" }
    }
}
