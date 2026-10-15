import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// 101：「我们」页换成 GPT 的「月下游鱼」（Design/KeUs）：寄语 · 这个月 · 也去看看（锦鲤池）。
// 数据全是真的：寄语柯写（小本子 verse），在一起天数和纪念日、排班、月经沿用原来的 UsViewModel / PeriodStore，
// 池子里四个入口：荷包、食单、药盒（小本子）、纸条（便利贴）。底色跟「柯的」同一套四款配色。

struct UsPondView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let line: ChatLine
    @StateObject private var vm: UsViewModel
    @StateObject private var periods: PeriodStore
    @StateObject private var notes: StickyNotesStore
    @StateObject private var book: NotebookStore
    @AppStorage(CamelliaPalette.storageKey) private var savedPalette = CamelliaPalette.defaultPalette.rawValue
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var editDay: PondDay?
    @State private var open: PondEntry?
    @State private var visible = false
    @State private var ripples: [PondRipple] = []
    private var palette: CamelliaPalette { .resolve(savedPalette) }

    init(line: ChatLine) {
        self.line = line
        let api = APIClient(baseURL: line.apiBaseURL)
        _vm = StateObject(wrappedValue: UsViewModel(api: api))
        _periods = StateObject(wrappedValue: PeriodStore(api: api, scope: line.rawValue))
        _notes = StateObject(wrappedValue: StickyNotesStore(api: api, scope: line.rawValue))
        _book = StateObject(wrappedValue: NotebookStore(api: api))
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    verse.padding(.horizontal, 28).padding(.top, 14)
                    calendar.padding(.horizontal, 28).padding(.top, 20)
                    sectionTitle("也去看看", "ALSO HERE").padding(.horizontal, 28).padding(.top, 22)
                    pond(width: geo.size.width)
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
        .background(ZStack {
            palette.paper
            Image("KeUsWater").resizable().scaledToFill().saturation(palette.mistSaturation).opacity(palette.mistOpacity * 0.9)
        }.ignoresSafeArea())
        .foregroundStyle(Ink.primary)
        .task { await load() }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
        .sheet(item: $editDay) { day in daySheet(day.date) }
        .fullScreenCover(item: $open) { entry in page(entry).swipeBackToClose { open = nil; Task { await book.load(); await notes.load() } } }
    }

    private func load() async {
        async let a: Void = vm.loadReminders()
        async let b: Void = periods.load()
        async let c: Void = notes.load()
        async let d: Void = book.load()
        _ = await (a, b, c, d)
    }

    // MARK: 寄语

    private func sectionTitle(_ zh: String, _ en: String) -> some View {
        HStack(spacing: 8) {
            Text(zh).font(Ink.song(15)).tracking(2.5)
            Text("·").font(Ink.song(13))
            Text(en).font(Ink.latin(10)).tracking(2.2)
            Rectangle().fill(Ink.line.opacity(0.8)).frame(height: 0.7)
        }
        .foregroundStyle(Ink.primary)
    }

    private var together: Anniversary? { vm.anniversaries.first { $0.id == "together" } ?? vm.anniversaries.first }

    private var verse: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("寄语", "VERSE")
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(book.snapshot?.verse?.en ?? "With you, even ordinary days shine.")
                        .font(Ink.script(23)).lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.top, 10)
                    Text(book.snapshot?.verse?.zh ?? "和你一起，平常的日子也有光。")
                        .font(Ink.song(15)).tracking(1.2)
                    if let t = together {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("在一起").font(Ink.song(12)).tracking(1.6)
                            Text("\(vm.daysTogether(since: t.date))").font(Ink.latin(17)).monospacedDigit()
                            Text("天").font(Ink.song(12))
                        }.padding(.top, 4)
                    }
                }
                Image("KeUsMoon").resizable().scaledToFit().frame(width: 42, height: 42)
                    .saturation(0.15).opacity(0.55).padding(.top, 34).padding(.trailing, 6)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 这个月

    private var calendar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                sectionTitle("这个月", "NOTRE MOIS")
                Button("写班表") { editDay = PondDay(date: Calendar.current.startOfDay(for: .now)) }
                    .font(Ink.song(11)).tracking(1.4).frame(minHeight: 32)
            }
            HStack {
                Text(vm.monthTitle(for: month)).font(Ink.song(16)).tracking(1.8)
                Spacer()
                Button { month = vm.month(byAdding: -1, to: month) } label: { Image(systemName: "chevron.left").font(.system(size: 16, weight: .ultraLight)).frame(width: 44, height: 40) }
                    .accessibilityLabel("上个月")
                Button { month = vm.month(byAdding: 1, to: month) } label: { Image(systemName: "chevron.right").font(.system(size: 16, weight: .ultraLight)).frame(width: 44, height: 40) }
                    .accessibilityLabel("下个月")
            }.padding(.top, 6)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) {
                    Text($0).font(Ink.song(12)).foregroundStyle(Ink.secondary).frame(height: 26)
                }
                ForEach(Array(vm.monthCells(for: month).enumerated()), id: \.offset) { _, date in
                    if let date { dayCell(date) } else { Color.clear.frame(height: 44) }
                }
            }
            .padding(.top, 2)
            HStack {
                Button { editDay = PondDay(date: Calendar.current.startOfDay(for: .now)) } label: {
                    Text("\(Calendar.current.component(.day, from: .now))日 · 今日记事").font(Ink.song(12)).tracking(0.8)
                }.frame(minHeight: 36)
                Spacer()
                legend(Circle().fill(Ink.accent), "今天")
                legend(Circle().fill(Ink.periodFill), "月经")
                legend(Text("☾").font(.system(size: 11)).foregroundStyle(Ink.accent), "纪念日")
            }
            .padding(.top, 6)
            .overlay(alignment: .top) { Rectangle().fill(Ink.line.opacity(0.5)).frame(height: 0.7) }
            if !vm.isCurrentMonth(month) {
                Button("回到本月") { month = vm.startOfMonth(for: .now) }.font(Ink.song(12)).frame(minHeight: 32)
            }
        }
    }

    private func legend<V: View>(_ mark: V, _ title: String) -> some View {
        HStack(spacing: 4) { mark.frame(width: 7, height: 7); Text(title).font(.system(size: 10)).foregroundStyle(Ink.secondary) }
            .padding(.leading, 8)
    }

    private func dayCell(_ date: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        let period = isPeriod(date)
        let shift = vm.shift(on: date).map { vm.shiftDisplay($0, on: date) }
        return Button { editDay = PondDay(date: date) } label: {
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(Ink.latin(14)).monospacedDigit()
                    .foregroundStyle(isToday ? Color.white : Ink.primary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(isToday ? Ink.accent : (period ? Ink.periodFill : .clear)))
                    .overlay(alignment: .topTrailing) {
                        if isAnniversary(date) { Text("☾").font(.system(size: 10)).foregroundStyle(Ink.accent).offset(x: 7, y: -3) }
                    }
                Text(shift ?? " ").font(Ink.song(9.5)).lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(Ink.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(vm.calendarDayAccessibilityLabel(date) + (period ? "，月经" : "") + (isAnniversary(date) ? "，纪念日" : ""))
        .accessibilityIdentifier(vm.calendarDayIdentifier(date))
    }

    private func isPeriod(_ date: Date) -> Bool {
        let key = HomeReminderCoordinator.dayKey(date)
        return periods.records.contains { $0.start_date <= key && key <= periods.shownEnd(of: $0) }
    }
    private func isAnniversary(_ date: Date) -> Bool {
        let c = Calendar.current
        return vm.anniversaries.contains {
            c.component(.month, from: $0.date) == c.component(.month, from: date) && c.component(.day, from: $0.date) == c.component(.day, from: date)
        }
    }

    /// 点一天：排班（沿用原来的排班编辑），月经来了 / 走了。
    private func daySheet(_ date: Date) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("月经").font(Ink.song(15))
                Spacer()
                PeriodCalendarControls(store: periods)
            }
            .padding(.horizontal, 24).padding(.top, 18)
            ScheduleEditorSheet(model: vm, date: date, currentShift: vm.shift(on: date), currentNote: vm.shiftNote(on: date)) { shift, note in
                vm.setShift(shift, note: note, on: date); editDay = nil
            }
        }
        .presentationDetents([.large])
        .presentationBackground(palette.paper)
    }

    // MARK: 也去看看（锦鲤池）

    private func pond(width: CGFloat) -> some View {
        let height = width * 0.78
        let snap = book.snapshot
        return ZStack(alignment: .topLeading) {
            PondCanvas(paused: !visible || reduceMotion || scenePhase != .active, reduceMotion: reduceMotion, ripples: ripples)
                .frame(width: width, height: height)
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { p in
                    ripples.append(PondRipple(x: p.x / width, y: p.y / height, start: Date()))
                    if ripples.count > 8 { ripples.removeFirst() }
                }
                .accessibilityHidden(true)
            entry(.purse, x: 0.127, y: 0.09, width: width, height: height,
                  badge: snap.map { p in p.purse.cap_cents > 0 ? "还能花 ¥\(max(0, (p.purse.left_cents ?? 0)) / 100)" : "这个月花了 ¥\(p.purse.spent_cents / 100)" })
            entry(.menu, x: 0.66, y: 0.26, width: width, height: height,
                  badge: snap?.menu.meals.first.map { $0.title })
            entry(.notes, x: 0.145, y: 0.47, width: width, height: height,
                  badge: { let n = notes.notes.filter { !$0.acked }.count; return n > 0 ? "\(n) 张贴着" : nil }())
            entry(.meds, x: 0.65, y: 0.68, width: width, height: height,
                  badge: snap.flatMap { s in
                      let left = (s.meds.order ?? []).filter { !(s.meds.today[$0]?.taken ?? false) }
                      return s.meds.rx.isEmpty ? nil : (left.isEmpty ? "今天的都吃了" : "\(left.first!)的还没吃")
                  })
        }
        .frame(width: width, height: height)
    }

    private func entry(_ e: PondEntry, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, badge: String?) -> some View {
        Button { open = e } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title).font(Ink.song(19)).tracking(2.5).shadow(color: .white, radius: 6)
                Rectangle().fill(Ink.accent.opacity(0.7)).frame(width: 9, height: 0.7).padding(.vertical, 3)
                Text(e.sub).font(Ink.latin(12)).italic().foregroundStyle(Ink.accent)
                if let badge { Text(badge).font(.system(size: 10.5)).foregroundStyle(Ink.secondary).padding(.top, 2) }
                Text(e.title).font(Ink.song(16)).tracking(2.5)
                    .scaleEffect(x: 1, y: -0.65).opacity(0.12).blur(radius: 0.4)
                    .accessibilityHidden(true)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: x * width, y: y * height)
        .accessibilityLabel(e.title + (badge.map { "，" + $0 } ?? ""))
        .accessibilityIdentifier("us-entry-\(e.rawValue)")
    }

    @ViewBuilder private func page(_ e: PondEntry) -> some View {
        let close = { open = nil; Task { await book.load(); await notes.load() } }
        switch e {
        case .purse: PursePage(store: book, paper: palette.paper, onClose: close)
        case .menu: MenuPage(store: book, paper: palette.paper, onClose: close)
        case .meds: MedsPage(store: book, paper: palette.paper, onClose: close)
        case .notes: NotesPage(notes: notes, api: book.api, paper: palette.paper, onClose: close)
        }
    }
}

