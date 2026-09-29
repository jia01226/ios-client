import SwiftUI

// 【我们】—— 两个人的日期、提醒与排班，由同一条月相轨迹串起来。

struct UsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let line: ChatLine
    @StateObject private var vm: UsViewModel
    @State private var selectedAnniversaryIndex = 0
    @State private var selectedWeekIndex = min(6, max(0, (Calendar.current.component(.weekday, from: .now) + 5) % 7))
    @State private var showingCompanionHub = false

    init(line: ChatLine = .test1) {
        self.line = line
        _vm = StateObject(wrappedValue: UsViewModel(api: APIClient(baseURL: line.apiBaseURL)))
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 0) {
                if dynamicTypeSize.isAccessibilitySize {
                    AccessibleAnniversaryHero(display: selectedDisplay)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 28)
                } else {
                    WatercolorAnniversaryHero(
                        events: vm.anniversaries,
                        selectedIndex: $selectedAnniversaryIndex,
                        display: selectedDisplay
                    )
                    .frame(height: 405)
                }

                reminder
                    .padding(.horizontal, 30)

                companionEntry
                    .padding(.horizontal, 30)
                    .padding(.top, 34)

                if dynamicTypeSize.isAccessibilitySize {
                    AccessibleWeekSchedule(days: vm.thisWeek, vm: vm)
                        .padding(.horizontal, 30)
                        .padding(.top, 44)
                        .accessibilityIdentifier("curved-week-schedule")
                } else {
                    CurvedWeekSchedule(days: vm.thisWeek, selectedIndex: $selectedWeekIndex, vm: vm)
                        .padding(.top, 64)
                        .accessibilityIdentifier("curved-week-schedule")
                }

                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(UsPalette.gold.opacity(0.68))
                    .padding(.top, 18)
                    .padding(.bottom, 88)
                    .accessibilityHidden(true)

                    MonthCalendar(vm: vm)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 34)
                        .id("moon-calendar")
                        .accessibilityIdentifier("moon-calendar")
                }
            }
            .scrollIndicators(.hidden)
            .refreshable { await vm.loadReminders() }
            .scrollContentBackground(.hidden)
            .background(UsPalette.paper.ignoresSafeArea())
            .task {
                if ProcessInfo.processInfo.arguments.contains("-preview-us-calendar") {
                    try? await Task.sleep(for: .milliseconds(280))
                    scrollProxy.scrollTo("moon-calendar", anchor: .top)
                }
            }
            .onChange(of: vm.anniversaries.map(\.id)) { _, ids in
                selectedAnniversaryIndex = min(selectedAnniversaryIndex, max(0, ids.count - 1))
            }
            .task(id: line) { await vm.loadReminders() }
            .sheet(isPresented: $showingCompanionHub) {
                CompanionHubView(line: line, model: vm)
            }
        }
    }

    private var selectedDisplay: AnniversaryDisplay? {
        guard vm.anniversaries.indices.contains(selectedAnniversaryIndex) else { return nil }
        return vm.display(for: vm.anniversaries[selectedAnniversaryIndex])
    }

    private var reminder: some View {
        HStack(alignment: .center, spacing: 14) {
            BotanicalSprig()
                .frame(width: 40, height: 52)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("柯替你记得")
                    .font(.custom("STSongti-SC-Regular", size: 18, relativeTo: .headline))
                    .tracking(1.5)
                    .foregroundStyle(UsPalette.ink)

                if let item = vm.activeReminders.first {
                    Text(vm.reminderHeadline(item))
                        .font(.custom("STSongti-SC-Light", size: 16, relativeTo: .body))
                        .tracking(0.7)
                        .foregroundStyle(UsPalette.ink)
                    Text(vm.reminderDetail(item))
                        .font(.custom("STSongti-SC-Light", size: 12, relativeTo: .caption))
                        .tracking(0.8)
                        .foregroundStyle(UsPalette.mutedInk)
                } else if vm.loadingReminders {
                    Text("正在看看记下了什么")
                        .font(.custom("STSongti-SC-Light", size: 14, relativeTo: .body))
                        .foregroundStyle(UsPalette.mutedInk)
                } else if vm.reminderLoadError != nil {
                    Button("提醒暂时没接上 · 点这里重试") {
                        Task { await vm.loadReminders() }
                    }
                    .font(.custom("STSongti-SC-Light", size: 14, relativeTo: .body))
                    .foregroundStyle(UsPalette.coral)
                } else {
                    Text("现在没有待着的提醒")
                        .font(.custom("STSongti-SC-Light", size: 14, relativeTo: .body))
                        .foregroundStyle(UsPalette.mutedInk)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var companionEntry: some View {
        Button { showingCompanionHub = true } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    Text("柯的接口")
                        .font(.custom("STSongti-SC-Regular", size: 20, relativeTo: .headline))
                        .tracking(1.8)
                    Spacer()
                    Text("打开")
                        .font(.custom("STSongti-SC-Light", size: 13, relativeTo: .caption))
                        .tracking(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                }

                Text("提醒你的事 · 柯在忙什么 · 柯的抽屉")
                    .font(.custom("STSongti-SC-Light", size: 14, relativeTo: .body))
                    .tracking(0.7)
                    .foregroundStyle(UsPalette.mutedInk)

                HStack(spacing: 17) {
                    hubStatus("提醒", value: reminderStatus)
                    hubStatus("能力", value: "逐步接通")
                    hubStatus("抽屉", value: "去看看")
                }
            }
            .foregroundStyle(UsPalette.ink)
            .padding(.vertical, 17)
            .overlay(alignment: .top) {
                Rectangle().fill(UsPalette.hairline.opacity(0.52)).frame(height: 0.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(UsPalette.hairline.opacity(0.28)).frame(height: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("us-companion-hub")
        .accessibilityHint("查看提醒、抽屉和柯能做的事情")
    }

    private var reminderStatus: String {
        if vm.loadingReminders { return "连接中" }
        if vm.reminderLoadError != nil { return "未接上" }
        return vm.activeReminders.isEmpty ? "暂无" : "\(vm.activeReminders.count) 件"
    }

    private func hubStatus(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.custom("STSongti-SC-Light", size: 12, relativeTo: .caption))
                .foregroundStyle(UsPalette.mutedInk)
            Text(value)
                .font(.custom("STSongti-SC-Regular", size: 14, relativeTo: .subheadline))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccessibleAnniversaryHero: View {
    let display: AnniversaryDisplay?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text("我们的时间")
                    .font(.title.weight(.regular))
                    .foregroundStyle(UsPalette.ink)
                Spacer()
                Image("WatercolorMoon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .accessibilityHidden(true)
            }
            Text(display?.title ?? "")
                .font(.headline)
                .foregroundStyle(UsPalette.mutedInk)
            Text("\(display?.number ?? "—") \(display?.unit ?? "")")
                .font(.largeTitle.monospacedDigit())
                .foregroundStyle(UsPalette.coral)
            Text(display?.dateLabel ?? "")
                .font(.body)
                .foregroundStyle(UsPalette.mutedInk)
        }
        .accessibilityElement(children: .combine)
    }
}

private enum UsPalette {
    static let paper = Color(red: 0.992, green: 0.982, blue: 0.955)
    static let ink = Color(red: 0.25, green: 0.20, blue: 0.24)
    static let mutedInk = Color(red: 0.52, green: 0.46, blue: 0.45)
    static let coral = Color(red: 0.91, green: 0.43, blue: 0.40)
    static let blush = Color(red: 0.96, green: 0.71, blue: 0.68)
    static let sage = Color(red: 0.49, green: 0.59, blue: 0.45)
    static let gold = Color(red: 0.78, green: 0.57, blue: 0.27)
    static let hairline = Color(red: 0.88, green: 0.72, blue: 0.48)
}

private struct WatercolorAnniversaryHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let events: [Anniversary]
    @Binding var selectedIndex: Int
    let display: AnniversaryDisplay?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .topLeading) {
                Image("WatercolorMoon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 430, height: 430)
                    .position(x: width + 20, y: 102)
                    .opacity(0.97)
                    .shadow(color: UsPalette.gold.opacity(0.10), radius: 28, x: -14, y: 12)
                    .accessibilityHidden(true)

                WatercolorOrbit(width: width)
                    .accessibilityHidden(true)

                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    Button { select(index) } label: {
                        WatercolorOrbitBody(index: index, selected: index == selectedIndex)
                    }
                    .buttonStyle(.plain)
                    .position(markerPoint(index: index, width: width))
                    .accessibilityLabel(event.title)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("我们的时间")
                        .font(.custom("STSongti-SC-Light", size: 27, relativeTo: .title))
                        .tracking(2.8)
                        .foregroundStyle(UsPalette.ink)

                    Text(display?.title ?? "")
                        .font(.custom("STSongti-SC-Light", size: 14, relativeTo: .subheadline))
                        .tracking(2.0)
                        .foregroundStyle(UsPalette.mutedInk)
                        .padding(.top, 15)

                    HStack(alignment: .lastTextBaseline, spacing: 7) {
                        Text(display?.number ?? "—")
                            .font(.custom("Didot", size: 72, relativeTo: .largeTitle))
                            .tracking(-2)
                            .monospacedDigit()
                            .foregroundStyle(UsPalette.coral)
                            .contentTransition(.numericText())

                        Text(display?.unit ?? "")
                            .font(.custom("STSongti-SC-Light", size: 16, relativeTo: .body))
                            .tracking(1)
                            .foregroundStyle(UsPalette.ink)
                            .padding(.bottom, 9)
                    }

                    Text(display?.dateLabel ?? "")
                        .font(.custom("STSongti-SC-Light", size: 13, relativeTo: .caption))
                        .tracking(1)
                        .foregroundStyle(UsPalette.mutedInk)
                }
                .padding(.leading, 31)
                .padding(.top, 166)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.38, dampingFraction: 1),
                    value: selectedIndex
                )

                Capsule(style: .continuous)
                    .fill(UsPalette.blush.opacity(0.58))
                    .frame(width: 9, height: 5)
                    .rotationEffect(.degrees(22))
                    .position(x: width * 0.63, y: 68)

                Circle()
                    .fill(UsPalette.sage.opacity(0.50))
                    .frame(width: 6, height: 6)
                    .position(x: width * 0.83, y: 345)
            }
            .contentShape(Rectangle())
            .sensoryFeedback(.alignment, trigger: selectedIndex)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("us-moon-orbit-selector")
            .accessibilityLabel("纪念日月球")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("上下调整可切换日期，也可以轻点轨道上的小星球")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: select(min(selectedIndex + 1, events.count - 1))
                case .decrement: select(max(selectedIndex - 1, 0))
                @unknown default: break
                }
            }
        }
    }

    private var accessibilityValue: String {
        guard let display else { return "还没有纪念日" }
        return "\(display.title)，\(display.number)\(display.unit)，\(display.dateLabel)"
    }

    private func markerPoint(index: Int, width: CGFloat) -> CGPoint {
        let fractions: [CGFloat] = [0.08, 0.36, 0.67, 0.92]
        let fraction = fractions[min(index, fractions.count - 1)]
        let angle = Double(108 + 142 * fraction) * .pi / 180
        return CGPoint(
            x: width + 20 + 258 * CGFloat(cos(angle)),
            y: 102 + 258 * CGFloat(sin(angle))
        )
    }

    private func select(_ index: Int) {
        guard events.indices.contains(index) else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.38, dampingFraction: 1)) {
            selectedIndex = index
        }
    }
}

