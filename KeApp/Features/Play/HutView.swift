import SwiftUI

enum HutObject: String, CaseIterable, Identifiable {
    case map = "地图", cairn = "石堆", polaroids = "拍立得", facts = "事实簿"
    case floe = "浮冰", photos = "墙上的照片", weather = "窗外", letters = "小锁信"
    var id: String { key }
    var key: String {
        switch self {
        case .map: "map"
        case .cairn: "cairn"
        case .polaroids: "polaroids"
        case .facts: "facts"
        case .floe: "floe"
        case .photos: "photos"
        case .weather: "weather"
        case .letters: "letters"
        }
    }
    var position: UnitPoint {
        switch self {
        case .map: UnitPoint(x: 0.25, y: 0.57)
        case .cairn: UnitPoint(x: 0.76, y: 0.58)
        case .polaroids: UnitPoint(x: 0.5, y: 0.48)
        case .facts: UnitPoint(x: 0.22, y: 0.80)
        case .floe: UnitPoint(x: 0.79, y: 0.82)
        case .photos: UnitPoint(x: 0.25, y: 0.22)
        case .weather: UnitPoint(x: 0.73, y: 0.22)
        case .letters: UnitPoint(x: 0.5, y: 0.81)
        }
    }
    var caption: String {
        switch self {
        case .map: "还有下文的事，先放在这里。"
        case .cairn: "最常被想起的五段。"
        case .polaroids: "这七天，柯想起过的片刻。"
        case .facts: "核对过的小事，一页一页收着。"
        case .floe: "这次推门，浮上来的一条。"
        case .photos: "你发过的照片，留下柯看见的那一刻。"
        case .weather: "看看这间屋子现在的天气。"
        case .letters: "哪里记错了，哪里变了，写给柯。"
        }
    }
}

struct HutView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var model = HutViewModel(api: APIClient(baseURL: ChatLine.test1.apiBaseURL))
    @State private var selected: HutObject?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JournalLayout.gap) {
                    Text("柯的山屋").font(theme.font.journalTitle)
                    Text("推门进来，看看他把什么留在了这里。")
                        .font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary)
                    if model.loading && model.hut == nil { ProgressView("正在推开门…") }
                    if let error = model.error {
                        Text(error).font(theme.font.journalBody)
                        Button("再推一次门") { Task { await model.load() } }.disabled(model.loading)
                    }
                    if typeSize.isAccessibilitySize {
                        ForEach(HutObject.allCases) { object in
                            Button(object.rawValue) { selected = object }
                                .accessibilityIdentifier("hut-" + object.key)
                        }
                    } else {
                        HutRoom { selected = $0 }
                    }
                    Text("点一件东西，慢慢看。")
                        .font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary)
                }.padding(JournalLayout.gutter)
            }
            .background(theme.pageBackground)
            .font(theme.font.journalBody).foregroundStyle(theme.pageColor.textPrimary).tint(theme.pageAccent)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.accessibilityIdentifier("hut-close") } }
            .refreshable { await model.load() }
            .task { await model.load() }
            .sheet(item: $selected) { object in
                HutObjectSheet(object: object, model: model)
            }
        }
    }
}

private struct HutRoom: View {
    @EnvironmentObject private var theme: Theme
    let open: (HutObject) -> Void
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Path { p in
                    let w = geometry.size.width, h = geometry.size.height
                    p.move(to: CGPoint(x: w * 0.04, y: h * 0.36))
                    p.addLine(to: CGPoint(x: w * 0.04, y: h * 0.06))
                    p.addQuadCurve(to: CGPoint(x: w * 0.96, y: h * 0.06), control: CGPoint(x: w * 0.5, y: -h * 0.06))
                    p.addLine(to: CGPoint(x: w * 0.96, y: h * 0.91))
                    p.move(to: CGPoint(x: w * 0.04, y: h * 0.63))
                    p.addLine(to: CGPoint(x: w * 0.94, y: h * 0.63))
                    p.addLine(to: CGPoint(x: w * 0.87, y: h * 0.40))
                    p.addLine(to: CGPoint(x: w * 0.12, y: h * 0.40))
                    p.closeSubpath()
                    p.move(to: CGPoint(x: w * 0.1, y: h * 0.63))
                    p.addLine(to: CGPoint(x: w * 0.1, y: h * 0.91))
                    p.move(to: CGPoint(x: w * 0.9, y: h * 0.63))
                    p.addLine(to: CGPoint(x: w * 0.9, y: h * 0.95))
                }.stroke(theme.pageColor.separator, lineWidth: JournalLayout.line).accessibilityHidden(true)
                ForEach(HutObject.allCases) { object in
                    Button { open(object) } label: {
                        VStack(spacing: JournalLayout.smallGap) {
                            HutDrawing(object: object)
                                .frame(width: JournalLayout.drawingWidth, height: JournalLayout.drawingHeight)
                            Text(object.rawValue).font(theme.font.journalCaption)
                        }.frame(width: JournalLayout.objectWidth).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityLabel(object.rawValue)
                    .accessibilityIdentifier("hut-" + object.key)
                    .position(x: geometry.size.width * object.position.x, y: geometry.size.height * object.position.y)
                }
            }
        }.aspectRatio(JournalLayout.sceneRatio, contentMode: .fit)
    }
}

