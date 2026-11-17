import SwiftUI
import UIKit

// 11-17 她：「加一个转盘放在塔罗下面，颜色搞成我们 App 那种淡淡的，转动有传感反应，这些都可以修改」
// 「不一定是 2 个，可以今天吃什么：寿司、川菜、早茶……」「柯也知道，也可以他帮我转，我能看到」。
// 转盘存在服务器（/api/wheels），柯看的是同一份：她转出来的记一笔，柯知道；柯替她转的（spin_wheel），
// 她打开这页时重放那一转、停在那一格。转的时候每过一格轻轻震一下，停下来再震一下。

struct WheelOption: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var title: String
    var weight = 1
    var tone = 0
}

struct Wheel: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var question: String
    var options: [WheelOption]
}

struct WheelSpin: Codable, Identifiable, Hashable {
    let id: String
    let wheel_id: String
    let question: String
    let option_id: String
    let result: String
    let by: String
    let at: String
}

struct WheelSnapshot: Codable {
    var wheels: [Wheel]
    var spins: [WheelSpin]
}

/// 转盘的几种淡颜色，跟 App 的纸和山茶一套
enum WheelTone {
    static let colors: [Color] = [
        Color(hex: 0xF3DDE4), Color(hex: 0xE8E0EE), Color(hex: 0xE2ECE5), Color(hex: 0xF3E6D6),
        Color(hex: 0xDFE8F1), Color(hex: 0xF5E1D8), Color(hex: 0xEDE6DA), Color(hex: 0xE6DDE8),
    ]
    static func color(_ tone: Int) -> Color { colors[((tone % colors.count) + colors.count) % colors.count] }
}

@MainActor final class WheelStore: ObservableObject {
    static let shared = WheelStore()

    @Published private(set) var wheels: [Wheel] = []
    @Published private(set) var spins: [WheelSpin] = []
    @Published var currentID: String {
        didSet { defaults.set(currentID, forKey: "wheel.current") }
    }
    @Published private(set) var error: String?
    private let defaults = UserDefaults.standard
    private let cacheKey = "wheel.snapshot"
    private lazy var api = APIClient(baseURL: ChatLine.allCases.first?.apiBaseURL ?? AppConfiguration.apiBaseURL)

    init() {
        currentID = defaults.string(forKey: "wheel.current") ?? ""
        if let data = defaults.data(forKey: cacheKey), let saved = try? JSONDecoder().decode(WheelSnapshot.self, from: data) {
            wheels = saved.wheels; spins = saved.spins
        }
    }

    var current: Wheel? { wheels.first { $0.id == currentID } ?? wheels.first }

    /// 柯替她转的、她还没看过的那一转
    var unseenKeSpin: WheelSpin? {
        guard let last = spins.last(where: { $0.by == "ke" }), last.id != defaults.string(forKey: "wheel.seenSpin") else { return nil }
        return last
    }
    func markSeen(_ spin: WheelSpin) { defaults.set(spin.id, forKey: "wheel.seenSpin") }

    func load() async {
        do {
            apply(try await api.fetchWheels())
            error = nil
        } catch {
            if wheels.isEmpty { self.error = "转盘没拉下来，过会儿再试" }
        }
    }

    /// 改完整份送上去（先在手机上改好，不等网）
    func save(_ updated: [Wheel]) async {
        let before = wheels
        wheels = updated
        do {
            apply(try await api.saveWheels(updated))
            error = nil
        } catch {
            wheels = before
            self.error = "没存上，再试一次"
        }
    }

    func update(_ wheel: Wheel) async {
        var all = wheels
        if let i = all.firstIndex(where: { $0.id == wheel.id }) { all[i] = wheel } else { all.append(wheel) }
        currentID = wheel.id
        await save(all)
    }

    func remove(_ id: String) async {
        await save(wheels.filter { $0.id != id })
        if currentID == id { currentID = wheels.first?.id ?? "" }
    }

    func logSpin(_ wheel: Wheel, _ option: WheelOption) async {
        try? await api.logWheelSpin(wheelID: wheel.id, optionID: option.id)
        await load()
    }

    private func apply(_ snapshot: WheelSnapshot) {
        wheels = snapshot.wheels; spins = snapshot.spins
        if !wheels.contains(where: { $0.id == currentID }) { currentID = wheels.first?.id ?? "" }
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: cacheKey) }
    }
}

// MARK: - 一个转盘怎么分格

struct WheelLayout {
    /// 每格从正上方顺时针量的起止角（度）
    let spans: [(start: Double, end: Double)]

    init(_ options: [WheelOption]) {
        let total = Double(max(1, options.reduce(0) { $0 + max(1, $1.weight) }))
        var at = 0.0
        spans = options.map { o in
            let width = 360 * Double(max(1, o.weight)) / total
            defer { at += width }
            return (at, at + width)
        }
    }

