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
    @StateObject private var scrollAnchorController = ChatScrollAnchorController()
    @State private var draft = ""
    /// Thinking 展开/收起后的短窗：期间自动滚底一律禁行，防两套滚动打架闪屏。
    @State private var suppressAutoScrollUntil: Date = .distantPast
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
    @State private var expandedThinkingMessageIDs: Set<String> = []
    /// 键盘出现到完全收回期间，由同一条事务负责把最新消息贴住可视区底部。
    /// 不能在 focus / didShow 各滚一次，否则两套终点会造成闪跳。
    @State private var keyboardFollowsLatest = false
    @State private var keyboardScrollPosition: String?

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
                guard let data = image.jpegData(compressionQuality: 0.88) else { return }
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: theme.metric.gapM) {
                    if vm.messages.isEmpty {
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
                        } else {
                            Text("这里还没有聊天记录。\n想说什么，就从下面开始。")
                                .font(theme.font.body)
                                .foregroundStyle(theme.color.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, theme.metric.gapXL)
                        }
                    }

                    ForEach(vm.messages) { message in
                        MessageRow(
                            message: message,
                            isHighlighted: highlightedMessageID == message.id,
                            isThinkingExpanded: expandedThinkingMessageIDs.contains(message.id),
                            visibleSegmentCount: vm.visibleSegmentCount(for: message),
                            scrollAnchorController: scrollAnchorController,
                            onThinkingToggle: {
                                toggleThinking(for: message.id)
                            }
                        )
                            .id(message.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom")
                }
                .scrollTargetLayout()
                .padding(.horizontal, theme.metric.pagePadding)
                .padding(.bottom, theme.metric.gapL)
            }
            // 不用 defaultScrollAnchor(.bottom)：它在内容变高时自动贴底，会和
            // Thinking 展开的锚定恢复抢方向盘（两帧各拽一次＝她报的"点开最后会闪"）。
            // 初始定位靠 onAppear 的 scrollTo，流式/新消息跟随靠下面两个 onChange——
            // 滚动只留这一套显式控制者。
            .scrollContentBackground(.hidden)
            .scrollPosition(id: $keyboardScrollPosition, anchor: .bottom)
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture {
                inputFocused = false
                if attachmentsOpen { attachmentsOpen = false }
            }
            .onChange(of: vm.messages.last?.id) { _, _ in
                // 展开 Thinking 时，当前视口属于用户；下面即使继续收到分条消息，
                // 也只让内容向下生长，不把已经展开的标题和上方消息拖走。
                guard expandedThinkingMessageIDs.isEmpty else { return }
                guard Date.now >= suppressAutoScrollUntil else { return }
                scrollToBottom(proxy, animated: true)
            }
            .onChange(of: vm.streamRevision) { _, _ in
                // Thinking 展开/收起后的短窗内不跟滚——锚定恢复期间谁都不许抢方向盘，
                // 消息纹丝不动（她要的：被输入框遮住没关系，不许跳）。
                guard expandedThinkingMessageIDs.isEmpty else { return }
                guard Date.now >= suppressAutoScrollUntil else { return }
                scrollToBottom(proxy, animated: false)
            }
            .onChange(of: inputFocused) { _, focused in
                // 聚焦只转交滚动所有权；真正移动与系统键盘的 frame 动画同步进行。
                if focused {
                    keyboardFollowsLatest = true
                    attachmentsOpen = false
                    scrollAnchorController.cancelPreservation()
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillChangeFrameNotification
                )
            ) { notification in
                followLatestAlongsideKeyboard(notification)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIResponder.keyboardDidShowNotification
                )
            ) { _ in
                guard keyboardFollowsLatest else { return }
                // didShow 比 SwiftUI 最后一帧 safe-area 布局略早；继续跟一小段，
                // 等真实可视高度稳定后再停，避免“原本就在底部”时仍被压住。
                scrollAnchorController.followBottomAlongsideKeyboard(duration: 0.16)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIResponder.keyboardDidHideNotification
                )
            ) { _ in
                if keyboardFollowsLatest, !attachmentsOpen {
                    scrollAnchorController.followBottomAlongsideKeyboard(duration: 0.16)
                } else {
                    scrollAnchorController.stopFollowingBottom()
                }
                keyboardFollowsLatest = false
                DispatchQueue.main.async {
                    if !inputFocused {
                        keyboardScrollPosition = nil
                    }
                }
            }
            .onChange(of: highlightedMessageID) { _, value in
                guard let value else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(value, anchor: .center)
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("chat-bottom", anchor: .bottom)
        }
    }

    private func followLatestAlongsideKeyboard(_ notification: Notification) {
        // UIKit 的 keyboardWillChangeFrame 偶尔早于 SwiftUI FocusState 更新。
        // 聊天页没有打开设置抽屉时，键盘“正在出现”本身就是输入框接管的可靠信号。
        guard !settingsOpen else { return }
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else { return }

        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey]
            as? TimeInterval ?? 0
        let keyboardIsHiding = endFrame.minY >= UIScreen.main.bounds.maxY
        if !keyboardIsHiding {
            keyboardFollowsLatest = true
        }
        guard keyboardFollowsLatest || inputFocused else { return }

        // 点 + 时面板只是盖在原视口上，键盘收起不能顺手搬动聊天记录。
        // 普通点空白收键盘则继续贴住最新消息，避免底部留下整块空白。
        if keyboardIsHiding, attachmentsOpen {
            scrollAnchorController.stopFollowingBottom()
        } else {
            withAnimation(reduceMotion ? nil : .easeOut(duration: duration)) {
                keyboardScrollPosition = "chat-bottom"
            }
            scrollAnchorController.followBottomAlongsideKeyboard(duration: duration)
        }
    }

    private var inputBar: some View {
        HStack(spacing: theme.metric.gapS) {
            Button {
                keyboardFollowsLatest = false
                keyboardScrollPosition = nil
                scrollAnchorController.stopFollowingBottom()
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
                                    guard let value = await recentPhotos.imageData(for: photo.id) else { return }
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
                    guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
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

    private func toggleThinking(for messageID: String) {
        let willExpand = !expandedThinkingMessageIDs.contains(messageID)
        // 展开/收起后的 0.8 秒内，新消息/流式刷新一律不自动滚底，
        // 让锚定恢复独占滚动位置——治"点开思考链最后屏幕闪一下"。
        suppressAutoScrollUntil = Date.now.addingTimeInterval(0.8)
        // 展开固定消息顶部，让上方记录不动、内容只向下长；
        // 收起只固定当前视口，不把聊天拉回展开前的位置。
        scrollAnchorController.prepareToRestore(
            messageID: messageID,
            edge: willExpand ? .top : .viewport
        )
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            if willExpand {
                expandedThinkingMessageIDs.insert(messageID)
            } else {
                expandedThinkingMessageIDs.remove(messageID)
            }
        }
        scrollAnchorController.restoreAfterCurrentLayout(messageID: messageID)
#if DEBUG
        vm.didToggleThinkingForUITest(messageID: messageID)
#endif
    }

    private var pendingAttachmentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.metric.gapS) {
                if vm.isUploading {
                    HStack(spacing: theme.metric.gapXS) {
                        ProgressView().controlSize(.small)
                        Text("正在上传…")
                    }
                    .font(theme.font.caption)
                    .foregroundStyle(theme.color.textSecondary)
                }

                ForEach(vm.pendingAttachments) { attachment in
                    HStack(spacing: theme.metric.gapXS) {
                        Image(systemName: attachment.isImage ? "photo" : "doc")
                        Text(attachment.name).lineLimit(1)
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
                    Text(error)
                        .font(theme.font.caption)
                        .foregroundStyle(theme.color.textSecondary)
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
                Task { await vm.loadModels() }
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
            if vm.isLoadingModels {
                settingsProgress("正在读取可用模型…")
            } else if let error = vm.modelError {
                settingsError(error) {
                    Task { await vm.loadModels(force: true) }
                }
            } else if vm.modelOptions.isEmpty {
                settingsHint("服务器没有返回可用模型。")
            } else {
                ForEach(vm.modelOptions) { option in
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
                                    .foregroundStyle(theme.effectiveAccent)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: theme.metric.touchTarget, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isSelectingModel)
                }
            }
        }
        .padding(.top, theme.metric.gapS)
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

private struct LoginView: View {
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

private struct StatusBanner: View {
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

/// 保存一条可见消息的边缘快照，并在折叠布局稳定后恢复。
/// 这是聊天列表常用的 item snapshot 做法；不要在动画每一帧修正 contentOffset。
@MainActor
private final class ChatScrollAnchorController: ObservableObject {
    enum AnchorEdge: Equatable {
        case top
        case viewport
    }

    private final class WeakAnchor {
        weak var view: UIView?

        init(_ view: UIView) {
            self.view = view
        }
    }

    private struct PendingRestore {
        let token: UUID
        let messageID: String
        let edge: AnchorEdge
        let viewportCoordinate: CGFloat
        var attempts: Int
    }

    private weak var scrollView: UIScrollView?
    private var anchors: [String: WeakAnchor] = [:]
    private var pendingRestore: PendingRestore?
    private var scheduledToken: UUID?
    private var keyboardDisplayLink: CADisplayLink?
    private var keyboardFollowDeadline: CFTimeInterval = 0

    func register(_ anchor: UIView, messageID: String) {
        anchors[messageID] = WeakAnchor(anchor)
        resolveScrollView(from: anchor)
        if pendingRestore?.messageID == messageID {
            scheduleRestore(messageID: messageID)
        }
    }

    func prepareToRestore(messageID: String, edge: AnchorEdge) {
        cancelPreservation()
        guard
            let anchor = anchors[messageID]?.view,
            anchor.window != nil
        else { return }

        resolveScrollView(from: anchor)
        guard let scrollView else { return }
        let boundsInViewport = anchor.convert(anchor.bounds, to: nil)
        pendingRestore = PendingRestore(
            token: UUID(),
            messageID: messageID,
            edge: edge,
            viewportCoordinate: edge == .top
                ? boundsInViewport.minY
                : scrollView.contentOffset.y,
            attempts: 0
        )
    }

    func restoreAfterCurrentLayout(messageID: String) {
        guard pendingRestore?.messageID == messageID else { return }
        scheduleRestore(messageID: messageID)
    }

    func anchorDidLayout(messageID: String) {
        guard pendingRestore?.messageID == messageID else { return }
        scheduleRestore(messageID: messageID)
    }

    func cancelPreservation() {
        pendingRestore = nil
        scheduledToken = nil
    }

    /// 键盘改变可视高度时，最大 contentOffset 也逐帧变化。只算一次终点会过早，
    /// 因而在系统动画存续期间逐帧钉住真实底部；没有额外动画，也没有第二次跳转。
    func followBottomAlongsideKeyboard(duration: TimeInterval) {
        cancelPreservation()
        keyboardFollowDeadline = max(
            keyboardFollowDeadline,
            CACurrentMediaTime() + max(duration, 0.1) + 0.1
        )
        pinToBottom()
        guard keyboardDisplayLink == nil else { return }
        let displayLink = CADisplayLink(target: self, selector: #selector(followKeyboardFrame))
        displayLink.add(to: .main, forMode: .common)
        keyboardDisplayLink = displayLink
    }

    func stopFollowingBottom() {
        keyboardDisplayLink?.invalidate()
        keyboardDisplayLink = nil
        keyboardFollowDeadline = 0
    }

    @objc private func followKeyboardFrame(_ displayLink: CADisplayLink) {
        pinToBottom()
        if displayLink.timestamp >= keyboardFollowDeadline {
            stopFollowingBottom()
        }
    }

    private func pinToBottom() {
        guard let scrollView else { return }
        scrollView.layoutIfNeeded()
        let minimumY = -scrollView.adjustedContentInset.top
        let maximumY = max(
            minimumY,
            scrollView.contentSize.height
                + scrollView.adjustedContentInset.bottom
                - scrollView.bounds.height
        )
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: maximumY),
            animated: false
        )
    }

    private func scheduleRestore(messageID: String) {
        guard let pendingRestore, pendingRestore.messageID == messageID else { return }
        let token = pendingRestore.token
        guard scheduledToken != token else { return }
        scheduledToken = token
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.scheduledToken == token else { return }
            self.scheduledToken = nil
            self.restoreOnce(token: token)
        }
    }

    private func restoreOnce(token: UUID) {
        guard
            var pendingRestore,
            pendingRestore.token == token,
            let anchor = anchors[pendingRestore.messageID]?.view,
            let scrollView,
            anchor.window != nil,
            !scrollView.isTracking,
            !scrollView.isDragging,
            !scrollView.isDecelerating
        else {
            if self.pendingRestore?.token == token {
                cancelPreservation()
            }
            return
        }

        scrollView.layoutIfNeeded()
        let boundsInViewport = anchor.convert(anchor.bounds, to: nil)
        let currentCoordinate = pendingRestore.edge == .top
            ? boundsInViewport.minY
            : scrollView.contentOffset.y
        let delta = currentCoordinate - pendingRestore.viewportCoordinate
        guard abs(delta) > 0.5 else {
            pendingRestore.attempts += 1
            self.pendingRestore = pendingRestore
            if pendingRestore.attempts >= 3 {
                cancelPreservation()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                    guard self?.pendingRestore?.token == token else { return }
                    self?.scheduleRestore(messageID: pendingRestore.messageID)
                }
            }
            return
        }

        let minimumY = -scrollView.adjustedContentInset.top
        let maximumY = max(
            minimumY,
            scrollView.contentSize.height
                + scrollView.adjustedContentInset.bottom
                - scrollView.bounds.height
        )
        let proposedY = pendingRestore.edge == .top
            ? scrollView.contentOffset.y + delta
            : pendingRestore.viewportCoordinate
        let targetY = min(maximumY, max(minimumY, proposedY))
        cancelPreservation()
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: targetY),
            animated: false
        )
    }

    private func resolveScrollView(from anchor: UIView) {
        var ancestor = anchor.superview
        while let view = ancestor {
            if let scrollView = view as? UIScrollView {
                self.scrollView = scrollView
                return
            }
            ancestor = view.superview
        }
    }
}

