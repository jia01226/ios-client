import SwiftUI
import SceneKit

// 95：记忆星河的页面。上面是标题、15 号花体、分类；中间是 3D 星河；下面是「查看 N 颗记忆」。
// 点一颗星：镜头飞过去，卡片浮上来，可以喜欢、记错了、上一颗/下一颗。永远是夜。

struct MemoryGalaxyView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: MemoryGardenStore
    @Binding var page: Int
    @State private var world = GalaxyWorld()
    @State private var includeOthers = false
    @State private var category: String?
    @State private var selectedID: String?
    @State private var listOpen = false
    @State private var dimmedOpen = false
    @State private var correcting: MemoryFlower?
    @State private var note = ""
    @State private var toast = false
    @State private var meteors = GalaxyMeteors()
    @State private var visible = false
    @AppStorage("memory.galaxy.lastSeen") private var lastSeen = ""

    private static let ink = Color(red: 0.945, green: 0.94, blue: 0.93)
    private static let muted = Color(red: 0.72, green: 0.74, blue: 0.81)
    private static let line = Color(red: 0.76, green: 0.8, blue: 0.87).opacity(0.2)
    private static let rose = Color(red: 0.89, green: 0.66, blue: 0.72)

    private var mine: [MemoryFlower] {
        store.visible(includeOthers: false).sorted { ($0.occurred_at ?? $0.written_at ?? "") < ($1.occurred_at ?? $1.written_at ?? "") }
    }
    private var others: [MemoryFlower] { store.visible(includeOthers: true).filter { $0.author != "ke" } }
    private var ordered: [MemoryFlower] { mine.filter { category == nil || $0.category == category } }
    private var selected: MemoryFlower? { selectedID.flatMap { id in store.flowers.first { $0.id == id } } }
    private var categories: [String] {
        let used = Set(mine.map(\.category))
        return store.categories.filter { used.contains($0) }
    }

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.027, blue: 0.05).ignoresSafeArea()
            SceneView(scene: world.scene, pointOfView: world.cameraNode, options: [.rendersContinuously],
                      preferredFramesPerSecond: 60, antialiasingMode: .multisampling2X, delegate: world)
                .ignoresSafeArea()
                .gesture(
                    SimultaneousGesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { world.drag($0.translation) }
                            .onEnded { v in
                                world.endGesture(fling: CGSize(width: v.predictedEndTranslation.width - v.translation.width,
                                                               height: v.predictedEndTranslation.height - v.translation.height))
                            },
                        MagnifyGesture()
                            .onChanged { world.pinch($0.magnification) }
                            .onEnded { _ in world.endGesture() }
                    )
                )
                .onTapGesture(coordinateSpace: .local) { tapped($0) }
                .accessibilityElement()
                .accessibilityLabel("记忆星河，\(ordered.count) 颗记忆")
                .accessibilityHint("用下面的「查看记忆」按列表一条一条读")
            GalaxyMeteorLayer(meteors: meteors, world: world, paused: !visible || reduceMotion)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                if selected == nil { footer }
            }
            if let flower = selected {
                VStack { Spacer(); card(flower) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            overlays
            Text("柯记下了一件新的事")
                .font(.custom("NotoSerifSC-Regular", size: 14, relativeTo: .subheadline)).tracking(4)
                .foregroundStyle(Color(red: 0.94, green: 0.88, blue: 0.73))
                .shadow(color: Color(red: 0.94, green: 0.88, blue: 0.73).opacity(0.55), radius: 14)
                .opacity(toast ? 1 : 0)
                .frame(maxHeight: .infinity, alignment: .top).padding(.top, 220)
                .allowsHitTesting(false)
                .accessibilityHidden(!toast)
        }
        .foregroundStyle(Self.ink)
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.88), value: selectedID)
        .sensoryFeedback(.selection, trigger: selectedID)
        .task { world.reduceMotion = reduceMotion; await store.load() }
        .onAppear { visible = true; sync() }
        .onDisappear { visible = false }
        .onChange(of: store.flowers) { _, _ in sync() }
        .onChange(of: includeOthers) { _, on in world.showOthers = on; sync() }
        .onChange(of: category) { _, c in selectedID = nil; world.filter(c) }
        .onChange(of: selectedID) { _, id in world.select(id) }
        .sheet(isPresented: $listOpen) { memoryList }
        .sheet(isPresented: $dimmedOpen) { dimmedList }
        .alert("这件事记错了吗？", isPresented: Binding(get: { correcting != nil }, set: { if !$0 { correcting = nil } })) {
            TextField("哪里错了，可以留空", text: $note)
            Button("取消", role: .cancel) { correcting = nil }
            Button("确认记错了", role: .destructive) {
                guard let flower = correcting else { return }
                correcting = nil
                Task { if await store.change(flower, action: "wither", note: note) { selectedID = nil } }
            }
        } message: { Text("会告诉柯不再记起这件事。这颗星会熄灭，点错了可以从「熄灭的星」重新点亮。") }
    }

    // MARK: 上面

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("记忆").font(.custom("NotoSerifSC-Regular", size: 28, relativeTo: .title)).tracking(3.4)
                Spacer()
                Button("语录") { page = 1 }
                    .font(.system(size: 13)).foregroundStyle(Self.muted)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("memory-quotes")
                Menu {
                    Toggle("以前整理的", isOn: $includeOthers)
                    Button("熄灭的星") { dimmedOpen = true }
                    Button("看一颗流星") { meteors.ambient(now: Date()) }
                    Button("回到最初视角") { selectedID = nil; category = nil; world.goHome() }
                    Button("刷新") { Task { await store.load() } }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("星河设置")
                .accessibilityIdentifier("memory-menu")
                .padding(.trailing, -10)
            }
            Text("A small universe of us")
                .font(.custom("PinyonScript-Regular", size: 36, relativeTo: .largeTitle))
                .foregroundStyle(Color(red: 0.93, green: 0.93, blue: 0.95))
                .lineLimit(1).fixedSize()
                .transformEffect(CGAffineTransform(a: 0.9, b: 0, c: -0.287, d: 1, tx: 14, ty: 0))
                .padding(.top, 4).padding(.bottom, 2)
                .accessibilityHidden(true)
            Text("\(Self.monthName())的星河 · \(ordered.count) 颗记忆")
                .font(.system(size: 12)).tracking(1.3).foregroundStyle(Self.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    categoryButton(nil, "全部")
                    ForEach(categories, id: \.self) { categoryButton($0, $0) }
                }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 26).padding(.top, 8).padding(.bottom, 18)
        .background(LinearGradient(colors: [Color(red: 0.02, green: 0.027, blue: 0.05).opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea(edges: .top).allowsHitTesting(false))
    }

    private func categoryButton(_ key: String?, _ title: String) -> some View {
        let on = category == key
        return Button { category = key } label: {
            Text(title).font(.system(size: 12)).tracking(1)
                .foregroundStyle(on ? Color(red: 0.95, green: 0.93, blue: 0.92) : Self.muted)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(red: 0.84, green: 0.74, blue: 0.77)).frame(height: 1).opacity(on ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("memory-category-\(title)")
    }

    // MARK: 下面

    private var footer: some View {
        VStack(spacing: 14) {
            Text(mine.isEmpty ? " " : "带名字的亮星是记忆，其余是星尘 · 轻拖漫游 · 点亮星读记忆")
                .font(.system(size: 11)).tracking(0.4).foregroundStyle(Self.muted)
                .multilineTextAlignment(.center)
            HStack {
                Text(includeOthers ? "含以前整理的 \(others.count) 颗" : "柯亲手记下")
                    .font(.system(size: 11)).tracking(1.3).foregroundStyle(Self.muted)
                Spacer()
                Button { listOpen = true } label: {
                    HStack(spacing: 4) { Text("查看 \(ordered.count) 颗记忆"); Image(systemName: "chevron.right").font(.system(size: 11)) }
                        .font(.system(size: 13)).frame(minHeight: 44)
                }
                .accessibilityIdentifier("memory-list")
            }
            .padding(.top, 8)
            .overlay(alignment: .top) { Rectangle().fill(Self.line).frame(height: 1) }
        }
        .padding(.horizontal, 26).padding(.top, 28).padding(.bottom, 10)
        .background(LinearGradient(colors: [.clear, Color(red: 0.02, green: 0.027, blue: 0.05).opacity(0.92)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.6))
            .allowsHitTesting(false))
    }

    // MARK: 卡片

    private func card(_ flower: MemoryFlower) -> some View {
        let list = ordered, index = list.firstIndex { $0.id == flower.id }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(flower.category).font(.system(size: 12)).tracking(1.7).foregroundStyle(Color(red: 0.78, green: 0.71, blue: 0.87))
                Spacer()
                Button { selectedID = nil } label: { Image(systemName: "xmark").font(.system(size: 15)).frame(width: 44, height: 44) }
                    .accessibilityLabel("收起").padding(.trailing, -12)
            }
            Text(flower.title).font(.custom("NotoSerifSC-Regular", size: 23, relativeTo: .title2)).padding(.top, 2).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(flower.body).font(.system(size: 15)).lineSpacing(9).foregroundStyle(Color(red: 0.93, green: 0.9, blue: 0.97))
                        .textSelection(.enabled)
                    ForEach(Array(flower.quotes.prefix(2).enumerated()), id: \.offset) { _, quote in
                        Text("「\(quote)」").font(.system(size: 14)).lineSpacing(7).foregroundStyle(Color(red: 0.78, green: 0.74, blue: 0.84))
                            .padding(.leading, 14)
                            .overlay(alignment: .leading) { Rectangle().fill(Color(red: 0.6, green: 0.51, blue: 0.7)).frame(width: 1) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
            HStack {
                Text(Self.dateText(flower)).font(.system(size: 11)).foregroundStyle(Self.muted)
                Spacer()
                Text(flower.author == "ke" ? "柯亲手记下" : "以前整理的").font(.system(size: 11)).foregroundStyle(Self.muted)
            }
            .padding(.top, 14)
            Button { Task { await store.change(flower, action: "love") } } label: {
                HStack(spacing: 10) {
                    Image(systemName: flower.loved ? "heart.fill" : "heart")
                    Text(flower.loved ? "喜欢着" : "这颗我很喜欢")
                }
                .font(.system(size: 13))
                .foregroundStyle(flower.loved ? Color(red: 1, green: 0.77, blue: 0.82) : Color(red: 0.89, green: 0.8, blue: 0.87))
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(RoundedRectangle(cornerRadius: 12).fill(flower.loved ? Color(red: 0.69, green: 0.31, blue: 0.36).opacity(0.19) : Color(red: 0.85, green: 0.77, blue: 0.91).opacity(0.11)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.77, green: 0.69, blue: 0.83).opacity(0.21), lineWidth: 1))
            }
            .buttonStyle(.plain).disabled(store.busy).padding(.top, 14)
            .accessibilityIdentifier("memory-love")
            HStack {
                Button("上一颗") { if let index, index > 0 { selectedID = list[index - 1].id } }
                    .disabled(index == nil || index == 0)
                Spacer()
                if let index { Text("\(index + 1) / \(list.count)").font(.system(size: 12).monospacedDigit()).foregroundStyle(Self.muted) }
                Spacer()
                Button("下一颗") { if let index, index < list.count - 1 { selectedID = list[index + 1].id } }
                    .disabled(index == nil || index == list.count - 1)
            }
            .font(.system(size: 13)).frame(minHeight: 44).padding(.top, 6)
            .opacity(flower.author == "ke" ? 1 : 0)
            .allowsHitTesting(flower.author == "ke")
            Button("记错了") { note = ""; correcting = flower }
                .font(.system(size: 12)).foregroundStyle(Self.muted)
                .frame(maxWidth: .infinity, minHeight: 36)
                .accessibilityIdentifier("memory-correct")
            if let error = store.error { Text(error).font(.system(size: 12)).foregroundStyle(Self.muted) }
        }
        .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(red: 0.08, green: 0.1, blue: 0.14).opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color(red: 0.73, green: 0.78, blue: 0.86).opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 35, y: 18)
        .padding(.horizontal, 14).padding(.bottom, 12)
        .frame(maxWidth: 500)
    }

    // MARK: 列表

    private var memoryList: some View {
        NavigationStack {
            List {
                ForEach(ordered.reversed()) { flower in
                    Button { listOpen = false; selectedID = flower.id } label: {
                        HStack(spacing: 12) {
                            Text(flower.title)
                            Spacer()
                            Text("\(flower.category) · \(Self.dateText(flower))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("\(Self.monthName())，记住的瞬间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { listOpen = false } } }
        }
        .presentationDetents([.medium, .large])
        .environment(\.colorScheme, .dark)
    }

    private var dimmedList: some View {
        NavigationStack {
            List {
                if let error = store.error { Text(error).foregroundStyle(.secondary) }
                let dimmed = store.flowers.filter { $0.state == "withered" && (includeOthers || $0.author == "ke") }
                if dimmed.isEmpty { Text("还没有熄灭的星。") }
                ForEach(dimmed) { flower in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(flower.title)
                        Text(flower.body).font(.subheadline).foregroundStyle(.secondary)
                        Button("重新点亮") { Task { await store.change(flower, action: "revive") } }
                            .disabled(store.busy || store.loading)
                            .accessibilityIdentifier("memory-revive-\(flower.id)")
                    }.padding(.vertical, 8)
                }
            }
            .navigationTitle("熄灭的星").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dimmedOpen = false } } }
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var overlays: some View {
        if store.loading && !store.loaded {
            ProgressView("正在点亮星河").padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        } else if store.loaded && mine.isEmpty && !includeOthers {
            Text("柯还没开始点星星，他每天会自己记下你们的事")
                .font(.subheadline).multilineTextAlignment(.center).lineSpacing(6).foregroundStyle(Self.muted)
                .padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(30)
                .accessibilityIdentifier("memory-empty")
        } else if let error = store.error, !store.loaded {
            VStack(spacing: 10) {
                Text(error).font(.subheadline).multilineTextAlignment(.center)
                Button("重试") { Task { await store.load() } }.disabled(store.loading || store.busy)
            }.padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(30)
        }
    }

    // MARK: 动作

    private func tapped(_ point: CGPoint) {
        if let hit = world.hit(point) {
            if hit.ke { selectedID = hit.id }
            else if let flower = store.flowers.first(where: { $0.id == hit.id }) { selectedID = flower.id }
        } else if selectedID != nil {
            selectedID = nil
        }
    }

    private func sync() {
        world.reduceMotion = reduceMotion
        world.showOthers = includeOthers
        world.sync(ke: mine, others: includeOthers ? others : [])
        if let id = selectedID, !store.flowers.contains(where: { $0.id == id && $0.isDrawable }) { selectedID = nil }
        welcomeNewMemory()
    }

    /// 柯上次之后新记的事：一颗流星从右上角划过来，落下，那颗星亮起来。
    private func welcomeNewMemory() {
        guard store.loaded, visible else { return }
        let ke = store.flowers.filter { $0.author == "ke" && $0.isDrawable }
        guard let newest = ke.compactMap(\.written_at).max() else { return }
        defer { lastSeen = max(lastSeen, newest) }
        guard newest > lastSeen, !reduceMotion, let target = ke.first(where: { $0.written_at == newest }) else { return }
        let start = Date().addingTimeInterval(1.2)
        world.hide(target.id, until: start.addingTimeInterval(1.6))
        meteors.arrive(target.id, at: start)
        withAnimation(.easeOut(duration: 0.8).delay(1.2)) { toast = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4.2))
            withAnimation(.easeIn(duration: 0.9)) { toast = false }
        }
    }

    private static func monthName(_ date: Date = Date()) -> String {
        let m = Calendar.current.component(.month, from: date)
        return ["一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月"][max(0, min(11, m - 1))]
    }
    private static func dateText(_ flower: MemoryFlower) -> String {
        let raw = flower.occurred_at ?? flower.written_at ?? ""
        let parts = raw.prefix(10).split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return "" }
        return "\(y).\(m).\(d)"
    }
}

