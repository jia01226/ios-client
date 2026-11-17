import SwiftUI

// 11-17 她发来「粑粑日历」的样子（每天一个带表情的小团子），日历上显示「出恭」。
// 团子是我们自己画的、跟 App 一套的淡色：顺 = 薄荷绿眯眼笑，有点难 = 杏色皱眉，很难 = 淡紫委屈，蹲了没出来 = 浅灰困困。
// 点哪天，日历下面列那天的几次；「新增」：时间、蹲了没出来、顺不顺、用时、形状（选填）、备注。也可以直接跟柯说，柯记。

enum PoopMood {
    case ok, hard, veryHard, skipped

    init(feel: String?, none: Bool) {
        if none { self = .skipped; return }
        switch feel {
        case PoopFeel.hard.rawValue: self = .hard
        case PoopFeel.very_hard.rawValue: self = .veryHard
        default: self = .ok
        }
    }

    /// 一天画哪个团子：有出来的看最难那次；整天都只是蹲了没出来就是灰的
    init(day logs: [PoopLog]) {
        let done = logs.filter { !$0.isNone }
        if done.isEmpty { self = .skipped; return }
        if done.contains(where: { $0.feel == PoopFeel.very_hard.rawValue }) { self = .veryHard }
        else if done.contains(where: { $0.feel == PoopFeel.hard.rawValue }) { self = .hard }
        else { self = .ok }
    }

    var color: Color {
        switch self {
        case .ok: return Color(hex: 0xBFE3C8)
        case .hard: return Color(hex: 0xF7D3A6)
        case .veryHard: return Color(hex: 0xD3C4EE)
        case .skipped: return Color(hex: 0xE3E5EB)
        }
    }

    var label: String {
        switch self {
        case .ok: return "顺"
        case .hard: return "有点难"
        case .veryHard: return "很难"
        case .skipped: return "蹲了没出来"
        }
    }
}

/// 一个圆滚滚的小团子（三层叠起来 + 小尖），脸跟着心情变
struct PoopBlob: View {
    let mood: PoopMood
    var width: CGFloat = 28

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let fill = GraphicsContext.Shading.color(mood.color)
            ctx.fill(Path(ellipseIn: CGRect(x: 0, y: h * 0.46, width: w, height: h * 0.54)), with: fill)
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.13, y: h * 0.24, width: w * 0.74, height: h * 0.5)), with: fill)
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.3, y: h * 0.06, width: w * 0.4, height: h * 0.34)), with: fill)
            var tip = Path()
            tip.move(to: CGPoint(x: w * 0.44, y: h * 0.12))
            tip.addQuadCurve(to: CGPoint(x: w * 0.62, y: 0), control: CGPoint(x: w * 0.5, y: h * 0.02))
            tip.addQuadCurve(to: CGPoint(x: w * 0.6, y: h * 0.16), control: CGPoint(x: w * 0.66, y: h * 0.1))
            ctx.fill(tip, with: fill)

            let ink = GraphicsContext.Shading.color(Color(hex: 0x5A4A50).opacity(0.85))
            let ey = h * 0.64, lx = w * 0.37, rx = w * 0.63, e = w * 0.06
            switch mood {
            case .ok:
                for x in [lx, rx] {   // 眯眼笑：两道往上弯的弧
                    var a = Path()
                    a.addArc(center: CGPoint(x: x, y: ey + e * 0.6), radius: e, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                    ctx.stroke(a, with: ink, lineWidth: max(1, w * 0.045))
                }
            case .hard:
                for x in [lx, rx] { ctx.fill(Path(ellipseIn: CGRect(x: x - e * 0.6, y: ey - e * 0.6, width: e * 1.2, height: e * 1.2)), with: ink) }
                var m = Path()   // 抿着的小波浪嘴
                m.move(to: CGPoint(x: w * 0.44, y: h * 0.8))
                m.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.8), control: CGPoint(x: w * 0.47, y: h * 0.76))
                m.addQuadCurve(to: CGPoint(x: w * 0.56, y: h * 0.8), control: CGPoint(x: w * 0.53, y: h * 0.84))
                ctx.stroke(m, with: ink, lineWidth: max(1, w * 0.04))
            case .veryHard:
                for x in [lx, rx] { ctx.fill(Path(ellipseIn: CGRect(x: x - e * 0.6, y: ey - e * 0.6, width: e * 1.2, height: e * 1.2)), with: ink) }
                var m = Path()   // 往下撇的嘴
                m.addArc(center: CGPoint(x: w * 0.5, y: h * 0.86), radius: w * 0.06, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                ctx.stroke(m, with: ink, lineWidth: max(1, w * 0.04))
                ctx.fill(Path(ellipseIn: CGRect(x: rx + e * 0.2, y: ey + e * 0.6, width: e * 0.9, height: e * 1.4)),
                         with: .color(Color(hex: 0x9CC3E6)))   // 一滴小眼泪
            case .skipped:
                for x in [lx, rx] {   // 困困的两道横线
                    var d = Path()
                    d.move(to: CGPoint(x: x - e, y: ey)); d.addLine(to: CGPoint(x: x + e, y: ey))
                    ctx.stroke(d, with: ink, lineWidth: max(1, w * 0.04))
                }
            }
            if mood != .skipped {   // 两团腮红
                let blush = GraphicsContext.Shading.color(Color(hex: 0xF2A7B8).opacity(0.55))
                for x in [w * 0.24, w * 0.76] {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - e, y: ey + e * 0.5, width: e * 2, height: e * 1.1)), with: blush)
                }
            }
        }
        .frame(width: width, height: width * 0.82)
        .accessibilityHidden(true)
    }
}