private struct WatercolorOrbit: View {
    let width: CGFloat

    var body: some View {
        Canvas { context, _ in
            let center = CGPoint(x: width + 20, y: 102)
            let main = arc(center: center, radius: 258, start: 108, end: 250)
            let soft = arc(center: CGPoint(x: center.x - 2, y: center.y + 1), radius: 262, start: 109, end: 249)
            let inner = arc(center: CGPoint(x: center.x + 1, y: center.y), radius: 253, start: 112, end: 247)

            context.stroke(soft, with: .color(UsPalette.blush.opacity(0.12)), lineWidth: 7)
            context.stroke(main, with: .color(UsPalette.hairline.opacity(0.72)), lineWidth: 0.9)
            context.stroke(inner, with: .color(UsPalette.coral.opacity(0.16)), style: StrokeStyle(lineWidth: 0.55, dash: [2, 5]))

            for sample in pigmentSamples {
                let radians = sample.angle * .pi / 180
                let point = CGPoint(
                    x: center.x + sample.radius * cos(radians),
                    y: center.y + sample.radius * sin(radians)
                )
                let rect = CGRect(x: point.x - sample.size / 2, y: point.y - sample.size / 2, width: sample.size, height: sample.size)
                context.fill(Path(ellipseIn: rect), with: .color(sample.color))
            }
        }
    }

