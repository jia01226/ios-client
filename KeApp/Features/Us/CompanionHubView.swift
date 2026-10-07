import SwiftUI

struct CompanionHubView: View {
    let line: ChatLine
    @ObservedObject var model: UsViewModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    @State private var destination: Destination?

    private enum Destination: String, Identifiable {
        case work, drawer
        var id: String { rawValue }
    }

    private let groups: [CapabilityGroup] = [
        .init(title: "已经在身边", items: [
            .init("提醒与监督", "柯安排的提醒会在这里留下，也会主动来找你。", .live),
            .init("记忆、日记与故事", "保存你们说过的话，整理日记，也可以让柯写故事。", .live),
            .init("位置与身边天气", "在你允许时，柯可以知道你到了哪里。", .live),
        ]),
        .init(title: "正在接通", items: [
            .init("每日早报与上网探索", "整理你关心的新闻、网页和视频，也能看看远方。", .next),
            .init("照片与相册", "尚未接通；接通后也只会在你授权时查看你选定的照片。", .next),
            .init("邮箱、笔友与群聊", "尚未接通；将来发出邮件或消息前仍会保留边界。", .next),
            .init("购买与每月预算", "尚未接通；将来可以做清单和预算，真正下单必须单独确认。", .next),
            .init("小游戏与宠物", "钓鱼、轻量小游戏和一只会长大的宠物。", .next),
            .init("社交与 Agent 社区", "尚未接通；将来可以浏览社区，公开发布前由你确认。", .next),
        ]),
    ]

    private var paper: Color { PageColors.background }
    private var ink: Color { PageColors.ink }
    private var muted: Color { PageColors.muted }
    private var coral: Color { PageColors.rose }
    private var gold: Color { PageColors.tea }
    private var mauve: Color { PageColors.mauve }
    private func song(_ size: CGFloat, _ style: Font.TextStyle = .body) -> Font {
        .custom("STSongti-SC-Light", size: size, relativeTo: style)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    header
                    reminderSection
                    drawerSection
                    // 2026-10-07 拿掉功能介绍：大半写着「正在接通」，点进去什么也做不了。
                    Text("需要照片、邮箱、社交或购买权限时，柯会先告诉你要做什么；没有授权，就不会读取或执行。")
                        .font(song(13, .caption))
                        .lineSpacing(5)
                        .foregroundStyle(muted)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 28)
                .padding(.top, 18)
            }
            .scrollIndicators(.hidden)
            .background(paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(ink)
                }
            }
            .sheet(item: $destination) { target in
                switch target {
                case .work: WorkDrawerView(line: line).environmentObject(theme)
                case .drawer: DrawerView(line: line).environmentObject(theme)
                }
            }
        }
        .accessibilityIdentifier("companion-hub")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("柯在这里")
                .font(.custom("STSongti-SC-Light", size: 34, relativeTo: .largeTitle))
                .tracking(2.2)
                .foregroundStyle(ink)
            Text("提醒你的事，收着自己的心事，也慢慢长出更多能陪你的手。")
                .font(song(15))
                .lineSpacing(6)
                .foregroundStyle(muted)
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle("提醒我的事情", tint: coral)
            if model.loadingReminders && model.reminders.isEmpty {
                ProgressView("正在看看记下了什么")
                    .tint(coral)
            } else if let error = model.reminderLoadError, model.reminders.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(error).font(song(14)).foregroundStyle(muted)
                    Button("重新连接") { Task { await model.loadReminders() } }
                        .font(song(14)).foregroundStyle(coral)
                }
            } else if model.activeReminders.isEmpty {
                Text("现在没有待着的提醒。柯记下新的事情后，会出现在这里。")
                    .font(song(15)).lineSpacing(5).foregroundStyle(muted)
            } else {
                ForEach(model.activeReminders.prefix(5)) { reminder in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Circle().fill(coral.opacity(0.74)).frame(width: 5, height: 5)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reminder.text).font(song(16)).foregroundStyle(ink)
                            Text(model.reminderTime(reminder)).font(song(12, .caption)).foregroundStyle(muted)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("hub-reminders")
    }

    private var drawerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("柯的两只抽屉", tint: gold)
            drawerButton("柯在忙什么", detail: "看他手边正在跑的活和最近做过的事", target: .work)
            drawerButton("柯的抽屉", detail: "看他主动放在外面的心事与碎片", target: .drawer)
        }
    }

    private func drawerButton(_ title: String, detail: String, target: Destination) -> some View {
        Button { destination = target } label: {
            HStack(spacing: 13) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(song(17)).foregroundStyle(ink)
                    Text(detail).font(song(12, .caption)).foregroundStyle(muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).foregroundStyle(gold)
            }
            .padding(.vertical, 13)
            .overlay(alignment: .bottom) { Rectangle().fill(gold.opacity(0.22)).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(target == .work ? "hub-work-drawer" : "hub-personal-drawer")
    }

    private func capabilitySection(_ group: CapabilityGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(group.title, tint: mauve)
            ForEach(group.items) { item in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(song(16)).foregroundStyle(ink)
                        Text(item.detail).font(song(13, .caption)).lineSpacing(4).foregroundStyle(muted)
                    }
                    Spacer(minLength: 10)
                    Text(item.state.label)
                        .font(song(11, .caption))
                        .foregroundStyle(item.state == .live ? coral : mauve)
                        .padding(.top, 2)
                }
                .padding(.vertical, 13)
                .overlay(alignment: .bottom) { Rectangle().fill(mauve.opacity(0.16)).frame(height: 0.5) }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func sectionTitle(_ text: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Capsule().fill(tint.opacity(0.72)).frame(width: 18, height: 3)
            Text(text).font(song(20, .headline)).tracking(1.2).foregroundStyle(ink)
        }
        .padding(.bottom, 7)
    }
}

private struct CapabilityGroup: Identifiable {
    let title: String
    let items: [Capability]
    var id: String { title }
}

private struct Capability: Identifiable {
    let title: String
    let detail: String
    let state: State
    var id: String { title }

    init(_ title: String, _ detail: String, _ state: State) {
        self.title = title
        self.detail = detail
        self.state = state
    }

    enum State: Equatable {
        case live, next
        var label: String {
            switch self {
            case .live: return "可用"
            case .next: return "待接通"
            }
        }
    }
}