    /// 转了 rotation 度以后，指针（正上方）指着第几格
    func index(at rotation: Double) -> Int? {
        guard !spans.isEmpty else { return nil }
        let a = ((-rotation).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return spans.firstIndex { a >= $0.start && a < $0.end } ?? spans.count - 1
    }

    /// 要停在第 i 格（格子里随机一处），从 current 起至少多转几圈
    func target(for i: Int, from current: Double, turns: Int = 6) -> Double {
        let s = spans[i]
        let a = s.start + (s.end - s.start) * Double.random(in: 0.18...0.82)
        let delta = ((-a - current).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return current + Double(turns * 360) + delta
    }

    static func pick(_ options: [WheelOption]) -> Int? {
        guard !options.isEmpty else { return nil }
        var r = Double.random(in: 0..<Double(options.reduce(0) { $0 + max(1, $1.weight) }))
        for (i, o) in options.enumerated() {
            r -= Double(max(1, o.weight))
            if r < 0 { return i }
        }
        return options.count - 1
    }
}

private struct WheelDisc: View {
    let options: [WheelOption]

    var body: some View {
        Canvas { context, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let layout = WheelLayout(options)
            let fontSize = max(11, min(17, 150 / Double(max(1, options.count)) + 8))
            for (i, o) in options.enumerated() {
                let s = layout.spans[i]
                var wedge = Path()
                wedge.move(to: c)
                wedge.addArc(center: c, radius: r, startAngle: .degrees(s.start - 90), endAngle: .degrees(s.end - 90), clockwise: false)
                wedge.closeSubpath()
                context.fill(wedge, with: .color(WheelTone.color(o.tone)))
                context.stroke(wedge, with: .color(.white.opacity(0.9)), lineWidth: 1)
                var label = context
                label.translateBy(x: c.x, y: c.y)
                label.rotate(by: .degrees((s.start + s.end) / 2))
                label.draw(Text(o.title).font(.custom("NotoSerifSC-Regular", size: fontSize)).foregroundColor(Ink.primary),
                           at: CGPoint(x: 0, y: -r * 0.66), anchor: .center)
            }
            context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                           with: .color(Ink.line), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// 正中那颗：圆钮 + 朝上的尖，指着转到的那一格
private struct WheelHub: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.width / 2, c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        p.move(to: CGPoint(x: c.x - r * 0.32, y: c.y - r * 0.9))
        p.addLine(to: CGPoint(x: c.x, y: c.y - r * 1.32))
        p.addLine(to: CGPoint(x: c.x + r * 0.32, y: c.y - r * 0.9))
        p.closeSubpath()
        return p
    }
}

// MARK: - 转盘页

struct WheelView: View {
    var onClose: () -> Void
    @StateObject private var store = WheelStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation = 0.0
    @State private var spinning = false
    @State private var result: String?
    @State private var resultByKe = false
    @State private var editing: Wheel?
    @State private var listOpen = false
    @State private var dragLast: Double?
    @State private var lastTick: Int?
    private let ticker = UIImpactFeedbackGenerator(style: .light)
    private var paper: Color { CamelliaPalette.stored().paper }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width - 48, geo.size.height * 0.5, 360)
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 12)
                Text(store.current?.question ?? "转盘").font(Ink.song(22)).tracking(1.5).foregroundStyle(Ink.primary)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
                    .accessibilityAddTraits(.isHeader)
                Text(result ?? "？？？").font(Ink.song(30)).foregroundStyle(result == nil ? Ink.secondary : Ink.accent)
                    .padding(.top, 10).contentTransition(.opacity)
                    .accessibilityLabel(result.map { "转到了 \($0)" } ?? "还没转")
                Text(resultByKe ? "柯替你转的" : " ").font(Ink.song(12)).foregroundStyle(Ink.secondary).padding(.top, 4)
                Spacer(minLength: 16)
                wheel(side: side)
                Spacer(minLength: 16)
                bottomBar
            }
            .frame(maxWidth: .infinity)
        }
        .background(paper.ignoresSafeArea())
        .task {
            ticker.prepare()
            await store.load()
            replayKeSpin()
        }
        .sheet(item: $editing) { wheel in
            WheelEditor(wheel: wheel, canDelete: store.wheels.count > 1) { saved in
                Task { await store.update(saved) }
                resetWheel()
            } onDelete: { id in
                Task { await store.remove(id) }
                resetWheel()
            }
        }
        .sheet(isPresented: $listOpen) { listSheet }
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .light))
                    .frame(width: 44, height: 44, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("返回").accessibilityIdentifier("wheel-close")
            Spacer()
            Button { listOpen = true } label: {
                Image(systemName: "square.grid.2x2").font(.system(size: 18, weight: .light))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("换一个转盘")
        }
        .foregroundStyle(Ink.primary)
        .padding(.horizontal, 20).padding(.top, 6)
    }

    private func wheel(side: CGFloat) -> some View {
        let options = store.current?.options ?? []
        return ZStack {
            if options.isEmpty {
                Circle().stroke(Ink.line, lineWidth: 1)
                Text("先加几个选项").font(Ink.song(15)).foregroundStyle(Ink.secondary)
            } else {
                WheelDisc(options: options).rotationEffect(.degrees(rotation))
            }
            WheelHub().fill(paper).frame(width: side * 0.26, height: side * 0.26)
                .shadow(color: Ink.primary.opacity(0.12), radius: 6, y: 2)
            Circle().stroke(Ink.line, lineWidth: 1.2).frame(width: side * 0.13, height: side * 0.13)
            Button { spin() } label: {
                Text("转").font(Ink.song(17)).foregroundStyle(Ink.accent)
                    .frame(width: side * 0.26, height: side * 0.26).contentShape(Circle())
            }
            .buttonStyle(.plain).disabled(spinning || options.isEmpty)
            .accessibilityLabel("转一下").accessibilityIdentifier("wheel-spin")
        }
        .frame(width: side, height: side)
        .contentShape(Circle())
        .gesture(dragToSpin(side: side, options: options))
    }

    private var bottomBar: some View {
        HStack {
            Button { resetWheel() } label: {
                Text("还原").font(Ink.song(15)).padding(.horizontal, 22).frame(minHeight: 44)
                    .overlay(Capsule().stroke(Ink.line, lineWidth: 0.8)).contentShape(Capsule())
            }
            .buttonStyle(.plain).disabled(spinning)
            Spacer()
            Button { if let w = store.current { editing = w } } label: {
                Label("改一改", systemImage: "square.and.pencil").font(Ink.song(15)).padding(.horizontal, 18).frame(minHeight: 44)
                    .overlay(Capsule().stroke(Ink.line, lineWidth: 0.8)).contentShape(Capsule())
            }
            .buttonStyle(.plain).disabled(spinning || store.current == nil)
            .accessibilityIdentifier("wheel-edit")
        }
        .foregroundStyle(Ink.primary)
        .padding(.horizontal, 28).padding(.bottom, 24)
    }

    // MARK: 转

    /// 手指拖着转：跟着手走、每过一格震一下；甩出去就真转
    private func dragToSpin(side: CGFloat, options: [WheelOption]) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                guard !spinning, !options.isEmpty else { return }
                let c = CGPoint(x: side / 2, y: side / 2)
                let a = atan2(v.location.y - c.y, v.location.x - c.x) * 180 / .pi
                if let last = dragLast {
                    var d = a - last
                    if d > 180 { d -= 360 } else if d < -180 { d += 360 }
                    rotation += d
                    tick(options)
                }
                dragLast = a
            }
            .onEnded { v in
                dragLast = nil
                let speed = hypot(v.predictedEndTranslation.width - v.translation.width,
                                  v.predictedEndTranslation.height - v.translation.height)
                if speed > 120 { spin() }
            }
    }

    private func tick(_ options: [WheelOption]) {
        let i = WheelLayout(options).index(at: rotation)
        if i != lastTick {
            lastTick = i
            ticker.impactOccurred(intensity: 0.7)
        }
    }

    private func spin() {
        guard let wheel = store.current, let winner = WheelLayout.pick(wheel.options) else { return }
        run(wheel, winner: winner, byKe: false)
    }

    /// 柯替她转、她还没看过的：打开这页时把那一转放一遍
    private func replayKeSpin() {
        guard let spin = store.unseenKeSpin, let wheel = store.wheels.first(where: { $0.id == spin.wheel_id }),
              let i = wheel.options.firstIndex(where: { $0.id == spin.option_id }) else { return }
        store.markSeen(spin)
        store.currentID = wheel.id
        run(wheel, winner: i, byKe: true)
    }

    private func run(_ wheel: Wheel, winner: Int, byKe: Bool) {
        let layout = WheelLayout(wheel.options)
        let start = rotation, end = layout.target(for: winner, from: rotation)
        spinning = true
        withAnimation(.easeOut(duration: 0.2)) { result = nil; resultByKe = false }
        Task { @MainActor in
            if !reduceMotion {
                let duration = 4.2, began = Date()
                while true {
                    let p = min(1, Date().timeIntervalSince(began) / duration)
                    rotation = start + (end - start) * (1 - pow(1 - p, 4))   // 越转越慢
                    tick(wheel.options)
                    if p >= 1 { break }
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
            rotation = end
            spinning = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                result = wheel.options[winner].title
                resultByKe = byKe
            }
            if !byKe { await store.logSpin(wheel, wheel.options[winner]) }   // 柯就知道她转到了什么
        }
    }

    private func resetWheel() {
        guard !spinning else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) { rotation = 0; result = nil; resultByKe = false }
    }

    // MARK: 好几个转盘

    private var listSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.wheels) { w in
                        Button {
                            store.currentID = w.id; listOpen = false; resetWheel()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(w.question).font(Ink.song(16)).foregroundStyle(Ink.primary)
                                    if w.id == store.current?.id { Image(systemName: "checkmark").font(.footnote).foregroundStyle(Ink.accent) }
                                }
                                Text(w.options.map(\.title).joined(separator: "、")).font(Ink.song(12)).foregroundStyle(Ink.secondary).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        listOpen = false
                        editing = Wheel(question: "", options: [WheelOption(title: "", tone: 0), WheelOption(title: "", tone: 1)])
                    } label: {
                        Label("新建一个转盘", systemImage: "plus").font(Ink.song(15)).foregroundStyle(Ink.accent)
                    }
                    .buttonStyle(.plain)
                }
                if !store.spins.isEmpty {
                    Section("最近转到的") {
                        ForEach(Array(store.spins.suffix(8).reversed())) { s in
                            HStack {
                                Text("\(s.question) → \(s.result)").font(Ink.song(14)).foregroundStyle(Ink.primary)
                                Spacer()
                                Text((s.by == "ke" ? "柯转的 · " : "") + String(s.at.dropFirst(5).prefix(11)))
                                    .font(Ink.song(11)).foregroundStyle(Ink.secondary)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(paper)
            .navigationTitle("转盘").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("好了") { listOpen = false } } }
        }
        .tint(Ink.accent)
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 改转盘

struct WheelEditor: View {
    @State var wheel: Wheel
    let canDelete: Bool
    var onSave: (Wheel) -> Void
    var onDelete: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var batchOpen = false
    @State private var batchText = ""
    @State private var confirmDelete = false

    private var total: Int { max(1, wheel.options.reduce(0) { $0 + max(1, $1.weight) }) }
    private var cleaned: Wheel {
        var w = wheel
        w.question = w.question.trimmingCharacters(in: .whitespacesAndNewlines)
        w.options = w.options.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        return w
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("问题") {
                    TextField("比如：今天吃什么", text: $wheel.question).font(Ink.song(16))
                }
                Section("选项（\(wheel.options.count)）") {
                    ForEach($wheel.options) { $o in
                        HStack(spacing: 10) {
                            Button { o.tone = (o.tone + 1) % WheelTone.colors.count } label: {
                                Circle().fill(WheelTone.color(o.tone)).frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(Ink.line, lineWidth: 0.6))
                                    .frame(width: 36, height: 36).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).accessibilityLabel("换个颜色")
                            TextField("选项", text: $o.title).font(Ink.song(15))
                            Text("\(Int((Double(max(1, o.weight)) / Double(total) * 100).rounded()))%")
                                .font(Ink.song(12)).foregroundStyle(Ink.secondary).monospacedDigit().frame(minWidth: 36)
                            Stepper("权重", value: $o.weight, in: 1...10).labelsHidden()
                        }
                    }
                    .onDelete { wheel.options.remove(atOffsets: $0) }
                    Button {
                        wheel.options.append(WheelOption(title: "", tone: wheel.options.count % WheelTone.colors.count))
                    } label: { Label("添加选项", systemImage: "plus.circle") }
                    Button { batchOpen = true } label: { Label("一次加好几个", systemImage: "text.badge.plus") }
                }
                if canDelete {
                    Section {
                        Button("删掉这个转盘", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .font(Ink.song(15))
            .scrollContentBackground(.hidden)
            .background(CamelliaPalette.stored().paper)
            .navigationTitle(wheel.question.isEmpty ? "新转盘" : "改转盘").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("好了") { onSave(cleaned); dismiss() }
                        .disabled(cleaned.question.isEmpty || cleaned.options.count < 2)
                }
            }
            .alert("一次加好几个", isPresented: $batchOpen) {
                TextField("寿司、川菜、早茶", text: $batchText)
                Button("加上") {
                    let titles = batchText.split(whereSeparator: { "、,，;；\n ".contains($0) }).map(String.init)
                    for t in titles where !t.isEmpty {
                        wheel.options.append(WheelOption(title: t, tone: wheel.options.count % WheelTone.colors.count))
                    }
                    batchText = ""
                }
                Button("取消", role: .cancel) { batchText = "" }
            } message: {
                Text("用顿号或逗号隔开")
            }
            .confirmationDialog("删掉这个转盘？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删掉", role: .destructive) { onDelete(wheel.id); dismiss() }
            }
        }
        .tint(Ink.accent)
        .foregroundStyle(Ink.primary)
    }
}