/// 出恭那面的一格：数字，底下团子；选中的那天描一圈；一天不止一次，团子右上角写几次
struct PoopDayCell: View {
    let date: Date
    let logs: [PoopLog]
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        let isToday = Calendar.current.isDateInToday(date)
        let done = logs.filter { !$0.isNone }.count
        Button(action: onTap) {
            VStack(spacing: 0) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(Cool.didot(16, .body)).monospacedDigit()
                    .foregroundStyle(isToday ? Cool.ink : Cool.number)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 28, height: 26)
                    .background(Circle().fill(isToday ? Cool.today : .clear).frame(width: 26, height: 26))
                    .overlay(Circle().stroke(selected ? Cool.mauve : .clear, lineWidth: 1).frame(width: 26, height: 26))
                ZStack(alignment: .topTrailing) {
                    if logs.isEmpty {
                        Color.clear
                    } else {
                        PoopBlob(mood: PoopMood(day: logs), width: 28)
                        if done > 1 {
                            Text("\(done)").font(.system(size: 9, weight: .medium)).foregroundStyle(.white)
                                .frame(width: 13, height: 13).background(Circle().fill(Cool.mauve)).offset(x: 5, y: -3)
                        }
                    }
                }
                .frame(width: 30, height: 24)
            }
            .frame(maxWidth: .infinity, minHeight: 53, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Calendar.current.component(.month, from: date)) 月 \(Calendar.current.component(.day, from: date)) 日，"
                            + (logs.isEmpty ? "没有记录" : "\(done) 次，\(PoopMood(day: logs).label)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 日历下面：这个月的数、那天的几次、「新增」
struct PoopPanel: View {
    @ObservedObject var store: BodyLogStore
    let month: Date
    let day: Date
    var onAdd: () -> Void
    var onEdit: (PoopLog) -> Void

    private static let dayTitle: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日"; return f
    }()

    var body: some View {
        let logs = store.poopLogs(on: day)
        let gap = store.daysSinceLastPoop()
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                stat("\(store.poopMonth(month))", "本月次数")
                stat(gap.map { $0 == 0 ? "今天" : "\($0) 天前" } ?? "—", "上一次")
                stat("\(store.poopHard(month))", "不顺")
                stat("\(store.poopNone(month))", "没出来")
            }
            HStack {
                Text(Self.dayTitle.string(from: day) + " · \(logs.filter { !$0.isNone }.count) 次").font(Cool.song(14, .subheadline)).foregroundStyle(Cool.ink)
                Spacer()
                Button(action: onAdd) {
                    Text("新增").font(Cool.song(13, .subheadline)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(minHeight: 32)
                        .background(Capsule().fill(Cool.mauve))
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("poop-add")
            }
            if logs.isEmpty {
                Text("这天还没有。懒得点的话，跟柯说一声他就记上。").font(Cool.tiny()).foregroundStyle(Cool.secondary)
            }
            ForEach(logs) { log in
                Button { onEdit(log) } label: { row(log) }.buttonStyle(.plain)
            }
            if let error = store.error {
                Text(error).font(Cool.tiny()).foregroundStyle(Cool.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(Cool.didot(17, .title3)).foregroundStyle(Cool.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(Cool.tiny()).foregroundStyle(Cool.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Cool.line.opacity(0.35)))
        .accessibilityElement(children: .combine)
    }

    private func row(_ log: PoopLog) -> some View {
        let mood = PoopMood(feel: log.feel, none: log.isNone)
        let head = log.isNone ? "蹲了没出来"
            : [mood.label, log.duration.flatMap(PoopDuration.init(rawValue:))?.label].compactMap { $0 }.joined(separator: " · ")
        let sub = [log.shape.flatMap(PoopShape.init(rawValue:))?.label, log.note, log.author == "ke" ? "柯记的" : nil]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(spacing: 12) {
            Text(log.time ?? "").font(Cool.didot(15, .subheadline)).foregroundStyle(Cool.ink).monospacedDigit().frame(width: 46, alignment: .leading)
            PoopBlob(mood: mood, width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(head).font(Cool.song(14, .subheadline)).foregroundStyle(Cool.ink)
                if !sub.isEmpty { Text(sub).font(Cool.tiny()).foregroundStyle(Cool.secondary).lineLimit(2) }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .light)).foregroundStyle(Cool.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("改这一次")
    }
}

// MARK: - 新增一次 / 改一次

struct PoopEditor: View {
    @State var log: PoopLog
    let isNew: Bool
    var onSave: (PoopLog) -> Void
    var onDelete: (PoopLog) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var when: Date
    @State private var confirmDelete = false

    init(log: PoopLog, isNew: Bool, onSave: @escaping (PoopLog) -> Void, onDelete: @escaping (PoopLog) -> Void) {
        _log = State(initialValue: log)
        self.isNew = isNew; self.onSave = onSave; self.onDelete = onDelete
        let d = log.day.prefix(10).split(separator: "-").compactMap { Int($0) }
        let t = (log.time ?? "").split(separator: ":").compactMap { Int($0) }
        let now = Calendar.current.dateComponents([.hour, .minute], from: .now)
        var parts = DateComponents(hour: t.count == 2 ? t[0] : now.hour, minute: t.count == 2 ? t[1] : now.minute)
        if d.count == 3 { parts.year = d[0]; parts.month = d[1]; parts.day = d[2] }
        _when = State(initialValue: Calendar.current.date(from: parts) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("时间", selection: $when).environment(\.locale, Locale(identifier: "zh_CN"))
                    Toggle("蹲了没出来", isOn: Binding(get: { log.isNone }, set: { log.none = $0 ? true : nil })).tint(Ink.accent)
                }
                if !log.isNone {
                    Section("顺不顺") {
                        chips(PoopFeel.allCases.map { ($0.rawValue, $0.label) }, \.feel)
                    }
                    Section("用了多久") {
                        chips(PoopDuration.allCases.map { ($0.rawValue, $0.label) }, \.duration)
                    }
                    Section {
                        chips(PoopShape.allCases.map { ($0.rawValue, $0.label) }, \.shape)
                    } header: {
                        Text("形状（选填）")
                    } footer: {
                        Text("从硬到稀排的，看医生时用得上。不想选就跳过。")
                    }
                }
                Section("备注") {
                    TextField("臭、有点痛、屁多…", text: Binding(get: { log.note ?? "" }, set: { log.note = $0.isEmpty ? nil : $0 }),
                              axis: .vertical).lineLimit(1...4)
                }
                if !isNew {
                    Section { Button("删掉这一次", role: .destructive) { confirmDelete = true } }
                }
            }
            .font(Ink.song(15))
            .scrollContentBackground(.hidden)
            .background(CamelliaPalette.stored().paper)
            .navigationTitle(isNew ? "新增" : "这一次").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("好了") { save() } }
            }
            .confirmationDialog("删掉这一次？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删掉", role: .destructive) { onDelete(log); dismiss() }
            }
        }
        .tint(Ink.accent)
        .foregroundStyle(Ink.primary)
    }

    private func chips(_ items: [(String, String)], _ key: WritableKeyPath<PoopLog, String?>) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
            ForEach(items.indices, id: \.self) { i in
                let (value, label) = items[i]
                let on = log[keyPath: key] == value
                Button { log[keyPath: key] = on ? nil : value } label: {
                    Text(label).font(Ink.song(13)).foregroundStyle(on ? Color.white : Ink.primary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Capsule().fill(on ? Ink.accent : Color.clear))
                        .overlay(Capsule().stroke(Ink.line, lineWidth: on ? 0 : 0.7))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func save() {
        log.day = HomeReminderCoordinator.dayKey(when)
        let hm = Calendar.current.dateComponents([.hour, .minute], from: when)
        log.time = String(format: "%02d:%02d", hm.hour ?? 0, hm.minute ?? 0)
        if log.isNone { log.feel = nil; log.duration = nil; log.shape = nil }
        onSave(log)
        dismiss()
    }
}