    private func arc(center: CGPoint, radius: CGFloat, start: Double, end: Double) -> Path {
        Path { path in
            path.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        }
    }

    private var pigmentSamples: [(angle: CGFloat, radius: CGFloat, size: CGFloat, color: Color)] {
        [
            (121, 260, 2.4, UsPalette.gold.opacity(0.36)),
            (145, 255, 1.8, UsPalette.coral.opacity(0.28)),
            (177, 263, 2.0, UsPalette.gold.opacity(0.26)),
            (208, 255, 2.8, UsPalette.blush.opacity(0.34)),
            (236, 261, 1.7, UsPalette.gold.opacity(0.34)),
        ]
    }
}

private struct WatercolorOrbitBody: View {
    let index: Int
    let selected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(UsPalette.paper.opacity(0.90))
                .frame(width: selected ? 43 : 31, height: selected ? 43 : 31)
                .shadow(color: UsPalette.gold.opacity(selected ? 0.19 : 0.07), radius: selected ? 9 : 3, y: 3)

            Image("WatercolorMoon")
                .resizable()
                .scaledToFit()
                .frame(width: selected ? 38 : 27, height: selected ? 38 : 27)
                .colorMultiply(tint)
                .opacity(selected ? 1 : 0.74)

            if selected {
                Ellipse()
                    .stroke(UsPalette.coral.opacity(0.48), lineWidth: 1)
                    .frame(width: 50, height: 17)
                    .rotationEffect(.degrees(-18))
            }
        }
        .frame(width: 52, height: 52)
        .animation(.spring(response: 0.32, dampingFraction: 1), value: selected)
    }

    private var tint: Color {
        switch index % 4 {
        case 0: return Color(red: 0.74, green: 0.82, blue: 0.68)
        case 1: return Color(red: 1.00, green: 0.78, blue: 0.73)
        case 2: return Color(red: 0.98, green: 0.88, blue: 0.78)
        default: return Color(red: 0.90, green: 0.84, blue: 0.75)
        }
    }
}

