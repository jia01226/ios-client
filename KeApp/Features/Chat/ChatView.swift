import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

private enum ChatSettingsPage: Equatable {
    case root
    case search
    case delete
    case models
    case palettes, fonts, appearance, dates, tools
}

struct ChatView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let line: ChatLine
    @Binding var selectedLine: ChatLine
    @ObservedObject private var chatNotifications = ChatNotificationCoordinator.shared
    @StateObject private var vm: ChatViewModel
    @StateObject private var recentPhotos = RecentPhotosStore()
    @StateObject private var wallpaperStore = ChatWallpaperStore.shared
    @State private var draft = ""
    /// 137：上次没发的草稿只在打开时放回一次
    @State private var didRestoreDraft = false
    @State private var showingCallPlaceholder = false
    @State private var tarotOpen = false
    @State private var showingMemoryUsage = false
    @State private var showingUsageDashboard = false
    @State private var quoteToSave: Message?
    @ObservedObject private var quotesStore: AppQuotesStore
    @Binding var quoteOpenRequest: QuoteOpenRequest?
    @Binding var sendRequests: [ChatSendRequest]
    @State private var quoteToRemove: AppQuote?
    @State private var quoteNavigationError: String?
    @State private var messageToRecall: Message?
    @State private var recallConfirmation = false
    @State private var recallError: String?
    @State private var historyDate = Date()
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
    /// 136：点开的图（一整组，能左右翻）；格子里点图交到 ChatImageRouter
    @ObservedObject private var imageRouter = ChatImageRouter.shared
    @State private var expandedModelGroups: Set<String> = []
    @State private var showsScrollToLatest = false
    @State private var scrollToLatestRequest = 0
    // 112：月隐设置抽屉、换窗挑选、钉住的轮
    @StateObject private var keWindow: KeWindowStore
    @State private var keDrawerOpen = false
    /// 127：拉抽屉时的距离放在单独的对象里，只有抽屉外框看着它（ChatView 不订阅，拉的时候整页不重画）
    @State private var keDrawerPull = KeDrawerPullState()
    /// 127：时间线条目缓存。ChatView 每重画一次都会把整段记录重新切一遍（日期、气泡分段），
    /// 记录很长时一次要好几毫秒；输入没变就直接用上一次的
    @State private var timelineItems = ChatTimelineItemsCache()
    @State private var keDrawerPage: KeSettingsTab = .garden
    @State private var keWindowPickerOpen = false
    /// 120：「+」里的「锁着的日记」单子
    @State private var lockedDiariesOpen = false
    /// 120：点了「爸爸开锁了」那张卡，直接翻开的那一篇
    @State private var openedDiary: DiaryOpenRequest?
    /// 128：night = 「夜里日记」卡点进来的，翻开日记 › 夜里的那一篇
    private struct DiaryOpenRequest: Identifiable {
        let entryID: Int
        var night = false
        var id: String { "\(night ? "night" : "diary")-\(entryID)" }
    }
    /// 128：「夜里日记」卡和日记页「夜里」那一栏共用的一份（聊天页自己不看它变，卡片自己看）
    private let nightStore: NightStore
    /// 121：输入框的动静——只报字数和删光/卡住/切走，不带字
    @StateObject private var presence: ComposerPresenceReporter
    /// 126：顶栏、输入栏、底栏浮在聊天记录上；记录一直铺到屏幕底，靠上下留白让第一条、最后一条露出来
    @Environment(\.floatingDockInset) private var dockInset
    /// 聊天这块（安全区以内）顶边、顶上浮栏下沿、输入胶囊上沿，都是全局坐标
    @State private var contentTopEdge: CGFloat = 0
    @State private var chromeTopEdge: CGFloat = 0
    @State private var composerTopEdge: CGFloat = 0

    init(line: ChatLine, selectedLine: Binding<ChatLine>, quoteOpenRequest: Binding<QuoteOpenRequest?> = .constant(nil), sendRequests: Binding<[ChatSendRequest]> = .constant([])) {
        self.line = line
        _selectedLine = selectedLine
        _vm = StateObject(wrappedValue: ChatViewModel(line: line))
        // 115：设置抽屉、换窗、钉住要打这条线自己的服务器（/ke-test1/…），不能用默认那个
        _keWindow = StateObject(wrappedValue: KeWindowStore(api: APIClient(baseURL: line.apiBaseURL)))
        _presence = StateObject(wrappedValue: ComposerPresenceReporter.live(api: APIClient(baseURL: line.apiBaseURL)))
        quotesStore = .shared(line: line)
        nightStore = NightStore.shared(line)
        _quoteOpenRequest = quoteOpenRequest
        _sendRequests = sendRequests
    }

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
        .background {
            if case .ready = vm.phase { ChatWallpaperBackground(store: wallpaperStore) }
        }
#if DEBUG
        .overlay(alignment: .topTrailing) { ChatRecoveryUITestTimingProbe() }
