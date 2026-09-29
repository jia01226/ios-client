import SwiftUI

struct RemoteDrawer: Decodable, Sendable {
    let sealed: Bool
    let outside: [Item]
    let compartments: [Compartment]?
    struct Compartment: Decodable, Identifiable, Sendable {
        let key: String
        let label: String
        let description: String
        let has_items: Bool
        var id: String { key }
    }
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
                    Section("柯的小空间") {
                        ForEach(drawer.compartments ?? Self.defaultCompartments) { compartment in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(compartment.label).font(theme.font.body)
                                    Text(compartment.description).font(theme.font.caption)
                                        .foregroundStyle(theme.color.textSecondary)
                                }
                                Spacer()
                                if compartment.has_items {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 7))
                                        .foregroundStyle(theme.effectiveAccent)
                                        .accessibilityLabel("有内容")
                                }
                            }
                        }
                    }
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
    private static let defaultCompartments = [
        RemoteDrawer.Compartment(key: "share", label: "想和你分享", description: "她想留给你的见闻与片段。", has_items: false),
        RemoteDrawer.Compartment(key: "thinking_of_you", label: "想起你", description: "外面的事，让她想到了你。", has_items: false),
        RemoteDrawer.Compartment(key: "preparing", label: "正在准备", description: "还在酝酿的小心思。", has_items: false),
        RemoteDrawer.Compartment(key: "together", label: "一起做过", description: "值得留住的共同瞬间。", has_items: false),
        RemoteDrawer.Compartment(key: "shared", label: "已经分享", description: "已经拿出来和你讲过的内容。", has_items: false),
    ]
    @MainActor private func load() async {
        do { drawer = try await APIClient(baseURL: line.apiBaseURL).fetchDrawer(); error = nil }
        catch { self.error = "没有打开成功，请重试。" }
    }
}
