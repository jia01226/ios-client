import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

private enum ChatSettingsPage: Equatable {
    case root
    case search
    case delete
    case models
}

struct ChatView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var vm = ChatViewModel()
    @StateObject private var recentPhotos = RecentPhotosStore()
    @State private var draft = ""
    @FocusState private var inputFocused: Bool
    @State private var settingsOpen = false
    @State private var attachmentsOpen = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var importingFile = false
    @State private var showingCamera = false
    @State private var settingsPage: ChatSettingsPage = .root
    @State private var searchQuery = ""
    @State private var selectedMessageIDs: Set<Int> = []
    @State private var showingDeleteConfirmation = false
    @State private var highlightedMessageID: String?
    @State private var presentedThinkingMessageID: String?
    @State private var previewedImage: ChatAttachment?
    @State private var expandedModelGroups: Set<String> = []

    var body: some View {
        Group {
            switch vm.phase {
            case .checking:
                checkingView
            case .needsLogin:
                LoginView(vm: vm)
            case .ready:
                chatContent
            case let .unavailable(message):
                unavailableView(message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .animation(.easeInOut(duration: 0.6), value: theme.isBedroom)
        .task { await vm.bootstrap() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await vm.resumeFromForeground() }
        }
    }

    private var chatContent: some View {
        GeometryReader { _ in
            ZStack(alignment: .trailing) {
                VStack(spacing: 0) {
                    header
                    if let status = vm.statusText {
                        StatusBanner(text: status)
                            .padding(.horizontal, theme.metric.pagePadding)
                            .padding(.bottom, theme.metric.gapS)
                    }
                    messageList
                        .overlay(alignment: .bottom) {
                            if attachmentsOpen { attachmentTray }
                        }
                    if vm.isUploading || !vm.pendingAttachments.isEmpty || vm.uploadError != nil {
                        pendingAttachmentBar
                    }
                    inputBar
                }

                if settingsOpen {
                    theme.color.glassShadow.opacity(theme.glass.scrimOpacity)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { closeTransientPanels() }
                        .transition(.opacity)

                    settingsDrawer
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

#if DEBUG
                if vm.replyStreamTriggerAvailable {
                    VStack {
                        HStack {
                            Button {
                                Task { await vm.startReplyStreamForUITest() }
                            } label: {
                                Color.clear
                                    .frame(
                                        width: theme.metric.touchTarget,
                                        height: theme.metric.touchTarget
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("继续测试流式回复")
                            .accessibilityIdentifier("ui-test-reply-stream-trigger")
                            Spacer()
                        }
                        Spacer()
                    }
                }
#endif
            }
        }
        .animation(.easeOut(duration: 0.22), value: settingsOpen)
        .fileImporter(
            isPresented: $importingFile,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            attachmentsOpen = false
            guard case let .success(urls) = result, let url = urls.first else { return }
            Task { await vm.addFile(url: url) }
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker { image in
                guard let data = image.chatUploadJPEGData() else {
                    vm.reportUploadFailure("这张照片没有读取成功，请重新拍一次。")
                    return
                }
                Task {
                    await vm.addAttachment(
                        data: data,
                        fileName: "照片-\(UUID().uuidString.prefix(8)).jpg",
                        mimeType: "image/jpeg"
                    )
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: thinkingSheetPresented) {
            thinkingSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .fullScreenCover(item: $previewedImage) { attachment in
            AttachmentImageViewer(attachment: attachment) {
                previewedImage = nil
            }
        }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 3) {
                Text("柯")
                    .font(theme.font.chatHeader)
                    .foregroundStyle(theme.color.textPrimary)

                if vm.isSending {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(theme.color.glassEdge)
                        Text("正在输入…")
                    }
                    .font(.caption2)
                    .foregroundStyle(theme.color.textSecondary)
                    .transition(.opacity)
                } else {
                    Text(vm.isShowingCachedMessages ? "离线记录" : "在线")
                        .font(.caption2)
                        .foregroundStyle(theme.color.textSecondary)
                        .transition(.opacity)
                }
            }

            HStack {
                Spacer()
                Button {
                    settingsOpen = true
                    settingsPage = .root
                    attachmentsOpen = false
                    inputFocused = false
                } label: {
                    Image(systemName: "ellipsis")
                        .symbolVariant(.none)
                        .rotationEffect(.degrees(90))
                        .font(theme.font.menuIcon)
                        .foregroundStyle(theme.color.textPrimary)
                        .frame(width: theme.metric.touchTarget, height: theme.metric.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开聊天设置")
            }
        }
        .padding(.horizontal, theme.metric.pagePadding)
        .padding(.top, theme.metric.headerTopPadding)
        .padding(.bottom, theme.metric.headerBottomPadding)
        .frame(minHeight: theme.metric.headerMinHeight)
    }

    private var messageList: some View {
        Group {
            if vm.messages.isEmpty {
                emptyTimeline
            } else {
                ChatCollectionTimeline(
                    items: vm.messages.flatMap { message in
                        ChatTimelineItem.make(
                            message: message,
                            isHighlighted: highlightedMessageID == message.id,
                            visibleSegmentCount: vm.visibleSegmentCount(for: message)
                        )
                    },
                    streamRevision: vm.streamRevision,
                    suppressAutoScrollUntil: presentedThinkingMessageID == nil
                        ? .distantPast
                        : .distantFuture,
                    inputFocused: inputFocused,
                    highlightedMessageID: highlightedMessageID,
                    onThinkingOpen: { messageID in
                        inputFocused = false
                        attachmentsOpen = false
                        presentedThinkingMessageID = messageID
#if DEBUG
                        vm.didOpenThinkingForUITest(messageID: messageID)
#endif
                    },
                    onAttachmentTap: { attachment in
                        previewedImage = attachment
                    },
                    onBackgroundTap: {
                        inputFocused = false
                        if attachmentsOpen { attachmentsOpen = false }
                    }
                )
                .equatable()
            }
        }
        .onChange(of: inputFocused) { _, focused in
            if focused {
                attachmentsOpen = false
            }
        }
    }

    @ViewBuilder
    private var emptyTimeline: some View {
        if vm.isLoadingHistory {
            VStack(spacing: theme.metric.gapM) {
                ProgressView()
                    .tint(theme.effectiveAccent)
                Text("正在接回聊天记录…")
                    .font(theme.font.body)
                    .foregroundStyle(theme.color.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, theme.metric.gapXL)
            .frame(maxHeight: .infinity, alignment: .top)
        } else if vm.historyLoadFailed {
            VStack(spacing: theme.metric.gapM) {
                Text("聊天记录这次没有接上。")
                    .font(theme.font.body)
                    .foregroundStyle(theme.color.textSecondary)
                Button("重新加载聊天记录") {
                    Task { await vm.retryHistory() }
                }
                .buttonStyle(.bordered)
                .tint(theme.effectiveAccent)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, theme.metric.gapXL)
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            Text("这里还没有聊天记录。\n想说什么，就从下面开始。")
                .font(theme.font.body)
                .foregroundStyle(theme.color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, theme.metric.gapXL)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var inputBar: some View {
        HStack(spacing: theme.metric.gapS) {
            Button {
                inputFocused = false
                if reduceMotion {
                    attachmentsOpen.toggle()
                } else {
                    withAnimation(.easeOut(duration: 0.18)) {
                        attachmentsOpen.toggle()
                    }
                }
            } label: {
                Image(systemName: attachmentsOpen ? "xmark" : "plus")
                    .font(theme.font.composerIcon)
                    .frame(width: theme.metric.touchTarget, height: theme.metric.touchTarget)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.color.textPrimary)
            .accessibilityLabel(attachmentsOpen ? "关闭附件" : "打开附件")

            TextField("和柯说点什么…", text: $draft, axis: .vertical)
                .accessibilityIdentifier("chat-composer")
                .lineLimit(1...5)
                .font(theme.font.body)
                .foregroundStyle(theme.color.textPrimary)
                .focused($inputFocused)
                .padding(.horizontal, 4)
                .padding(.vertical, 11)

            Button { send() } label: {
                Group {
                    if vm.isSending {
                        ProgressView()
                            .tint(theme.color.textOnAccent)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(theme.font.sendIcon)
                    }
                }
                .foregroundStyle(theme.color.textOnAccent)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(theme.effectiveAccent.opacity(theme.glass.sendFillOpacity))
                        .overlay(Circle().stroke(theme.color.glassEdge, lineWidth: theme.metric.glassStrokeWidth))
                )
            }
            .disabled(!canSend || vm.isSending || vm.isUploading)
            .opacity(!canSend || vm.isSending || vm.isUploading ? 0.45 : 1)
            .accessibilityLabel("发送消息")
            .accessibilityIdentifier("send-message")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(CrystalSurface(cornerRadius: theme.metric.radiusComposer, strength: 1.05))
        .padding(.horizontal, theme.metric.pagePadding)
        .padding(.vertical, theme.metric.gapS)
    }

    private var attachmentTray: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapM) {
            HStack(spacing: theme.metric.gapM) {
                attachmentButton(title: "拍照", systemImage: "camera") {
                    attachmentsOpen = false
                    showingCamera = UIImagePickerController.isSourceTypeAvailable(.camera)
                }

                PhotosPicker(
                    selection: $pickedPhotos,
                    maxSelectionCount: max(1, 9 - vm.pendingAttachments.count),
                    matching: .images
                ) {
                    attachmentLabel(title: "所有照片", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.plain)
                .disabled(vm.pendingAttachments.count >= 9 || vm.isUploading)

                attachmentButton(title: "文件", systemImage: "folder") {
                    importingFile = true
                }
            }

            if recentPhotos.isLoading {
                settingsProgress("正在读取最近照片…")
            } else if recentPhotos.permissionDenied {
                settingsHint("照片权限未开放，可以点“所有照片”从系统选择器中选取。")
            } else if !recentPhotos.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: theme.metric.gapS) {
                        ForEach(recentPhotos.photos) { photo in
                            Button {
                                Task {
                                    guard let value = await recentPhotos.imageData(for: photo.id) else {
                                        vm.reportUploadFailure("这张照片没有读取成功，请再选一次。")
                                        return
                                    }
                                    await vm.addPhotoAttachment(
                                        data: value.data,
                                        fileName: value.fileName,
                                        mimeType: value.mimeType
                                    )
                                }
                            } label: {
                                Image(uiImage: photo.thumbnail)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(
                                        width: theme.metric.recentPhotoSize,
                                        height: theme.metric.recentPhotoSize
                                    )
                                    .clipShape(RoundedRectangle(
                                        cornerRadius: theme.metric.radiusChip,
                                        style: .continuous
                                    ))
                            }
                            .buttonStyle(.plain)
                            .disabled(vm.isUploading || vm.pendingAttachments.count >= 9)
                        }
                    }
                }
                .frame(height: theme.metric.recentPhotoSize)
            }
        }
        .padding(theme.metric.gapM)
        .background(
            CrystalSurface(cornerRadius: theme.metric.radiusAttachmentTray, strength: 1.08)
                .accessibilityElement()
                .accessibilityIdentifier("attachment-tray")
        )
        .padding(.horizontal, theme.metric.pagePadding)
        .fixedSize(horizontal: false, vertical: true)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-test-attachment-overlay") {
                return
            }
#endif
            await recentPhotos.loadIfNeeded()
        }
        .onChange(of: pickedPhotos) { _, value in
            guard !value.isEmpty else { return }
            attachmentsOpen = false
            let items = value
            pickedPhotos = []
            Task {
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        vm.reportUploadFailure("有一张照片没有读取成功，请再选一次。")
                        continue
                    }
                    let type = item.supportedContentTypes.first ?? .jpeg
                    let ext = type.preferredFilenameExtension ?? "jpg"
                    await vm.addPhotoAttachment(
                        data: data,
                        fileName: "照片-\(UUID().uuidString.prefix(8)).\(ext)",
                        mimeType: type.preferredMIMEType ?? "image/jpeg"
                    )
                }
            }
        }
    }

    private var thinkingSheetPresented: Binding<Bool> {
        Binding(
            get: { presentedThinkingMessageID != nil },
            set: { presented in
                if !presented { presentedThinkingMessageID = nil }
            }
        )
    }

    @ViewBuilder
    private var thinkingSheet: some View {
        if let messageID = presentedThinkingMessageID,
           let message = vm.messages.first(where: { $0.id == messageID }) {
            ThinkingSheetView(message: message) {
                presentedThinkingMessageID = nil
            }
        }
    }

    private var pendingAttachmentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.metric.gapS) {
                if vm.isUploading {
                    HStack(spacing: theme.metric.gapXS) {
                        ProgressView().controlSize(.small)
                        Text(vm.uploadingFileName.map { "正在上传 \($0)…" } ?? "正在上传…")
                    }
                    .font(theme.font.caption)
                    .foregroundStyle(theme.color.textSecondary)
                }

                ForEach(vm.pendingAttachments) { attachment in
                    HStack(spacing: theme.metric.gapXS) {
                        if attachment.isImage {
                            Button {
                                previewedImage = attachment
                            } label: {
                                HStack(spacing: theme.metric.gapXS) {
                                    Image(systemName: "photo")
                                    Text(attachment.name).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("预览待发送图片 \(attachment.name)")
                        } else {
                            Image(systemName: "doc")
                            Text(attachment.name).lineLimit(1)
                        }
                        Button {
                            vm.removePendingAttachment(attachment)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("移除 \(attachment.name)")
                    }
                    .font(theme.font.caption)
                    .foregroundStyle(theme.color.textSecondary)
                    .padding(.leading, theme.metric.gapS)
                    .background(CrystalSurface(
                        cornerRadius: theme.metric.radiusChip,
                        strength: 0.7,
                        usesChatControls: true
                    ))
                }

                if let error = vm.uploadError {
                    HStack(spacing: theme.metric.gapS) {
                        Text(error)
                            .font(theme.font.caption)
                            .foregroundStyle(theme.color.textSecondary)
                        if vm.canRetryUpload {
                            Button("重试") {
                                Task { await vm.retryLastUpload() }
                            }
                            .buttonStyle(.borderless)
                            .font(theme.font.caption)
                            .foregroundStyle(theme.effectiveAccent)
                        }
                    }
                }
            }
            .padding(.horizontal, theme.metric.pagePadding)
        }
    }

    private func attachmentButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            attachmentLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func attachmentLabel(title: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(theme.font.attachmentIcon)
            Text(title).font(.caption)
        }
        .foregroundStyle(theme.color.textPrimary)
        .frame(maxWidth: .infinity, minHeight: 66)
        .contentShape(Rectangle())
    }

    private var settingsDrawer: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsHeader

            ScrollView {
                Group {
                    switch settingsPage {
                    case .root:
                        settingsRoot
                    case .search:
                        searchSettings
                    case .delete:
                        deleteSettings
                    case .models:
                        modelSettings
                    }
                }
                .padding(.horizontal, theme.metric.gapL)
                .padding(.bottom, theme.metric.gapXL)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
        }
        .frame(width: theme.metric.drawerWidth)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(theme.color.glassEdge.opacity(theme.glass.drawerEdgeOpacity))
                .frame(width: 0.7)
        }
        .alert("删除选中的聊天记录？", isPresented: $showingDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("确认删除") {
                let ids = selectedMessageIDs
                Task {
                    let deleted = await vm.deleteMessages(ids: ids)
                    selectedMessageIDs.subtract(deleted)
                }
            }
        } message: {
            Text("将删除 \(selectedMessageIDs.count) 条聊天记录。不会删除长期记忆。")
        }
    }

    private var settingsHeader: some View {
        HStack(spacing: theme.metric.gapS) {
            if settingsPage != .root {
                Button {
                    settingsPage = .root
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: theme.metric.touchTarget, height: theme.metric.touchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回聊天设置")
            }

            Text(settingsTitle)
                .font(theme.font.sectionTitle)
                .foregroundStyle(theme.color.textPrimary)
            Spacer()
            Button { closeTransientPanels() } label: {
                Image(systemName: "xmark")
                    .frame(width: theme.metric.touchTarget, height: theme.metric.touchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭聊天设置")
        }
        .foregroundStyle(theme.color.textSecondary)
        .padding(.horizontal, theme.metric.gapM)
        .padding(.vertical, theme.metric.gapXS)
        .frame(minHeight: theme.metric.drawerHeaderHeight)
    }

    private var settingsTitle: String {
        switch settingsPage {
        case .root: return "聊天设置"
        case .search: return "查找聊天记录"
        case .delete: return "批量删除"
        case .models: return "模型选择"
        }
    }

    private var settingsRoot: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapL) {
            settingsLink("查找聊天记录", icon: "magnifyingglass") {
                settingsPage = .search
                Task { await vm.prepareSearchCorpus() }
            }
            settingsLink("批量删除聊天记录", icon: "checklist") {
                settingsPage = .delete
                Task { await vm.prepareSearchCorpus() }
            }
            settingsLink("模型选择", icon: "sparkles") {
                settingsPage = .models
                Task {
                    await vm.loadModelSettings(force: true)
                    expandSelectedModelGroup()
                }
            }

            settingSlider(
                title: "气泡透明度",
                value: $theme.bubbleOpacity,
                range: 0...0.06,
                valueText: String(format: "%.1f%%", theme.bubbleOpacity * 100)
            )
            settingSlider(
                title: "玻璃模糊",
                value: $theme.glassBlur,
                range: 0...theme.glass.maximumBlurValue,
                valueText: "\(Int(theme.glassBlur.rounded()))"
            )
            settingSlider(
                title: "气泡圆角",
                value: $theme.bubbleCornerRadius,
                range: 12...34,
                valueText: "\(Int(theme.bubbleCornerRadius))"
            )
            settingSlider(
                title: "聊天字体",
                value: $theme.chatFontSize,
                range: 13...22,
                valueText: "\(Int(theme.chatFontSize))"
            )

            Text("透明度可以降到完全透明；模糊、圆角和字体会即时预览，并保存在这台手机上。")
                .font(theme.font.caption)
                .foregroundStyle(theme.color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, theme.metric.gapS)
    }

    private func settingsLink(
        _ title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 22)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .font(theme.font.body)
            .foregroundStyle(theme.color.textPrimary)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var searchSettings: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapM) {
            HStack(spacing: theme.metric.gapS) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.color.textSecondary)
                TextField("输入关键词", text: $searchQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, theme.metric.gapM)
            .frame(minHeight: theme.metric.touchTarget)
            .background(CrystalSurface(
                cornerRadius: theme.metric.radiusChip,
                strength: 0.72,
                usesChatControls: true
            ))

            if vm.isPreparingSearch {
                settingsProgress("正在整理本地聊天缓存…")
            } else {
                if let error = vm.searchError {
                    settingsError(error) {
                        Task { await vm.prepareSearchCorpus(force: true) }
                    }
                }

                if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    settingsHint("输入一句话或关键词；第一版只搜索这台手机已缓存的记录。")
                } else if vm.searchResults(for: searchQuery).isEmpty {
                    settingsHint("本地缓存里没有找到。")
                } else {
                    LazyVStack(spacing: theme.metric.gapS) {
                        ForEach(vm.searchResults(for: searchQuery)) { message in
                            Button {
                                vm.revealSearchResult(message)
                                highlightedMessageID = message.id
                                settingsOpen = false
                                Task {
                                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                                    if highlightedMessageID == message.id {
                                        highlightedMessageID = nil
                                    }
                                }
                            } label: {
                                searchResultRow(message)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.top, theme.metric.gapS)
    }

    private var deleteSettings: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapM) {
            settingsHint("选择要删除的聊天记录。只调用现有删除接口，不动长期记忆。")

            if vm.isPreparingSearch {
                settingsProgress("正在整理本地聊天缓存…")
            }

            if let error = vm.deleteError {
                Text(error)
                    .font(theme.font.caption)
                    .foregroundStyle(theme.color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVStack(spacing: theme.metric.gapS) {
                ForEach(vm.deletionCandidates) { message in
                    Button {
                        guard let id = message.serverID else { return }
                        if selectedMessageIDs.contains(id) {
                            selectedMessageIDs.remove(id)
                        } else {
                            selectedMessageIDs.insert(id)
                        }
                    } label: {
                        deleteRow(message)
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isDeleting)
                }
            }

            Button {
                showingDeleteConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    if vm.isDeleting {
                        ProgressView().tint(theme.color.textOnAccent)
                    } else {
                        Text(selectedMessageIDs.isEmpty
                             ? "选择消息"
                             : "删除 \(selectedMessageIDs.count) 条")
                    }
                    Spacer()
                }
                .font(theme.font.body)
                .foregroundStyle(theme.color.textOnAccent)
                .frame(minHeight: theme.metric.touchTarget)
                .background(
                    RoundedRectangle(cornerRadius: theme.metric.radiusChip, style: .continuous)
                        .fill(theme.effectiveAccent)
                )
            }
            .buttonStyle(.plain)
            .disabled(selectedMessageIDs.isEmpty || vm.isDeleting)
            .opacity(selectedMessageIDs.isEmpty || vm.isDeleting ? 0.45 : 1)
        }
        .padding(.top, theme.metric.gapS)
    }

    private var modelSettings: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapM) {
            if vm.isLoadingModels && vm.modelOptions.isEmpty {
                settingsProgress("正在读取可用模型…")
            } else if let error = vm.modelError, vm.modelOptions.isEmpty {
                settingsError(error) {
                    Task { await vm.loadModelSettings(force: true) }
                }
            } else {
                if let error = vm.modelError {
                    Text("模型列表暂时没刷新：\(error)")
                        .font(.caption)
                        .foregroundStyle(theme.color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("model-catalog-error")
                }

                if let selected = selectedModelOption {
                    HStack(alignment: .top, spacing: theme.metric.gapS) {
                        VStack(alignment: .leading, spacing: theme.metric.gapXS) {
                            Text("主线路")
                                .font(.caption)
                                .foregroundStyle(theme.color.textSecondary)
                            Text("\(modelSectionTitle(for: selected)) · \(selected.displayName)")
                                .font(theme.font.sectionTitle)
                                .foregroundStyle(theme.color.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("selected-model-summary")
                            if let routeSummary = modelRouteSummary {
                                Text(routeSummary)
                                    .font(.caption)
                                    .foregroundStyle(theme.color.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("model-route-summary")
                            }
                        }
                        Spacer(minLength: theme.metric.gapS)
                        Button {
                            Task { await vm.loadModelSettings(force: true) }
                        } label: {
                            Group {
                                if vm.isLoadingModelQuotas {
                                    ProgressView()
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                            }
                            .frame(
                                width: theme.metric.touchTarget,
                                height: theme.metric.touchTarget
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.color.textSecondary)
                        .disabled(vm.isLoadingModelQuotas || vm.isLoadingModels)
                        .accessibilityLabel("刷新模型额度")
                        .accessibilityIdentifier("refresh-model-quotas")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, theme.metric.gapS)
                }

                if let error = vm.modelQuotaError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(theme.color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("model-quota-error")
                }

                ForEach(modelSections) { section in
                    modelDisclosure(section)
                }
            }
        }
        .padding(.top, theme.metric.gapS)
    }

    private var modelSections: [ChatModelSection] {
        ChatModelSection.make(options: vm.modelOptions, groups: vm.modelGroups)
    }

    private var selectedModelOption: ChatModelOption? {
        vm.modelOptions.first { $0.id == vm.selectedModel }
    }

    private func modelSectionTitle(for option: ChatModelOption) -> String {
        let groupID = ChatModelSection.normalizedGroup(
            option.family ?? option.group ?? option.provider ?? ""
        )
        return modelSections.first(where: { $0.id == groupID })?.title ?? "模型"
    }

    @ViewBuilder
    private func modelDisclosure(_ section: ChatModelSection) -> some View {
        let isExpanded = expandedModelGroups.contains(section.id)
        let quotaSummary = modelQuotaSummary(for: section.id)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleModelGroup(section.id)
            } label: {
                HStack(spacing: theme.metric.gapS) {
                    VStack(alignment: .leading, spacing: theme.metric.gapXS) {
                        Text(section.title)
                            .font(theme.font.sectionTitle)
                            .foregroundStyle(theme.color.textPrimary)
                        if let selected = section.options.first(where: { $0.id == vm.selectedModel }) {
                            Text(selected.displayName)
                                .font(theme.font.caption)
                                .foregroundStyle(theme.effectiveAccent)
                        }
                        if let quotaSummary {
                            Text(quotaSummary)
                                .font(.caption)
                                .foregroundStyle(theme.color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("model-quota-\(section.id)")
                        } else if !section.isAvailable, let message = section.statusMessage {
                            Text(message)
                                .font(theme.font.caption)
                                .foregroundStyle(theme.color.textSecondary)
                        }
                    }
                    Spacer(minLength: theme.metric.gapS)
                    Image(systemName: "chevron.right")
                        .font(theme.font.disclosureIcon)
                        .foregroundStyle(theme.color.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("model-group-\(section.id)")
            .accessibilityLabel("\(section.title)，\(isExpanded ? "已展开" : "已折叠")")
            .accessibilityValue(quotaSummary ?? "")
            .accessibilityHint(isExpanded ? "点两下折叠" : "点两下查看模型")

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    if let quota = modelQuotaGroup(for: section.id), !quota.windows.isEmpty {
                        modelQuotaDetails(quota)
                    }
                    if section.options.isEmpty {
                        Text(section.statusMessage ?? "暂时没有可选模型")
                            .font(theme.font.caption)
                            .foregroundStyle(theme.color.textSecondary)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: theme.metric.touchTarget,
                                alignment: .leading
                            )
                    } else {
                        ForEach(section.options) { option in
                            modelOptionRow(option)
                        }
                    }
                }
                .padding(.leading, theme.metric.gapM)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Rectangle()
                .fill(theme.color.separator)
                .frame(height: 0.7)
        }
    }

    private func modelOptionRow(_ option: ChatModelOption) -> some View {
        Button {
            Task { await vm.selectModel(option.id) }
        } label: {
            HStack(alignment: .top, spacing: theme.metric.gapM) {
                VStack(alignment: .leading, spacing: theme.metric.gapXS) {
                    Text(option.displayName)
                        .font(theme.font.body)
                        .foregroundStyle(theme.color.textPrimary)
                    if let description = option.description,
                       !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(description)
                            .font(theme.font.caption)
                            .foregroundStyle(theme.color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: theme.metric.gapS)
                if vm.selectedModel == option.id {
                    Image(systemName: "checkmark")
                        .font(theme.font.disclosureIcon)
                        .foregroundStyle(theme.effectiveAccent)
                        .accessibilityHidden(true)
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: theme.metric.touchTarget,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(vm.isSelectingModel || !option.isAvailable)
        .opacity(option.isAvailable ? 1 : 0.45)
        .accessibilityIdentifier("model-option-\(option.id)")
        .accessibilityValue(vm.selectedModel == option.id ? "已选择" : "")
    }

    private var modelRouteSummary: String? {
        guard vm.modelQuotaError == nil,
              let selectedModelOption,
              let catalog = vm.modelQuotaCatalog,
              let selected = catalog.selectedGroup,
              let current = catalog.currentRouteGroup,
              selected != current else { return nil }
        let selectedOptionGroup = ChatModelSection.normalizedGroup(
            selectedModelOption.family
                ?? selectedModelOption.group
                ?? selectedModelOption.provider
                ?? ""
        )
        guard selectedOptionGroup == ChatModelSection.normalizedGroup(selected) else {
            return nil
        }
        return "当前自动接到 \(modelRouteTitle(current))；\(modelRouteTitle(selected)) 恢复后会自动回来"
    }

    private func modelRouteTitle(_ id: String) -> String {
        switch ChatModelSection.normalizedGroup(id) {
        case "claude_1": return "Claude 1"
        case "claude_2": return "Claude 2"
        case "gpt": return "GPT"
        case "deepseek": return "DPSK"
        default: return "备用线路"
        }
    }

    private func modelQuotaGroup(for id: String) -> ChatModelQuotaGroup? {
        vm.modelQuotaCatalog?.groups.first {
            ChatModelSection.normalizedGroup($0.id) == ChatModelSection.normalizedGroup(id)
        }
    }

    private func modelQuotaSummary(for id: String) -> String? {
        let normalized = ChatModelSection.normalizedGroup(id)
        guard ["claude_1", "claude_2", "gpt"].contains(normalized) else { return nil }
        guard let quota = modelQuotaGroup(for: normalized) else {
            if vm.isLoadingModelQuotas { return "正在读取额度…" }
            if vm.modelQuotaError != nil { return "额度暂时没读到" }
            return nil
        }

        let staleSuffix = quota.stale ? " · 上次结果" : ""
        switch quota.status {
        case "cooldown":
            if let reset = modelQuotaResetText(quota.resetAt) {
                return "额度已用完 · \(reset)\(staleSuffix)"
            }
            return "额度已用完\(staleSuffix)"
        case "not_configured":
            return "尚未接入"
        case "unknown":
            return "额度暂时没读到\(staleSuffix)"
        default:
            if let remaining = quota.remainingPercent {
                let value = Int(min(100, max(0, remaining)).rounded())
                return "剩余 \(value)%\(staleSuffix)"
            }
            return "可用 · 暂无精确比例\(staleSuffix)"
        }
    }

    private func modelQuotaDetails(_ quota: ChatModelQuotaGroup) -> some View {
        VStack(alignment: .leading, spacing: theme.metric.gapS) {
            ForEach(Array(quota.windows.enumerated()), id: \.offset) { _, window in
                VStack(alignment: .leading, spacing: theme.metric.gapXS) {
                    HStack(spacing: theme.metric.gapS) {
                        Text(modelQuotaWindowLabel(window.windowMinutes))
                        Spacer(minLength: theme.metric.gapS)
                        if let remaining = window.remainingPercent {
                            Text("剩余 \(Int(min(100, max(0, remaining)).rounded()))%")
                                .monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(theme.color.textSecondary)

                    if let remaining = window.remainingPercent {
                        ProgressView(value: min(100, max(0, remaining)), total: 100)
                            .tint(theme.effectiveAccent)
                            .accessibilityLabel(modelQuotaWindowLabel(window.windowMinutes))
                            .accessibilityValue("剩余 \(Int(remaining.rounded()))%")
                    }

                    if let reset = modelQuotaResetText(window.resetAt) {
                        Text(reset)
                            .font(.caption)
                            .foregroundStyle(theme.color.textSecondary)
                    }
                }
            }
        }
        .padding(.vertical, theme.metric.gapS)
        .accessibilityIdentifier("model-quota-details-\(quota.id)")
    }

    private func modelQuotaWindowLabel(_ minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "订阅额度" }
        if minutes % 10_080 == 0 { return "\(minutes / 10_080 * 7) 天额度" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440) 天额度" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时额度" }
        return "\(minutes) 分钟额度"
    }

    private func modelQuotaResetText(_ epoch: TimeInterval?) -> String? {
        guard let epoch, epoch > 0 else { return nil }
        let date = Date(timeIntervalSince1970: epoch)
        let calendar = Calendar.autoupdatingCurrent
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .autoupdatingCurrent

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return "\(formatter.string(from: date)) 恢复"
        }
        if calendar.isDateInTomorrow(date) {
            formatter.dateFormat = "HH:mm"
            return "明天 \(formatter.string(from: date)) 恢复"
        }
        formatter.dateFormat = "M月d日 HH:mm"
        return "\(formatter.string(from: date)) 恢复"
    }

    private func toggleModelGroup(_ id: String) {
        let animation: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.18)
        withAnimation(animation) {
            if expandedModelGroups.contains(id) {
                expandedModelGroups.remove(id)
            } else {
                expandedModelGroups.insert(id)
            }
        }
    }

    private func expandSelectedModelGroup() {
        guard let option = selectedModelOption else { return }
        let groupID = ChatModelSection.normalizedGroup(
            option.family ?? option.group ?? option.provider ?? ""
        )
        expandedModelGroups.insert(groupID)
    }

    private func searchResultRow(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: theme.metric.gapXS) {
            HStack {
                Text(message.sender == .me ? "我" : "柯")
                Spacer()
                Text(message.time.formatted(date: .abbreviated, time: .shortened))
            }
            .font(theme.font.caption)
            .foregroundStyle(theme.color.textSecondary)
            Text(message.text)
                .font(theme.font.body)
                .foregroundStyle(theme.color.textPrimary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, theme.metric.gapS)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deleteRow(_ message: Message) -> some View {
        HStack(alignment: .top, spacing: theme.metric.gapM) {
            Image(systemName: selectedMessageIDs.contains(message.serverID ?? -1)
                  ? "checkmark.circle.fill"
                  : "circle")
                .foregroundStyle(selectedMessageIDs.contains(message.serverID ?? -1)
                                 ? theme.effectiveAccent
                                 : theme.color.textSecondary)
            VStack(alignment: .leading, spacing: theme.metric.gapXS) {
                Text(message.text.isEmpty ? "附件消息" : message.text)
                    .font(theme.font.body)
                    .foregroundStyle(theme.color.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Text(message.time.formatted(date: .abbreviated, time: .shortened))
                    .font(theme.font.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, theme.metric.gapS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func settingsProgress(_ text: String) -> some View {
        HStack(spacing: theme.metric.gapS) {
            ProgressView().controlSize(.small)
            Text(text)
        }
        .font(theme.font.caption)
        .foregroundStyle(theme.color.textSecondary)
    }

    private func settingsHint(_ text: String) -> some View {
        Text(text)
            .font(theme.font.caption)
            .foregroundStyle(theme.color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func settingsError(_ text: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: theme.metric.gapS) {
            Text(text)
                .font(theme.font.caption)
                .foregroundStyle(theme.color.textSecondary)
            Button("再试一次", action: retry)
                .buttonStyle(.bordered)
                .tint(theme.effectiveAccent)
        }
    }

    private func settingSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueText: String
    ) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText).monospacedDigit()
            }
            .font(theme.font.caption)
            .foregroundStyle(theme.color.textSecondary)
            Slider(value: value, in: range)
                .tint(theme.effectiveAccent)
        }
    }

    private func closeTransientPanels() {
        settingsOpen = false
        attachmentsOpen = false
        inputFocused = false
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmedDraft.isEmpty || !vm.pendingAttachments.isEmpty
    }

    private func send() {
        let text = trimmedDraft
        guard canSend, !vm.isSending, !vm.isUploading else { return }
        draft = ""
        Task { await vm.send(text, reduceMotion: reduceMotion) }
    }

    private var checkingView: some View {
        VStack(spacing: theme.metric.gapM) {
            ProgressView()
                .tint(theme.effectiveAccent)
            Text("正在接回聊天记录…")
                .font(theme.font.body)
                .foregroundStyle(theme.color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unavailableView(_ message: String) -> some View {
        VStack(spacing: theme.metric.gapM) {
            Image(systemName: "wifi.exclamationmark")
                .font(theme.font.unavailableIcon)
                .foregroundStyle(theme.effectiveAccent)
            Text(message)
                .font(theme.font.body)
                .foregroundStyle(theme.color.textSecondary)
                .multilineTextAlignment(.center)
            Button("再试一次") {
                Task { await vm.retryBootstrap() }
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.effectiveAccent)
        }
        .padding(theme.metric.gapXL)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ChatView().environmentObject(Theme.shared)
}
