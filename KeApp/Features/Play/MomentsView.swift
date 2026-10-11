import SwiftUI
import PhotosUI
import UIKit

/// A small, shared timeline. Only the user's own words expose editing controls.
struct MomentsView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: MomentsStore
    let line: ChatLine
    @State private var sheet: MomentSheet?
    @State private var deletion: MomentDeletion?
    @StateObject private var drafts: MomentsDraftStore

    init(store: MomentsStore, line: ChatLine) {
        self.store = store
        self.line = line
        _drafts = StateObject(wrappedValue: MomentsDraftStore(scope: line.rawValue))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: theme.metric.gapXL) {
                    cover
                    if let error = store.error {
                        MomentErrorBanner(message: error) { Task { await store.load() } }
                            .padding(.horizontal, theme.metric.pagePadding)
                    }
                    if store.loading && store.moments.isEmpty {
                        ProgressView("正在翻开朋友圈")
                            .padding(theme.metric.gapXL)
                            .accessibilityIdentifier("moments-loading")
                    } else if store.moments.isEmpty && store.error == nil {
                        VStack(spacing: theme.metric.gapM) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(theme.font.unavailableIcon)
                            Text("把今天的小事，留在这里。")
                                .font(theme.font.journalHeading)
                            Button("发第一条动态") { sheet = .compose }
                                .frame(minHeight: theme.metric.touchTarget)
                                .accessibilityIdentifier("moments-first-post")
                        }
                        .foregroundStyle(theme.pageColor.textSecondary)
                        .padding(theme.metric.gapXL)
                        .accessibilityIdentifier("moments-empty")
                    }
                    LazyVStack(spacing: theme.metric.gapXL) {
                        ForEach(store.moments) { moment in
                            MomentRow(moment: moment, line: line, saving: store.saving,
                                      like: { Task { await store.like(moment) } },
                                      comment: { openTextSheet(.comment(moment)) },
                                      edit: { openTextSheet(.editMoment(moment)) },
                                      delete: { deletion = .moment(moment) },
                                      editComment: { openTextSheet(.editComment($0)) },
                                      deleteComment: { deletion = .comment($0) },
                                      preview: { sheet = .image($0) })
                        }
                    }
                    .padding(.horizontal, theme.metric.pagePadding)
                    .padding(.bottom, theme.metric.gapXL)
                }
                .frame(maxWidth: MomentsTheme.maximumWidth)
                .frame(maxWidth: .infinity)
            }
            .background(theme.pageBackground.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .refreshable { await store.load() }
            .navigationTitle("朋友圈")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("返回") { dismiss() }
                        .accessibilityIdentifier("moments-close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { sheet = .compose } label: {
                        Label("发动态", systemImage: "square.and.pencil")
                    }
                    .disabled(store.saving)
                    .accessibilityIdentifier("moments-compose")
                }
            }
            .sheet(item: $sheet) { item in
                switch item {
                case .compose:
                    MomentComposer(store: store, drafts: drafts, line: line)
                        .environmentObject(theme)
                case .comment(let moment):
                    textEditor(for: item, title: "评论\(moment.author == "user" ? "佳佳" : "柯")的动态", action: "发送") {
                        await store.comment(on: moment, content: $0)
                    }
                case .editMoment(let moment):
                    textEditor(for: item, title: "编辑动态", action: "保存") {
                        await store.edit(moment, content: $0)
                    }
                case .editComment(let comment):
                    textEditor(for: item, title: "编辑评论", action: "保存") {
                        await store.editComment(comment, content: $0)
                    }
                case .image(let url):
                    MomentImagePreview(url: url, line: line).environmentObject(theme)
                }
            }
            .confirmationDialog("要删除这段话吗？", isPresented: Binding(
                get: { deletion != nil },
                set: { if !$0 { deletion = nil } }
            ), titleVisibility: .visible, presenting: deletion) { target in
                Button("删除", role: .destructive) {
                    Task {
                        switch target {
                        case .moment(let moment): _ = await store.delete(moment)
                        case .comment(let comment): _ = await store.deleteComment(comment)
                        }
                    }
                }
                Button("保留", role: .cancel) { deletion = nil }
            }
        }
        .tint(theme.pageAccent)
        .foregroundStyle(theme.pageColor.textPrimary)
        .font(theme.font.body)
        .task(id: scenePhase == .active && sheet == nil) {
            guard scenePhase == .active, sheet == nil else { return }
            while !Task.isCancelled {
                await store.load()
                do { try await Task.sleep(nanoseconds: store.pollInterval) }
                catch { return }
            }
        }
        .accessibilityIdentifier("moments-screen")
    }

    private var cover: some View {
        VStack(alignment: .trailing, spacing: theme.metric.gapS) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [theme.pageColor.accentSoft, theme.pageColor.cardElevated, theme.pageColor.bg],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image("KeMoonCamellia")
                    .resizable().scaledToFit()
                    .frame(width: MomentsTheme.coverArtworkSize, height: MomentsTheme.coverArtworkSize)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: theme.metric.gapS) {
                    Text("我们的日常").font(theme.font.journalTitle)
                    Text("有话想说，就留在这里。")
                        .font(theme.font.journalCaption)
                        .foregroundStyle(theme.pageColor.textSecondary)
                }
                .padding(theme.metric.gapXL)
            }
            .frame(height: MomentsTheme.coverHeight)
            .clipped()
            HStack(alignment: .bottom, spacing: theme.metric.gapM) {
                Text("佳佳").font(theme.font.journalHeading)
                    .padding(.bottom, theme.metric.gapS)
                MomentAvatar(author: "user", size: MomentsTheme.profileAvatarSize)
            }
            .padding(.horizontal, theme.metric.pagePadding)
            .padding(.top, MomentsTheme.profileOverlap)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("moments-cover")
    }

    private func openTextSheet(_ item: MomentSheet) {
        if drafts.textDrafts[item.id] == nil {
            switch item {
            case .editMoment(let moment): drafts.textDrafts[item.id] = moment.content
            case .editComment(let comment): drafts.textDrafts[item.id] = comment.content
            default: drafts.textDrafts[item.id] = ""
            }
        }
        sheet = item
    }

    private func textEditor(for item: MomentSheet, title: String, action: String,
                            submit: @escaping (String) async -> Bool) -> some View {
        MomentTextEditor(store: store, drafts: drafts, title: title, action: action,
                         text: Binding(get: { drafts.textDrafts[item.id] ?? "" }, set: { drafts.textDrafts[item.id] = $0 })) { value in
            if await submit(value) {
                drafts.textDrafts[item.id] = nil
                return true
            }
            return false
        }
        .environmentObject(theme)
    }
}