// MARK: - 流星（2D 叠在最上面一层）

final class GalaxyMeteors {
    struct Meteor { let start: Date; let duration: Double; let from: CGPoint; let delta: CGPoint; let target: String? }
    var list: [Meteor] = []
    var next = Date().addingTimeInterval(6)
    private var random = GalaxyRandom(seed: 7)

    func ambient(now: Date) {
        let a = CGFloat(random.next()), b = CGFloat(random.next()), c = CGFloat(random.next()), d = CGFloat(random.next())
        list.append(Meteor(start: now, duration: 1.1 + Double(a) * 0.5, from: CGPoint(x: 0.75 + b * 0.25, y: 0.1 + c * 0.15),
                           delta: CGPoint(x: -(0.8 + d * 0.2), y: 0.32 + a * 0.12), target: nil))
    }
    func arrive(_ id: String, at date: Date) {
        list.append(Meteor(start: date, duration: 1.6, from: CGPoint(x: 0.92, y: -0.01), delta: .zero, target: id))
    }
}

private struct GalaxyMeteorLayer: View {
    let meteors: GalaxyMeteors
    let world: GalaxyWorld
    let paused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: paused)) { timeline in
            Canvas { context, size in
                let now = timeline.date
                if now > meteors.next {
                    meteors.ambient(now: now)
                    meteors.next = now.addingTimeInterval(8 + Double.random(in: 0...9))
                }
                meteors.list.removeAll { now.timeIntervalSince($0.start) > $0.duration }
                for m in meteors.list {
                    let p = now.timeIntervalSince(m.start) / m.duration
                    guard p > 0 else { continue }
                    let from = CGPoint(x: m.from.x * size.width, y: m.from.y * size.height)
                    var end = CGPoint(x: from.x + m.delta.x * size.width, y: from.y + m.delta.y * size.height)
                    if let id = m.target, let point = world.screenPoint(of: id) { end = point }
                    let e = CGFloat(m.target == nil ? 1 - pow(1 - p, 2.2) : 1 - pow(1 - p, 3))
                    let head = CGPoint(x: from.x + (end.x - from.x) * e, y: from.y + (end.y - from.y) * e)
                    let angle = atan2(end.y - from.y, end.x - from.x), length: CGFloat = m.target == nil ? 110 : 130
                    let tail = CGPoint(x: head.x - cos(angle) * length, y: head.y - sin(angle) * length)
                    let fade = m.target == nil ? sin(Double.pi * p) : 1
                    var path = Path(); path.move(to: head); path.addLine(to: tail)
                    context.stroke(path, with: .linearGradient(
                        Gradient(colors: [Color(red: 1, green: 0.98, blue: 0.94).opacity(0.92 * fade), .clear]),
                        startPoint: head, endPoint: tail), lineWidth: m.target == nil ? 1.3 : 1.8)
                }
            }
        }
    }
}