private struct BotanicalSprig: View {
    var body: some View {
        Canvas { context, size in
            let stem = Path { path in
                path.move(to: CGPoint(x: size.width * 0.22, y: size.height * 0.96))
                path.addCurve(
                    to: CGPoint(x: size.width * 0.72, y: size.height * 0.06),
                    control1: CGPoint(x: size.width * 0.28, y: size.height * 0.60),
                    control2: CGPoint(x: size.width * 0.62, y: size.height * 0.35)
                )
            }
            context.stroke(stem, with: .color(UsPalette.sage.opacity(0.80)), lineWidth: 1)
            for leaf in [
                CGRect(x: 7, y: 21, width: 13, height: 7),
                CGRect(x: 19, y: 10, width: 12, height: 7),
                CGRect(x: 16, y: 31, width: 11, height: 6),
            ] {
                context.fill(Path(ellipseIn: leaf), with: .color(UsPalette.sage.opacity(0.64)))
            }
            context.fill(Path(ellipseIn: CGRect(x: 27, y: 1, width: 6, height: 6)), with: .color(UsPalette.coral.opacity(0.72)))
            context.fill(Path(ellipseIn: CGRect(x: 33, y: 7, width: 4, height: 4)), with: .color(UsPalette.blush.opacity(0.82)))
        }
    }
}

private struct CurvedWeekSchedule: View {
    let days: [ShiftDay]
    @Binding var selectedIndex: Int
    let vm: UsViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("这一周")
                    .font(.custom("STSongti-SC-Light", size: 18, relativeTo: .headline))
                    .tracking(1.8)
                    .foregroundStyle(UsPalette.ink)
                Spacer()
                Text(vm.weekRangeLabel)
                    .font(.custom("STSongti-SC-Light", size: 11, relativeTo: .caption2))
                    .tracking(0.8)
                    .foregroundStyle(UsPalette.mutedInk)
            }
            .padding(.horizontal, 30)

            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .topLeading) {
                    WeekGlowTrail(width: width, selectedIndex: selectedIndex)

                    ForEach(Array(days.prefix(7).enumerated()), id: \.element.id) { index, day in
                        let x = width * (CGFloat(index) + 0.5) / 7
                        let relative = (x - width / 2) / (width / 2)
                        let curveY = 31 + 24 * relative * relative
                        let displayedShift = vm.shift(on: day.date)

                        Button {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                                selectedIndex = index
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Text(vm.weekdayLabel(day.date))
                                    .font(.custom("STSongti-SC-Light", size: 10, relativeTo: .caption2))
                                    .foregroundStyle(index == selectedIndex ? UsPalette.coral : UsPalette.mutedInk)
                                ShiftMoonMarker(hasShift: displayedShift != nil, selected: index == selectedIndex)
                                    .frame(width: index == selectedIndex ? 42 : 34, height: index == selectedIndex ? 42 : 34)
                                Text(displayedShift.map { vm.shiftDisplay($0, on: day.date) } ?? " ")
                                    .font(.custom("STSongti-SC-Light", size: 13, relativeTo: .caption))
                                    .foregroundStyle(index == selectedIndex ? UsPalette.coral : UsPalette.ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                            }
                            .frame(width: width / 7, height: 90)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .position(x: x, y: curveY + 39)
                        .accessibilityLabel("\(vm.weekdayFullLabel(day.date))，\(displayedShift.map { vm.shiftDetail($0, on: day.date) } ?? "未排班")")
                        .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])
                    }
                }
            }
            .frame(height: 126)
            .padding(.horizontal, 15)

            if days.indices.contains(selectedIndex) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(UsPalette.coral.opacity(0.72))
                        .frame(width: 5, height: 5)
                    Text(vm.weekdayFullLabel(days[selectedIndex].date))
                        .font(.custom("STSongti-SC-Light", size: 13, relativeTo: .caption))
                        .foregroundStyle(UsPalette.mutedInk)
                    Text(vm.shift(on: days[selectedIndex].date).map { vm.shiftDetail($0, on: days[selectedIndex].date) } ?? "未填写班表 · 轻点月历添加")
                        .font(.custom("STSongti-SC-Light", size: 14, relativeTo: .body))
                        .foregroundStyle(UsPalette.ink)
                    Spacer()
                }
                .padding(.horizontal, 31)
                .contentTransition(.numericText())
            }
        }
        .sensoryFeedback(.selection, trigger: selectedIndex)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("这周排班")
    }
}

private struct WeekGlowTrail: View {
    let width: CGFloat
    let selectedIndex: Int

    var body: some View {
        Canvas { context, _ in
            let glow = glowPath(width: width)
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 13))
                layer.stroke(glow, with: .color(UsPalette.gold.opacity(0.22)), lineWidth: 24)
            }
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 5))
                layer.stroke(glow, with: .color(UsPalette.blush.opacity(0.28)), lineWidth: 7)
            }

            let x = width * (CGFloat(selectedIndex) + 0.5) / 7
            let relative = (x - width / 2) / (width / 2)
            let y = 31 + 24 * relative * relative
            let halo = CGRect(x: x - 28, y: y - 18, width: 56, height: 56)
            context.fill(
                Path(ellipseIn: halo),
                with: .radialGradient(
                    Gradient(colors: [UsPalette.blush.opacity(0.18), .clear]),
                    center: CGPoint(x: x, y: y + 10),
                    startRadius: 2,
                    endRadius: 29
                )
            )
        }
        .allowsHitTesting(false)
    }

    private func glowPath(width: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: -10, y: 59))
            path.addCurve(
                to: CGPoint(x: width + 10, y: 59),
                control1: CGPoint(x: width * 0.27, y: 17),
                control2: CGPoint(x: width * 0.73, y: 17)
            )
        }
    }
}