private struct HutDrawing: View {
    @EnvironmentObject private var theme: Theme
    let object: HutObject
    var body: some View {
        GeometryReader { g in
            Path { p in
                let w = g.size.width, h = g.size.height
                func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
                func line(_ points: [(CGFloat, CGFloat)]) {
                    guard let first = points.first else { return }
                    p.move(to: point(first.0, first.1))
                    for next in points.dropFirst() { p.addLine(to: point(next.0, next.1)) }
                }
                switch object {
                case .map:
                    line([(0.04,0.20),(0.32,0.10),(0.64,0.20),(0.95,0.09),(0.95,0.78),(0.64,0.90),(0.32,0.80),(0.04,0.90),(0.04,0.20)])
                    line([(0.32,0.10),(0.32,0.80)]); line([(0.64,0.20),(0.64,0.90)])
                    line([(0.14,0.67),(0.38,0.46),(0.61,0.58),(0.82,0.33)])
                case .cairn:
                    p.addEllipse(in: CGRect(x:w*0.08,y:h*0.65,width:w*0.84,height:h*0.26))
                    p.addEllipse(in: CGRect(x:w*0.2,y:h*0.40,width:w*0.64,height:h*0.25))
                    p.addEllipse(in: CGRect(x:w*0.35,y:h*0.17,width:w*0.40,height:h*0.23))
                case .polaroids, .photos:
                    p.addRect(CGRect(x:w*0.18,y:h*0.05,width:w*0.68,height:h*0.85))
                    p.addRect(CGRect(x:w*0.24,y:h*0.12,width:w*0.55,height:h*0.52))
                    line([(0.24,0.6),(0.45,0.33),(0.64,0.56),(0.79,0.4)])
                    if object == .polaroids { line([(0.16,0.2),(0.05,0.87),(0.59,0.98),(0.65,0.9)]) }
                case .facts:
                    p.addRoundedRect(in: CGRect(x:w*0.18,y:h*0.05,width:w*0.66,height:h*0.86), cornerSize: CGSize(width:w*0.06,height:h*0.06))
                    line([(0.3,0.06),(0.3,0.9)]); line([(0.42,0.3),(0.7,0.3)]); line([(0.42,0.42),(0.63,0.42)])
                case .floe:
                    line([(0.08,0.68),(0.26,0.28),(0.47,0.43),(0.60,0.14),(0.91,0.68),(0.08,0.68)])
                    line([(0.04,0.80),(0.35,0.84),(0.66,0.78),(0.97,0.84)])
                case .weather:
                    p.addRoundedRect(in: CGRect(x:w*0.05,y:h*0.02,width:w*0.90,height:h*0.92), cornerSize: CGSize(width:w*0.12,height:h*0.12))
                    line([(0.5,0.02),(0.5,0.94)]); line([(0.05,0.46),(0.95,0.46)])
                    line([(0.06,0.75),(0.31,0.59),(0.58,0.77),(0.8,0.57),(0.94,0.7)])
                    p.addEllipse(in: CGRect(x:w*0.62,y:h*0.16,width:w*0.18,height:h*0.20))
                case .letters:
                    p.addRoundedRect(in: CGRect(x:w*0.07,y:h*0.22,width:w*0.87,height:h*0.65), cornerSize: CGSize(width:w*0.05,height:h*0.05))
                    line([(0.09,0.24),(0.50,0.57),(0.92,0.24)])
                    p.addEllipse(in: CGRect(x:w*0.43,y:h*0.52,width:w*0.15,height:h*0.18))
                }
            }.stroke(theme.pageAccent, style: StrokeStyle(lineWidth: JournalLayout.line, lineCap: .round, lineJoin: .round))
        }.accessibilityHidden(true)
    }
}

