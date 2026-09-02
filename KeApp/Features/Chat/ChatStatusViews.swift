import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var theme: Theme
    @ObservedObject var vm: ChatViewModel
    @State private var passcode = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapL) {
            Spacer()

            Text("回家")
                .font(theme.font.pageTitle)
                .foregroundStyle(theme.color.textPrimary)

            Text("输入和网页端相同的口令。口令不会保存在手机里；登录成功后只保存服务器签发的登录 Cookie。")
                .font(theme.font.body)
                .foregroundStyle(theme.color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("口令", text: $passcode)
                .textContentType(.password)
                .focused($focused)
                .submitLabel(.go)
                .onSubmit(login)
                .padding(.horizontal, theme.metric.gapM)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: theme.metric.radiusBubble, style: .continuous)
                        .fill(theme.color.card)
                )

            if let error = vm.loginError {
                Text(error)
                    .font(theme.font.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }

            Button(action: login) {
                HStack {
                    Spacer()
                    if vm.isLoggingIn {
                        ProgressView().tint(theme.color.textOnAccent)
                    } else {
                        Text("进去")
                            .font(theme.font.sectionTitle)
                    }
                    Spacer()
                }
                .foregroundStyle(theme.color.textOnAccent)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: theme.metric.radiusBubble, style: .continuous)
                        .fill(theme.effectiveAccent)
                )
            }
            .disabled(passcode.isEmpty || vm.isLoggingIn)
            .opacity(passcode.isEmpty || vm.isLoggingIn ? 0.5 : 1)

            Spacer()
            Spacer()
        }
        .padding(theme.metric.pagePadding)
        .onAppear { focused = true }
    }

    private func login() {
        guard !passcode.isEmpty, !vm.isLoggingIn else { return }
        let value = passcode
        passcode = ""
        Task { await vm.login(passcode: value) }
    }
}

struct StatusBanner: View {
    @EnvironmentObject private var theme: Theme
    let text: String

    var body: some View {
        HStack(spacing: theme.metric.gapS) {
            ProgressView()
                .controlSize(.small)
                .tint(theme.effectiveAccent)
            Text(text)
                .font(theme.font.caption)
                .foregroundStyle(theme.color.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, theme.metric.gapM)
        .padding(.vertical, theme.metric.gapS)
        .background(
            RoundedRectangle(cornerRadius: theme.metric.radiusChip, style: .continuous)
                .fill(theme.color.card)
        )
    }
}

struct ReplyFailureBanner: View {
    @EnvironmentObject private var theme: Theme
    let failure: ChatViewModel.ReplyFailure
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: theme.metric.gapS) {
            Image(systemName: "exclamationmark.circle")
                .font(theme.font.body)
                .foregroundStyle(theme.effectiveAccent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: theme.metric.gapXS) {
                Text(failure.message)
                    .font(theme.font.caption)
                    .foregroundStyle(theme.color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if failure.canRetry {
                    Button("重试这条回复", action: retry)
                        .buttonStyle(.plain)
                        .font(theme.font.caption)
                        .foregroundStyle(theme.effectiveAccent)
                        .frame(minHeight: theme.metric.touchTarget, alignment: .leading)
                        .accessibilityIdentifier("reply-failure-retry")
                }
            }

            Spacer(minLength: 0)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .frame(
                        width: theme.metric.touchTarget,
                        height: theme.metric.touchTarget,
                        alignment: .topTrailing
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.color.textSecondary)
            .accessibilityLabel("收起回复失败提示")
        }
        .padding(.leading, theme.metric.gapM)
        .padding(.trailing, theme.metric.gapXS)
        .padding(.vertical, theme.metric.gapS)
        .background(
            RoundedRectangle(cornerRadius: theme.metric.radiusBubble, style: .continuous)
                .fill(theme.color.card)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reply-failure-banner")
    }
}

/// 保存一条可见消息的边缘快照，并在折叠布局稳定后恢复。
/// 这是聊天列表常用的 item snapshot 做法；不要在动画每一帧修正 contentOffset。