private struct AccessibleWeekSchedule: View {
    let days: [ShiftDay]
    let vm: UsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("这周排班")
                .font(.headline)
                .foregroundStyle(UsPalette.ink)
            ForEach(Array(days.prefix(7).enumerated()), id: \.element.id) { index, day in
                HStack {
                    Text("第 \(index + 1) 天")
                    Spacer()
                    Text(vm.shift(on: day.date).map { vm.shiftDisplay($0, on: day.date) } ?? "未排")
                        .foregroundStyle(UsPalette.coral)
                }
                .font(.body)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ShiftMoonMarker: View {
    let hasShift: Bool
    let selected: Bool

    var body: some View {
        ZStack {
            if hasShift {
                Circle()
                    .fill(UsPalette.paper.opacity(0.90))
                    .shadow(color: UsPalette.gold.opacity(selected ? 0.30 : 0.16), radius: selected ? 11 : 7, y: 3)
                Image("WatercolorMoon")
                    .resizable()
                    .scaledToFit()
                    .padding(selected ? 3 : 5)
                    .opacity(selected ? 0.96 : 0.78)
            } else {
                Circle()
                    .fill(UsPalette.gold.opacity(selected ? 0.34 : 0.16))
                    .frame(width: selected ? 7 : 5, height: selected ? 7 : 5)
                    .shadow(color: UsPalette.gold.opacity(0.22), radius: 5)
            }
        }
        .overlay {
            if hasShift && selected {
                Circle().stroke(UsPalette.gold.opacity(0.68), lineWidth: 1)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 1), value: selected)
    }
}

private struct MonthCalendar: View {
    @ObservedObject var vm: UsViewModel
    @State private var editingDate: CalendarEditSelection?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            ZStack(alignment: .topTrailing) {
                Image("WatercolorMoon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 118, height: 118)
                    .opacity(0.12)
                    .offset(x: 18, y: -28)
                    .accessibilityHidden(true)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(vm.monthTitle)
                            .font(.custom("STSongti-SC-Light", size: 29, relativeTo: .title))
                            .tracking(2)
                            .foregroundStyle(UsPalette.ink)
                        Text("月亮替我们记下每一天")
                            .font(.custom("STSongti-SC-Light", size: 12, relativeTo: .caption))
                            .tracking(1.1)
                            .foregroundStyle(UsPalette.mutedInk)
                    }
                    Spacer()
                    Image(systemName: "sparkle")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(UsPalette.gold)
                        .padding(.top, 7)
                }
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.custom("STSongti-SC-Light", size: 12, relativeTo: .caption))
                        .foregroundStyle(UsPalette.mutedInk)
                }
                ForEach(Array(vm.monthCells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        Button {
                            editingDate = CalendarEditSelection(date: date)
                        } label: {
                            let shift = vm.shift(on: date)
                            CalendarDay(
                                date: date,
                                shift: shift,
                                shiftText: shift.map { vm.shiftDisplay($0, on: date) }
                            )
                        }
                        .buttonStyle(CalendarDayButtonStyle())
                        .accessibilityIdentifier(vm.calendarDayIdentifier(date))
                        .accessibilityLabel(vm.calendarDayAccessibilityLabel(date))
                        .accessibilityHint("轻点写班表")
                    } else {
                        Color.clear.frame(minHeight: 50)
                    }
                }
            }

            HStack(spacing: 14) {
                Rectangle()
                    .fill(UsPalette.hairline.opacity(0.52))
                    .frame(height: 0.7)
                Text("今日记事")
                    .font(.custom("STSongti-SC-Light", size: 13, relativeTo: .caption))
                    .tracking(1.4)
                    .foregroundStyle(UsPalette.mutedInk)
                    .fixedSize()
                Rectangle()
                    .fill(UsPalette.hairline.opacity(0.52))
                    .frame(height: 0.7)
            }

            VStack(spacing: 16) {
                ForEach(vm.activeReminders) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: item.category == .medicine ? "cross.case" : "calendar")
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(UsPalette.coral)
                            .frame(width: 18)
                        Text(item.text)
                            .font(.custom("STSongti-SC-Light", size: 14, relativeTo: .body))
                            .foregroundStyle(UsPalette.ink)
                        Spacer(minLength: 8)
                        Text(vm.reminderTime(item))
                            .font(.custom("STSongti-SC-Light", size: 11, relativeTo: .caption2))
                            .foregroundStyle(UsPalette.gold)
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: editingDate)
        .sheet(item: $editingDate) { selection in
            ScheduleEditorSheet(
                date: selection.date,
                currentShift: vm.shift(on: selection.date),
                currentNote: vm.shiftNote(on: selection.date),
                onSave: { shift, note in
                    vm.setShift(shift, note: note, on: selection.date)
                    editingDate = nil
                }
            )
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.visible)
            .presentationBackground(UsPalette.paper)
        }
    }
}