#endif
        .animation(.easeInOut(duration: 0.6), value: theme.isBedroom)
        .task(id: externalSendTaskID) {
            guard let request = sendRequests.first(where: { $0.line == line }) else { return }
            await vm.prepareExternalSend()
            guard !Task.isCancelled, vm.canAcceptExternalMessage else { return }
            if await vm.sendExternalMessage(id: request.id, text: request.text, shownAttachments: request.attachments, reduceMotion: reduceMotion) {
                sendRequests.removeAll { $0.id == request.id }
            }
        }
        .sheet(isPresented: $showingMemoryUsage) {
            NavigationStack { MemoryUsageView(line: line).environmentObject(theme) }
        }
        .sheet(isPresented: $showingUsageDashboard) {
            NavigationStack { UsageDashboardView(line: line).environmentObject(theme) }
        }
        .sheet(item: $quoteToSave) { message in
            AppQuoteSaveView(line: line, message: message)
                .environmentObject(theme)
        }
        .alert("从语录拿掉？", isPresented: Binding(get: { quoteToRemove != nil }, set: { if !$0 { quoteToRemove = nil } })) {
            Button("取消", role: .cancel) { quoteToRemove = nil }
            Button("拿掉", role: .destructive) {
                if let quote = quoteToRemove { Task { await quotesStore.remove(quote) } }
                quoteToRemove = nil
            }
        } message: { Text("不会删除聊天中的原话。") }
        .alert("还没找到原话", isPresented: Binding(get: { quoteNavigationError != nil }, set: { if !$0 { quoteNavigationError = nil } })) {
            Button("好") { quoteNavigationError = nil }
        } message: { Text(quoteNavigationError ?? "") }
        .task(id: quoteOpenRequest?.id) {
            guard let request = quoteOpenRequest else { return }
            do {
                let message = try await vm.revealQuotedMessage(serverID: request.messageID)
                highlightedMessageID = nil
                await Task.yield()
                highlightedMessageID = message.id
            } catch is CancellationError { return }
            catch { quoteNavigationError = "这条原话可能已删除，或不在当前聊天窗口。语录中的收藏仍然保留。" }
            if quoteOpenRequest?.id == request.id { quoteOpenRequest = nil }
        }
        .task {
            restoreSavedDraft()
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-test-wallpaper"), wallpaperStore.image == nil {
                let image = UIGraphicsImageRenderer(size: CGSize(width: 360, height: 780)).image { context in
                    UIColor.systemIndigo.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 360, height: 780))
                    UIColor.systemYellow.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 360, height: 260))
                    UIColor.systemTeal.setFill()
                    context.fill(CGRect(x: 0, y: 520, width: 360, height: 260))
                }
                try? wallpaperStore.save(source: image, cropped: image)
                theme.lockscreenGlass = true
            }