private final class ChatMessageAnchorView: UIView {
    weak var controller: ChatScrollAnchorController?
    var messageID = ""

    override func layoutSubviews() {
        super.layoutSubviews()
        controller?.anchorDidLayout(messageID: messageID)
    }
}

private struct ChatMessageAnchorProbe: UIViewRepresentable {
    let messageID: String
    let controller: ChatScrollAnchorController

    func makeUIView(context: Context) -> ChatMessageAnchorView {
        let view = ChatMessageAnchorView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.controller = controller
        view.messageID = messageID
        controller.register(view, messageID: messageID)
        return view
    }

    func updateUIView(_ uiView: ChatMessageAnchorView, context: Context) {
        uiView.controller = controller
        uiView.messageID = messageID
        controller.register(uiView, messageID: messageID)
    }
}

private struct MessageUnitLayout: Layout {
    let includesThinking: Bool
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let bubble = subviews.last else { return .zero }
        let bubbleSize = bubble.sizeThatFits(
            ProposedViewSize(width: proposal.width, height: nil)
        )
        guard includesThinking, subviews.count > 1 else { return bubbleSize }

        let thinkingSize = subviews[0].sizeThatFits(
            ProposedViewSize(width: proposal.width, height: nil)
        )
        return CGSize(
            width: max(thinkingSize.width, bubbleSize.width),
            height: thinkingSize.height + spacing + bubbleSize.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let bubble = subviews.last else { return }
        var nextY = bounds.minY

        if includesThinking, subviews.count > 1 {
            let thinkingProposal = ProposedViewSize(width: bounds.width, height: nil)
            let thinkingSize = subviews[0].sizeThatFits(thinkingProposal)
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: nextY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: thinkingSize.height)
            )
            nextY += thinkingSize.height + spacing
        }

        let bubbleProposal = ProposedViewSize(width: bounds.width, height: nil)
        let bubbleSize = bubble.sizeThatFits(bubbleProposal)
        bubble.place(
            at: CGPoint(x: bounds.minX, y: nextY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bubbleSize.height)
        )
    }
}