private struct CalendarEditSelection: Identifiable, Equatable {
    let date: Date
    var id: Date { date }
}

private struct CalendarDayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

private struct ScheduleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let onSave: (ShiftDay.Kind?, String?) -> Void
    @State private var selectedShift: ShiftDay.Kind?
    @State private var note: String

    init(
        date: Date,
        currentShift: ShiftDay.Kind?,
        currentNote: String?,
        onSave: @escaping (ShiftDay.Kind?, String?) -> Void
    ) {
        self.date = date
        self.onSave = onSave
        _selectedShift = State(initialValue: currentShift)
        _note = State(initialValue: currentNote ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("写班表")
                        .font(.custom("STSongti-SC-Light", size: 24, relativeTo: .title2))
                        .tracking(1.8)
                        .foregroundStyle(UsPalette.ink)
                    Text(dateLabel)
                        .font(.custom("STSongti-SC-Light", size: 13, relativeTo: .caption))
                        .foregroundStyle(UsPalette.mutedInk)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .font(.custom("STSongti-SC-Light", size: 14, relativeTo: .body))
                    .foregroundStyle(UsPalette.mutedInk)
                    .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                ForEach(ShiftDay.Kind.allCases, id: \.self) { kind in
                    ShiftChoice(kind: kind, selected: selectedShift == kind) {
                        selectedShift = kind
                    }
                }
            }

            Group {
                if selectedShift == .other {
                    HStack(spacing: 10) {
                        Image(systemName: "pencil.line")
                            .foregroundStyle(UsPalette.gold)
                        TextField("写下班次，例如：培训、临时班", text: $note)
                            .textInputAutocapitalization(.never)
                            .submitLabel(.done)
                    }
                    .font(.custom("STSongti-SC-Light", size: 14, relativeTo: .body))
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(UsPalette.blush.opacity(0.09))
                    )
                } else {
                    Text("休息日无需填写，清除当天排班即可。")
                        .font(.custom("STSongti-SC-Light", size: 13, relativeTo: .caption))
                        .foregroundStyle(UsPalette.mutedInk)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                }
            }

            HStack(spacing: 12) {
                Button {
                    selectedShift = nil
                    note = ""
                } label: {
                    Text("清除排班")
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedShift == nil ? UsPalette.coral : UsPalette.mutedInk)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(UsPalette.blush.opacity(selectedShift == nil ? 0.16 : 0.07))
                )

                Button {
                    onSave(selectedShift, selectedShift == .other ? normalizedNote : nil)
                } label: {
                    Text("保存班表")
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(UsPalette.coral.opacity(0.88))
                )
            }
            .font(.custom("STSongti-SC-Light", size: 15, relativeTo: .body))
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .sensoryFeedback(.selection, trigger: selectedShift)
        .accessibilityElement(children: .contain)
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }

    private var normalizedNote: String? {
        let value = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private struct ShiftChoice: View {
    let kind: ShiftDay.Kind
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .light))
                Text(label)
                    .font(.custom("STSongti-SC-Light", size: 14, relativeTo: .body))
            }
            .foregroundStyle(selected ? UsPalette.coral : UsPalette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(selected ? UsPalette.blush.opacity(0.18) : UsPalette.paper)
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(selected ? UsPalette.gold.opacity(0.72) : UsPalette.hairline.opacity(0.28), lineWidth: selected ? 1.2 : 0.7)
                    }
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var label: String {
        switch kind {
        case .early: return "早班"
        case .deputy: return "副班"
        case .other: return "其他"
        }
    }

    private var icon: String {
        switch kind {
        case .early: return "sunrise"
        case .deputy: return "person.2"
        case .other: return "ellipsis"
        }
    }
}

private struct CalendarDay: View {
    let date: Date
    let shift: ShiftDay.Kind?
    let shiftText: String?

    var body: some View {
        let isToday = Calendar.current.isDateInToday(date)
        ZStack {
            if shift != nil || isToday {
                Circle()
                    .fill(dayDisc(isToday: isToday))
                    .frame(width: isToday ? 34 : 31, height: isToday ? 34 : 31)
            }

            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.custom("Didot", size: 15, relativeTo: .body))
                    .foregroundStyle(isToday ? Color.white : UsPalette.ink)
                Text(shiftText ?? " ")
                    .font(.custom("STSongti-SC-Light", size: 9, relativeTo: .caption2))
                    .foregroundStyle(isToday ? Color.white.opacity(0.90) : markerColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: 42)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 50)
    }

    private func dayDisc(isToday: Bool) -> Color {
        if isToday { return UsPalette.coral.opacity(0.84) }
        switch shift {
        case .early: return UsPalette.gold.opacity(0.11)
        case .deputy: return UsPalette.sage.opacity(0.10)
        case .other: return UsPalette.blush.opacity(0.13)
        case .none: return .clear
        }
    }

    private var markerColor: Color {
        switch shift {
        case .early: return UsPalette.gold
        case .deputy: return UsPalette.sage
        case .other: return UsPalette.coral
        case .none: return .clear
        }
    }
}

