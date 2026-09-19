import SwiftUI

// MARK: - 抽屉（2026-09-19）：柯说他在干活，这页让她自己看见到底有没有。数字在最上面，别让她翻。

struct WorkDrawerSummary: Decodable, Sendable {
    let running: Int
    let today: Int
    let last_dispatch: String?
    let last_dispatch_ago: String?
}

struct WorkDrawerRun: Decodable, Sendable {
    let title: String
    let detail: String?
    let status: String?
    let created_at: String?
}

struct WorkDrawerTask: Decodable, Identifiable, Sendable {
    let id: String
    let status: String
    let instruction: String
    let created_at: String?
    let updated_at: String?
    let steps: Int?
    let runs: [WorkDrawerRun]?
}

struct WorkDrawer: Decodable, Sendable {
    let summary: WorkDrawerSummary
    let tasks: [WorkDrawerTask]
}

struct WorkDrawerView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    let line: ChatLine

    @State private var drawer: WorkDrawer?
    @State private var loaded = false
    @State private var error: String?
    @State private var openTasks: Set<String> = []
    @State private var openDetails: Set<String> = []

    private var ink: Color { theme.skin == .night ? theme.color.textPrimary : Color(hex: 0x302D28) }
    private var gold: Color { theme.skin == .night ? theme.color.accentSoft : Color(hex: 0x947343) }
    private func serif(_ size: CGFloat) -> Font { .custom("NotoSerifSC-Regular", size: size, relativeTo: .body).weight(.light) }
    private var api: APIClient { APIClient(baseURL: line.apiBaseURL) }

    /// 手边没活、而且上一次派活已经过去一个多小时。用来轻轻提一句，不报警。
    private var quiet: Bool {
        guard let summary = drawer?.summary, summary.running == 0 else { return false }
        let ago = summary.last_dispatch_ago ?? ""
        if ago.isEmpty { return summary.today == 0 }
        return ago.contains("小时") || ago.contains("天") || ago.contains("月")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .light)).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("关闭")
                    Spacer()
                }
                Text("抽屉").font(serif(44))
                Text("他手边在干什么，写在这儿。").font(serif(15)).foregroundStyle(ink.opacity(0.65))

                summaryBlock

                if quiet {
                    Text("这会儿他手边没有在跑的活。")
                        .font(serif(14))
                        .foregroundStyle(ink.opacity(0.45))
                        .padding(.top, -6)
                }

                if let error {
                    Text(error).font(serif(14)).foregroundStyle(ink.opacity(0.55))
                }

                taskList
            }
            .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 40)
        }
        .refreshable { await load() }
        .foregroundStyle(ink).background(theme.effectiveBackground.ignoresSafeArea())
        .task { if !loaded { await load() } }
    }

    private var summaryBlock: some View {
        let summary = drawer?.summary
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 0) {
                number(summary.map { String($0.running) } ?? "—", "在跑")
                number(summary.map { String($0.today) } ?? "—", "今天派出")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(summary?.last_dispatch_ago?.isEmpty == false ? summary!.last_dispatch_ago! : "还没派过")
                    .font(serif(28))
                Text(summary?.last_dispatch?.isEmpty == false ? "最后一次派活 · \(summary!.last_dispatch!)" : "最后一次派活")
                    .font(serif(13)).foregroundStyle(ink.opacity(0.55))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(gold.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawer-summary")
    }

    private func number(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(serif(40))
            Text(label).font(serif(13)).foregroundStyle(ink.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let tasks = drawer?.tasks, !tasks.isEmpty {
                ForEach(tasks) { task in taskCard(task) }
            } else if loaded && error == nil {
                Text("今天还没派过活。").font(serif(16)).foregroundStyle(ink.opacity(0.55))
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("drawer-tasks")
    }

    private func taskCard(_ task: WorkDrawerTask) -> some View {
        let open = openTasks.contains(task.id)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                if open { openTasks.remove(task.id) } else { openTasks.insert(task.id) }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(statusLabel(task.status)).font(serif(13))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(gold.opacity(task.status == "running" ? 0.22 : 0.08))
                            .clipShape(Capsule())
                        Spacer()
                        Image(systemName: open ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .light)).foregroundStyle(ink.opacity(0.5))
                    }
                    Text(task.instruction).font(serif(17)).lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(footnote(task)).font(serif(13)).foregroundStyle(ink.opacity(0.55))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("drawer-task-\(task.id)")

            if open {
                let runs = task.runs ?? []
                if runs.isEmpty {
                    Text("这个活还没有记下步骤。").font(serif(13)).foregroundStyle(ink.opacity(0.5))
                } else {
                    Divider().overlay(gold.opacity(0.12))
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(runs.enumerated()), id: \.offset) { index, run in
                            runRow(task: task, index: index, run: run)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(gold.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func runRow(task: WorkDrawerTask, index: Int, run: WorkDrawerRun) -> some View {
        let key = "\(task.id)#\(index)"
        let open = openDetails.contains(key)
        let detail = run.detail ?? ""
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(run.title).font(serif(15)).frame(maxWidth: .infinity, alignment: .leading)
                if let status = run.status, !status.isEmpty {
                    Text(statusLabel(status)).font(serif(12)).foregroundStyle(ink.opacity(0.5))
                }
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(serif(14)).lineSpacing(4).foregroundStyle(ink.opacity(0.7))
                    .lineLimit(open ? nil : 2)
                if detail.count > 40 {
                    Button {
                        if open { openDetails.remove(key) } else { openDetails.insert(key) }
                    } label: {
                        Text(open ? "收起" : "展开").font(serif(13)).foregroundStyle(ink.opacity(0.5))
                    }.buttonStyle(.plain)
                }
            }
            if let at = run.created_at, !at.isEmpty {
                Text(at).font(serif(12)).foregroundStyle(ink.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footnote(_ task: WorkDrawerTask) -> String {
        var parts: [String] = []
        if let at = task.created_at, !at.isEmpty { parts.append("派出 \(at)") }
        if let steps = task.steps { parts.append("跑了 \(steps) 步") }
        return parts.joined(separator: " · ")
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "running": return "在跑"
        case "done", "succeeded": return "跑完了"
        case "failed", "error": return "没跑成"
        case "queued", "pending": return "排着"
        default: return status
        }
    }

    @MainActor private func load() async {
        error = nil
        do { drawer = try await api.fetchWorkDrawer() }
        catch { self.error = "没读出来，下拉再试一次。" }
        loaded = true
    }
}