#endif
            await vm.bootstrap()
            await quotesStore.load()
            if chatNotifications.openRequest != nil {
                await vm.resumeFromForeground(forceReconnect: true)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .inactive: vm.becameInactive()
            case .background:
                vm.enteredBackgroundScene()
                presence.didEnterBackground()
            case .active:
                presence.didBecomeActive()
                Task { await vm.resumeFromForeground() }
            @unknown default: break
            }
        }
        .onChange(of: chatNotifications.openRequest) { _, _ in
            Task { await vm.resumeFromForeground(forceReconnect: true) }
        }
        // 137：开着 App 时来了推送：不打断正在回的那句，只是空着时拉一次记录
        .onChange(of: chatNotifications.incoming) { _, _ in
            Task { await vm.resumeFromForeground() }
        }
    }

    private var externalSendTaskID: String {
        let request = sendRequests.first { $0.line == line }
        return "\(request?.id.uuidString ?? "none")-\(vm.canAcceptExternalMessage)"
    }

    private var chatContent: some View {
        GeometryReader { _ in
            ZStack(alignment: .trailing) {
                // 126：记录铺满整屏（上到状态栏、下到屏幕底），浮栏盖在上面；
                // 键盘起来时记录只到键盘上沿（和以前一样，由时间线自己保持在最新）
                messageList

                floatingChrome

                if settingsOpen {
                    settingsDrawer
                        .transition(.move(edge: .trailing))
                }

                KeDrawerOverlay(isOpen: $keDrawerOpen, pullState: keDrawerPull, contentKey: [AnyHashable(keDrawerOpen), AnyHashable(keDrawerPage)]) {
                    KeSettingsDrawer(
                        isOpen: keDrawerOpen,
                        vm: vm,
                        store: keWindow,
                        page: $keDrawerPage,
                        onClose: closeKeDrawer,
                        onOpenTool: openDrawerTool,
                        onStartPick: {
                            keDrawerOpen = false
                            keWindowPickerOpen = true
                        }
                    )
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
        .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minY }) { contentTopEdge = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: settingsOpen)
        .onChange(of: settingsOpen || keDrawerOpen) { _, value in
            NotificationCenter.default.post(name: .chatSettingsVisibility, object: value)
        }
        .task { await keWindow.loadWindow() }
        .onReceive(NotificationCenter.default.publisher(for: .openKeSettings)) { _ in openKeDrawer() }
        .alert("没钉上", isPresented: Binding(
            get: { keWindow.pinError != nil && !keDrawerOpen },
            set: { if !$0 { keWindow.clearPinError() } }
        )) {
            Button("知道了", role: .cancel) { keWindow.clearPinError() }
        } message: { Text(keWindow.pinError ?? "") }
        .onDisappear { NotificationCenter.default.post(name: .chatSettingsVisibility, object: false) }
        .alert("撤回这条消息？", isPresented: $recallConfirmation) {
            Button("撤回消息", role: .destructive) {
                guard let message = messageToRecall, message.canRecall, let id = message.serverID else { return }
                messageToRecall = nil
                Task {
                    let deleted = await vm.deleteMessages(ids: [id])
                    if !deleted.contains(id) { recallError = "撤回没有成功，请稍后再试。" }
                }
            }
            Button("取消", role: .cancel) { messageToRecall = nil }
        } message: {
            Text("将从聊天记录中删除这条消息。已经开始生成的回复可能继续。")
        }
        .alert("未能撤回", isPresented: Binding(get: { recallError != nil }, set: { if !$0 { recallError = nil } })) {
            Button("知道了", role: .cancel) { recallError = nil }
        } message: { Text(recallError ?? "") }
        .sheet(isPresented: $showingCallPlaceholder) {
            KeCallPlaceholderCard()
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
        }
        .sheet(isPresented: $lockedDiariesOpen) {
            LockedDiarySheet(line: line) { entry in
                lockedDiariesOpen = false
                // 120：和日记里「去找柯要」走同一条路：根视图收到后排进待发，聊天接上就替她发出去
                NotificationCenter.default.post(name: .tarotReadingRequest, object: KeDiaryListView.askMessage(for: entry))
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
        }
        .fullScreenCover(isPresented: $keWindowPickerOpen) {
            KeWindowPickerView(
                store: keWindow,
                onBack: returnFromWindowPicker,
                onFinished: {
                    keWindowPickerOpen = false
                    Task { await keWindow.loadWindow() }
                }
            )
            .swipeBackToClose(returnFromWindowPicker)
        }
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
        .fullScreenCover(isPresented: $tarotOpen) {
            TarotView(line: line).environmentObject(theme)
        }
        .fullScreenCover(item: $imageRouter.gallery) { gallery in
            AttachmentImageViewer(gallery: gallery) {
                imageRouter.gallery = nil
            }
        }
        // 120：从聊天直接翻开柯刚开锁的那一篇；「目录」回日记目录，左上返回（或从左边缘右划）回聊天
        .fullScreenCover(item: $openedDiary) { request in
            KeDiaryListView(
                line: line,
                onClose: { openedDiary = nil },
                openingID: request.night ? nil : request.entryID,
                openingNightID: request.night ? request.entryID : nil
            )
                .environmentObject(theme)
                .swipeBackToClose { openedDiary = nil }
                .preferredColorScheme(theme.skin == .night ? .dark : .light)
        }
        // 日记里点「去找柯要」也是回聊天替她说一句：盖着的日记先收起来
        .onReceive(NotificationCenter.default.publisher(for: .tarotReadingRequest)) { _ in openedDiary = nil }
    }

    // MARK: 126 浮栏

    /// 顶上：标题胶囊 + 提示条；底下：附件面板、待发附件、输入胶囊。中间空着，点和划都落到记录上。
    private var floatingChrome: some View {
        VStack(spacing: 0) {
            VStack(spacing: theme.metric.gapS) {
                header
                if let error = quotesStore.error {
                    HStack {
                        Text(error).font(.caption).foregroundStyle(theme.chatTextSecondary)
                        Button("重试") { Task { await quotesStore.load() } }
                            .font(.caption).foregroundStyle(theme.chatAccent)
                    }
                    .padding(.horizontal, theme.metric.gapM)
                    .padding(.vertical, theme.metric.gapXS)
                    .background { chromeSurface(radius: theme.metric.radiusChip) }
                    .padding(.horizontal, theme.metric.pagePadding)
                }
                if let status = vm.statusText {
                    StatusBanner(text: status)
                        .padding(.horizontal, theme.metric.pagePadding)
                }
                if let failure = vm.replyFailure {
                    ReplyFailureBanner(
                        failure: failure,
                        retry: {
                            Task {
                                await vm.retryFailedReply(reduceMotion: reduceMotion)
                            }
                        },
                        dismiss: vm.dismissReplyFailure
                    )
                    .padding(.horizontal, theme.metric.pagePadding)
                }
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).maxY }) { chromeTopEdge = $0 }

            Spacer(minLength: 0)

            if showsScrollToLatest && !attachmentsOpen {
                scrollToLatestButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.bottom, theme.metric.gapS)
            }
            if attachmentsOpen {
                attachmentTray
                    .padding(.bottom, theme.metric.gapS)
            }
            inputBar
                .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minY }) { composerTopEdge = $0 }
        }
        // 底栏在的时候站在底栏上面；键盘起来底栏收起，就贴着键盘上沿
        .padding(.bottom, dockInset > 0 ? dockInset : theme.metric.chromeGap)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(
                    response: theme.motion.scrollControlResponse,
                    dampingFraction: theme.motion.scrollControlDampingFraction
                ),
            value: showsScrollToLatest && !attachmentsOpen
        )
    }

    /// 空聊天页（还没有记录、正在接回）的字从顶栏下面开始
    private var emptyTimelineTop: CGFloat {
        max(0, chromeTopEdge - contentTopEdge) + theme.metric.chromeGap
    }

    /// 浮栏的玻璃：只画在圆角里，外面不铺底板、不扩散白雾。
    /// 127：浮栏就盖在滚动的记录上，不再用 iOS 26 的液态玻璃（每帧都要重新折射底下滑过的字）。
    /// 白天走 KeGlass（系统 ultraThinMaterial + 纸色，透度在素笺里调）；照片壁纸、夜里、卧室也是一层系统模糊，
    /// 不叠影子。系统开了「降低透明度」，材质自己会变实心，KeGlass 换成实心纸。
    @ViewBuilder
    private func chromeSurface(radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if theme.lockscreenGlass {
            shape.fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        } else if theme.skin == .night || theme.isBedroom {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(theme.color.glassTint.opacity(0.12))
                shape.strokeBorder(theme.color.glassEdge.opacity(0.5), lineWidth: 0.6)
            }
        } else {
            KeGlass(shape: shape, minPaper: 0.2)
        }
    }

    private var scrollToLatestButton: some View {
        Button {
            scrollToLatestRequest &+= 1
        } label: {
            Image(systemName: "arrow.down")
                .font(theme.font.scrollToLatestIcon)
                .foregroundStyle(theme.color.textPrimary)
                .frame(
                    width: theme.metric.touchTarget,
                    height: theme.metric.touchTarget
                )
                .background(
                    CrystalSurface(
                        cornerRadius: theme.metric.touchTarget / 2,
                        strength: 1.08,
                        usesChatControls: true
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("回到最新消息")
        .accessibilityIdentifier("scroll-to-latest")
        .padding(.trailing, theme.metric.pagePadding)
        .transition(
            reduceMotion
                ? .opacity
                : .scale(scale: 0.88, anchor: .bottomTrailing)
                    .combined(with: .opacity)
        )
        .zIndex(2)
    }

    private func headerTitle(showsSwitcher: Bool) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Text("柯")
                    .font(theme.font.chatHeader)
                if showsSwitcher {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
            }
            .foregroundStyle(theme.chatTextPrimary)

            if vm.isSending {
                WaitingShimmer(color: theme.chatTextPrimary)
                    .transition(.opacity)
            } else {
                let status = vm.isShowingCachedMessages ? "离线记录" : "在线"
                Text(showsSwitcher ? "\(line.title) · \(status)" : status)
                    .font(theme.font.chatStatus)
                    .foregroundStyle(theme.chatTextSecondary)
                    .transition(.opacity)
            }
        }
    }

    @State private var sendBounce = 0

    private var header: some View {
        ZStack {
            // 佳佳 2026-10-06：「只留一个就可以了……就不需要叫什么」。只剩一个窗口时
            // 顶上只写「柯」，不再给切换菜单，也不显示窗口名。
            Group {
                if ChatLine.allCases.count > 1 {
                    Menu {
                        ForEach(ChatLine.allCases) { option in
                            Button {
                                selectedLine = option
                            } label: {
                                Label(
                                    option.title,
                                    systemImage: selectedLine == option ? "checkmark.circle.fill" : "circle"
                                )
                            }
                        }
                    } label: {
                        headerTitle(showsSwitcher: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("切换柯的聊天窗口，当前\(line.title)")
                    .accessibilityIdentifier("chat-line-switcher-\(line.rawValue)")
                } else {
                    headerTitle(showsSwitcher: false)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("chat-header-\(line.rawValue)")
                }
            }
            // 112：设置都收进往左划出来的抽屉；读屏时在标题上也能打开。
            .accessibilityAction(named: "打开设置") { openKeDrawer() }

            // 112：顶上只留标题和电话。原来「…」里的功能都在抽屉的话笺页「更多」里。
            // 121 她：电话放左边、竖着的三个点放右边——抽屉本来就从右边出来，点的和划的在同一边。
            // 126：电话、三个点不再各垫一个玻璃圆，整条顶栏就是一块圆角玻璃
            HStack {
                Button { showingCallPlaceholder = true } label: {
                    Image(systemName: "phone").font(.title3)
                        .frame(width: theme.metric.touchTarget, height: theme.metric.touchTarget)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("语音通话")
                Spacer()
                // 116 竖着 3 个点（原来在左上）。点一下打开设置；从右边缘往左划也照样能开
                Button(action: openKeDrawer) {
                    Image(systemName: "ellipsis").font(.title3).rotationEffect(.degrees(90))
                        .frame(width: theme.metric.touchTarget, height: theme.metric.touchTarget)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("打开设置").accessibilityIdentifier("ke-drawer-open")
            }
        }
        .padding(.horizontal, theme.metric.gapS)
        .frame(minHeight: theme.metric.chromeHeaderHeight)
        .foregroundStyle(theme.chatTextPrimary)
        .modifier(ChatLegibility())
        // Toolbar glyphs stay inside their touch targets; message text remains uncapped.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background { chromeSurface(radius: theme.metric.chromeHeaderRadius) }
        .contentShape(RoundedRectangle(cornerRadius: theme.metric.chromeHeaderRadius, style: .continuous))
        .simultaneousGesture(drawerSwipe)
        .padding(.horizontal, theme.metric.chromeHeaderInset)
        .padding(.top, theme.metric.chromeHeaderTop)
    }

    // MARK: 112 月隐设置抽屉

    /// 标题栏、空聊天页上的左划；聊天记录上的左划由 UIKit 那边转过来，走同一个入口。
    private var drawerSwipe: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .global)
            .onChanged { value in
                let dx = value.translation.width, dy = value.translation.height
                guard Self.fromRightEdge(value.startLocation.x), abs(dx) > abs(dy) * 1.3 else { return }
                handleDrawerPan(.changed(dx))
            }
            .onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                guard Self.fromRightEdge(value.startLocation.x), abs(dx) > abs(dy) * 1.3 else {
                    handleDrawerPan(.cancelled)
                    return
                }
                let fling = value.predictedEndTranslation.width - dx
                handleDrawerPan(.ended(dx, velocity: fling * 4))
            }
    }

    static func fromRightEdge(_ x: CGFloat) -> Bool {
        x > UIScreen.main.bounds.width - KeDrawerEdge.width
    }

    private func handleDrawerPan(_ pan: ChatDrawerPan) {
        guard !keDrawerOpen, !settingsOpen, !keWindowPickerOpen else {
            if keDrawerPull.pull != 0 { keDrawerPull.pull = 0 }
            return
        }
        switch pan {
        case let .changed(dx):
            let next = max(0, -dx)
            if keDrawerPull.pull != next { keDrawerPull.pull = next }
        case let .ended(dx, velocity):
            let shouldOpen = dx < -80 || (dx < -24 && velocity < -500)
            withAnimation(KeDrawerMotion.animation(reduceMotion: reduceMotion)) {
                keDrawerPull.pull = 0
                if shouldOpen { showKeDrawer(page: .garden) }
            }
        case .cancelled:
            withAnimation(KeDrawerMotion.animation(reduceMotion: reduceMotion)) { keDrawerPull.pull = 0 }
        }
    }

    private func openKeDrawer() {
        guard !settingsOpen else { return }
        withAnimation(KeDrawerMotion.animation(reduceMotion: reduceMotion)) {
            showKeDrawer(page: .garden)
        }
    }

    private func showKeDrawer(page: KeSettingsTab) {
        keDrawerPage = page
        keDrawerOpen = true
        attachmentsOpen = false
        inputFocused = false
    }

    private func closeKeDrawer() {
        withAnimation(KeDrawerMotion.animation(reduceMotion: reduceMotion)) {
            keDrawerOpen = false
        }
    }

    /// 挑选页点「返回」：回到抽屉的换窗页。
    private func returnFromWindowPicker() {
        keWindowPickerOpen = false
        showKeDrawer(page: .window)
    }

    /// 话笺「更多」：打开原来的功能区页面，功能一个不少。
    private func openDrawerTool(_ tool: KeDrawerTool) {
        keDrawerOpen = false
        attachmentsOpen = false
        inputFocused = false
        switch tool {
        case .search:
            settingsPage = .search
            Task { await vm.prepareSearchCorpus() }
        case .dates:
            settingsPage = .dates
            Task { await vm.prepareSearchCorpus() }
        case .fonts:
            settingsPage = .fonts
        case .appearance:
            settingsPage = .appearance
        case .usage:
            showingUsageDashboard = true
            return
        case .all:
            settingsPage = .root
        }
        settingsOpen = true
    }

    private func togglePin(_ message: Message) {
        guard let id = message.serverID else { return }
        let pinned = keWindow.isPinned(messageID: id)
        Task { await keWindow.setPin(messageID: id, pinned: !pinned) }
    }

    private var messageList: some View {
        Group {
            if vm.messages.isEmpty {
                emptyTimeline
                    .contentShape(Rectangle())
                    .simultaneousGesture(drawerSwipe)
            } else {
                ChatCollectionTimeline(
                    items: timelineItems.items(
                        messages: vm.messages,
                        highlightedMessageID: highlightedMessageID,
                        quotedIDs: quotesStore.quotes.map(\.message_id),
                        pinnedIDs: keWindow.pinnedMessageIDs,
                        // 121：减弱动态效果时柯的几个气泡一起出来，不一个个冒
                        revealCounts: reduceMotion ? nil : vm.segmentRevealCounts,
                        visibleSegmentCount: { reduceMotion ? nil : vm.visibleSegmentCount(for: $0) }
                    ),
                    streamRevision: vm.streamRevision,
                    suppressAutoScrollUntil: presentedThinkingMessageID == nil
                        ? .distantPast
                        : .distantFuture,
                    inputFocused: inputFocused,
                    highlightedMessageID: highlightedMessageID,
                    scrollToLatestRequest: scrollToLatestRequest,
                    onThinkingOpen: { messageID in
                        inputFocused = false
                        attachmentsOpen = false
                        presentedThinkingMessageID = messageID
#if DEBUG
                        vm.didOpenThinkingForUITest(messageID: messageID)
#endif
                    },
                    onAttachmentTap: { attachment in
                        // 120：日记卡的「附件」是那一篇日记，不是图片
                        if let id = attachment.diaryID {
                            inputFocused = false
                            attachmentsOpen = false
                            openedDiary = DiaryOpenRequest(entryID: id)
                        } else if let id = attachment.nightID {
                            inputFocused = false
                            attachmentsOpen = false
                            openedDiary = DiaryOpenRequest(entryID: id, night: true)
                        } else {
                            imageRouter.open([attachment], at: 0)
                        }
                    },
                    onRecall: { message in
                        inputFocused = false
                        messageToRecall = message
                        recallConfirmation = true
                    },
                    onSaveQuote: { message in
                        inputFocused = false
                        if let quote = quotesStore.quote(messageID: message.serverID) { quoteToRemove = quote }
                        else { quoteToSave = message }
                    },
                    onTogglePin: { message in
                        inputFocused = false
                        togglePin(message)
                    },
                    onDrawerPan: { pan in handleDrawerPan(pan) },
                    onBackgroundTap: {
                        inputFocused = false
                        if attachmentsOpen { attachmentsOpen = false }
                    },
                    onScrollToLatestVisibilityChanged: { shouldShow in
                        guard showsScrollToLatest != shouldShow else { return }
                        showsScrollToLatest = shouldShow
                    },
                    chromeTopEdge: chromeTopEdge + theme.metric.chromeGap,
                    chromeBottomEdge: composerTopEdge,
                    nightStore: nightStore
                )
                .equatable()
                // 126：时间线铺满整屏（上到状态栏、下到屏幕底），浮栏盖在上面；
                // 上下留白由时间线按自己在窗口里的位置和这两条边算（键盘起来时它只到键盘上沿，和以前一样）
                .ignoresSafeArea(.container, edges: [.top, .bottom])
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
                    .foregroundStyle(theme.chatTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, emptyTimelineTop + theme.metric.gapXL)
            .frame(maxHeight: .infinity, alignment: .top)
        } else if vm.historyLoadFailed {
            VStack(spacing: theme.metric.gapM) {
                Text("聊天记录这次没有接上。")
                    .font(theme.font.body)
                    .foregroundStyle(theme.chatTextSecondary)
                Button("重新加载聊天记录") {
                    Task { await vm.retryHistory() }
                }
                .buttonStyle(.bordered)
                .tint(theme.effectiveAccent)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, emptyTimelineTop + theme.metric.gapXL)
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            Text("这里还没有聊天记录。\n想说什么，就从下面开始。")
                .font(theme.font.body)
                .foregroundStyle(theme.chatTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, emptyTimelineTop + theme.metric.gapXL)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// 126：待发的附件收进输入胶囊里（在打字那一行上面），整块是一枚圆角玻璃
    private var inputBar: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapXS) {
            if vm.isUploading || !vm.pendingAttachments.isEmpty || vm.uploadError != nil {
                pendingAttachmentBar
                    .padding(.top, theme.metric.gapXS)
            }
            composerRow
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background { chromeSurface(radius: theme.metric.chromeComposerRadius) }
        .padding(.horizontal, theme.metric.chromeComposerInset)
    }

    private var composerRow: some View {
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
            .foregroundStyle(theme.chatTextPrimary)
                .modifier(ChatLegibility())
            .accessibilityLabel(attachmentsOpen ? "关闭附件" : "打开附件")

            TextField("和柯说点什么…", text: $draft,
                      prompt: Text("和柯说点什么…").foregroundColor(theme.chatTextSecondary), axis: .vertical)
                .accessibilityIdentifier("chat-composer")
                .lineLimit(1...5)
                .font(theme.font.body)
                .foregroundStyle(theme.chatTextPrimary)
                .modifier(ChatLegibility())
                .focused($inputFocused)
                .padding(.horizontal, 4)
                .padding(.vertical, 11)
                // 121：打字、删字、粘贴都算；只把字数交出去
                .onChange(of: draft) { _, text in
                    presence.textChanged(text)
                    // 137：随打随存，App 在后台被系统关掉，回来字还在
                    ChatDraftStore.save(text, for: line)
                }

            Button { send() } label: {
                // 佳佳 2026-10-06：「先回消息 不要等消息」——柯回着的时候也能接着发。
                Image(systemName: "arrow.up")
                    .font(theme.font.sendIcon)
                    .symbolEffect(.bounce.up, value: sendBounce)
                .foregroundStyle(theme.lockscreenGlass ? theme.chatTextPrimary : theme.color.textOnAccent)
                .modifier(ChatLegibility())
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(theme.sendColor)
                )
            }
            .buttonStyle(PressBounceStyle())
            .disabled(!canSend || vm.isUploading)
            .opacity(!canSend || vm.isUploading ? 0.45 : 1)
            .accessibilityLabel("发送消息")
            .accessibilityIdentifier("send-message")
        }
    }

    private var attachmentTray: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapM) {
            HStack(spacing: theme.metric.gapM) {
                attachmentButton(title: "拍照", systemImage: "camera") {
                    attachmentsOpen = false
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showingCamera = true
                    } else {
                        vm.reportUploadFailure("这台设备现在没有可用的相机。")
                    }
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

                // 120：在聊天里直接问柯要锁着的日记。放在「+」里：顶上她只要电话和三个点，
                // 这里本来就是「给柯递东西」的地方，像微信的加号面板，点开就看得到。
                attachmentButton(title: "锁着的日记", systemImage: "book.closed") {
                    attachmentsOpen = false
                    lockedDiariesOpen = true
                }
                .accessibilityIdentifier("attachment-locked-diary")
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
            // 126：和输入胶囊同一种玻璃（压一层纸色，盖在记录上也看得清）
            chromeSurface(radius: theme.metric.radiusAttachmentTray)
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
                                imageRouter.open([attachment], at: 0)
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
            .padding(.horizontal, theme.metric.gapS)
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
                    case .palettes: paletteSettings
                    case .fonts: fontSettings
                    case .appearance: appearanceSettings
                    case .dates: dateSettings
                    case .tools: toolSettings
                    }
                }
                .padding(.horizontal, theme.metric.gapL)
                .padding(.bottom, theme.metric.gapXL)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity)
        // 86：调字体、字号、透明度、配色时只占下半截，上面露出聊天，改了马上看得到
        .frame(height: settingsPreviewsChat ? 380 : nil)
        .frame(maxHeight: settingsPreviewsChat ? nil : .infinity)
        .background {
            if settingsPreviewsChat {
                UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
                    .fill(theme.color.bg)
                    .shadow(color: .black.opacity(0.12), radius: 18, y: -4)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                theme.color.bg.ignoresSafeArea()
            }
        }
        .overlay(alignment: .leading) {
            if !settingsPreviewsChat {
                Rectangle()
                    .fill(theme.color.glassEdge.opacity(theme.glass.drawerEdgeOpacity))
                    .frame(width: 0.7)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        // 从左边缘右划返回，避免把 Slider 的横向拖动当成返回。
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let dx = value.translation.width, dy = value.translation.height
                    guard value.startLocation.x <= theme.metric.pagePadding,
                          dx > 80, abs(dx) > abs(dy) * 1.5 else { return }
                    if settingsPage == .root { closeTransientPanels() } else { settingsPage = .root }
                }
        )
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: settingsPage)
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

    private var settingsPreviewsChat: Bool {
        switch settingsPage {
        case .appearance, .fonts, .palettes: return true
        default: return false
        }
    }

    private var settingsHeader: some View {
        HStack {
            Button {
                if settingsPage == .root { closeTransientPanels() }
                else { settingsPage = .root }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: theme.metric.touchTarget, height: theme.metric.touchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settingsPage == .root ? "关闭聊天设置" : "返回聊天设置")
            Spacer()
            Text(settingsTitle).font(theme.font.sectionTitle)
            Spacer()
            Color.clear.frame(width: theme.metric.touchTarget, height: theme.metric.touchTarget)
        }
        .foregroundStyle(theme.color.textPrimary)
        .padding(.horizontal, theme.metric.gapM)
        .padding(.vertical, theme.metric.gapXS)
    }

    private var settingsTitle: String {
        switch settingsPage {
        case .root: return "功能区"
        case .search: return "查找聊天记录"
        case .delete: return "批量删除"
        case .models: return "模型选择"
        case .palettes: return "聊天配色"
        case .fonts: return "聊天字体"
        case .appearance: return "界面与气泡"
        case .dates: return "按日期查找"
        case .tools: return "工具状态"
        }
    }

    private var settingsRoot: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapL) {
            Text("聊天记录").font(theme.font.caption).foregroundStyle(theme.color.textSecondary)
            settingsLink("查找聊天记录", icon: "magnifyingglass") {
                settingsPage = .search
                Task { await vm.prepareSearchCorpus() }
            }
            settingsLink("按日期查找", icon: "calendar") {
                settingsPage = .dates
                Task { await vm.prepareSearchCorpus() }
            }
            Text("聊天设置").font(theme.font.caption).foregroundStyle(theme.color.textSecondary).padding(.top, 12)
            settingsLink("模型选择", icon: "circle.hexagongrid") {
                settingsPage = .models
                Task { await vm.loadModelSettings(force: true); expandSelectedModelGroup() }
            }
            settingsLink("聊天配色", icon: "paintpalette") { settingsPage = .palettes }
            VStack(alignment: .leading, spacing: theme.metric.gapS) {
                Button {
                    Task { await vm.refreshClaudeSession() }
                } label: {
                    HStack(spacing: theme.metric.gapM) {
                        Image(systemName: "arrow.clockwise")
                        Text(vm.isRefreshingClaude ? "正在刷新…" : "刷新 Claude 会话")
                        Spacer()
                        if vm.isRefreshingClaude { ProgressView().controlSize(.small) }
                    }
                    .font(theme.font.body)
                    .foregroundStyle(theme.color.textPrimary)
                    .frame(minHeight: theme.metric.touchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!vm.canRefreshClaude)
                .opacity(vm.canRefreshClaude || vm.isRefreshingClaude ? 1 : 0.5)
                .accessibilityIdentifier("refresh-claude-session")
                settingsHint("换个后台窗口，聊天记录和记忆不变。请先选 Claude，并等当前回复完成。")
                if let error = vm.claudeRefreshError {
                    settingsError(error) { Task { await vm.refreshClaudeSession() } }
                } else if let notice = vm.claudeRefreshNotice {
                    settingsHint(notice)
                }
            }
            settingsLink("聊天字体", icon: "textformat") { settingsPage = .fonts }
            settingsLink("界面与气泡", icon: "slider.horizontal.3") { settingsPage = .appearance }
            settingsLink("工具状态", icon: "sparkle.magnifyingglass") { settingsPage = .tools }
            Text("记录管理").font(theme.font.caption).foregroundStyle(theme.color.textSecondary).padding(.top, 12)
            Button {
                Task { await vm.clearCurrentWindow() }
            } label: {
                Label(vm.isClearingWindow ? "正在清空…" : "清空当前窗口聊天", systemImage: "trash")
                    .font(theme.font.body)
                    .frame(minHeight: theme.metric.touchTarget)
            }
            .disabled(!vm.canClearWindow)
            .accessibilityIdentifier("clear-chat-window")
            settingsHint("清空当前聊天和上下文。事实记忆、其他窗口保留。旧记录单独归档。")
            if let error = vm.clearWindowError {
                settingsError(error) { Task { await vm.clearCurrentWindow() } }
            } else if let notice = vm.clearWindowNotice {
                settingsHint(notice)
            }
            settingsLink("批量删除聊天记录", icon: "checklist") {
                settingsPage = .delete
                Task { await vm.prepareSearchCorpus() }
            }
        }.padding(.top, 20)
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapL) {
            ChatWallpaperSettings(store: wallpaperStore)
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

        }.padding(.top, 12)
    }

    private var paletteSettings: some View {
        VStack(spacing: 14) {
            ForEach(ChatPalette.all) { choice in
                Button { theme.chatPalette = choice } label: {
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            ForEach([choice.base, choice.tint, choice.accent], id: \.self) { color in
                                Circle().fill(Color(hex: color)).frame(width: 22, height: 22)
                            }
                        }
                        Text(choice.name).foregroundStyle(theme.color.textPrimary)
                        Spacer()
                        if theme.chatPalette.id == choice.id { Image(systemName: "checkmark") }
                    }.frame(minHeight: 52).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }.padding(.top, 12)
    }

    private var fontSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("今天不着急，慢慢说，我在听。")
                .font(theme.font.bubble).lineSpacing(5).padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.color.bubbleMe.opacity(0.2), in: RoundedRectangle(cornerRadius: 20))
            ForEach(ChatTypography.all) { choice in
                Button { theme.chatTypeface = choice } label: {
                    HStack {
                        Text(choice.title).font(choice.font(size: 17))
                        Spacer()
                        if theme.chatTypeface.id == choice.id { Image(systemName: "checkmark") }
                    }.foregroundStyle(theme.color.textPrimary).frame(minHeight: 48).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            settingSlider(title: "文字大小", value: $theme.chatFontSize, range: 13...22, valueText: "\(Int(theme.chatFontSize))")
        }.padding(.top, 12)
    }

    private var dateSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            DatePicker("选择日期", selection: $historyDate, displayedComponents: .date)
                .datePickerStyle(.graphical).environment(\.locale, Locale(identifier: "zh_CN"))
                .accessibilityIdentifier("chat-date-picker")
            if vm.isPreparingSearch { settingsProgress("正在整理聊天记录…") }
            if let error = vm.searchError {
                settingsError(error) { Task { await vm.prepareSearchCorpus(force: true) } }
            }
            let matches = vm.deletionCandidates.filter { $0.serverTimeIsValid != false && ChatTimelineDate.calendar.isDate($0.time, inSameDayAs: historyDate) }
            if matches.isEmpty { settingsHint("这一天没有找到已缓存的聊天记录。") }
            ForEach(matches) { message in
                Button {
                    vm.revealSearchResult(message)
                    highlightedMessageID = message.id
                    settingsOpen = false
                } label: { searchResultRow(message) }.buttonStyle(.plain)
            }
        }.padding(.top, 8)
    }

    private var toolSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            let runs = vm.messages.flatMap { $0.toolRuns ?? [] }
            if runs.isEmpty { settingsHint("当前聊天还没有工具记录。调用工具时，状态会显示在聊天中。") }
            ForEach(runs) { run in ChatToolStatusRow(toolRun: run) }
        }.padding(.top, 12)
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
                        .frame(
                            width: theme.metric.touchTarget,
                            height: theme.metric.touchTarget
                        )
                        .contentShape(Rectangle())
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

                Button { showingUsageDashboard = true } label: {
                    HStack(spacing: theme.metric.gapS) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                        VStack(alignment: .leading, spacing: theme.metric.gapXS) {
                            Text("用量与额度").font(theme.font.sectionTitle)
                            Text("查看小时额度、Token 和调用趋势")
                                .font(.caption).foregroundStyle(theme.color.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(theme.color.textSecondary)
                    }
                    .frame(minHeight: theme.metric.touchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("open-usage-dashboard")

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

        // 124：刷新没成时 vm 留着上次的额度，这里也标一声「上次结果」
        let staleSuffix = quota.stale || vm.modelQuotaError != nil ? " · 上次结果" : ""
        switch quota.status {
        case "cooldown":
            if let reset = modelQuotaResetText(quota.resetAt) {
                return "额度已用完 · \(reset)\(staleSuffix)"
            }
            return "额度已用完\(staleSuffix)"
        case "auth_required":
            return "需要重新验证登录，暂时读不到额度"
        case "local_cooldown":
            return "本地线路暂缓 · 官方额度见下方\(staleSuffix)"
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
            if quota.id.hasPrefix("claude") {
                Text("账号共享额度，包含 App 和 CC 的使用")
                    .font(theme.font.caption).foregroundStyle(theme.color.textSecondary)
            }
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

    /// 137：放回上次没发的字。先告诉 presence 这是恢复的，不算她在打字（不会报给服务器、不会叫醒柯）
    private func restoreSavedDraft() {
        guard !didRestoreDraft else { return }
        didRestoreDraft = true
        let saved = ChatDraftStore.load(line)
        guard draft.isEmpty, !saved.isEmpty else { return }
        presence.adoptRestoredDraft(saved)
        draft = saved
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmedDraft.isEmpty || !vm.pendingAttachments.isEmpty
    }

    private func send() {
        sendBounce &+= 1
        let text = trimmedDraft
        guard canSend, !vm.isUploading, !vm.isRefreshingClaude else { return }
        // 121：发出去这份草稿就结束了，什么都不报；随后清空输入框那一下在它看来是空→空
        presence.didSend()
        draft = ""
        scrollToLatestRequest &+= 1
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

/// 137：输入框里没发的字，按线路存在本机（UserDefaults）。发出去、删光就清掉。
enum ChatDraftStore {
    static func key(_ line: ChatLine) -> String { "chat.draft.\(line.rawValue)" }

    static func load(_ line: ChatLine, defaults: UserDefaults = .standard) -> String {
        guard isEnabled else { return "" }
        return defaults.string(forKey: key(line)) ?? ""
    }

    static func save(_ text: String, for line: ChatLine, defaults: UserDefaults = .standard) {
        guard isEnabled else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.removeObject(forKey: key(line))
        } else {
            defaults.set(text, forKey: key(line))
        }
    }

    /// UI 测试每次都从空输入框开始
    private static var isEnabled: Bool {
#if DEBUG
        !ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-ui-test") }
#else
        true
#endif
    }
}

#Preview {
    ChatView(line: .main, selectedLine: .constant(.main)).environmentObject(Theme.shared)
}