private struct MessageRow: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let message: Message
    let isHighlighted: Bool
    let isThinkingExpanded: Bool
    let visibleSegmentCount: Int?
    let scrollAnchorController: ChatScrollAnchorController
    let onThinkingToggle: () -> Void
    @State private var copied = false

    var body: some View {
        HStack(spacing: 0) {
            if message.sender == .me { Spacer(minLength: theme.metric.messageSideReserve) }

            VStack(
                alignment: message.sender == .ke ? .leading : .trailing,
                spacing: theme.metric.gapXS
            ) {
                if hasBubbleContent {
                    MessageUnitLayout(
                        includesThinking: message.sender == .ke && hasThinkingContent,
                        spacing: theme.metric.thinkingBubbleGap
                    ) {
                        if message.sender == .ke, hasThinkingContent {
                            thoughtCard(
                                summary: message.thoughtSummary,
                                note: message.thoughtNote
                            )
                        }
                        bubbleStack
                    }
                } else if message.sender == .ke, hasThinkingContent {
                    thoughtCard(
                        summary: message.thoughtSummary,
                        note: message.thoughtNote
                    )
                }

                HStack(spacing: theme.metric.gapS) {
                    Text(message.time.formatted(date: .omitted, time: .shortened))

                    if let label = message.deliveryState.label {
                        Text(label)
                    }

                    if !message.text.isEmpty {
                        Button {
                            UIPasteboard.general.string = message.text
                            copied = true
                            Task {
                                try? await Task.sleep(nanoseconds: 1_200_000_000)
                                copied = false
                            }
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(theme.font.copyIcon)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(copied ? theme.effectiveAccent : theme.color.textSecondary)
                    }

                    if message.sender == .me && message.deliveryState == .sent {
                        HStack(spacing: -4) {
                            Image(systemName: "checkmark")
                            Image(systemName: "checkmark")
                        }
                        .font(theme.font.receiptIcon)
                        .foregroundStyle(theme.effectiveAccent)
                    }
                }
                .font(theme.font.caption)
                .foregroundStyle(theme.color.textSecondary)
                .padding(.horizontal, theme.metric.gapXS)
            }
            .frame(
                maxWidth: usesFullWidthKeRow ? .infinity : nil,
                alignment: message.sender == .ke ? .leading : .trailing
            )

            if message.sender == .ke && !usesFullWidthKeRow {
                Spacer(minLength: theme.metric.messageSideReserve)
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: message.sender == .ke ? .leading : .trailing
        )
        .background(
            ChatMessageAnchorProbe(
                messageID: message.id,
                controller: scrollAnchorController
            )
        )
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: CGFloat(theme.bubbleCornerRadius), style: .continuous)
                    .stroke(theme.effectiveAccent.opacity(0.72), lineWidth: 1.2)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    private var hasThinkingContent: Bool {
        !thinkingSections.isEmpty
    }

    private var hasBubbleContent: Bool {
        !message.text.isEmpty || !(message.attachments ?? []).isEmpty
    }

    private var thinkingSections: [String] {
        [message.thoughtSummary, message.thoughtNote]
            .compactMap { value in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
    }

    private func thoughtCard(summary: String?, note: String?) -> some View {
        VStack(alignment: .leading, spacing: theme.metric.gapS) {
            Button(action: onThinkingToggle) {
                HStack(spacing: theme.metric.gapS) {
                    Text("Thinking")
                    Image(systemName: isThinkingExpanded ? "chevron.up" : "chevron.down")
                        .font(theme.font.thinkingChevron)
                }
                .font(theme.font.thinking)
                .foregroundStyle(theme.color.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isThinkingExpanded ? "收起思考" : "展开思考")
            .accessibilityValue(isThinkingExpanded ? "已展开" : "已收起")

            if isThinkingExpanded {
                // 不挂 .transition：展开/收起本来就走无动画事务（toggleThinking 里
                // transaction.animation = nil），而 transition 会在流式期间列表高频
                // 重建时被误触发，opacity 反复重播就是她报的"点开频闪"。
                thinkingTextStack(summary: summary, note: note)
            }
        }
        .padding(.leading, theme.metric.thinkingLineGap + theme.metric.thinkingLineWidth)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(theme.color.accentSoft.opacity(theme.glass.thinkingLineOpacity))
                .frame(width: theme.metric.thinkingLineWidth)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.metric.thinkingHorizontalPadding)
    }

    private func thinkingTextStack(summary: String?, note: String?) -> some View {
        let sections = [summary, note]
            .compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        return VStack(alignment: .leading, spacing: theme.metric.gapS) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                thoughtText(section)
            }
        }
    }

    private func thoughtText(_ summary: String) -> some View {
        Text(summary)
            .font(theme.font.thinkingBody)
            .foregroundStyle(theme.color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var bubbleStack: some View {
        VStack(
            alignment: message.sender == .ke ? .leading : .trailing,
            spacing: theme.metric.splitBubbleGap
        ) {
            if visibleSegments.isEmpty, !(message.attachments ?? []).isEmpty {
                bubbleSurface(text: nil, includesAttachments: true)
            } else {
                ForEach(Array(visibleSegments.enumerated()), id: \.offset) { index, segment in
                    bubbleSurface(text: segment, includesAttachments: index == 0)
                }
            }
        }
        .frame(
            maxWidth: usesWideKeLayout ? .infinity : nil,
            alignment: message.sender == .ke ? .leading : .trailing
        )
    }

    @ViewBuilder
    private func bubbleSurface(text: String?, includesAttachments: Bool) -> some View {
        if isWideBubble(text) {
            bubbleContent(text: text, includesAttachments: includesAttachments)
                .frame(
                    maxWidth: .infinity,
                    alignment: message.sender == .ke ? .leading : .trailing
                )
                .background(bubbleBackground)
        } else {
            bubbleContent(text: text, includesAttachments: includesAttachments)
                .background(bubbleBackground)
                .frame(
                    maxWidth: theme.metric.bubbleMaxWidth,
                    alignment: message.sender == .ke ? .leading : .trailing
                )
        }
    }

    private func bubbleContent(text: String?, includesAttachments: Bool) -> some View {
        VStack(
            alignment: message.sender == .ke ? .leading : .trailing,
            spacing: theme.metric.gapS
        ) {
            if includesAttachments {
                ForEach(message.attachments ?? []) { attachment in
                    attachmentView(attachment)
                }
            }
            if let text, !text.isEmpty {
                Text(text)
                    .font(theme.font.bubble)
                    .foregroundStyle(message.sender == .ke
                                     ? theme.color.bubbleKeText
                                     : theme.color.bubbleMeText)
                    .lineSpacing(CGFloat(max(3, theme.chatFontSize * 0.28)))
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.horizontal, theme.metric.bubbleHorizontalPadding)
        .padding(.vertical, theme.metric.bubbleVerticalPadding)
    }

    private var bubbleBackground: some View {
        CrystalSurface(
            cornerRadius: CGFloat(theme.bubbleCornerRadius),
            strength: message.sender == .ke ? 0.92 : 1.08,
            usesChatControls: true
        )
    }

    private var visibleSegments: [String] {
        let segments = message.bubbleSegments
        guard message.sender == .ke,
              !message.isStreaming,
              !reduceMotion,
              let visibleSegmentCount else { return segments }
        return Array(segments.prefix(max(1, visibleSegmentCount)))
    }

    @ViewBuilder
    private func attachmentView(_ attachment: ChatAttachment) -> some View {
        if attachment.isImage,
           let url = URL(string: attachment.url, relativeTo: AppConfiguration.apiBaseURL) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ProgressView().controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .frame(height: theme.metric.messageImageHeight)
            .clipShape(RoundedRectangle(cornerRadius: theme.metric.radiusChip, style: .continuous))
        } else {
            HStack(spacing: theme.metric.gapS) {
                Image(systemName: "doc")
                Text(attachment.name.isEmpty ? "文件" : attachment.name)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .font(theme.font.caption)
            .foregroundStyle(theme.color.textSecondary)
        }
    }

    private var usesWideKeLayout: Bool {
        guard message.sender == .ke else { return false }
        return message.bubbleSegments.contains(where: isWideBubble)
    }

    private var usesFullWidthKeRow: Bool {
        message.sender == .ke && (hasThinkingContent || usesWideKeLayout)
    }

    private func isWideBubble(_ text: String?) -> Bool {
        guard message.sender == .ke, let text else { return false }
        let visibleLineCount = text.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
        return text.count >= theme.metric.wideMessageCharacterThreshold
            || visibleLineCount >= theme.metric.wideMessageLineThreshold
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    enum Phase: Equatable {
        case checking
        case needsLogin
        case ready
        case unavailable(String)
    }

    @Published var phase: Phase = .checking
    @Published var messages: [Message] = []
    @Published var statusText: String?
    @Published var loginError: String?
    @Published var isLoggingIn = false
    @Published var isSending = false
    @Published var isShowingCachedMessages = false
    @Published var isLoadingHistory = false
    @Published var historyLoadFailed = false
    @Published var streamRevision = 0
    @Published var modelOptions: [ChatModelOption] = []
    @Published var selectedModel: String?
    @Published var isLoadingModels = false
    @Published var isSelectingModel = false
    @Published var modelError: String?
    @Published var searchCorpus: [Message] = []
    @Published var isPreparingSearch = false
    @Published var searchError: String?
    @Published var isDeleting = false
    @Published var deleteError: String?
    @Published var pendingAttachments: [ChatAttachment] = []
    @Published var isUploading = false
    @Published var uploadError: String?
    @Published private var visibleSegmentCounts: [String: Int] = [:]

    private let api = APIClient.shared
    private let cache = ChatCache.shared
    private var sessionID: Int?
    private var didBootstrap = false
    private var activeJobID: String?
    private var recoveringJobID: String?
    private var activeStreamClientID: String?
    private var recoveryProbeID: UUID?
    private var segmentRevealTasks: [String: Task<Void, Never>] = [:]

#if DEBUG
    private enum UITestFixture: Equatable {
        case thinkingStatic
        case thinkingStreaming
        case segmentedReply
        case scrollControl
        case thinkingSegmentRace
    }

    private var uiTestFixture: UITestFixture?
#endif

    init() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-test-thinking-static") {
            uiTestFixture = .thinkingStatic
            phase = .ready
            messages = [
                Message(
                    id: "ui-test-user",
                    sender: .me,
                    text: "你刚刚在想什么？",
                    time: .now
                ),
                Message(
                    id: "ui-test-assistant",
                    sender: .ke,
                    text: "我先把你的话接稳，再慢慢说给你听。",
                    time: .now,
                    thoughtSummary: "先在心里把她这句话接住，再确认怎样回应才不会让她落空。",
                    thoughtSummaryRaw: "Hold her words first, then answer gently."
                )
            ]
        } else if arguments.contains("-ui-test-thinking-streaming") {
            uiTestFixture = .thinkingStreaming
            phase = .ready
            isSending = true
            messages = [
                Message(
                    id: "ui-test-streaming-user",
                    sender: .me,
                    text: "慢慢想，我在这里。",
                    time: .now
                ),
                Message(
                    id: "ui-test-streaming-assistant",
                    sender: .ke,
                    text: "",
                    time: .now,
                    thoughtSummary: "先接住她这句话。",
                    isStreaming: true,
                    deliveryState: .sending
                )
            ]
        } else if arguments.contains("-ui-test-segmented-reply") {
            uiTestFixture = .segmentedReply
            phase = .ready
            let message = Message(
                id: "ui-test-segmented-assistant",
                serverID: 9001,
                sender: .ke,
                text: "第一句先接住你。\n\n第二句慢一点出来。\n\n   \n第三句最后跟上。",
                time: .now
            )
            messages = [message]
            visibleSegmentCounts[message.bubbleRevealKey] = 1
        } else if arguments.contains("-ui-test-scroll-control")
                    || arguments.contains("-ui-test-thinking-segment-race") {
            uiTestFixture = arguments.contains("-ui-test-thinking-segment-race")
                ? .thinkingSegmentRace
                : .scrollControl
            phase = .ready
            var fixtureMessages: [Message] = []
            for index in 0..<7 {
                fixtureMessages.append(Message(
                    id: "ui-test-history-user-\(index)",
                    sender: .me,
                    text: "前面的消息 \(index + 1)",
                    time: .now.addingTimeInterval(Double(index - 14) * 60)
                ))
                fixtureMessages.append(Message(
                    id: "ui-test-history-ke-\(index)",
                    sender: .ke,
                    text: "前面的回复 \(index + 1)，用来把聊天列表撑过一屏。",
                    time: .now.addingTimeInterval(Double(index - 13) * 60)
                ))
            }
            let latest = Message(
                id: "ui-test-scroll-latest",
                serverID: 9101,
                sender: .ke,
                text: arguments.contains("-ui-test-thinking-segment-race")
                    ? "第一条气泡已经到了。\n\n第二条气泡随后出现。\n\n第三条气泡最后出现。"
                    : "这是最新一条回复。",
                time: .now,
                thoughtSummary: "展开后标题应钉在原位，下面的内容只向下生长，不允许自动滚底抢走位置。"
            )
            fixtureMessages.append(latest)
            messages = fixtureMessages
            if uiTestFixture == .thinkingSegmentRace {
                visibleSegmentCounts[latest.bubbleRevealKey] = 1
            }
        }
#endif
    }

    func bootstrap() async {
#if DEBUG
        if let uiTestFixture {
            if uiTestFixture == .thinkingStreaming {
                await runUITestThinkingStream()
            } else if uiTestFixture == .segmentedReply {
                stageSegments(for: messages[0], reduceMotion: false)
            }
            return
        }
#endif
        guard !didBootstrap else { return }
        didBootstrap = true
        await connect()
    }

#if DEBUG
    private func runUITestThinkingStream() async {
        let messageID = "ui-test-streaming-assistant"
        let chunks = [
            "先分清她真正担心的地方，",
            "再把回答收得温柔一点。",
            "最后确认每句话都只用中文。"
        ]

        for chunk in chunks {
            try? await Task.sleep(nanoseconds: 420_000_000)
            updateMessage(id: messageID) {
                $0.thoughtSummary = ($0.thoughtSummary ?? "") + chunk
            }
            streamRevision += 1
        }

        try? await Task.sleep(nanoseconds: 420_000_000)
        updateMessage(id: messageID) {
            $0.text = "想好了，我会一直用中文把心里的话说给你听。"
            $0.isStreaming = false
            $0.deliveryState = .sent
        }
        isSending = false
        streamRevision += 1
    }

    func didToggleThinkingForUITest(messageID: String) {
        guard uiTestFixture == .thinkingSegmentRace,
              messageID == "ui-test-scroll-latest",
              let message = messages.first(where: { $0.id == messageID }),
              segmentRevealTasks[message.bubbleRevealKey] == nil else { return }
        stageSegments(for: message, reduceMotion: false)
    }
#endif

    func retryBootstrap() async {
        phase = .checking
        await connect()
    }

    func login(passcode: String) async {
        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }

        do {
            try await api.login(passcode: passcode)
            let active = try await api.activeSession()
            sessionID = active.id
            selectedModel = active.model
            phase = .ready
            CompanionPermissionCoordinator.shared.sessionDidBecomeReady()
            await loadCache(sessionID: active.id)
            await refreshHistory(showFailure: true)
            await recoverActiveJobsIfNeeded()
        } catch APIError.unauthorized {
            loginError = "口令不对，再试一次。"
        } catch {
            loginError = error.localizedDescription
        }
    }

    func resumeFromForeground() async {
        guard phase == .ready else { return }
        // 原 SSE 仍是这条回复的唯一所有者时，不并行启动 job polling。
        guard activeStreamClientID == nil else { return }
        await recoverActiveJobsIfNeeded()
        guard activeStreamClientID == nil else { return }
        if recoveringJobID == nil {
            await refreshHistory(showFailure: false)
        }
    }

    func retryHistory() async {
        await refreshHistory(showFailure: true)
    }

    func send(_ text: String, reduceMotion: Bool = false) async {
        guard let sessionID, !isSending else { return }
        let attachments = pendingAttachments
        guard !text.isEmpty || !attachments.isEmpty else { return }

        isSending = true
        statusText = nil
        activeJobID = nil
        // Invalidate any foreground recovery probe that is currently awaiting the network.
        recoveryProbeID = nil
        pendingAttachments = []

        let clientID = "ios-\(UUID().uuidString.lowercased())"
        let userLocalID = "user-\(clientID)"
        let assistantLocalID = "assistant-\(clientID)"
        activeStreamClientID = clientID
        defer {
            if activeStreamClientID == clientID {
                activeStreamClientID = nil
            }
        }

        messages.append(
            Message(
                id: userLocalID,
                clientID: clientID,
                sender: .me,
                text: text,
                time: .now,
                attachments: attachments,
                deliveryState: .sending
            )
        )
        messages.append(
            Message(
                id: assistantLocalID,
                clientID: clientID,
                sender: .ke,
                text: "",
                time: .now,
                isStreaming: true,
                deliveryState: .sending
            )
        )

        await performSend(
            text: text,
            sessionID: sessionID,
            clientID: clientID,
            userLocalID: userLocalID,
            assistantLocalID: assistantLocalID,
            attachments: attachments,
            reduceMotion: reduceMotion,
            retryCount: 0
        )
    }

    func addAttachment(data: Data, fileName: String, mimeType: String) async {
        guard !isUploading, pendingAttachments.count < 9 else { return }
        guard data.count < 29 * 1024 * 1024 else {
            uploadError = "文件需要小于 29MB。"
            return
        }
        isUploading = true
        uploadError = nil
        defer { isUploading = false }
        do {
            let uploaded = try await api.uploadAttachment(
                data: data,
                fileName: fileName,
                mimeType: mimeType
            )
            if !pendingAttachments.contains(where: { $0.url == uploaded.url }) {
                pendingAttachments.append(uploaded)
            }
        } catch {
            uploadError = error.localizedDescription
        }
    }

    func addPhotoAttachment(data: Data, fileName: String, mimeType: String) async {
        let allowed = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp"]
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        if allowed.contains(ext) {
            await addAttachment(data: data, fileName: fileName, mimeType: mimeType)
            return
        }
        guard let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.88) else {
            uploadError = "这张照片的格式暂时不能发送。"
            return
        }
        await addAttachment(
            data: jpeg,
            fileName: "照片-\(UUID().uuidString.prefix(8)).jpg",
            mimeType: "image/jpeg"
        )
    }

    func addFile(url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else {
                uploadError = "这个项目不是可以发送的文件。"
                return
            }
            guard (values.fileSize ?? 0) < 29 * 1024 * 1024 else {
                uploadError = "文件需要小于 29MB。"
                return
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let type = UTType(filenameExtension: url.pathExtension)
            await addAttachment(
                data: data,
                fileName: url.lastPathComponent,
                mimeType: type?.preferredMIMEType ?? "application/octet-stream"
            )
        } catch {
            uploadError = "没有读取到这个文件。"
        }
    }

    func removePendingAttachment(_ attachment: ChatAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
        if pendingAttachments.isEmpty { uploadError = nil }
    }

    func loadModels(force: Bool = false) async {
        guard force || modelOptions.isEmpty else { return }
        isLoadingModels = true
        modelError = nil
        defer { isLoadingModels = false }
        do {
            let catalog = try await api.fetchModels()
            modelOptions = catalog.options.isEmpty
                ? catalog.models.map {
                    ChatModelOption(
                        id: $0,
                        provider: nil,
                        label: nil,
                        description: nil,
                        group: nil
                    )
                }
                : catalog.options
            if selectedModel == nil { selectedModel = catalog.default }
        } catch {
            modelError = error.localizedDescription
        }
    }

    func selectModel(_ model: String) async {
        guard let sessionID, !isSelectingModel else { return }
        isSelectingModel = true
        modelError = nil
        defer { isSelectingModel = false }
        do {
            let active = try await api.selectModel(sessionID: sessionID, model: model)
            selectedModel = active.model ?? model
        } catch {
            modelError = error.localizedDescription
        }
    }

    func prepareSearchCorpus(force: Bool = false) async {
        guard let sessionID else { return }
        guard force || searchCorpus.isEmpty else { return }
        isPreparingSearch = true
        searchError = nil
        defer { isPreparingSearch = false }

        do {
            var collected = messages.filter { $0.serverID != nil }
            var currentBeforeID = collected.compactMap(\.serverID).min()
            for _ in 0..<4 {
                guard let beforeID = currentBeforeID else { break }
                let page = try await api.fetchMessages(
                    sessionID: sessionID,
                    limit: 100,
                    beforeID: beforeID
                )
                guard !page.isEmpty else { break }
                collected = mergeMessages(collected, with: page)
                guard page.count >= 100 else { break }
                let next = page.compactMap(\.serverID).min()
                guard next != beforeID else { break }
                currentBeforeID = next
            }
            searchCorpus = collected.sorted { ($0.serverID ?? 0) < ($1.serverID ?? 0) }
        } catch {
            searchCorpus = messages
            searchError = "较早的记录暂时没拉下来；仍可搜索当前本地缓存。"
        }
    }

    func searchResults(for query: String) -> [Message] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return Array(searchCorpus
            .filter { $0.text.localizedCaseInsensitiveContains(needle) }
            .suffix(80)
            .reversed())
    }

    var deletionCandidates: [Message] {
        let source = searchCorpus.isEmpty ? messages : searchCorpus
        return source
            .filter { $0.serverID != nil }
            .sorted { ($0.serverID ?? 0) > ($1.serverID ?? 0) }
    }

    func revealSearchResult(_ message: Message) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        messages = mergeMessages(messages, with: searchCorpus)
    }

    func deleteMessages(ids: Set<Int>) async -> Set<Int> {
        guard !ids.isEmpty, !isDeleting else { return [] }
        isDeleting = true
        deleteError = nil
        defer { isDeleting = false }

        var deleted: Set<Int> = []
        for id in ids.sorted() {
            do {
                try await api.deleteMessage(id: id)
                deleted.insert(id)
            } catch {
                deleteError = "有些记录没有删成功，可以再试一次。"
                break
            }
        }
        guard !deleted.isEmpty else { return deleted }
        messages.removeAll { $0.serverID.map(deleted.contains) == true }
        searchCorpus.removeAll { $0.serverID.map(deleted.contains) == true }
        if let sessionID { await cache.save(messages, sessionID: sessionID) }
        return deleted
    }

    private func connect() async {
        if let snapshot = await cache.loadLatest() {
            sessionID = snapshot.sessionID
            messages = snapshot.messages
            isShowingCachedMessages = true
            phase = .ready
            statusText = "正在接回服务器…"
        }

        do {
            let active = try await api.activeSession()
            sessionID = active.id
            selectedModel = active.model
            CompanionPermissionCoordinator.shared.sessionDidBecomeReady()
            await loadCache(sessionID: active.id)
            phase = .ready
            await refreshHistory(showFailure: messages.isEmpty)
            await recoverActiveJobsIfNeeded()
        } catch APIError.unauthorized {
            phase = .needsLogin
            statusText = nil
        } catch {
            if messages.isEmpty {
                phase = .unavailable("暂时连不上服务器，也没有可显示的本地记录。")
            } else {
                phase = .ready
                statusText = "现在显示本地记录，网络恢复后会自动更新。"
                isShowingCachedMessages = true
            }
        }
    }

    private func loadCache(sessionID: Int) async {
        let cached = await cache.load(sessionID: sessionID)
        guard self.sessionID == sessionID, !cached.isEmpty else { return }
        // Cache I/O may finish after send() has created local bubbles. Always merge
        // so streaming, waiting and failed local bubbles remain addressable.
        messages = mergeRemoteHistory(cached)
        if !messages.isEmpty {
            isShowingCachedMessages = true
        }
    }

    private func refreshHistory(showFailure: Bool) async {
        guard let sessionID else { return }
        isLoadingHistory = messages.isEmpty
        historyLoadFailed = false
        defer { isLoadingHistory = false }
        do {
            let remote = try await api.fetchMessages(sessionID: sessionID)
            guard self.sessionID == sessionID else { return }
            if remote.isEmpty, messages.contains(where: { $0.serverID != nil }) {
                isShowingCachedMessages = true
                statusText = "服务器这次返回了空记录，先保留手机里的聊天。"
                return
            }
            let withThinking = preserveLocalThinking(in: remote)
            let merged = mergeRemoteHistory(withThinking)
            messages = merged
            searchCorpus = mergeMessages(searchCorpus, with: merged)
            isShowingCachedMessages = false
            statusText = nil
            await cache.save(merged, sessionID: sessionID)
            try? await api.markSeen(
                sessionID: sessionID,
                throughID: merged.last(where: { $0.sender == .ke })?.serverID
            )
        } catch APIError.unauthorized {
            phase = .needsLogin
        } catch {
            isShowingCachedMessages = !messages.isEmpty
            historyLoadFailed = messages.isEmpty
            if showFailure || !messages.isEmpty {
                statusText = messages.isEmpty
                    ? "聊天记录暂时没有拉下来。"
                    : "现在显示本地记录，网络恢复后会自动更新。"
            }
        }
    }

    private func performSend(
        text: String,
        sessionID: Int,
        clientID: String,
        userLocalID: String,
        assistantLocalID: String,
        attachments: [ChatAttachment],
        reduceMotion: Bool,
        retryCount: Int
    ) async {
        var didComplete = false
        var pendingText = ""
        var pendingThinking = ""
        var lastPublish = Date.distantPast

        func flushBufferedEvents() {
            guard !pendingText.isEmpty || !pendingThinking.isEmpty else { return }
            let textDelta = pendingText
            let thinkingDelta = pendingThinking
            pendingText = ""
            pendingThinking = ""
            updateMessage(id: assistantLocalID) {
                $0.text += textDelta
                if !thinkingDelta.isEmpty {
                    $0.thoughtSummary = ($0.thoughtSummary ?? "") + thinkingDelta
                }
            }
            streamRevision += 1
            lastPublish = .now
        }

        do {
            let stream = try await api.streamMessage(
                text: text,
                sessionID: sessionID,
                clientMessageID: clientID,
                model: selectedModel,
                attachments: attachments
            )

            for try await event in stream {
                switch event {
                case let .receipt(userMessageID, jobID, bedroom):
                    if let jobID {
                        activeJobID = jobID
                    }
                    updateMessage(id: userLocalID) {
                        $0.serverID = userMessageID ?? $0.serverID
                        $0.deliveryState = .sent
                    }
                    applyBedroom(bedroom)

                case let .text(delta):
                    pendingText += delta
                    if Date.now.timeIntervalSince(lastPublish) >= 0.05 {
                        flushBufferedEvents()
                    }

                case let .thinkingDelta(delta):
                    pendingThinking += delta
                    if Date.now.timeIntervalSince(lastPublish) >= 0.05 {
                        flushBufferedEvents()
                    }

                case let .thoughtNote(summary):
                    flushBufferedEvents()
                    updateMessage(id: assistantLocalID) { $0.thoughtNote = summary }
                    streamRevision += 1

                case let .completed(assistantMessageID, bedroom):
                    flushBufferedEvents()
                    didComplete = true
                    updateMessage(id: assistantLocalID) {
                        $0.serverID = assistantMessageID ?? $0.serverID
                        $0.isStreaming = false
                        $0.deliveryState = .sent
                    }
                    if let completed = messages.first(where: { $0.id == assistantLocalID }) {
                        stageSegments(for: completed, reduceMotion: reduceMotion)
                    }
                    applyBedroom(bedroom)

                case let .serverError(message):
                    throw APIError.serverMessage(message)
                }
            }

            guard didComplete else { throw APIError.streamClosed }
            activeJobID = nil
            statusText = nil
            await refreshHistory(showFailure: false)
            isSending = false
            CompanionPermissionCoordinator.shared.conversationDidComplete()

        } catch APIError.unauthorized {
            flushBufferedEvents()
            isSending = false
            markFailed(userLocalID: userLocalID, assistantLocalID: assistantLocalID)
            phase = .needsLogin

        } catch {
            flushBufferedEvents()
            if let activeJobID {
                updateMessage(id: assistantLocalID) {
                    $0.isStreaming = false
                    $0.deliveryState = .waiting
                }
                statusText = "连接断了一下，柯的话还在服务器写，写完会自动接回来。"
                await pollForCompletion(jobID: activeJobID)
            } else if retryCount == 0 {
                statusText = "连接断了一下，正在用同一条消息接回…"
                try? await Task.sleep(nanoseconds: 800_000_000)
                await performSend(
                    text: text,
                    sessionID: sessionID,
                    clientID: clientID,
                    userLocalID: userLocalID,
                    assistantLocalID: assistantLocalID,
                    attachments: attachments,
                    reduceMotion: reduceMotion,
                    retryCount: 1
                )
            } else {
                isSending = false
                markFailed(userLocalID: userLocalID, assistantLocalID: assistantLocalID)
                statusText = "这句没有发稳。内容留在这里，网络恢复后可以再发。"
                pendingAttachments = mergeAttachments(pendingAttachments, with: attachments)
            }
        }
    }

    private func recoverActiveJobsIfNeeded() async {
        guard let sessionID,
              recoveringJobID == nil,
              activeStreamClientID == nil,
              recoveryProbeID == nil else { return }
        let probeID = UUID()
        recoveryProbeID = probeID
        defer {
            if recoveryProbeID == probeID {
                recoveryProbeID = nil
            }
        }
        do {
            let jobs = try await api.activeJobs(sessionID: sessionID)
            // send() may have started while activeJobs was in flight. A stale probe
            // must never clear its state or start a second polling owner.
            guard recoveryProbeID == probeID,
                  activeStreamClientID == nil else { return }
            guard let job = jobs.first else {
                isSending = false
                return
            }
            isSending = true
            statusText = "柯还有一句话在写，写完会自动接回来。"
            await pollForCompletion(jobID: job.id)
        } catch APIError.unauthorized {
            phase = .needsLogin
        } catch {
            // 前台恢复失败不覆盖已经显示的聊天记录。
        }
    }

    private func pollForCompletion(jobID: String) async {
        guard let sessionID, recoveringJobID == nil else { return }
        recoveringJobID = jobID
        defer {
            recoveringJobID = nil
            activeJobID = nil
        }

        for _ in 0..<150 {
            if Task.isCancelled { break }
            do {
                let jobs = try await api.activeJobs(sessionID: sessionID)
                if !jobs.contains(where: { $0.id == jobID }) {
                    await refreshHistory(showFailure: true)
                    isSending = false
                    statusText = nil
                    return
                }
            } catch APIError.unauthorized {
                isSending = false
                phase = .needsLogin
                return
            } catch {
                // 短暂断网时继续等；最终以 VPS 历史记录为准。
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        isSending = false
        statusText = "回复仍留在服务器，下次回到 App 会继续接回。"
    }

    private func applyBedroom(_ bedroom: Bool?) {
        guard let bedroom else { return }
        Theme.shared.applyServerSignal(bedroom: bedroom)
    }

    func visibleSegmentCount(for message: Message) -> Int? {
        visibleSegmentCounts[message.bubbleRevealKey]
    }

    private func stageSegments(for message: Message, reduceMotion: Bool) {
        let key = message.bubbleRevealKey
        segmentRevealTasks[key]?.cancel()
        guard !reduceMotion, message.bubbleSegments.count > 1 else {
            visibleSegmentCounts.removeValue(forKey: key)
            return
        }

        let total = message.bubbleSegments.count
        visibleSegmentCounts[key] = 1
        segmentRevealTasks[key] = Task { [weak self] in
            guard let self else { return }
            for count in 2...total {
                try? await Task.sleep(
                    nanoseconds: UInt64(Theme.shared.motion.splitBubbleInterval * 1_000_000_000)
                )
                guard !Task.isCancelled else { return }
                visibleSegmentCounts[key] = count
                streamRevision += 1
            }
            visibleSegmentCounts.removeValue(forKey: key)
            segmentRevealTasks[key] = nil
        }
    }

    private func updateMessage(id: String, mutate: (inout Message) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        mutate(&messages[index])
    }

    private func preserveLocalThinking(in remote: [Message]) -> [Message] {
        let localByServerID = Dictionary(
            messages.compactMap { message -> (Int, Message)? in
                guard let serverID = message.serverID else { return nil }
                return (serverID, message)
            },
            uniquingKeysWith: { first, _ in first }
        )
        return remote.map { message in
            guard let serverID = message.serverID,
                  let local = localByServerID[serverID] else { return message }
            var preserved = message
            if nonBlank(preserved.thoughtSummary) == nil {
                preserved.thoughtSummary = nonBlank(local.thoughtSummary)
            }
            if nonBlank(preserved.thoughtNote) == nil {
                preserved.thoughtNote = nonBlank(local.thoughtNote)
            }
            if nonBlank(preserved.thoughtSummaryRaw) == nil {
                preserved.thoughtSummaryRaw = nonBlank(local.thoughtSummaryRaw)
            }
            return preserved
        }
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func mergeRemoteHistory(_ remote: [Message]) -> [Message] {
        let remoteServerIDs = Set(remote.compactMap(\.serverID))
        var merged = remote
        for local in messages {
            if let serverID = local.serverID, remoteServerIDs.contains(serverID) {
                continue
            }
            let belongsToActiveStream = local.clientID != nil
                && local.clientID == activeStreamClientID
            let needsPreserving = local.isStreaming
                || local.deliveryState != .sent
                || belongsToActiveStream
            if needsPreserving && !merged.contains(where: { $0.id == local.id }) {
                merged.append(local)
            }
        }
        return merged.sorted(by: messagePrecedes)
    }

    private func mergeMessages(_ current: [Message], with incoming: [Message]) -> [Message] {
        var values: [String: Message] = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for message in incoming { values[message.id] = message }
        return values.values.sorted(by: messagePrecedes)
    }

    private func messagePrecedes(_ lhs: Message, _ rhs: Message) -> Bool {
        if (lhs.serverTimeIsValid == false || rhs.serverTimeIsValid == false),
           let lhsServerID = lhs.serverID,
           let rhsServerID = rhs.serverID {
            return lhsServerID < rhsServerID
        }
        if lhs.time == rhs.time {
            return (lhs.serverID ?? 0) < (rhs.serverID ?? 0)
        }
        return lhs.time < rhs.time
    }

    private func mergeAttachments(
        _ current: [ChatAttachment],
        with incoming: [ChatAttachment]
    ) -> [ChatAttachment] {
        var values = current
        for attachment in incoming where !values.contains(where: { $0.url == attachment.url }) {
            values.append(attachment)
        }
        return Array(values.prefix(9))
    }

    private func markFailed(userLocalID: String, assistantLocalID: String) {
        updateMessage(id: userLocalID) { $0.deliveryState = .failed }
        if let index = messages.firstIndex(where: { $0.id == assistantLocalID }) {
            if messages[index].text.isEmpty
                && nonBlank(messages[index].thoughtSummary) == nil
                && nonBlank(messages[index].thoughtNote) == nil {
                messages.remove(at: index)
            } else {
                messages[index].isStreaming = false
                messages[index].deliveryState = .failed
            }
        }
    }
}

#Preview {
    ChatView().environmentObject(Theme.shared)
}