struct PondDay: Identifiable { let date: Date; var id: Date { date } }

enum PondEntry: String, Identifiable {
    case purse, menu, notes, meds
    var id: String { rawValue }
    var title: String { ["purse": "荷包", "menu": "食单", "notes": "纸条", "meds": "药盒"][rawValue]! }
    var sub: String { ["purse": "Bourse", "menu": "Menu", "notes": "Billets", "meds": "Remèdes"][rawValue]! }
}

struct PondRipple: Equatable { let x: CGFloat; let y: CGFloat; let start: Date }

// MARK: - 锦鲤池画布

/// 两条锦鲤沿脊线摆尾（照 Design/KeUs/fish-motion.js：头先转、肩轻摆、尾巴一波一波往后传，推一下滑一段），
/// 花瓣落到水上漾开一圈，点水面也漾一圈。鱼图事先切成一条一条，每帧只做斜切，不重画整张图。
struct PondCanvas: View {
    let paused: Bool
    let reduceMotion: Bool
    let ripples: [PondRipple]

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: paused)) { timeline in
            Canvas(rendersAsynchronously: false) { ctx, size in
                draw(&ctx, size: size, now: timeline.date)
            }
        }
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, now: Date) {
        let t = reduceMotion ? 12.0 : now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
        for index in 0..<2 { fish(&ctx, index: index, t: t, size: size) }
        petals(&ctx, t: t, size: size)
        for r in ripples {
            let age = now.timeIntervalSince(r.start)
            guard age >= 0, age < 3.4 else { continue }
            ring(&ctx, at: CGPoint(x: r.x * size.width, y: r.y * size.height), age: age, duration: 3.4)
        }
    }

    private func ring(_ ctx: inout GraphicsContext, at p: CGPoint, age: Double, duration: Double) {
        for k in 0..<2 {
            let a = age - Double(k) * 0.45
            guard a > 0 else { continue }
            let f = a / duration, rad = 8 + 46 * f
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - rad, y: p.y - rad * 0.42, width: rad * 2, height: rad * 0.84)),
                       with: .color(Color.white.opacity(0.75 * (1 - f))), lineWidth: 1)
        }
    }

    // —— 鱼 ——
    private static let slices = 24
    private static let strips: [Image] = {
        #if canImport(UIKit)
        guard let cg = UIImage(named: "KeUsKoi")?.cgImage else { return [] }
        let h = cg.height / slices
        return (0..<slices).compactMap { j in
            cg.cropping(to: CGRect(x: 0, y: j * h, width: cg.width, height: j == slices - 1 ? cg.height - j * h : h + 1))
                .map { Image(decorative: $0, scale: 1) }
        }
        #else
        return []
        #endif
    }()
    private static let aspect: CGFloat = 853.0 / 1844.0

    private struct Point { var x: Double; var y: Double }
    private static func position(_ t: Double, _ i: Int) -> Point {
        let fq = i == 1 ? 0.61 : 0.73, r = t * fq + Double(i) * 2.3
        let a = t * (i == 1 ? 0.082 : 0.088) + 0.035 * sin(r) + 0.008 * sin(2 * r) + 0.4 + Double(i) * 2.8
        let rx = 0.215 + 0.025 * sin(t * 0.11 + Double(i)), ry = 0.265 + 0.025 * cos(t * 0.095 + Double(i) * 1.7)
        return Point(x: 0.51 + rx * cos(a) + 0.022 * sin(2 * a + 0.2), y: 0.49 + ry * sin(a) + 0.024 * cos(2 * a))
    }

    private func fish(_ ctx: inout GraphicsContext, index i: Int, t: Double, size: CGSize) {
        let strips = Self.strips
        guard strips.count == Self.slices else { return }
        let W = Double(size.width), H = Double(size.height)
        let length = W * (i == 1 ? 0.235 : 0.28), breadthBase = length * Self.aspect
        let p = Self.position(t, i), q = Self.position(t + 0.12, i), ahead = Self.position(t + 1.2, i)
        let heading = atan2((q.y - p.y) * H, (q.x - p.x) * W)
        let next = atan2((ahead.y - q.y) * H, (ahead.x - q.x) * W)
        let turn = atan2(sin(next - heading), cos(next - heading))
        let r = t * (i == 1 ? 0.61 : 0.73) + Double(i) * 2.3
        let effort = 0.13 + 0.87 * pow((1 + cos(r)) / 2, 3)
        let beat = t * (i == 1 ? 2.48 : 2.72) + 0.28 * sin(r) + Double(i) * 1.9
        let nose = turn * 0.65 + (0.065 + 0.145 * effort) * sin(beat + 0.4)
        let n = Self.slices
        var points = [Point(x: 0, y: 0)]
        for j in 1...n {
            let f = (Double(j) - 0.5) / Double(n)
            let tail = max(0, (f - 0.18) / 0.82)
            let amp = (0.03 + 0.98 * pow(tail, 1.7)) * (0.24 + 0.76 * effort)
            let headArc = 0.27 * (0.45 + 0.55 * effort) * exp(-pow((f - 0.12) / 0.2, 2)) * sin(beat + 0.85)
            let bend = headArc + amp * sin(beat - tail * 4.6) - turn * tail * 2.1
            let prev = points[j - 1], step = length / Double(n)
            points.append(Point(x: prev.x + sin(bend) * step, y: prev.y + cos(bend) * step))
        }
        let anchor = points[Int((Double(n) * 0.32).rounded())]
        var g = ctx
        g.opacity = i == 1 ? 0.77 : 0.86
        g.translateBy(x: p.x * W, y: p.y * H)
        g.rotate(by: .radians(heading + .pi / 2 + nose))
        let dh = length / Double(n)
        for j in 0..<n {
            let a = Point(x: points[j].x - anchor.x, y: points[j].y - anchor.y)
            let b = Point(x: points[j + 1].x - anchor.x, y: points[j + 1].y - anchor.y)
            let f = Double(j) / Double(n)
            let fins = exp(-pow((f - 0.31) / 0.09, 2))
            let breadth = breadthBase * (1 + fins * 0.045 * sin(beat - 0.8))
            var s = g
            s.concatenate(CGAffineTransform(a: 1, b: 0, c: (b.x - a.x) / dh, d: (b.y - a.y) / dh, tx: a.x, ty: a.y))
            s.draw(strips[j], in: CGRect(x: -breadth / 2, y: 0, width: breadth, height: dh + 0.6))
        }
    }

    // —— 花瓣：沿错开的弧线飘下来，落水漾一圈，漂一会儿淡掉 ——
    private static let routes: [[(Double, Double)]] = [
        [(0.18, -0.08), (0.08, 0.22), (0.30, 0.38)], [(0.82, -0.08), (0.95, 0.18), (0.72, 0.30)],
        [(0.55, -0.08), (0.40, 0.25), (0.48, 0.56)], [(0.30, -0.08), (0.22, 0.40), (0.38, 0.82)],
        [(0.92, -0.06), (0.80, 0.45), (0.86, 0.62)]
    ]
    private func petals(_ ctx: inout GraphicsContext, t: Double, size: CGSize) {
        guard !reduceMotion else { return }
        let gap = 3.1, fall = 5.2, rest = 6.0, fade = 2.4, total = fall + rest + fade
        let newest = Int(floor(t / gap))
        let image = Image("KeUsPetal")
        for k in 0..<Int(ceil(total / gap)) {
            let n = newest - k, age = t - Double(n) * gap
            guard age >= 0, age < total else { continue }
            let route = Self.routes[((n % 5) + 5) % 5]
            let f = min(age / fall, 1), e = f * f * (3 - 2 * f), one = 1 - e
            let x = one * one * route[0].0 + 2 * one * e * route[1].0 + e * e * route[2].0 + sin(age * 1.7 + Double(n)) * 0.007 * (1 - e)
            let y = one * one * route[0].1 + 2 * one * e * route[1].1 + e * e * route[2].1
            let landed = max(0, age - fall)
            let opacity = 0.75 * min(1, age / 2) * (1 - max(0, min(1, (age - fall - rest) / fade)))
            let p = CGPoint(x: x * size.width + sin(landed * 0.25) * 2, y: y * size.height)
            if landed > 0 && landed < 3.6 { ring(&ctx, at: p, age: landed, duration: 4.2) }
            var g = ctx
            g.opacity = opacity
            g.translateBy(x: p.x, y: p.y)
            g.rotate(by: .degrees(Double(n * 47 % 360) + age * (landed > 0 ? 2 : 28)))
            let w = size.width * (0.05 + Double(n % 3) * 0.008)
            g.draw(image, in: CGRect(x: -w / 2, y: -w / 2, width: w, height: w))
        }
    }
}