private enum MomentSheet: Identifiable {
    case compose, comment(RemoteMoment), editMoment(RemoteMoment), editComment(RemoteMomentComment), image(String)
    var id: String {
        switch self {
        case .compose: return "compose"
        case .comment(let moment): return "comment-\(moment.id)"
        case .editMoment(let moment): return "edit-\(moment.id)"
        case .editComment(let comment): return "edit-comment-\(comment.id)"
        case .image(let url): return "image-\(url)"
        }
    }
}

private enum MomentDeletion {
    case moment(RemoteMoment), comment(RemoteMomentComment)
}

private struct MomentAvatar: View {
    @EnvironmentObject private var theme: Theme
    let author: String
    let size: CGFloat
    var body: some View {
        ZStack {
            theme.pageColor.cardElevated
            Image("CamelliaMoonlight").resizable().scaledToFill()
            Text(author == "user" ? "佳" : "柯")
                .font(theme.font.journalHeading)
                .foregroundStyle(theme.pageColor.textPrimary)
                .padding(theme.metric.gapXS)
                .background(theme.pageColor.card, in: Circle())
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: theme.metric.radiusChip))
        .overlay(RoundedRectangle(cornerRadius: theme.metric.radiusChip)
            .stroke(theme.pageColor.separator, lineWidth: theme.metric.glassStrokeWidth))
        .accessibilityHidden(true)
    }
}

