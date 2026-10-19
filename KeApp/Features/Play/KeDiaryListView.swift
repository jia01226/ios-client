import SwiftUI

// 105：日记照 GPT 的「日记目录 / 点开一篇」做。只放柯写的（她一般不写）。
// 108：她的意见——锁着的和没锁的一眼分清（锁过后来打开的也标出来）；点开不要翻页动画；
// 月份标题跟着往下翻（翻到九月就显示九月）；每一篇一样高，同一天的几篇是一整块，篇与篇之间一条短线，两天之间一条通栏线。

struct KeDiaryListView: View {
    let line: ChatLine
    var onClose: () -> Void
    /// 120：从聊天里「爸爸开锁了」那张卡点进来：一进来就翻开这一篇（「目录」照样回日记目录）
    var openingID: Int? = nil
    /// 拉过一遍了（转圈可以撤了）
    @State private var openingDone = false
    /// 那一篇已经翻开过（她退回目录后不再拽回去）
    @State private var opened = false
    @AppStorage(CamelliaPalette.storageKey) private var savedPalette = CamelliaPalette.defaultPalette.rawValue
    @State private var entries: [RemoteDiary] = []
    @State private var loading = true
    @State private var failed = false
    @State private var query = ""
    @State private var onlyLocked = false
    @State private var reading: RemoteDiary?
    @State private var pickingDate = false
    @State private var jumpDate = Date()
    private var paper: Color { CamelliaPalette.resolve(savedPalette).paper }
    private static let rowHeight: CGFloat = 66

