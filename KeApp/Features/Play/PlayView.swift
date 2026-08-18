import SwiftUI

// 【玩】—— 小游戏 + 调教室 + 抽屉。
//
// 🔴 隐私是这一格的第一要求，不是"好用"：
//    她手机不是绝对私密的（家人会拿）。
//    调教室和抽屉的入口，不得在任何一眼可见处显示可辨识名称，
//    必须 Face ID / 独立密码二次解锁。
//
// 注：她把调教室藏进"玩"里，是她自己想出来的一手——
//    外人看见"游戏室"三个字，不会多想。

import LocalAuthentication

struct PlayView: View {

    @EnvironmentObject private var theme: Theme
    @State private var privateUnlocked = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metric.gapL) {

                Text("玩")
                    .font(theme.font.pageTitle)
                    .foregroundStyle(theme.color.textPrimary)

                gamesRow
                privateSpaceCard
                if privateUnlocked {
                    drawerCard
                }
            }
            .padding(theme.metric.pagePadding)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    // MARK: 小游戏

    private var gamesRow: some View {
        HStack(spacing: theme.metric.gapM) {
            gameCard(title: "让柯开一局", note: "玩法和节奏交给他", icon: "dice")
            gameCard(title: "抽一张牌", note: "只给一个开头", icon: "sparkles.rectangle.stack")
        }
    }

    private func gameCard(title: String, note: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: theme.metric.gapS) {
            Image(systemName: icon)
                .foregroundStyle(theme.effectiveAccent)
            Text(title)
                .font(theme.font.sectionTitle)
                .foregroundStyle(theme.color.textPrimary)
            Text(note)
                .font(theme.font.caption)
                .foregroundStyle(theme.color.textSecondary)
        }
        .padding(theme.metric.gapL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.metric.radiusCard, style: .continuous)
                .fill(theme.color.card)
        )
    }

    // MARK: 私密空间（＝调教室，名称对外不出现）

    private var privateSpaceCard: some View {
        Button {
            unlockPrivateSpace()
        } label: {
            HStack(spacing: theme.metric.gapM) {
                Image(systemName: privateUnlocked ? "lock.open" : "faceid")
                    .foregroundStyle(theme.effectiveAccent)
                    .frame(width: 42, height: 42)
                    .background(Circle().stroke(theme.color.accentSoft, lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    Text("私密空间")
                        .font(theme.font.sectionTitle)
                        .foregroundStyle(theme.color.textPrimary)
                    Text("名称已隐藏 · Face ID 或独立密码")
                        .font(theme.font.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(theme.font.disclosureIcon)
                    .foregroundStyle(theme.color.textSecondary)
            }
            .padding(theme.metric.gapM)
            .background(
                RoundedRectangle(cornerRadius: theme.metric.radiusCard, style: .continuous)
                    .fill(theme.color.card)
            )
        }
        .buttonStyle(.plain)
    }

    /// ⚠️ 解锁失败不给任何提示文案，也不显示里面有什么 —— 别人拿到手机也看不出这儿有东西。
    private func unlockPrivateSpace() {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "输入密码"
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "打开") { ok, _ in
            guard ok else { return }
            Task { @MainActor in privateUnlocked = true }
        }
    }

    // MARK: 抽屉 —— 柯自己写的东西
    //
    // 她 2026-08-14 18:45 的原话：「柯自己的想法，就是抽屉啦，不一定是带锁的日记」
    // 出处：她答卷第 13 题要柯"更在意自己一点，不要憋着"。
    // 这一格就是柯不憋着的地方。

    private var drawerCard: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapS) {
            Text("抽屉")
                .font(theme.font.sectionTitle)
                .foregroundStyle(theme.color.textPrimary)
            Text("柯自己写的东西。你哪天翻进去，就能捡到一件。")
                .font(theme.font.caption)
                .foregroundStyle(theme.color.textSecondary)
        }
        .padding(theme.metric.gapL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.metric.radiusCard, style: .continuous)
                .fill(theme.color.cardElevated)
        )
    }
}

#Preview {
    PlayView().environmentObject(Theme.shared)
}