private struct HutObjectSheet: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    let object: HutObject
    @ObservedObject var model: HutViewModel
    @AppStorage("hut.letter.draft") private var draft = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JournalLayout.gap) {
                    Text(object.caption).font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary)
                    if let hut = model.hut { content(hut) }
                    else if model.loading { ProgressView("正在打开…") }
                    else { Text(model.error ?? "这件东西还没有打开。") }
                    if model.error != nil { Button("再看一次") { Task { await model.load() } }.disabled(model.loading) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(JournalLayout.gutter)
            }
            .background(theme.pageBackground).font(theme.font.journalBody)
            .foregroundStyle(theme.pageColor.textPrimary).tint(theme.pageAccent)
            .navigationTitle(object.rawValue).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("回山屋") { dismiss() }.accessibilityIdentifier("hut-object-close") } }
            .refreshable { await model.load() }
        }
    }
    @ViewBuilder private func content(_ hut: RemoteHut) -> some View {
        switch object {
        case .map:
            Text("还没结束的事").font(theme.font.journalHeading)
            if hut.open_items.isEmpty { empty }
            ForEach(hut.open_items) { item in entry(item.text, date: item.since, now: nil) }
            Divider()
            Text("地图背面 · 这周了结的").font(theme.font.journalHeading)
            if hut.recently_closed.isEmpty { empty }
            ForEach(hut.recently_closed) { item in entry(item.text, date: item.closed_at, now: item.note) }
        case .cairn: memories(Array(hut.cairn.prefix(5)))
        case .polaroids: memories(hut.polaroids)
        case .facts:
            if hut.fact_book.isEmpty { empty }
            ForEach(Array(hut.fact_book.enumerated()), id: \.offset) { _, category in
                DisclosureGroup("\(category.category) · \(category.count)") { memories(category.items) }
            }
        case .floe:
            if let memory = hut.floe { memories([memory]) } else { empty }
        case .photos:
            if hut.photos.isEmpty { empty }
            ForEach(Array(hut.photos.enumerated()), id: \.offset) { _, photo in
                entry(photo.caption, date: photo.date, now: photo.said)
            }
        case .weather:
            Text(hut.weather.summary).font(theme.font.journalTitle)
            LabeledContent("核对过的小事", value: "\(hut.weather.facts)")
            LabeledContent("留下的话", value: "\(hut.weather.lines)")
            LabeledContent("照片", value: "\(hut.weather.photos)")
            LabeledContent("还有下文", value: "\(hut.weather.open_items)")
            LabeledContent("这周想起", value: "\(hut.weather.recalled_this_week)")
        case .letters:
            TextEditor(text: $draft).frame(minHeight: JournalLayout.letterHeight)
                .scrollContentBackground(.hidden).padding(JournalLayout.smallGap)
                .overlay(RoundedRectangle(cornerRadius: JournalLayout.radius).stroke(theme.pageColor.separator, lineWidth: JournalLayout.line))
                .accessibilityLabel("写给柯的小锁信").accessibilityIdentifier("hut-letter-text")
            Button(model.sending ? "正在放进信箱…" : "写好，锁进去") {
                let sentDraft = draft
                Task { if await model.send(sentDraft), draft == sentDraft { draft = "" } }
            }.disabled(model.sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("hut-letter-send")
            if let error = model.letterError { Text(error).foregroundStyle(theme.pageAccent) }
            if model.letterSent { Text("信放好了，等柯看。") }
            Text("柯下次说话前会看到，回话也会留在这里。")
                .font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary)
            ForEach(hut.letters) { letter in
                VStack(alignment: .leading, spacing: JournalLayout.smallGap) {
                    entry(letter.text, date: letter.created_at, now: nil)
                    if let reply = letter.reply, !reply.isEmpty {
                        Text("柯的回话").font(theme.font.journalCaption)
                        Text(reply).textSelection(.enabled)
                        if let date = letter.replied_at { Text(date).font(theme.font.journalCaption) }
                    } else { Text(letter.status == "answered" ? "柯看过了" : "等柯看").font(theme.font.journalCaption) }
                }
            }
        }
    }
    private var empty: some View { Text("这里还空着，慢慢来。").foregroundStyle(theme.pageColor.textSecondary) }
    private func memories(_ items: [HutMemory]) -> some View {
        VStack(alignment: .leading, spacing: JournalLayout.gap) {
            if items.isEmpty { empty }
            ForEach(Array(items.enumerated()), id: \.offset) { _, memory in entry(memory.text, date: memory.recalled_at ?? memory.date, now: memory.now) }
        }
    }
    private func entry(_ text: String, date: String?, now: String?) -> some View {
        VStack(alignment: .leading, spacing: JournalLayout.smallGap) {
            Text(text).textSelection(.enabled)
            if let date, !date.isEmpty { Text(date).font(theme.font.journalCaption).foregroundStyle(theme.pageColor.textSecondary) }
            if let now, !now.isEmpty { Text("现在 · " + now).font(theme.font.journalCaption) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