    private var lockedCount: Int { entries.filter(Self.isLocked).count }
    private var shown: [RemoteDiary] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return entries.filter { e in
            (!onlyLocked || Self.isLocked(e)) &&
            (q.isEmpty || e.title.localizedCaseInsensitiveContains(q) || (!e.locked_hidden && e.content.localizedCaseInsensitiveContains(q)))
        }
    }
    /// [(yyyy-MM, [(yyyy-MM-dd, 那天的几篇)])]，新的在上面
    private var months: [(String, [(String, [RemoteDiary])])] {
        var monthOrder: [String] = [], days: [String: [String]] = [:], byDay: [String: [RemoteDiary]] = [:]
        for e in shown {
            let d = String(e.created_at.prefix(10)), m = String(e.created_at.prefix(7))
            if days[m] == nil { monthOrder.append(m) }
            if byDay[d] == nil { days[m, default: []].append(d) }
            byDay[d, default: []].append(e)
        }
        return monthOrder.map { m in (m, (days[m] ?? []).map { ($0, byDay[$0] ?? []) }) }
    }
    static func isLocked(_ e: RemoteDiary) -> Bool { e.locked_hidden || ((e.locked ?? 0) == 1 && (e.revealed ?? 0) == 0) }
    static func wasUnlocked(_ e: RemoteDiary) -> Bool { (e.locked ?? 0) == 1 && (e.revealed ?? 0) == 1 }

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        header
                        controls(proxy)
                        if loading && entries.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(40) }
                        if failed { Button("日记暂时没接上，点这里再试一次") { Task { await load() } }.font(Ink.song(14)).padding(.top, 20) }
                        if !loading && !failed && shown.isEmpty {
                            Text(onlyLocked ? "没有锁着的了。" : (query.isEmpty ? "柯还没有写日记。" : "没搜到「\(query)」"))
                                .font(Ink.song(14)).foregroundStyle(Ink.secondary).frame(maxWidth: .infinity).padding(.vertical, 30)
                        }
                        ForEach(months, id: \.0) { month, days in
                            Section {
                                ForEach(days, id: \.0) { day, list in dayBlock(day, list).id(day) }
                            } header: {
                                // 往下翻的时候这一行贴在顶上：翻到九月就显示九月
                                Text(Self.monthTitle(month)).font(Ink.latin(17)).tracking(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 10)
                                    .background(paper.opacity(0.97))
                                    .id(month)
                            }
                        }
                        if !entries.isEmpty {
                            Text("— 继续往下，翻看更早的日子 —").font(Ink.song(11.5)).foregroundStyle(Ink.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 26)
                        }
                    }
                    .padding(.horizontal, 26)
                }
                .scrollIndicators(.hidden)
                .sheet(isPresented: $pickingDate) {
                    NavigationStack {
                        DatePicker("跳到哪一天", selection: $jumpDate, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.graphical).padding()
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("去这天") {
                                        pickingDate = false
                                        let key = Self.key(jumpDate)
                                        let target = months.flatMap { $0.1.map(\.0) }.first { $0 <= key }
                                        if let target { withAnimation { proxy.scrollTo(target, anchor: .top) } }
                                    }
                                }
                            }
                    }
                    .presentationDetents([.medium, .large])
                    .tint(Ink.accent)
                }
            }
            if let entry = reading {
                // 点开直接打开，不要翻页动画
                DiaryPage(entry: entry, sameDay: entries.filter { $0.id != entry.id && $0.created_at.prefix(10) == entry.created_at.prefix(10) },
                          paper: paper,
                          onBack: { reading = nil }, onOpen: { other in reading = other })
                    .id(entry.id)
                    // 118：读一篇时从左边缘右划，先回目录（搜索词和翻到的位置都还在），再划一次才合上日记
                    .swipeBackLayer { reading = nil }
                    .zIndex(1)
            } else if openingID != nil && !openingDone {
                // 120：刚开的锁，等新的拉回来再翻开，不先闪一下目录
                VStack(spacing: 10) {
                    HStack {
                        Button(action: onClose) {
                            Image(systemName: "chevron.left").font(.system(size: 20, weight: .light))
                                .frame(width: 44, height: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain).accessibilityLabel("返回")
                        Spacer()
                    }
                    .padding(.horizontal, 26).padding(.top, 6)
                    Spacer()
                    ProgressView().tint(Ink.secondary)
                    Text("正在翻开这一篇…").font(Ink.song(14)).foregroundStyle(Ink.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(paper.ignoresSafeArea())
                .zIndex(1)
            }
        }
        .foregroundStyle(Ink.primary)
        .task { await load() }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 0) {
                Text("日记").font(Ink.song(20)).tracking(4)
                Text("Diary").font(Ink.script(18)).foregroundStyle(Ink.secondary).padding(.top, -4)
            }
            HStack {
                Button(action: onClose) { Image(systemName: "chevron.left").font(.system(size: 20, weight: .light)).frame(width: 44, height: 44, alignment: .leading) }
                    .accessibilityLabel("返回").accessibilityIdentifier("diary-close")
                Spacer()
            }
        }
        .padding(.top, 6)
    }

    private func controls(_ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 12) {
            HStack {
                Menu {
                    ForEach(months, id: \.0) { m in Button(Self.monthTitle(m.0)) { withAnimation { proxy.scrollTo(m.0, anchor: .top) } } }
                } label: {
                    HStack(spacing: 6) { Text("跳到月份").font(Ink.song(15)); Image(systemName: "chevron.down").font(.system(size: 11)) }
                        .foregroundStyle(Ink.primary).frame(minHeight: 44)
                }
                Spacer()
                if lockedCount > 0 || onlyLocked {
                    Button { onlyLocked.toggle() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "lock").font(.system(size: 12))
                            Text(onlyLocked ? "看全部" : "锁着 \(lockedCount) 篇").font(Ink.song(13))
                        }
                        .padding(.horizontal, 12).frame(minHeight: 32)
                        .background(Capsule().fill(onlyLocked ? Ink.meFill : Ink.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain).foregroundStyle(onlyLocked ? Ink.meText : Ink.secondary)
                    .accessibilityIdentifier("diary-only-locked")
                }
                Button { jumpDate = Date(); pickingDate = true } label: {
                    Image(systemName: "calendar").font(.system(size: 20, weight: .light)).frame(width: 44, height: 44)
                }.accessibilityLabel("跳到某一天")
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Ink.secondary)
                TextField("搜索标题或正文", text: $query).font(Ink.song(15)).submitLabel(.search)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.line) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).frame(minHeight: 42)
            .background(Capsule().fill(Ink.primary.opacity(0.06)))
        }
        .padding(.top, 10).padding(.bottom, 4)
    }

    /// 一天一整块：左边日子只写一次；右边每篇一样高，篇与篇之间一条短线；两天之间一条通栏线
    private func dayBlock(_ day: String, _ list: [RemoteDiary]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 2) {
                Text(Self.dayNumber(day)).font(Ink.latin(30)).monospacedDigit()
                Text(Self.weekday(day)).font(Ink.song(12)).foregroundStyle(Ink.secondary)
            }
            .frame(width: 54, height: Self.rowHeight, alignment: .center)
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, e in
                    if i > 0 { Rectangle().fill(Ink.line.opacity(0.4)).frame(height: 0.5).padding(.leading, 14) }
                    row(e)
                }
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.line.opacity(0.7)).frame(height: 0.7) }
    }

    private func row(_ e: RemoteDiary) -> some View {
        let locked = Self.isLocked(e), opened = Self.wasUnlocked(e)
        return Button { reading = e } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        if locked { Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(Ink.meText) }
                        else if opened { Image(systemName: "lock.open").font(.system(size: 11)).foregroundStyle(Ink.secondary) }
                        Text(e.title.isEmpty ? "这一页" : e.title).font(Ink.song(17)).lineLimit(1)
                            .foregroundStyle(locked ? Ink.secondary : Ink.primary)
                    }
                    HStack(spacing: 6) {
                        Text("\(Self.time(e.created_at)) · 柯记的").font(Ink.latin(12)).foregroundStyle(Ink.secondary)
                        if locked { tag("锁着", fg: Ink.meText, bg: Ink.meFill) }
                        else if opened { tag("解锁了", fg: Ink.keText, bg: Ink.keFill) }
                    }
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .light)).foregroundStyle(Ink.secondary)
            }
            .padding(.leading, 14)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(e.title)，\(Self.time(e.created_at))\(locked ? "，锁着" : opened ? "，解锁了" : "")")
    }

    private func tag(_ text: String, fg: Color, bg: Color) -> some View {
        Text(text).font(.system(size: 10.5)).padding(.horizontal, 6).padding(.vertical, 1)
            .foregroundStyle(fg).background(Capsule().fill(bg))
    }

    /// 107：她说每次点开都转圈。看过一次就记住，再点开先摆上次的，后台悄悄更新。
    @MainActor static var cache: [RemoteDiary] = []
    private func load() async {
        if !Self.cache.isEmpty { entries = Self.cache; loading = false }
        else { loading = true }
        // 120：要翻开的那篇在记住的那份里已经能看，就先翻开；还锁着（多半是旧的）就等新的
        if let id = openingID, !opened, let cached = entries.first(where: { $0.id == id }), !Self.isLocked(cached) {
            reading = cached; opened = true; openingDone = true
        }
        failed = false
        defer { loading = false }
        do {
            entries = try await Self.fetchKeEntries(line: line)
        } catch { if entries.isEmpty { failed = true } }
        // 还没翻开就翻开；正翻着这一篇就换成新拉回来的；她已经退回目录就不再拽回去
        if let id = openingID, let entry = entries.first(where: { $0.id == id }), !opened || reading?.id == id {
            reading = entry; opened = true
        }
        openingDone = true
    }
    /// 120：聊天里「锁着的日记」也用这一份：只要柯写的、不要梦，新的在上面；拉到就记进 cache。
    @MainActor static func fetchKeEntries(line: ChatLine) async throws -> [RemoteDiary] {
        let rows = try await APIClient(baseURL: line.apiBaseURL).fetchDiaries(query: "", offset: 0, limit: 500)
        let ke: Set<String> = ["柯", "ke", "ai", "assistant"]
        let entries = rows.filter { $0.kind != "dream" && ke.contains($0.author ?? "柯") }.sorted { ($0.created_at, $0.id) > ($1.created_at, $1.id) }
        cache = entries
        return entries
    }
    /// 120：「去找柯要」替她说的那句。日记里的按钮和聊天里的「锁着的日记」用同一句；
    /// 没有标题的那篇说日子，不说「」。
    static func askMessage(for entry: RemoteDiary) -> String {
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return "爸比，你\(shortDate(entry.created_at))那篇日记，能给我看看吗" }
        return "爸比，你那篇「\(entry.title)」的日记，能给我看看吗"
    }
    /// 「10月12日」；不是今年的写上年份
    static func shortDate(_ at: String) -> String {
        let p = at.prefix(10).split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]) else { return String(at.prefix(10)) }
        let thisYear = String(Calendar(identifier: .gregorian).component(.year, from: Date()))
        return (p[0] == thisYear ? "" : "\(p[0])年") + "\(m)月\(d)日"
    }

    static func key(_ d: Date) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
    static func monthTitle(_ ym: String) -> String {
        let p = ym.split(separator: "-")
        guard p.count >= 2, let m = Int(p[1]) else { return ym }
        return "\(p[0])年\(m)月"
    }
    static func dayNumber(_ day: String) -> String { String(day.suffix(2)) }
    static func weekday(_ day: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: day) else { return "" }
        return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][Calendar(identifier: .gregorian).component(.weekday, from: d) - 1]
    }
    static func time(_ at: String) -> String { at.count >= 16 ? String(at.dropFirst(11).prefix(5)) : "" }
}