private struct MomentRow: View {
    @EnvironmentObject private var theme: Theme
    let moment: RemoteMoment
    let line: ChatLine
    let saving: Bool
    let like: () -> Void
    let comment: () -> Void
    let edit: () -> Void
    let delete: () -> Void
    let editComment: (RemoteMomentComment) -> Void
    let deleteComment: (RemoteMomentComment) -> Void
    let preview: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: theme.metric.gapM) {
            MomentAvatar(author: moment.author, size: MomentsTheme.avatarSize)
            VStack(alignment: .leading, spacing: theme.metric.gapM) {
                HStack(alignment: .firstTextBaseline) {
                    Text(moment.author == "user" ? "佳佳" : "柯")
                        .font(theme.font.sectionTitle)
                        .foregroundStyle(theme.pageAccent)
                    Spacer(minLength: theme.metric.gapS)
                    if moment.author == "user" {
                        Menu {
                            Button("编辑动态", systemImage: "pencil", action: edit)
                            Button("删除动态", systemImage: "trash", role: .destructive, action: delete)
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(minWidth: theme.metric.touchTarget, minHeight: theme.metric.touchTarget)
                        }
                        .disabled(saving)
                        .accessibilityLabel("这条动态的菜单")
                        .accessibilityIdentifier("moment-menu-\(moment.id)")
                    }
                }
                if !moment.content.isEmpty {
                    Text(moment.content)
                        .font(theme.font.body)
                        .lineSpacing(theme.metric.gapXS)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("moment-content-\(moment.id)")
                }
                if let image = moment.image, !image.isEmpty {
                    MomentRemoteImage(url: image, line: line, preview: { preview(image) })
                        .frame(height: MomentsTheme.imageHeight)
                        .clipShape(RoundedRectangle(cornerRadius: theme.metric.radiusChip))
                        .accessibilityIdentifier("moment-image-\(moment.id)")
                }
                HStack(spacing: theme.metric.gapS) {
                    Text(MomentDate.label(moment.created_at))
                        .font(theme.font.caption)
                        .foregroundStyle(theme.pageColor.textSecondary)
                    Spacer(minLength: theme.metric.gapXS)
                    Button(action: like) {
                        Label(moment.user_liked != 0 ? "已赞" : "赞", systemImage: moment.user_liked != 0 ? "heart.fill" : "heart")
                            .frame(minHeight: theme.metric.touchTarget)
                    }
                    .accessibilityLabel(moment.user_liked != 0 ? "取消赞" : "赞")
                    .accessibilityValue(moment.user_liked != 0 ? "已赞" : "未赞")
                    .accessibilityIdentifier("moment-like-\(moment.id)")
                    Button(action: comment) {
                        Label("评论", systemImage: "bubble.right")
                            .frame(minHeight: theme.metric.touchTarget)
                    }
                    .accessibilityIdentifier("moment-comment-\(moment.id)")
                }
                .font(theme.font.caption)
                .disabled(saving)
                if moment.user_liked != 0 || moment.ai_liked != 0 || !moment.comments.isEmpty {
                    responses
                }
                Divider().overlay(theme.pageColor.separator)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("moment-\(moment.id)")
    }

    private var responses: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapS) {
            if moment.user_liked != 0 || moment.ai_liked != 0 {
                Label(likeNames, systemImage: "heart")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.pageAccent)
                    .accessibilityIdentifier("moment-likes-\(moment.id)")
            }
            if (moment.user_liked != 0 || moment.ai_liked != 0) && !moment.comments.isEmpty {
                Divider().overlay(theme.pageColor.separator)
            }
            ForEach(moment.comments) { item in
                HStack(alignment: .top, spacing: theme.metric.gapXS) {
                    (Text(item.author == "user" ? "佳佳：" : "柯：")
                        .foregroundColor(theme.pageAccent) + Text(item.content))
                        .font(theme.font.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    if item.author == "user" {
                        Menu {
                            Button("编辑评论", systemImage: "pencil") { editComment(item) }
                            Button("删除评论", systemImage: "trash", role: .destructive) { deleteComment(item) }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(minWidth: theme.metric.touchTarget, minHeight: theme.metric.touchTarget)
                        }
                        .disabled(saving)
                        .accessibilityLabel("这条评论的菜单")
                        .accessibilityIdentifier("moment-comment-menu-\(item.id)")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("moment-reply-\(item.id)")
            }
        }
        .padding(theme.metric.gapM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.pageColor.card, in: RoundedRectangle(cornerRadius: theme.metric.radiusChip))
    }

    private var likeNames: String {
        [moment.user_liked != 0 ? "佳佳" : nil, moment.ai_liked != 0 ? "柯" : nil]
            .compactMap { $0 }.joined(separator: "、")
    }
}