struct AnniversaryDisplay {
    let title: String
    let number: String
    let unit: String
    let dateLabel: String
}

@MainActor
final class UsViewModel: ObservableObject {
    @Published var reminders: [Reminder] = []
    @Published var anniversaries: [Anniversary] = []
    @Published var thisWeek: [ShiftDay] = []
    @Published private(set) var savedShifts: [String: ShiftDay.Kind] = [:]
    @Published private(set) var savedShiftNotes: [String: String] = [:]
    @Published private(set) var clearedShiftKeys: Set<String> = []

    private let calendar = Calendar.current
    private let savedShiftsKey = "us.saved-shifts.v2"
    private let savedShiftNotesKey = "us.saved-shift-notes.v2"
    private let defaults: UserDefaults
    private let api: APIClient?
    @Published private(set) var reminderLoadError: String?
    @Published private(set) var loadingReminders = false

    var activeReminders: [Reminder] {
        reminders
            .filter { !$0.dismissedByKe }
            .sorted { $0.dueAt < $1.dueAt }
    }

    var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年 M月"
        return formatter.string(from: .now)
    }

    var weekRangeLabel: String {
        guard let first = thisWeek.first?.date, let last = thisWeek.last?.date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M.d"
        return "\(formatter.string(from: first)) — \(formatter.string(from: last))"
    }

    var monthCells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: .now),
              let dayRange = calendar.range(of: .day, in: .month, for: .now) else { return [] }
        let leading = (calendar.component(.weekday, from: interval.start) + 5) % 7
        return Array(repeating: nil, count: leading) + dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }.map(Optional.some)
    }

    init(defaults: UserDefaults = .standard, api: APIClient? = nil) {
        self.defaults = defaults
        self.api = api
        let today = calendar.startOfDay(for: .now)
        if let stored = defaults.dictionary(forKey: savedShiftsKey) as? [String: String] {
            savedShifts = stored.reduce(into: [:]) { result, entry in
                if let kind = ShiftDay.Kind(rawValue: entry.value) {
                    result[entry.key] = kind
                }
            }
            clearedShiftKeys = Set(stored.compactMap { $0.value == "none" ? $0.key : nil })
        }
        savedShiftNotes = defaults.dictionary(forKey: savedShiftNotesKey) as? [String: String] ?? [:]
        anniversaries = [
            Anniversary(id: "mine", title: "我的生日", date: calendar.date(byAdding: .day, value: 113, to: today) ?? today),
            Anniversary(id: "confession", title: "表白的日子", date: calendar.date(byAdding: .day, value: -320, to: today) ?? today, isYearly: false),
            Anniversary(id: "together", title: "在一起的日子", date: calendar.date(byAdding: .day, value: -286, to: today) ?? today, isYearly: false),
            Anniversary(id: "ke", title: "柯的生日", date: calendar.date(byAdding: .day, value: 204, to: today) ?? today),
        ]

        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-ui-test") || $0.hasPrefix("-preview-us") }) {
            let medicineTime = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: today) ?? today
            reminders = [
                Reminder(id: "r1", text: "吃维生素 D", dueAt: medicineTime, category: .medicine),
                Reminder(id: "r2", text: "周一有安排，提前半小时出发。", dueAt: Date().addingTimeInterval(86400), category: .work),
            ]
        }

        let weekday = calendar.component(.weekday, from: today)
        let monday = calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: today) ?? today
        let kinds: [ShiftDay.Kind?] = [nil, .early, .deputy, nil, .early, nil, .other]
        let notes: [String?] = [nil, nil, nil, nil, nil, nil, "培训"]
        thisWeek = (0..<7).map { index in
            let date = calendar.date(byAdding: .day, value: index, to: monday) ?? today
            let key = dateKey(date)
            let isCleared = clearedShiftKeys.contains(key)
            let kind = isCleared ? nil : (savedShifts[key] ?? kinds[index])
            let note = isCleared ? nil : (savedShiftNotes[key] ?? notes[index])
            return ShiftDay(id: "s\(index)", date: date, kind: kind, note: note)
        }
    }

    func loadReminders() async {
        guard let api else { return }
        loadingReminders = true
        defer { loadingReminders = false }
        do {
            async let scheduleTask = api.fetchSchedule()
            async let anniversariesTask = api.fetchAnniversaries()
            let (schedule, remoteAnniversaries) = try await (scheduleTask, anniversariesTask)
            reminders = Self.reminders(from: schedule.current)
            let resolvedAnniversaries = Self.anniversaries(from: remoteAnniversaries)
            if !resolvedAnniversaries.isEmpty {
                anniversaries = resolvedAnniversaries
            }
            reminderLoadError = nil
        } catch {
            reminderLoadError = "提醒暂时没有接上，请点重新连接或稍后再试。"
        }
    }

    static func anniversaries(from rows: [RemoteAnniversary]) -> [Anniversary] {
        let preferredOrder = ["表白的日子", "在一起的日子", "佳佳的生日", "柯的生日"]
        let byName = Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0) })
        return preferredOrder.compactMap { name in
            guard let row = byName[name], let date = CompanionDate.parse(row.date) else { return nil }
            return Anniversary(
                id: String(row.id),
                title: row.name,
                date: date,
                isYearly: name.contains("生日")
            )
        }
    }

    static func reminders(from rows: [RemoteReminder]) -> [Reminder] {
        rows.map { row in
            Reminder(
                id: String(row.id),
                text: row.text,
                dueAt: CompanionDate.parse(row.scheduled_for) ?? .now,
                dismissedByKe: row.status != "pending",
                category: .other
            )
        }
    }

    func display(for item: Anniversary) -> AnniversaryDisplay {
        let number = item.isYearly ? daysUntil(item) : daysTogether(since: item.date)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月 d 日"
        return AnniversaryDisplay(
            title: item.title,
            number: "\(number)",
            unit: item.isYearly ? "天后" : "天",
            dateLabel: formatter.string(from: item.date)
        )
    }

    func daysUntil(_ item: Anniversary) -> Int {
        let today = calendar.startOfDay(for: .now)
        var components = calendar.dateComponents([.month, .day], from: item.date)
        components.year = calendar.component(.year, from: today)
        var target = calendar.date(from: components) ?? item.date
        if target < today { target = calendar.date(byAdding: .year, value: 1, to: target) ?? target }
        return max(0, calendar.dateComponents([.day], from: today, to: target).day ?? 0)
    }

    func daysTogether(since date: Date) -> Int {
        max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? 0)
    }

    func shiftLabel(_ kind: ShiftDay.Kind) -> String {
        switch kind {
        case .early: return "早班"
        case .deputy: return "副班"
        case .other: return "其他"
        }
    }

    func shiftDisplay(_ kind: ShiftDay.Kind, on date: Date) -> String {
        if kind == .other, let note = shiftNote(on: date), !note.isEmpty { return note }
        return shiftLabel(kind)
    }

    func shiftDetail(_ kind: ShiftDay.Kind, on date: Date) -> String {
        switch kind {
        case .early: return "早班"
        case .deputy: return "副班"
        case .other: return shiftNote(on: date) ?? "其他班次"
        }
    }

    func weekdayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }

    func weekdayFullLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }

    func shift(on date: Date) -> ShiftDay.Kind? {
        let key = dateKey(date)
        if clearedShiftKeys.contains(key) { return nil }
        return savedShifts[key] ?? thisWeek.first { calendar.isDate($0.date, inSameDayAs: date) }?.kind
    }

    func shiftNote(on date: Date) -> String? {
        let key = dateKey(date)
        if clearedShiftKeys.contains(key) { return nil }
        return savedShiftNotes[key] ?? thisWeek.first { calendar.isDate($0.date, inSameDayAs: date) }?.note
    }

    func setShift(_ kind: ShiftDay.Kind?, note: String? = nil, on date: Date) {
        let key = dateKey(date)
        if let kind {
            savedShifts[key] = kind
            if kind == .other, let note, !note.isEmpty {
                savedShiftNotes[key] = note
            } else {
                savedShiftNotes.removeValue(forKey: key)
            }
            clearedShiftKeys.remove(key)
        } else {
            savedShifts.removeValue(forKey: key)
            savedShiftNotes.removeValue(forKey: key)
            clearedShiftKeys.insert(key)
        }

        if let index = thisWeek.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            thisWeek[index] = ShiftDay(
                id: thisWeek[index].id,
                date: thisWeek[index].date,
                kind: kind,
                note: kind == .other ? note : nil
            )
        }

        var stored = savedShifts.mapValues(\.rawValue)
        for key in clearedShiftKeys { stored[key] = "none" }
        defaults.set(stored, forKey: savedShiftsKey)
        defaults.set(savedShiftNotes, forKey: savedShiftNotesKey)
    }

    func calendarDayAccessibilityLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        if let kind = shift(on: date) {
            return "\(formatter.string(from: date))，\(shiftDetail(kind, on: date))"
        }
        return "\(formatter.string(from: date))，未排班"
    }

    func calendarDayIdentifier(_ date: Date) -> String {
        "calendar-day-\(dateKey(date))"
    }

    func reminderDetail(_ item: Reminder) -> String {
        item.category == .medicine ? "饭后 1 粒" : reminderTime(item)
    }

    func reminderHeadline(_ item: Reminder) -> String {
        guard item.category == .medicine else { return item.text }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "aaa h:mm"
        return "\(formatter.string(from: item.dueAt)) · \(item.text)"
    }

    func reminderTime(_ item: Reminder) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = calendar.isDateInToday(item.dueAt) ? "今天 HH:mm" : "M月d日 HH:mm"
        return formatter.string(from: item.dueAt)
    }

    private func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

enum OrbitSelectionMath {
    static func nearestIndex(position: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(Int(position.rounded()), 0), count - 1)
    }

    static func isVisible(relativePosition: CGFloat) -> Bool { abs(relativePosition) <= 1.24 }

    static func visibleIndices(count: Int, position: CGFloat) -> [Int] {
        guard count > 0 else { return [] }
        return (0..<count).filter { isVisible(relativePosition: CGFloat($0) - position) }
    }
}

#Preview {
    UsView().environmentObject(Theme.shared)
}
