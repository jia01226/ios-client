import SwiftUI

struct JiajiaView: View {
    @EnvironmentObject private var theme: Theme
    @AppStorage("jiajia.personalNotes") private var personalNotes = ""
    @State private var draft = ""
    @State private var isEditing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metric.gapXL) {
                VStack(alignment: .leading, spacing: theme.metric.gapS) {
                    Text("佳佳")
                        .font(theme.font.pageTitle)
                    Text("我的数字分身")
                        .font(theme.font.sectionTitle)
                        .foregroundStyle(theme.color.textSecondary)
                }

                VStack(alignment: .leading, spacing: theme.metric.gapM) {
                    Text("从真实的我开始")
                        .font(theme.font.quote)
                    Text("留下我说过的话、经历过的事，还有做选择时的理由。")
                        .font(theme.font.body)
                        .foregroundStyle(theme.color.textSecondary)
                    Button {
                        draft = personalNotes
                        isEditing = true
                    } label: {
                        Label(personalNotes.isEmpty ? "写下关于我的事" : "编辑我的记录", systemImage: "square.and.pencil")
                            .font(theme.font.sectionTitle)
                            .frame(minHeight: theme.metric.touchTarget)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.color.textPrimary)
                    .accessibilityIdentifier("jiajia-edit-notes")
                }
                .padding(theme.metric.gapL)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.color.cardElevated, in: RoundedRectangle(cornerRadius: theme.metric.radiusCard))

                VStack(alignment: .leading, spacing: theme.metric.gapM) {
                    Text("我的记录")
                        .font(theme.font.sectionTitle)
                    Text(personalNotes.isEmpty ? "还没有记录。可以从最近一次开心、犹豫，或坚持自己的时刻开始。" : personalNotes)
                        .font(theme.font.body)
                        .foregroundStyle(personalNotes.isEmpty ? theme.color.textSecondary : theme.color.textPrimary)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("jiajia-notes")
                    Text("记录仅保存在这台设备，尚未同步或用于训练。")
                        .font(theme.font.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }

                VStack(alignment: .leading, spacing: theme.metric.gapL) {
                    Text("数字分身的下一步")
                        .font(theme.font.sectionTitle)
                    roadmap("人格草稿", detail: "从真实资料整理表达与判断习惯，由我确认。")
                    roadmap("人生记忆", detail: "按来源保存经历，能够更正、删除和导出。")
                    roadmap("与分身对话", detail: "接入模型后，再试试她的回答像不像我。")
                    Text("以上功能尚未接通；现在可以先保存自己的记录。")
                        .font(theme.font.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }
            .foregroundStyle(theme.color.textPrimary)
            .padding(theme.metric.pagePadding)
        }
        .background(theme.effectiveBackground)
        .accessibilityIdentifier("jiajia-page")
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                VStack(alignment: .leading, spacing: theme.metric.gapM) {
                    Text("可以直接粘贴自己说过的话。保留当时的情境，比总结几个性格词更有用。")
                        .font(theme.font.body)
                        .foregroundStyle(theme.color.textSecondary)
                    TextEditor(text: $draft)
                        .font(theme.font.body)
                        .scrollContentBackground(.hidden)
                        .accessibilityIdentifier("jiajia-notes-editor")
                }
                .padding(theme.metric.pagePadding)
                .background(theme.effectiveBackground)
                .navigationTitle("关于我的事")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { isEditing = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            personalNotes = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            isEditing = false
                        }
                    }
                }
                .tint(theme.effectiveAccent)
            }
        }
    }

    private func roadmap(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: theme.metric.gapXS) {
            Text(title).font(theme.font.body)
            Text(detail)
                .font(theme.font.caption)
                .foregroundStyle(theme.color.textSecondary)
        }
    }
}