private struct MomentComposer: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: MomentsStore
    @ObservedObject var drafts: MomentsDraftStore
    let line: ChatLine
    @State private var photo: PhotosPickerItem?
    @State private var photoLoading = false
    @State private var submitting = false
    @State private var imageError: String?
    private var busy: Bool { submitting || photoLoading || store.saving }
    private var hasContent: Bool { !drafts.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || drafts.imageData != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metric.gapL) {
                    Text("今天有什么想告诉柯？").font(theme.font.journalHeading)
                    TextEditor(text: $drafts.text)
                        .font(theme.font.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: MomentsTheme.editorHeight)
                        .padding(theme.metric.gapS)
                        .background(theme.pageColor.card, in: RoundedRectangle(cornerRadius: theme.metric.radiusCard))
                        .accessibilityLabel("动态正文")
                        .accessibilityIdentifier("moment-draft-text")
                        .disabled(busy)
                    if let imageData = drafts.imageData, let image = UIImage(data: imageData) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(height: MomentsTheme.draftImageHeight)
                            .clipShape(RoundedRectangle(cornerRadius: theme.metric.radiusChip))
                            .accessibilityLabel("已选照片")
                            .accessibilityIdentifier("moment-draft-image")
                        Button("移除照片", role: .destructive) {
                            drafts.imageData = nil; photo = nil; imageError = nil
                        }
                        .frame(minHeight: theme.metric.touchTarget)
                        .disabled(busy)
                        .accessibilityIdentifier("moment-remove-image")
                    }
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label(drafts.imageData == nil ? "选一张照片" : "换一张照片", systemImage: "photo")
                            .frame(minHeight: theme.metric.touchTarget)
                    }
                    .disabled(busy)
                    .accessibilityIdentifier("moment-add-image")
                    if photoLoading { ProgressView("正在准备照片") }
                    if submitting { ProgressView(drafts.uploadedImage.isEmpty && drafts.imageData != nil ? "正在上传照片" : "正在发布") }
                    if let message = imageError ?? drafts.persistenceError ?? store.error {
                        Text(message).font(theme.font.caption)
                            .foregroundStyle(theme.pageColor.textSecondary)
                            .accessibilityIdentifier("moment-editor-error")
                    }
                    Text("可以只发文字，也可以只放一张照片。")
                        .font(theme.font.caption).foregroundStyle(theme.pageColor.textSecondary)
                }
                .padding(theme.metric.pagePadding)
            }
            .background(theme.pageBackground.ignoresSafeArea())
            .navigationTitle("发动态")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("稍后再写") { dismiss() }.disabled(busy)
                        .accessibilityIdentifier("moment-draft-close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发布") { Task { await publish() } }
                        .disabled(busy || !hasContent)
                        .accessibilityIdentifier("moment-publish")
                }
            }
        }
        .tint(theme.pageAccent)
        .foregroundStyle(theme.pageColor.textPrimary)
        .interactiveDismissDisabled(busy)
        .task(id: photo) { await preparePhoto() }
    }

    @MainActor private func preparePhoto() async {
        guard let photo else { return }
        photoLoading = true; imageError = nil
        defer { photoLoading = false }
        do {
            guard let data = try await photo.loadTransferable(type: Data.self),
                  let source = UIImage(data: data), let jpeg = source.chatUploadJPEGData() else {
                imageError = "这张照片没有读取出来，请重新选一张。"
                return
            }
            try Task.checkCancellation()
            drafts.imageData = jpeg
        } catch is CancellationError {
        } catch { imageError = "照片没有读取出来，请重新选择。" }
    }

    @MainActor private func publish() async {
        guard !busy, hasContent else { return }
        submitting = true; imageError = nil
        defer { submitting = false }
        if let imageData = drafts.imageData, drafts.uploadedImage.isEmpty {
            do {
                let attachment = try await APIClient(baseURL: line.apiBaseURL).uploadAttachment(
                    data: imageData, fileName: "朋友圈-\(UUID().uuidString).jpg", mimeType: "image/jpeg")
                drafts.uploadedImage = attachment.url
            } catch {
                imageError = "照片上传失败：\(error.localizedDescription) 草稿还在，点发布可以重试。"
                return
            }
        }
        if await store.publish(content: drafts.text, image: drafts.uploadedImage) {
            drafts.clearPost()
            dismiss()
        }
    }
}

