import SwiftUI

struct PlayView: View {
    @EnvironmentObject private var theme: Theme
    let line: ChatLine
    @State private var destination: CompanionPage?
    @State private var latestMoment: RemoteMoment?
    @State private var latestDiary: RemoteDiary?
    @State private var loadError: String?
    @State private var loading = false

    init(line: ChatLine = .main) { self.line = line }

    private var ink: Color { theme.skin == .night ? theme.color.textPrimary : Color(hex: 0x302D28) }
    private var gold: Color { theme.skin == .night ? theme.color.accentSoft : Color(hex: 0x947343) }
    private func serif(_ size: CGFloat) -> Font { .custom("NotoSerifSC-Regular", size: size, relativeTo: .body).weight(.light) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("玩").font(serif(52)).padding(.top, 12)
                Text("生活很长，\n一起，把平凡过成喜欢的样子。")
                    .font(serif(16)).lineSpacing(5).foregroundStyle(ink.opacity(0.65))
                    .padding(.top, -18)
                if loading { ProgressView().accessibilityLabel("正在加载") }
                if let loadError {
                    Text(loadError).font(serif(14))
                    Button("重试") { Task { await refresh() } }
                }
                Button { destination = .moments } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        heading("朋友圈", subtitle: "分享今天的小事")
                        if let item = latestMoment {
                            if let path = item.image, !path.isEmpty {
                                CompanionImage(api: APIClient(baseURL: line.apiBaseURL), path: path, thumbnail: true)
                                    .frame(maxWidth: .infinity).clipped()
                            }
                            Text("\(item.author == "user" ? "佳佳" : "柯") · \(item.content)")
                                .font(serif(16)).lineLimit(3).lineSpacing(5)
                        } else if !loading {
                            Text("还没有动态，写下今天的一件小事。")
                                .font(serif(16)).foregroundStyle(ink.opacity(0.65)).padding(.vertical, 25)
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("play-moments")
                Divider().overlay(gold.opacity(0.12))
                Button { destination = .diary } label: {
                    VStack(alignment: .leading, spacing: 18) {
                        heading("日记", subtitle: "把心情，安放在这里")
                        HStack(alignment: .center, spacing: 20) {
                            Text(latestDiary.map { String($0.created_at.dropFirst(8).prefix(2)) + "\n/\n" + String($0.created_at.dropFirst(5).prefix(2)) } ?? "—")
                                .font(.custom("Didot", size: 20, relativeTo: .title3))
                                .multilineTextAlignment(.center).frame(width: 95, height: 96)
                                .background(gold.opacity(0.045))
                            VStack(alignment: .leading, spacing: 9) {
                                Text(latestDiary?.title ?? "把今天留在这里").font(serif(20))
                                Text(latestDiary.map { $0.locked_hidden ? "暂时锁着的一页" : $0.content } ?? "有些话，慢慢写。")
                                    .font(serif(15)).lineLimit(2).foregroundStyle(ink.opacity(0.65))
                            }
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("play-diary")
            }.padding(.horizontal, 28).padding(.bottom, 12)
        }
        .foregroundStyle(ink).background(theme.effectiveBackground)
        .task { await refresh() }.refreshable { await refresh() }
        .fullScreenCover(item: $destination, onDismiss: { Task { await refresh() } }) { page in
            CompanionPages(page: page, line: line).environmentObject(theme)
        }
    }

    private func heading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(title).font(serif(26)); Spacer(); Image(systemName: "chevron.right").font(.system(size: 15, weight: .light)) }
            Text(subtitle).font(serif(14)).foregroundStyle(ink.opacity(0.65))
        }
    }

    @MainActor private func refresh() async {
        guard !loading else { return }
        loading = true; loadError = nil
        defer { loading = false }
        let api = APIClient(baseURL: line.apiBaseURL)
        do { latestMoment = try await api.fetchMoments().first }
        catch { loadError = "动态没有加载成功，请重试。" }
        do { latestDiary = try await api.fetchDiaries().first }
        catch { loadError = "日记没有加载成功，请重试。" }
    }

}
