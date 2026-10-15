import SwiftUI

// 105：日记照 GPT 的「日记目录 / 点开一篇」做。只放柯写的（她一般不写），
// 左边大日子、按月份、日历跳到某天、搜索；点开读全文，轻轻翻页进来，底下有「同一天的另一篇」。
// 柯锁着的那几页只露标题和一把小锁，正文要他同意了才看得到（和抽屉一个道理）。

struct KeDiaryListView: View {
    let line: ChatLine
    var onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CamelliaPalette.storageKey) private var savedPalette = CamelliaPalette.defaultPalette.rawValue
    @State private var entries: [RemoteDiary] = []
    @State private var loading = true
    @State private var failed = false
    @State private var query = ""
    @State private var reading: RemoteDiary?
    @State private var pickingDate = false
    @State private var jumpDate = Date()
    private var paper: Color { CamelliaPalette.resolve(savedPalette).paper }

    private var shown: [RemoteDiary] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.title.localizedCaseInsensitiveContains(q) || (!$0.locked_hidden && $0.content.localizedCaseInsensitiveContains(q)) }
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

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        controls(proxy)
                        if loading && entries.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(40) }
                        if failed { Button("日记暂时没接上，点这里再试一次") { Task { await load() } }.font(Ink.song(14)).padding(.top, 20) }
                        if !loading && !failed && shown.isEmpty {
                            Text(query.isEmpty ? "柯还没有写日记。" : "没搜到「\(query)」").font(Ink.song(14)).foregroundStyle(Ink.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 30)
                        }
                        ForEach(months, id: \.0) { month, days in
                            Color.clear.frame(height: 1).id(month)
                            ForEach(days, id: \.0) { day, list in dayBlock(day, list).id(day) }
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
                                        // 那天没写，就跳到它之前最近的一天
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
                DiaryPage(entry: entry, sameDay: entries.filter { $0.id != entry.id && $0.created_at.prefix(10) == entry.created_at.prefix(10) },
                          paper: paper, reduceMotion: reduceMotion,
                          onBack: { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { reading = nil } },
                          onOpen: { other in withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { reading = other } })
                    .id(entry.id)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .modifier(active: PageTurn(angle: -28, opacity: 0), identity: PageTurn(angle: 0, opacity: 1)),
                                                                       removal: .opacity))
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
        VStack(spacing: 14) {
            HStack {
                Menu {
                    ForEach(months, id: \.0) { m in Button(Self.monthTitle(m.0)) { withAnimation { proxy.scrollTo(m.0, anchor: .top) } } }
                } label: {
                    HStack(spacing: 6) {
                        Text(Self.monthTitle(months.first?.0 ?? Self.key(Date()).prefix(7).description)).font(Ink.latin(19))
                        Image(systemName: "chevron.down").font(.system(size: 11))
                    }.foregroundStyle(Ink.primary).frame(minHeight: 44)
                }
                Spacer()
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
        .padding(.top, 10).padding(.bottom, 8)
    }

    private func dayBlock(_ day: String, _ list: [RemoteDiary]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 2) {
                Text(Self.dayNumber(day)).font(Ink.latin(34)).monospacedDigit()
                Text(Self.weekday(day)).font(Ink.song(12)).foregroundStyle(Ink.secondary)
            }
            .frame(width: 58, alignment: .leading)
            .padding(.top, 14)
            Rectangle().fill(Ink.line.opacity(0.5)).frame(width: 0.7).padding(.vertical, 14)
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, e in
                    Button { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.45)) { reading = e } } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    if e.locked_hidden { Image(systemName: "lock").font(.system(size: 13)).foregroundStyle(Ink.secondary) }
                                    Text(e.title.isEmpty ? "这一页" : e.title).font(Ink.song(17)).lineLimit(2)
                                }
                                Text("\(Self.time(e.created_at)) · 柯记的\(e.locked_hidden ? " · 锁着" : "")")
                                    .font(Ink.latin(12.5)).foregroundStyle(Ink.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .light)).foregroundStyle(Ink.secondary)
                        }
                        .padding(.vertical, 14).padding(.leading, 16)
                        .contentShape(Rectangle())
                        .overlay(alignment: .bottom) {
                            if i < list.count - 1 { Rectangle().fill(Ink.line.opacity(0.4)).frame(height: 0.5).padding(.leading, 16) }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(e.title)，\(Self.time(e.created_at))\(e.locked_hidden ? "，锁着" : "")")
                }
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.line.opacity(0.6)).frame(height: 0.7) }
    }

    private func load() async {
        loading = true; failed = false
        defer { loading = false }
        do {
            let rows = try await APIClient(baseURL: line.apiBaseURL).fetchDiaries(query: "", offset: 0, limit: 500)
            let ke: Set<String> = ["柯", "ke", "ai", "assistant"]
            entries = rows.filter { $0.kind != "dream" && ke.contains($0.author ?? "柯") }.sorted { ($0.created_at, $0.id) > ($1.created_at, $1.id) }
        } catch { failed = true }
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

/// 轻轻翻页：从左边书脊转过来
private struct PageTurn: ViewModifier {
    let angle: Double
    let opacity: Double
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.5)
            .opacity(opacity)
    }
}

/// 点开的一篇
private struct DiaryPage: View {
    let entry: RemoteDiary
    let sameDay: [RemoteDiary]
    let paper: Color
    let reduceMotion: Bool
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
                            NotificationCenter.default.post(name: .tarotReadingRequest, object: "爸比，你那篇「\(entry.title)」的日记，能给我看看吗")
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

/// 抽屉那朵花：只放抽屉（原来和日记挤在一页的两个页签拆开了）
struct KeDrawerPage: View {
    @EnvironmentObject private var theme: Theme
    let line: ChatLine
    var onClose: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                VStack(spacing: 0) {
                    Text("抽屉").font(Ink.song(20)).tracking(4)
                    Text("Tiroir").font(Ink.script(18)).foregroundStyle(Ink.secondary).padding(.top, -4)
                }
                HStack {
                    Button(action: onClose) { Image(systemName: "chevron.left").font(.system(size: 20, weight: .light)).frame(width: 44, height: 44, alignment: .leading) }
                        .accessibilityLabel("返回").accessibilityIdentifier("drawer-close")
                    Spacer()
                }
            }
            .padding(.horizontal, 26).padding(.top, 6)
            .foregroundStyle(Ink.primary)
            MoonDrawerView(line: line)
        }
        .background(theme.pageBackground.ignoresSafeArea())
    }
}
