import SwiftUI

enum CompanionPage: String, Identifiable {
    case calendar = "日历", anniversaries = "纪念日", diary = "日记", moments = "朋友圈"
    var id: String { rawValue }
}

struct CompanionPages: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    private var journalInk: Color { theme.skin == .night ? theme.color.textPrimary : Color(hex: 0x302D28) }
    let page: CompanionPage
    private let api: APIClient
    @State private var anniversaries: [RemoteAnniversary] = []
    @State private var shifts: [RemoteShift] = []
    @State private var periods: [RemotePeriod] = []
    @State private var reminders: [RemoteReminder] = []
    @State private var diaries: [RemoteDiary] = []
    @State private var moments: [RemoteMoment] = []
    @State private var selectedDate = Date.now
    @State private var loading = false
    @State private var saving = false
    @State private var error: String?
    @State private var editing = false
    @State private var title = ""
    @State private var content = ""
    @State private var recordType = "排班"
    @State private var pendingDeletion: Int?
    @State private var calendarDeletionKind = "亲密"
    @State private var shiftDeletionDate = ""
    @State private var editingID: Int?
    @State private var operationID = UUID().uuidString
    @State private var privateRecords: [RemotePrivateRecord] = []
    @State private var privateExpanded = false
    @State private var privateError: String?
    @State private var commentTarget: Int?
    @State private var commentText = ""
    @State private var comments: [Int: [RemoteMomentComment]] = [:]
    @State private var diaryQuery = ""
    @State private var diaryHasMore = false
    @State private var diaryRequestID = UUID()
    @State private var diarySearchTask: Task<Void, Never>?
    private let diaryPageSize = 50

    init(page: CompanionPage, line: ChatLine) {
        self.page = page
        api = APIClient(baseURL: line.apiBaseURL)
    }

    var body: some View {
        NavigationStack {
            Group {
                if page == .diary || page == .moments {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            if let error { Text(error); Button("重新加载") { Task { await reload() } } }
                            if loading { ProgressView("正在加载") }
                            if page == .diary { diaryContent } else { momentsContent }
                        }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .diarySearchable(page == .diary, text: $diaryQuery)
                } else {
                    List {
                        if let error {
                            Section {
                                Text(error).foregroundStyle(theme.color.textSecondary)
                                Button("重新加载") { Task { await reload() } }.disabled(loading)
                            }
                        }
                        if loading { ProgressView("正在加载") }
                        switch page {
                        case .calendar: calendarContent
                        case .anniversaries: anniversaryContent
                        case .diary: diaryContent
                        case .moments: momentsContent
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.effectiveBackground)
            .font(page == .diary || page == .moments ? .custom("NotoSerifSC-Regular", size: 17, relativeTo: .body) : theme.font.body)
            .tint(theme.effectiveAccent)
            .navigationTitle(page.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if page == .diary || page == .moments {
                        Button("关闭", systemImage: "chevron.left") { dismiss() }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("关闭")
                            .accessibilityIdentifier("companion-close")
                    } else { Button("关闭") { dismiss() } }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(page == .diary ? "写一篇" : "添加", systemImage: page == .diary ? "square.and.pencil" : "plus") { editingID = nil; operationID = UUID().uuidString; title = ""; content = ""; editing = true }.disabled(saving)
                }
            }
            .refreshable {
                if page == .diary { await reloadDiaries(reset: true) }
                else { await reload() }
            }
            .task {
                if page == .diary { await reloadDiaries(reset: true) }
                else { await reload() }
            }
            .onChange(of: diaryQuery) { _, _ in
                guard page == .diary else { return }
                diarySearchTask?.cancel()
                diarySearchTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await reloadDiaries(reset: true)
                }
            }
            .onDisappear { diarySearchTask?.cancel() }
            .sheet(isPresented: $editing) { editor }
            .sheet(isPresented: Binding(get: { commentTarget != nil }, set: { if !$0 { commentTarget = nil } })) { commentEditor }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { privateExpanded = false; privateRecords = [] }
            }
            .task(id: dateKey) { if privateExpanded { await loadPrivateRecords() } }
            .onChange(of: privateExpanded) { _, expanded in
                if expanded { Task { await loadPrivateRecords() } }
                else { privateRecords = []; privateError = nil }
            }
            .alert("删除这条记录？", isPresented: Binding(
                get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }
            )) {
                Button("取消", role: .cancel) { pendingDeletion = nil }
                Button("删除", role: .destructive) {
                    guard let id = pendingDeletion else { return }
                    pendingDeletion = nil
                    Task { await remove(id) }
                }
            }
        }
    }

    private var calendarContent: some View {
        Group {
            DatePicker("查看日期", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .environment(\.calendar, CompanionDate.calendar)
                .environment(\.timeZone, CompanionDate.calendar.timeZone)
            Section("当天安排") {
                ForEach(shifts.filter { $0.date == dateKey }) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.shift)
                        if let note = item.note, !note.isEmpty { Text(note).font(theme.font.caption) }
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) {
                            calendarDeletionKind = "排班"; shiftDeletionDate = item.date; pendingDeletion = 0
                        }
                    }
                }
                ForEach(reminders.filter { $0.scheduled_for.hasPrefix(dateKey) }) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.text)
                        Text(item.scheduled_for).font(theme.font.caption)
                        if !item.outcome_label.isEmpty { Text(item.outcome_label).font(theme.font.caption) }
                    }
                }
                if !loading && error == nil && shifts.allSatisfy({ $0.date != dateKey })
                    && reminders.allSatisfy({ !$0.scheduled_for.hasPrefix(dateKey) }) {
                    Text("这一天还没有安排").foregroundStyle(theme.color.textSecondary)
                }
            }
            Section {
                DisclosureGroup("生理期记录") {
                    ForEach(periods.filter { $0.start_date == dateKey }) { item in
                        Text(item.note?.isEmpty == false ? item.note! : "记录开始日期")
                            .swipeActions { Button("删除", role: .destructive) {
                                calendarDeletionKind = "生理期"; pendingDeletion = item.id
                            } }
                    }
                    if periods.allSatisfy({ $0.start_date != dateKey }) { Text("这一天没有开始记录") }
                }
            }
            Section {
                DisclosureGroup("亲密记录", isExpanded: $privateExpanded) {
                    if let privateError { Text(privateError) }
                    ForEach(privateRecords) { item in
                        Text(item.note.isEmpty ? "记录了一次" : item.note)
                            .swipeActions { Button("删除", role: .destructive) { calendarDeletionKind = "亲密"; pendingDeletion = item.id } }
                    }
                    if privateRecords.isEmpty && privateError == nil { Text("这一天没有记录") }
                }
            }
        }
    }

    private var anniversaryContent: some View {
        Group {
            ForEach(anniversaries) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.name)
                    Text(item.date).font(theme.font.caption).foregroundStyle(theme.color.textSecondary)
                }
                .swipeActions {
                    Button("删除", role: .destructive) { pendingDeletion = item.id }
                    Button("编辑") {
                        editingID = item.id; title = item.name
                        selectedDate = CompanionDate.parse(item.date) ?? .now
                        operationID = UUID().uuidString; editing = true
                    }.tint(theme.effectiveAccent)
                }
            }
            if anniversaries.isEmpty && !loading && error == nil { Text("还没有纪念日，点右上角添加") }
        }
    }

    private var diaryContent: some View {
        Group {
            ForEach(diaries) { item in
                DisclosureGroup {
                    if item.locked_hidden {
                        Text("这一页还锁着，可以在聊天里问柯。")
                    } else {
                        Text(item.content).textSelection(.enabled)
                        ForEach(comments[item.id] ?? []) { comment in
                            Text("\(comment.author)：\(comment.content)").font(theme.font.caption)
                        }
                        Button("查看评论") { Task { await loadComments(item.id) } }
                        Button("写评论") { commentTarget = item.id; commentText = "" }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 20) {
                            Text(String(item.created_at.dropFirst(8).prefix(2)))
                                .font(.custom("Didot", size: 40, relativeTo: .largeTitle)).frame(width: 48)
                            Rectangle().fill(theme.color.separator).frame(width: 1, height: 66)
                            VStack(alignment: .leading, spacing: 10) {
                                Text(item.title).font(.custom("NotoSerifSC-Regular", size: 21, relativeTo: .title3))
                                Text(item.locked_hidden ? "暂时锁着的一页" : item.content).lineLimit(2).font(theme.font.caption)
                                Text(item.author ?? "柯").font(.custom("NotoSerifSC-Regular", size: 14, relativeTo: .caption))
                            }
                        }.foregroundStyle(journalInk)
                    }
                }
                .contextMenu { Button("删除", role: .destructive) { pendingDeletion = item.id } }
                Divider().padding(.vertical, 12)
            }
            if diaries.isEmpty && !loading && error == nil {
                Text(diaryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? "还没有日记，点右上角写一篇"
                     : "没有找到相关日记，换个词试试")
                    .foregroundStyle(theme.color.textSecondary)
            }
            if diaryHasMore && !loading {
                Button("再翻一些") { Task { await reloadDiaries(reset: false) } }
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }

    private var momentsContent: some View {
        Group {
            ForEach(moments) { item in
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Text(item.author == "user" ? "佳" : "柯").font(.custom("NotoSerifSC-Regular", size: 20)).frame(width: 40, height: 40).background(theme.color.accentSoft.opacity(0.15), in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.author == "user" ? "佳佳" : "柯")
                            Text(item.created_at).font(theme.font.caption).foregroundStyle(theme.color.textSecondary)
                        }
                    }
                    Text(item.content).textSelection(.enabled).lineSpacing(6)
                    if let image = item.image, !image.isEmpty { CompanionImage(api: api, path: image) }
                    HStack(spacing: 22) {
                        Spacer()
                        Button(item.user_liked != 0 ? "取消喜欢" : "喜欢", systemImage: item.user_liked != 0 ? "heart.fill" : "heart") { Task { await like(item) } }.disabled(saving)
                        Button("评论", systemImage: "bubble") { commentTarget = item.id; commentText = "" }
                    }.labelStyle(.iconOnly).font(.system(size: 23, weight: .light)).frame(minHeight: 44)
                    ForEach(item.comments) { comment in
                        Text("\(comment.author == "user" ? "我" : "柯")：\(comment.content)")
                    }
                }
                .contextMenu {
                    if item.author == "user" {
                        Button("删除", role: .destructive) { pendingDeletion = item.id }
                    }
                }
                Divider().padding(.vertical, 12)
            }
            if moments.isEmpty && !loading && error == nil { Text("还没有动态，点右上角分享一件事") }
        }
    }

    private var editor: some View {
        NavigationStack {
            Form {
                if page == .calendar {
                    Picker("记录类型", selection: $recordType) {
                        Text("排班").tag("排班")
                        Text("生理期开始").tag("生理期")
                        Text("亲密记录").tag("亲密")
                    }
                }
                if page == .calendar || page == .anniversaries {
                    DatePicker("日期", selection: $selectedDate, displayedComponents: .date)
                        .environment(\.timeZone, CompanionDate.calendar.timeZone)
                }
                if page == .anniversaries || page == .diary || (page == .calendar && recordType == "排班") {
                    TextField(page == .calendar ? "班次，例如白班" : "标题", text: $title)
                }
                if page != .anniversaries {
                    TextField(page == .calendar ? "备注" : "正文", text: $content, axis: .vertical)
                        .lineLimit(5...15)
                }
                if let error { Text(error).foregroundStyle(theme.color.textSecondary) }
            }
            .navigationTitle(page == .moments ? "写动态" : "添加记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { editing = false }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中" : "保存") { Task { await save() } }
                        .disabled(saving || !validInput)
                }
            }
            .interactiveDismissDisabled(saving)
        }
    }

    private var dateKey: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = CompanionDate.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: selectedDate)
    }

    private var validInput: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasContent = !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch page {
        case .anniversaries: return hasTitle
        case .calendar: return recordType != "排班" || hasTitle
        case .diary: return hasTitle && hasContent
        case .moments: return hasContent
        }
    }

    @MainActor private func reload() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            switch page {
            case .anniversaries: anniversaries = try await api.fetchAnniversaries()
            case .calendar:
                async let a = api.fetchShifts()
                async let b = api.fetchPeriods()
                async let c = api.fetchSchedule()
                let (newShifts, newPeriods, schedule) = try await (a, b, c)
                shifts = newShifts; periods = newPeriods; reminders = schedule.current + schedule.history
            case .diary: await reloadDiaries(reset: true); return
            case .moments: moments = try await api.fetchMoments()
            }
            if privateExpanded { await loadPrivateRecords() }
            error = nil
        } catch { self.error = "没有加载成功，请重试。" + error.localizedDescription }
    }

    @MainActor private func reloadDiaries(reset: Bool) async {
        let requestID = UUID()
        diaryRequestID = requestID
        loading = true
        let query = diaryQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let offset = reset ? 0 : diaries.count
        do {
            let rows = try await api.fetchDiaries(query: query, offset: offset, limit: diaryPageSize)
            guard diaryRequestID == requestID else { return }
            diaries = reset ? rows : diaries + rows
            diaryHasMore = rows.count == diaryPageSize
            error = nil
            loading = false
        } catch is CancellationError {
            if diaryRequestID == requestID { loading = false }
        } catch {
            guard diaryRequestID == requestID else { return }
            self.error = query.isEmpty
                ? "日记没有加载成功，请重试。"
                : "没有完成查找，请重试。"
            loading = false
        }
    }

    @MainActor private func save() async {
        guard !saving, validInput else { return }
        saving = true
        defer { saving = false }
        do {
            switch page {
            case .anniversaries:
                if let editingID { try await api.editAnniversary(id: editingID, name: title, date: dateKey, operationID: operationID) }
                else { try await api.addAnniversary(name: title, date: dateKey) }
            case .calendar:
                if recordType == "排班" { try await api.setShift(date: dateKey, shift: title, note: content) }
                else if recordType == "生理期" { try await api.addPeriod(startDate: dateKey, note: content) }
                else { try await api.savePrivateRecord(date: dateKey, note: content, operationID: operationID) }
            case .diary: try await api.addDiary(title: title, content: content, mood: "")
            case .moments: try await api.addMoment(content: content)
            }
            editing = false; title = ""; content = ""; error = nil
            await reload()
        } catch { self.error = "没有保存成功，内容已保留，请重试。" + error.localizedDescription }
    }

    @MainActor private func remove(_ id: Int) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            switch page {
            case .anniversaries: try await api.deleteAnniversary(id: id)
            case .diary: try await api.deleteDiary(id: id)
            case .moments: try await api.deleteMoment(id: id)
            case .calendar:
                if calendarDeletionKind == "排班" { try await api.deleteShift(date: shiftDeletionDate) }
                else if calendarDeletionKind == "生理期" { try await api.deletePeriod(id: id) }
                else { try await api.deletePrivateRecord(id: id, operationID: UUID().uuidString) }
            }
            await reload()
        } catch { self.error = "没有删除成功，请重试。" + error.localizedDescription }
    }

    private var commentEditor: some View {
        NavigationStack {
            Form {
                TextField("评论", text: $commentText, axis: .vertical).lineLimit(3...10)
                if let error { Text(error) }
            }
            .navigationTitle("写评论")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { commentTarget = nil }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送") { Task { await sendComment() } }
                        .disabled(saving || commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(saving)
        }
    }

    @MainActor private func loadPrivateRecords() async {
        let requestedDate = dateKey
        do {
            let rows = try await api.fetchPrivateRecords(date: requestedDate)
            guard privateExpanded, requestedDate == dateKey else { return }
            privateRecords = rows; privateError = nil
        } catch { privateRecords = []; privateError = "记录没有加载成功，请收起后重试。" }
    }

    @MainActor private func loadComments(_ id: Int) async {
        do { comments[id] = try await api.fetchDiaryComments(id: id) }
        catch { self.error = "评论没有加载成功，请重试。" }
    }

    @MainActor private func sendComment() async {
        guard let id = commentTarget, !saving else { return }
        saving = true
        defer { saving = false }
        do {
            if page == .diary { try await api.addDiaryComment(id: id, content: commentText); await loadComments(id) }
            else { try await api.addMomentComment(id: id, content: commentText); await reload() }
            commentTarget = nil; commentText = ""; error = nil
        } catch { self.error = "评论没有发送成功，内容已保留，请重试。" }
    }

    @MainActor private func like(_ item: RemoteMoment) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do { try await api.setMomentLike(id: item.id, liked: item.user_liked == 0); await reload() }
        catch { self.error = "没有保存喜欢状态，请重试。" + error.localizedDescription }
    }
}

private extension View {
    @ViewBuilder
    func diarySearchable(_ enabled: Bool, text: Binding<String>) -> some View {
        if enabled {
            searchable(text: text, prompt: "查找标题、正文或作者")
        } else {
            self
        }
    }
}

struct CompanionImage: View {
    let api: APIClient
    let path: String
    var thumbnail = false
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image {
                if thumbnail {
                    GeometryReader { bounds in
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: bounds.size.width, height: 170).clipped()
                    }.frame(height: 170).accessibilityLabel("动态图片")
                } else {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 320).accessibilityLabel("动态图片")
                }
            }
            else if failed { Text("图片未能加载") }
            else { ProgressView("正在加载图片") }
        }
        .task(id: path) {
            image = nil; failed = false
            do {
                let data = try await api.fetchAttachmentData(at: path)
                guard let decoded = UIImage(data: data) else { failed = true; return }
                image = decoded
            } catch { failed = true }
        }
    }
}