private struct MomentTextEditor: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: MomentsStore
    @ObservedObject var drafts: MomentsDraftStore
    let title: String
    let action: String
    @Binding var text: String
    let submit: (String) async -> Bool
    @State private var submitting = false
    private var busy: Bool { submitting || store.saving }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metric.gapM) {
                    TextEditor(text: $text)
                        .font(theme.font.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: MomentsTheme.editorHeight)
                        .padding(theme.metric.gapS)
                        .background(theme.pageColor.card, in: RoundedRectangle(cornerRadius: theme.metric.radiusCard))
                        .disabled(busy)
                        .accessibilityLabel(title)
                        .accessibilityIdentifier("moment-editor-text")
                    if busy { ProgressView("正在保存") }
                    if let error = drafts.persistenceError ?? store.error {
                        Text(error).font(theme.font.caption)
                            .foregroundStyle(theme.pageColor.textSecondary)
                            .accessibilityIdentifier("moment-editor-error")
                    }
                }.padding(theme.metric.pagePadding)
            }
            .background(theme.pageBackground.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("稍后再写") { dismiss() }.disabled(busy)
                        .accessibilityIdentifier("moment-editor-close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action) {
                        guard !busy else { return }
                        submitting = true
                        Task { @MainActor in
                            if await submit(text) { dismiss() }
                            submitting = false
                        }
                    }
                    .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("moment-editor-save")
                }
            }
        }
        .foregroundStyle(theme.pageColor.textPrimary)
        .tint(theme.pageAccent)
        .interactiveDismissDisabled(busy)
    }
}

private struct MomentRemoteImage: View {
    @EnvironmentObject private var theme: Theme
    let url: String
    let line: ChatLine
    var preview: (() -> Void)? = nil
    @State private var image: UIImage?
    @State private var failed = false
    @State private var retry = 0

    var body: some View {
        Group {
            if let image {
                if let preview {
                    Button(action: preview) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                    .accessibilityLabel("查看动态照片")
                } else {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("动态照片")
                }
            } else if failed {
                Button { retry += 1 } label: {
                    VStack(spacing: theme.metric.gapS) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(theme.font.attachmentIcon)
                        Text("图片未加载，点此重试").font(theme.font.caption)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.pageColor.card)
                }
                .accessibilityIdentifier("moment-image-retry")
            } else {
                ProgressView("正在载入照片")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.pageColor.card)
            }
        }
        .buttonStyle(.plain)
        .task(id: "\(url)-\(retry)") {
            image = nil; failed = false
            do {
                let data = try await APIClient(baseURL: line.apiBaseURL).fetchMomentImageData(at: url)
                try Task.checkCancellation()
                guard let decoded = UIImage(data: data) else { failed = true; return }
                image = decoded
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch { failed = true }
        }
    }
}

private struct MomentImagePreview: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    let url: String
    let line: ChatLine
    var body: some View {
        NavigationStack {
            MomentRemoteImage(url: url, line: line)
                .padding(theme.metric.pagePadding)
                .background(theme.pageBackground.ignoresSafeArea())
                .navigationTitle("照片")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("收起") { dismiss() }
                            .accessibilityIdentifier("moment-image-close")
                    }
                }
                .accessibilityIdentifier("moment-image-preview")
        }.tint(theme.pageAccent)
    }
}

private struct MomentErrorBanner: View {
    @EnvironmentObject private var theme: Theme
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapS) {
            Label(message, systemImage: "wifi.exclamationmark")
                .font(theme.font.caption)
            Button("重新载入", action: retry)
                .frame(minHeight: theme.metric.touchTarget)
                .accessibilityIdentifier("moments-retry")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.metric.gapM)
        .background(theme.pageColor.card, in: RoundedRectangle(cornerRadius: theme.metric.radiusCard))
        .accessibilityIdentifier("moments-error")
    }
}

private enum MomentDate {
    static func label(_ value: String) -> String {
        guard let date = CompanionDate.parse(value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "今天 HH:mm" : "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
