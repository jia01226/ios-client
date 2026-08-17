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
                if attachmentsOpen { attachmentTray }
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
        .animation(.easeOut(duration: 0.18), value: attachmentsOpen)
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
                        Text("这里还没有聊天记录。\n想说什么，就从下面开始。")
                            .font(theme.font.body)
                            .foregroundStyle(theme.color.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 80)
                    }

                    ForEach(vm.messages) { message in
                        MessageRow(
                            message: message,
                            isHighlighted: highlightedMessageID == message.id
                        )
                            .id(message.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom")
                }
                .padding(.horizontal, theme.metric.pagePadding)
                .padding(.bottom, theme.metric.gapL)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture {
                inputFocused = false
                if attachmentsOpen { attachmentsOpen = false }
            }
            .onChange(of: vm.messages.count) { _, _ in
                scrollToBottom(proxy, animated: true)
            }
            .onChange(of: vm.streamRevision) { _, _ in
                scrollToBottom(proxy, animated: false)
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

    private var inputBar: some View {
        HStack(spacing: theme.metric.gapS) {
            Button {
                inputFocused = false
                attachmentsOpen.toggle()
            } label: {
                Image(systemName: attachmentsOpen ? "xmark" : "plus")
                    .font(theme.font.composerIcon)
                    .frame(width: theme.metric.touchTarget, height: theme.metric.touchTarget)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.color.textPrimary)

            TextField("和柯说点什么…", text: $draft, axis: .vertical)
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
            }
        }
        .padding(theme.metric.gapM)
        .background(CrystalSurface(cornerRadius: theme.metric.radiusAttachmentTray, strength: 1.08))
        .padding(.horizontal, theme.metric.pagePadding)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task { await recentPhotos.loadIfNeeded() }
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
        Task { await vm.send(text) }
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

private struct MessageRow: View {
    @EnvironmentObject private var theme: Theme
    let message: Message
    let isHighlighted: Bool
    @State private var thoughtChoice: Bool?
    @State private var copied = false

    var body: some View {
        HStack(spacing: 0) {
            if message.sender == .me { Spacer(minLength: theme.metric.messageSideReserve) }

            VStack(
                alignment: message.sender == .ke ? .leading : .trailing,
                spacing: theme.metric.gapXS
            ) {
                if message.sender == .ke,
                   message.isStreaming || hasThoughtSummary {
                    thoughtCard(message.thoughtSummary)
                }

                if !message.text.isEmpty || !(message.attachments ?? []).isEmpty {
                    bubble
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
                maxWidth: usesWideKeLayout ? .infinity : nil,
                alignment: message.sender == .ke ? .leading : .trailing
            )

            if message.sender == .ke && !usesWideKeLayout {
                Spacer(minLength: theme.metric.messageSideReserve)
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: message.sender == .ke ? .leading : .trailing
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

    private var hasThoughtSummary: Bool {
        !(message.thoughtSummary ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private func thoughtCard(_ summary: String?) -> some View {
        let expanded = thoughtChoice ?? false
        return HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(theme.color.accentSoft.opacity(theme.glass.thinkingLineOpacity))
                .frame(width: 1)

            VStack(alignment: .leading, spacing: theme.metric.gapS) {
            Button {
                withAnimation(.easeOut(duration: 0.22)) {
                    thoughtChoice = !expanded
                }
            } label: {
                HStack(spacing: theme.metric.gapS) {
                    Text("Thinking")
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(theme.font.thinkingChevron)
                }
                .font(theme.font.thinking)
                .foregroundStyle(theme.color.textSecondary)
            }
            .buttonStyle(.plain)

            if expanded {
                Group {
                    if let summary,
                       !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       message.isStreaming {
                        ScrollView {
                            thoughtText(summary)
                        }
                        .frame(maxHeight: 118)
                    } else if let summary,
                              !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        thoughtText(summary)
                    } else {
                        Text("正在整理…")
                            .font(theme.font.thinkingBody)
                            .foregroundStyle(theme.color.textSecondary)
                    }
                }
                .transition(.opacity)
            }
            }
        }
        .padding(.vertical, theme.metric.gapXS)
        .padding(.horizontal, 2)
    }

    private func thoughtText(_ summary: String) -> some View {
        Text(summary)
            .font(theme.font.thinkingBody)
            .foregroundStyle(theme.color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var bubble: some View {
        VStack(
            alignment: message.sender == .ke ? .leading : .trailing,
            spacing: theme.metric.gapS
        ) {
            ForEach(message.attachments ?? []) { attachment in
                attachmentView(attachment)
            }
            if !message.text.isEmpty {
                Text(message.text)
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
            .background(CrystalSurface(
                cornerRadius: CGFloat(theme.bubbleCornerRadius),
                strength: message.sender == .ke ? 0.92 : 1.08,
                usesChatControls: true
            ))
            .frame(
                maxWidth: usesWideKeLayout ? .infinity : theme.metric.bubbleMaxWidth,
                alignment: message.sender == .ke ? .leading : .trailing
            )
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
        let visibleLineCount = message.text.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
        return message.text.count >= theme.metric.wideMessageCharacterThreshold
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

    private let api = APIClient.shared
    private let cache = ChatCache.shared
    private var sessionID: Int?
    private var didBootstrap = false
    private var activeJobID: String?
    private var recoveringJobID: String?
    private var activeStreamClientID: String?
    private var recoveryProbeID: UUID?

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        await connect()
    }

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

    func send(_ text: String) async {
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
        do {
            let remote = try await api.fetchMessages(sessionID: sessionID)
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

                case let .thoughtSummary(summary):
                    flushBufferedEvents()
                    updateMessage(id: assistantLocalID) { $0.thoughtSummary = summary }
                    streamRevision += 1

                case let .completed(assistantMessageID, bedroom):
                    flushBufferedEvents()
                    didComplete = true
                    updateMessage(id: assistantLocalID) {
                        $0.serverID = assistantMessageID ?? $0.serverID
                        $0.isStreaming = false
                        $0.deliveryState = .sent
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

    private func updateMessage(id: String, mutate: (inout Message) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        mutate(&messages[index])
    }

    private func preserveLocalThinking(in remote: [Message]) -> [Message] {
        let localByServerID = Dictionary(
            uniqueKeysWithValues: messages.compactMap { message -> (Int, String)? in
                guard let serverID = message.serverID,
                      let summary = message.thoughtSummary,
                      !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return (serverID, summary)
            }
        )
        return remote.map { message in
            guard message.thoughtSummary == nil,
                  let serverID = message.serverID,
                  let summary = localByServerID[serverID] else { return message }
            var preserved = message
            preserved.thoughtSummary = summary
            return preserved
        }
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
        return merged.sorted {
            if $0.time == $1.time { return ($0.serverID ?? 0) < ($1.serverID ?? 0) }
            return $0.time < $1.time
        }
    }

    private func mergeMessages(_ current: [Message], with incoming: [Message]) -> [Message] {
        var values: [String: Message] = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for message in incoming { values[message.id] = message }
        return values.values.sorted {
            if $0.time == $1.time { return ($0.serverID ?? 0) < ($1.serverID ?? 0) }
            return $0.time < $1.time
        }
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
            if messages[index].text.isEmpty && messages[index].thoughtSummary == nil {
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