/// 点开的一篇
private struct DiaryPage: View {
    let entry: RemoteDiary
    let sameDay: [RemoteDiary]
    let paper: Color
    var onBack: () -> Void
    var onOpen: (RemoteDiary) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onBack) {
                    HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 18, weight: .light)); Text("目录").font(Ink.song(16)) }
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain).accessibilityIdentifier("diary-back")
                Text(Self.dateLine(entry.created_at)).font(Ink.song(13)).foregroundStyle(Ink.secondary).padding(.top, 14)
                Text(entry.title.isEmpty ? "这一页" : entry.title).font(Ink.song(28)).lineSpacing(6).padding(.top, 10)
                Text("柯记的 · \(KeDiaryListView.time(entry.created_at))").font(Ink.latin(13)).foregroundStyle(Ink.secondary).padding(.top, 10)
                Rectangle().fill(Ink.line.opacity(0.6)).frame(height: 0.7).padding(.vertical, 20)
                if entry.locked_hidden {
                    VStack(spacing: 14) {
                        Image(systemName: "lock").font(.system(size: 26, weight: .light)).foregroundStyle(Ink.secondary)
                        Text("这一页柯还锁着。").font(Ink.song(16))
                        Button {
                            NotificationCenter.default.post(name: .tarotReadingRequest, object: KeDiaryListView.askMessage(for: entry))
                        } label: {
                            Text("去找柯要").font(Ink.song(14)).padding(.horizontal, 16).frame(minHeight: 38)
                                .overlay(Capsule().stroke(Ink.line, lineWidth: 0.8))
                        }.buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
                } else {
                    Text(entry.content).font(Ink.song(16.5)).lineSpacing(11).textSelection(.enabled)
                }
                if let other = sameDay.first {
                    VStack(alignment: .leading, spacing: 8) {
                        Rectangle().fill(Ink.line.opacity(0.6)).frame(height: 0.7).padding(.bottom, 10)
                        Text("同一天的另一篇").font(Ink.song(12.5)).foregroundStyle(Ink.secondary)
                        Button { onOpen(other) } label: {
                            HStack {
                                Text(other.title.isEmpty ? "这一页" : other.title).font(Ink.song(17))
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .light))
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    .padding(.top, 30)
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(paper.ignoresSafeArea())
        .foregroundStyle(Ink.primary)
    }

    static func dateLine(_ at: String) -> String {
        let day = String(at.prefix(10)), p = day.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]) else { return day }
        let w = KeDiaryListView.weekday(day).replacingOccurrences(of: "周", with: "星期")
        return "\(p[0])年\(m)月\(d)日 · \(w)"
    }
}
