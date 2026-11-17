import SwiftUI

// 11-17 夜里对账（照 Anthropic「agent 记忆」那篇）：每天夜里拿聊天原话对一遍柯的记忆，
// 改对记错的、并掉重复的、熄掉过时的、从原话里提炼「他学会的」。改动先放这里，她点同意才改；
// 打开「以后直接改」就不用问她。

struct MemoryProposal: Decodable, Identifiable, Equatable, Sendable {
    struct Before: Decodable, Equatable, Sendable {
        let id: String
        let title: String
        let fact: String
    }
    let id: String
    let action: String
    let label: String
    let before: [Before]
    let title: String
    let fact: String
    let group: String
    let evidence: String
    let why: String
}

struct MemoryProposalPage: Decodable, Sendable {
    struct Settings: Decodable, Sendable { let auto: Bool? }
    let proposals: [MemoryProposal]
    let settings: Settings?
}

@MainActor final class MemoryProposalStore: ObservableObject {
    @Published private(set) var proposals: [MemoryProposal] = []
    @Published private(set) var auto = false
    @Published private(set) var busyID: String?
    @Published var error: String?
    private lazy var api = APIClient(baseURL: ChatLine.allCases.first?.apiBaseURL ?? AppConfiguration.apiBaseURL)

    func load() async {
        do {
            let page = try await api.memoryProposals()
            proposals = page.proposals
            auto = page.settings?.auto ?? false
            error = nil
        } catch {
            // 没拉到就照旧，不打扰她看星星
        }
    }

    @discardableResult func decide(_ p: MemoryProposal, approve: Bool) async -> Bool {
        busyID = p.id
        defer { busyID = nil }
        do {
            proposals = try await api.decideMemoryProposal(id: p.id, approve: approve).proposals
            error = nil
            return true
        } catch {
            self.error = approve ? "这条没改成，过会儿再试" : "没处理上，再试一次"
            return false
        }
    }

    func setAuto(_ value: Bool) async {
        let before = auto
        auto = value
        do { try await api.setMemoryProposalAuto(value) } catch { auto = before; self.error = "没存上，再试一次" }
    }
}

struct MemoryProposalSheet: View {
    @ObservedObject var store: MemoryProposalStore
    var onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss

    private static let ink = Color(red: 0.945, green: 0.94, blue: 0.93)
    private static let sub = Color(red: 0.8, green: 0.82, blue: 0.88)
    private static let back = Color(red: 0.07, green: 0.08, blue: 0.13)
    private static let row = Color(red: 0.12, green: 0.13, blue: 0.2)
    private static let gold = Color(red: 0.94, green: 0.88, blue: 0.73)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(get: { store.auto }, set: { v in Task { await store.setAuto(v) } })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("以后直接改，不用问我").foregroundStyle(Self.ink)
                            Text("关着的时候，柯夜里想改的都先放在这里，你点同意才改。").font(.footnote).foregroundStyle(Self.sub)
                        }
                    }
                    .tint(Self.gold)
                    .listRowBackground(Self.row)
                }
                if store.proposals.isEmpty {
                    Text("今晚没有要改的。").foregroundStyle(Self.sub).listRowBackground(Self.row)
                }
                ForEach(store.proposals) { p in
                    Section { card(p) }
                        .listRowBackground(Self.row)
                }
                if let error = store.error {
                    Text(error).font(.footnote).foregroundStyle(Self.sub).listRowBackground(Self.row)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Self.back)
            .navigationTitle("柯想改的").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if store.proposals.count > 1 {
                        Button("全部同意") {
                            Task {
                                for p in store.proposals { await store.decide(p, approve: true) }
                                onChanged()
                            }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("好了") { dismiss() } }
            }
        }
        .tint(Self.gold)
        .environment(\.colorScheme, .dark)
        .presentationDetents([.medium, .large])
    }

    private func card(_ p: MemoryProposal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(p.label).font(.footnote).foregroundStyle(Self.back)
                    .padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(Self.gold))
                Text(p.title.isEmpty ? (p.before.first?.title ?? "") : p.title).font(.body).foregroundStyle(Self.ink).lineLimit(2)
            }
            ForEach(p.before, id: \.id) { b in
                VStack(alignment: .leading, spacing: 2) {
                    Text("原来：" + b.title).font(.footnote).foregroundStyle(Self.sub)
                    Text(b.fact).font(.footnote).foregroundStyle(Self.sub.opacity(0.85)).lineLimit(4)
                        .strikethrough(p.action == "retire", color: Self.sub.opacity(0.6))
                }
            }
            if p.action != "retire", !p.fact.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.before.isEmpty ? "要记的：" : "改成：").font(.footnote).foregroundStyle(Self.gold)
                    Text(p.fact).font(.subheadline).foregroundStyle(Self.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("为什么：" + p.why).font(.footnote).foregroundStyle(Self.sub).fixedSize(horizontal: false, vertical: true)
            if !p.evidence.isEmpty {
                Text("原话：" + p.evidence).font(.footnote).italic().foregroundStyle(Self.sub.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Spacer()
                Button("不要") { Task { await store.decide(p, approve: false) } }
                    .buttonStyle(.bordered).tint(Self.sub)
                Button("同意") {
                    Task { if await store.decide(p, approve: true) { onChanged() } }
                }
                .buttonStyle(.borderedProminent).tint(Self.gold).foregroundStyle(Self.back)
            }
            .disabled(store.busyID != nil)
            .padding(.top, 2)
        }
        .padding(.vertical, 6)
    }
}
