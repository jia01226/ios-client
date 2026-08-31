import SwiftUI

// 【我们】—— 月球里的纪念日，以及柯替她记住的事。
//
// 交互约定：
// - 月球是真正的 3D 球体，可连续旋转 360°。
// - 纪念日是有限的小行星队列；选中项永远吸附在左侧中点。
// - 队列两端不循环，没有相邻数据时对应位置保持空白。
// - 提醒没有勾选框；过期后安静收起。

struct UsView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var vm = UsViewModel()
    @State private var selectedAnniversaryIndex = 1

    var body: some View {
        GeometryReader { viewport in
            ZStack {
                theme.effectiveBackground
                    .ignoresSafeArea()

                UsCosmosBackground(reduceMotion: reduceMotion)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: theme.metric.gapM) {
                        pageHeader
                            .padding(.horizontal, theme.metric.pagePadding)

                        MoonOrbitSelector(
                            events: vm.anniversaries,
                            selectedIndex: $selectedAnniversaryIndex
                        )
                        .frame(height: 372)
                        .padding(.leading, theme.metric.pagePadding)
                        .clipped()

                        if let selectedAnniversary {
                            countdown(for: selectedAnniversary)
                                .padding(.horizontal, theme.metric.pagePadding)
                        }

                        Color.clear
                            .frame(height: 72)
                            .accessibilityHidden(true)

                        remindersSection
                            .padding(.horizontal, theme.metric.pagePadding)

                        Spacer(minLength: 0)

                        shiftSection
                            .padding(.horizontal, theme.metric.pagePadding)
                    }
                    .frame(
                        minHeight: max(0, viewport.size.height - theme.metric.gapM - theme.metric.gapS),
                        alignment: .top
                    )
                    .padding(.top, theme.metric.gapM)
                    .padding(.bottom, theme.metric.gapS)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .onChange(of: vm.anniversaries.map(\.id)) { _, ids in
            guard !ids.isEmpty else {
                selectedAnniversaryIndex = 0
                return
            }
            selectedAnniversaryIndex = min(selectedAnniversaryIndex, ids.count - 1)
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: theme.metric.gapXS) {
                Text("我们")
                    .font(.custom("STSongti-SC-Light", size: 42, relativeTo: .largeTitle))
                    .tracking(4.2)
                    .foregroundStyle(theme.color.textPrimary)
                Text("月亮替我们记得")
                    .font(.custom("STSongti-SC-Light", size: 14, relativeTo: .subheadline))
                    .tracking(2.0)
                    .foregroundStyle(theme.color.textSecondary)
            }

            Spacer()

            Image(systemName: "plus")
                .font(.system(size: 21, weight: .light))
                .foregroundStyle(theme.effectiveAccent)
                .padding(.top, 8)
                .accessibilityLabel("添加纪念日")
        }
    }

    private var selectedAnniversary: Anniversary? {
        guard vm.anniversaries.indices.contains(selectedAnniversaryIndex) else { return nil }
        return vm.anniversaries[selectedAnniversaryIndex]
    }

    private func countdown(for anniversary: Anniversary) -> some View {
        let days = vm.daysUntil(anniversary)

        return HStack(alignment: .lastTextBaseline, spacing: theme.metric.gapS) {
            Text("\(days)")
                .font(.custom("Didot", size: 64, relativeTo: .largeTitle))
                .fontWeight(.regular)
                .tracking(-2.2)
                .monospacedDigit()
                .foregroundStyle(theme.color.textPrimary)
                .contentTransition(
                    reduceMotion
                        ? .interpolate
                        : .numericText(value: Double(days))
                )
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.18)
                        : .spring(response: 0.42, dampingFraction: 0.88),
                    value: days
                )

            Text("天后")
                .font(.custom("STSongti-SC-Light", size: 16, relativeTo: .body))
                .tracking(1.0)
                .foregroundStyle(theme.color.textSecondary)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(anniversary.title)，\(days)天后")
    }

    private var remindersSection: some View {
        KeRemembersSummary(
            reminders: vm.activeReminders,
            reduceMotion: reduceMotion
        )
        .accessibilityIdentifier("us-ke-remembers")
    }

    private var shiftSection: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapM) {
            Text("这周排班")
                .font(.custom("STSongti-SC-Regular", size: 20, relativeTo: .title3))
                .tracking(1.0)
                .foregroundStyle(theme.color.textPrimary)

            HStack(spacing: theme.metric.gapS) {
                ForEach(vm.thisWeek) { day in
                    VStack(spacing: theme.metric.gapXS) {
                        Text(vm.weekdayLabel(day.date))
                            .font(theme.font.caption)
                            .foregroundStyle(theme.color.textSecondary)
                        Text(vm.shiftLabel(day.kind))
                            .font(theme.font.shiftBadge)
                            .foregroundStyle(
                                day.kind == .off
                                    ? theme.color.textSecondary
                                    : theme.color.textPrimary
                            )
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(
                        RoundedRectangle(cornerRadius: theme.metric.radiusChip, style: .continuous)
                            .fill(day.kind == .off ? Color.clear : theme.color.card.opacity(0.72))
                    )
                }
            }
        }
    }
}

// MARK: - 月球与小行星选择器

private struct MoonOrbitSelector: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let events: [Anniversary]
    @Binding var selectedIndex: Int

    @State private var orbitalPosition: CGFloat = 1
    @State private var moonYaw: Double = -0.18
    @State private var moonPitch: Double = -0.08
    @State private var dragOriginPosition: CGFloat?
    @State private var dragOriginYaw: Double?
    @State private var dragOriginPitch: Double?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let center = CGPoint(x: width - 10, y: proxy.size.height / 2)
            let orbitRadius = CGSize(
                width: min(224, width * 0.56),
                height: min(160, proxy.size.height * 0.43)
            )
            let moonSize = min(max(width * 1.08, 390), 446)

            ZStack {
                Ellipse()
                    .stroke(
                        theme.color.accentSoft.opacity(0.72),
                        style: StrokeStyle(lineWidth: 0.8, dash: [4, 6])
                    )
                    .frame(width: orbitRadius.width * 2, height: orbitRadius.height * 2)
                    .position(center)
                    .accessibilityHidden(true)

                Circle()
                    .fill(theme.effectiveAccent.opacity(0.10))
                    .frame(width: moonSize - 8, height: moonSize - 8)
                    .blur(radius: 15)
                    .position(center)
                    .accessibilityHidden(true)

                MoonSceneView(yaw: moonYaw, pitch: moonPitch)
                    .frame(width: moonSize, height: moonSize)
                    .position(center)
                    .accessibilityHidden(true)

                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    let relativePosition = CGFloat(index) - orbitalPosition

                    if OrbitSelectionMath.isVisible(relativePosition: relativePosition) {
                        let position = planetPosition(
                            relativePosition: relativePosition,
                            center: center,
                            radius: orbitRadius
                        )

                        OrbitEventMarker(
                            title: event.title,
                            activeProgress: max(0, 1 - abs(relativePosition)),
                            selected: index == selectedIndex
                        )
                        .position(x: position.x - 74, y: position.y)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(dragGesture)
            .sensoryFeedback(.alignment, trigger: selectedIndex)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("us-moon-orbit-selector")
            .accessibilityLabel("纪念日月球")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("上下滑动切换纪念日，左右滑动旋转月球")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    select(index: min(selectedIndex + 1, events.count - 1))
                case .decrement:
                    select(index: max(selectedIndex - 1, 0))
                @unknown default:
                    break
                }
            }
        }
        .onAppear(perform: synchronizeSelection)
        .onChange(of: events.map(\.id)) { _, _ in synchronizeSelection() }
    }

    private var selectedEvent: Anniversary? {
        guard events.indices.contains(selectedIndex) else { return nil }
        return events[selectedIndex]
    }

    private var accessibilityValue: String {
        guard let selectedEvent else { return "还没有纪念日" }
        return selectedEvent.title
    }

    private func planetPosition(
        relativePosition: CGFloat,
        center: CGPoint,
        radius: CGSize
    ) -> CGPoint {
        let angle = Double.pi + Double(relativePosition * 0.79)
        return CGPoint(
            x: center.x + radius.width * CGFloat(cos(angle)),
            y: center.y - radius.height * CGFloat(sin(angle))
        )
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard !events.isEmpty else { return }

                if dragOriginPosition == nil {
                    dragOriginPosition = orbitalPosition
                    dragOriginYaw = moonYaw
                    dragOriginPitch = moonPitch
                }

                let startPosition = dragOriginPosition ?? orbitalPosition
                let startYaw = dragOriginYaw ?? moonYaw
                let startPitch = dragOriginPitch ?? moonPitch

                let proposed = startPosition - value.translation.height / 112
                orbitalPosition = rubberBanded(proposed)
                moonYaw = startYaw + Double(value.translation.width) * 0.009
                moonPitch = clampedPitch(
                    startPitch - Double(value.translation.height) * 0.0032
                )

                let candidate = nearestIndex(to: orbitalPosition)
                if candidate != selectedIndex {
                    withAnimation(.easeOut(duration: 0.12)) {
                        selectedIndex = candidate
                    }
                }
            }
            .onEnded { value in
                guard !events.isEmpty else { return }

                let startPosition = dragOriginPosition ?? orbitalPosition
                let projectedPosition = startPosition - value.predictedEndTranslation.height / 112
                let targetIndex = nearestIndex(to: projectedPosition)
                let projectedYaw = moonYaw
                    + Double(value.predictedEndTranslation.width - value.translation.width) * 0.003

                selectedIndex = targetIndex
                withAnimation(settleAnimation) {
                    orbitalPosition = CGFloat(targetIndex)
                    moonYaw = projectedYaw
                }

                dragOriginPosition = nil
                dragOriginYaw = nil
                dragOriginPitch = nil
            }
    }

    private var settleAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(response: 0.42, dampingFraction: 0.84, blendDuration: 0.08)
    }

    private func nearestIndex(to position: CGFloat) -> Int {
        OrbitSelectionMath.nearestIndex(position: position, count: events.count)
    }

    private func rubberBanded(_ position: CGFloat) -> CGFloat {
        guard !events.isEmpty else { return 0 }
        let upperBound = CGFloat(events.count - 1)

        if position < 0 {
            return -rubberBand(distance: -position)
        }
        if position > upperBound {
            return upperBound + rubberBand(distance: position - upperBound)
        }
        return position
    }

    private func rubberBand(distance: CGFloat) -> CGFloat {
        (distance * 0.38) / (1 + distance * 0.9)
    }

    private func clampedPitch(_ value: Double) -> Double {
        min(max(value, -0.72), 0.72)
    }

    private func select(index: Int) {
        guard events.indices.contains(index) else { return }
        selectedIndex = index
        withAnimation(settleAnimation) {
            orbitalPosition = CGFloat(index)
        }
    }

    private func synchronizeSelection() {
        guard !events.isEmpty else {
            selectedIndex = 0
            orbitalPosition = 0
            return
        }

        selectedIndex = min(max(selectedIndex, 0), events.count - 1)
        orbitalPosition = CGFloat(selectedIndex)
    }
}

enum OrbitSelectionMath {
    static func nearestIndex(position: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(Int(position.rounded()), 0), count - 1)
    }

    static func isVisible(relativePosition: CGFloat) -> Bool {
        abs(relativePosition) <= 1.24
    }

    static func visibleIndices(count: Int, position: CGFloat) -> [Int] {
        guard count > 0 else { return [] }
        return (0..<count).filter {
            isVisible(relativePosition: CGFloat($0) - position)
        }
    }
}

private struct MemoryPlanet: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let activeProgress: CGFloat
    let selected: Bool

    var body: some View {
        let proximity = min(max(activeProgress, 0), 1)
        let illuminated = CGFloat(pow(Double(proximity), 1.55))
        let diameter = 14 + 14 * illuminated

        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.78),
                            theme.color.accentSoft.opacity(0.48),
                            theme.effectiveAccent.opacity(0.16),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter
                    )
                )
                .frame(width: diameter * 2.25, height: diameter * 2.25)
                .blur(radius: 1.5 + 2.5 * illuminated)
                .opacity(0.08 + 0.72 * illuminated)

            Image("MemoryPlanet")
                .resizable()
                .scaledToFit()
                .frame(width: diameter, height: diameter)
                .saturation(0.64 + 0.42 * illuminated)
                .brightness(-0.10 + 0.19 * illuminated)
                .contrast(0.94 + 0.10 * illuminated)
                .opacity(0.56 + 0.44 * proximity)
                .shadow(
                    color: theme.color.textPrimary.opacity(0.12 + 0.08 * illuminated),
                    radius: 2.5,
                    x: 0,
                    y: 1.5
                )
                .shadow(
                    color: theme.effectiveAccent.opacity(0.46 * illuminated),
                    radius: 8 * illuminated,
                    x: 0,
                    y: 1
                )

            AsteroidFlare()
                .offset(x: -diameter * 0.24, y: -diameter * 0.23)
                .scaleEffect(0.72 + 0.34 * illuminated)
                .opacity(selected ? 0.94 : 0.18 * illuminated)
        }
        .frame(width: 52, height: 52)
        .scaleEffect(selected ? 1.06 : 1)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.14)
                : .spring(response: 0.34, dampingFraction: 0.86),
            value: selected
        )
        .accessibilityHidden(true)
    }
}

private struct AsteroidFlare: View {
    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.92))
                .frame(width: 8, height: 0.8)
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.92))
                .frame(width: 0.8, height: 8)
            Circle()
                .fill(Color.white)
                .frame(width: 2.2, height: 2.2)
        }
        .shadow(color: Color.white.opacity(0.72), radius: 2, x: 0, y: 1)
        .accessibilityHidden(true)
    }
}

private struct OrbitEventMarker: View {
    @EnvironmentObject private var theme: Theme
    let title: String
    let activeProgress: CGFloat
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(
                    .custom(
                        selected ? "STSongti-SC-Regular" : "STSongti-SC-Light",
                        size: 16,
                        relativeTo: .callout
                    )
                )
                .tracking(selected ? 1.1 : 0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .foregroundStyle(selected ? theme.effectiveAccent : theme.color.textPrimary)
                .frame(width: 96, alignment: .trailing)

            if selected {
                Rectangle()
                    .fill(theme.effectiveAccent.opacity(0.82))
                    .frame(width: 22, height: 0.8)
            }

            MemoryPlanet(activeProgress: activeProgress, selected: selected)
        }
        .frame(width: 160, alignment: .trailing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 背景星空

private struct UsBackgroundStar: Identifiable {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let phase: CGFloat
    let speed: CGFloat
    let peakOpacity: CGFloat
    let warm: Bool
    let glint: Bool
}

private struct UsCosmosBackground: View {
    let reduceMotion: Bool

    @State private var startedAt = Date()

    private let stars: [UsBackgroundStar] = [
        .init(id: 0, x: 0.06, y: 0.08, size: 0.8, phase: 0.2, speed: 0.42, peakOpacity: 0.15, warm: false, glint: false),
        .init(id: 1, x: 0.18, y: 0.16, size: 1.1, phase: 2.4, speed: 0.31, peakOpacity: 0.12, warm: true, glint: false),
        .init(id: 2, x: 0.42, y: 0.10, size: 1.7, phase: 4.2, speed: 0.27, peakOpacity: 0.18, warm: false, glint: true),
        .init(id: 3, x: 0.67, y: 0.18, size: 0.9, phase: 1.5, speed: 0.48, peakOpacity: 0.13, warm: true, glint: false),
        .init(id: 4, x: 0.89, y: 0.25, size: 1.3, phase: 5.3, speed: 0.36, peakOpacity: 0.15, warm: false, glint: false),
        .init(id: 5, x: 0.11, y: 0.29, size: 1.5, phase: 3.1, speed: 0.52, peakOpacity: 0.16, warm: false, glint: true),
        .init(id: 6, x: 0.32, y: 0.36, size: 0.7, phase: 0.8, speed: 0.39, peakOpacity: 0.11, warm: true, glint: false),
        .init(id: 7, x: 0.61, y: 0.33, size: 1.0, phase: 5.8, speed: 0.29, peakOpacity: 0.12, warm: false, glint: false),
        .init(id: 8, x: 0.82, y: 0.43, size: 1.6, phase: 2.0, speed: 0.25, peakOpacity: 0.18, warm: true, glint: true),
        .init(id: 9, x: 0.04, y: 0.51, size: 0.8, phase: 4.8, speed: 0.46, peakOpacity: 0.12, warm: true, glint: false),
        .init(id: 10, x: 0.24, y: 0.58, size: 1.2, phase: 1.1, speed: 0.33, peakOpacity: 0.14, warm: false, glint: false),
        .init(id: 11, x: 0.49, y: 0.49, size: 0.7, phase: 3.8, speed: 0.54, peakOpacity: 0.10, warm: false, glint: false),
        .init(id: 12, x: 0.72, y: 0.57, size: 1.4, phase: 0.4, speed: 0.41, peakOpacity: 0.16, warm: true, glint: true),
        .init(id: 13, x: 0.94, y: 0.63, size: 0.9, phase: 5.0, speed: 0.28, peakOpacity: 0.12, warm: false, glint: false),
        .init(id: 14, x: 0.14, y: 0.70, size: 1.5, phase: 2.8, speed: 0.47, peakOpacity: 0.16, warm: true, glint: true),
        .init(id: 15, x: 0.39, y: 0.76, size: 0.8, phase: 1.7, speed: 0.37, peakOpacity: 0.11, warm: false, glint: false),
        .init(id: 16, x: 0.63, y: 0.69, size: 1.1, phase: 4.5, speed: 0.24, peakOpacity: 0.14, warm: true, glint: false),
        .init(id: 17, x: 0.86, y: 0.80, size: 1.6, phase: 0.9, speed: 0.45, peakOpacity: 0.17, warm: false, glint: true),
        .init(id: 18, x: 0.27, y: 0.86, size: 0.9, phase: 3.6, speed: 0.30, peakOpacity: 0.11, warm: false, glint: false),
        .init(id: 19, x: 0.53, y: 0.91, size: 1.2, phase: 5.5, speed: 0.40, peakOpacity: 0.14, warm: true, glint: false),
        .init(id: 20, x: 0.76, y: 0.94, size: 0.7, phase: 2.2, speed: 0.51, peakOpacity: 0.10, warm: false, glint: false),
        .init(id: 21, x: 0.96, y: 0.90, size: 1.4, phase: 1.0, speed: 0.32, peakOpacity: 0.15, warm: true, glint: true),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(startedAt))
            let time = CGFloat(elapsed)

            GeometryReader { _ in
                ZStack {
                    Canvas { context, size in
                        for star in stars {
                            let wave = 0.5 + 0.5 * sin(time * star.speed + star.phase)
                            let shimmer = reduceMotion ? 0.22 : wave * wave * wave * wave
                            let opacity = 0.018 + star.peakOpacity * shimmer
                            let center = CGPoint(x: size.width * star.x, y: size.height * star.y)
                            let radius = star.size * (0.72 + 0.34 * shimmer)

                            let color = star.warm
                                ? Color(red: 0.82, green: 0.66, blue: 0.38)
                                : Color(red: 0.69, green: 0.66, blue: 0.87)

                            context.fill(
                                Path(ellipseIn: CGRect(
                                    x: center.x - radius / 2,
                                    y: center.y - radius / 2,
                                    width: radius,
                                    height: radius
                                )),
                                with: .color(color.opacity(Double(opacity)))
                            )

                            if star.glint, shimmer > 0.46 {
                                var glintPath = Path()
                                glintPath.move(to: CGPoint(x: center.x - radius * 2.5, y: center.y))
                                glintPath.addLine(to: CGPoint(x: center.x + radius * 2.5, y: center.y))
                                glintPath.move(to: CGPoint(x: center.x, y: center.y - radius * 2.5))
                                glintPath.addLine(to: CGPoint(x: center.x, y: center.y + radius * 2.5))
                                context.stroke(
                                    glintPath,
                                    with: .color(color.opacity(Double(opacity * 0.66))),
                                    style: StrokeStyle(lineWidth: 0.45, lineCap: .round)
                                )
                            }
                        }

                        if !reduceMotion, let meteor = activeMeteor(elapsed: elapsed) {
                            let eased = meteor.progress * meteor.progress * (3 - 2 * meteor.progress)
                            let flare = sin(meteor.progress * .pi)
                            let head = CGPoint(
                                x: size.width * (meteor.startX + meteor.travelX * eased),
                                y: size.height * (meteor.startY + meteor.travelY * eased)
                            )
                            let travel = CGVector(
                                dx: size.width * meteor.travelX,
                                dy: size.height * meteor.travelY
                            )
                            let travelLength = max(1, hypot(travel.dx, travel.dy))
                            let tailLength = meteor.tailLength * flare
                            let tail = CGPoint(
                                x: head.x - travel.dx / travelLength * tailLength,
                                y: head.y - travel.dy / travelLength * tailLength
                            )

                            var streak = Path()
                            streak.move(to: tail)
                            streak.addLine(to: head)
                            let meteorColor = meteor.warm
                                ? Color(red: 0.91, green: 0.73, blue: 0.43)
                                : Color(red: 0.73, green: 0.69, blue: 0.91)

                            context.stroke(
                                streak,
                                with: .linearGradient(
                                    Gradient(colors: [
                                        meteorColor.opacity(0),
                                        meteorColor.opacity(Double(0.18 * flare)),
                                        Color.white.opacity(Double(0.42 * flare)),
                                    ]),
                                    startPoint: tail,
                                    endPoint: head
                                ),
                                style: StrokeStyle(lineWidth: 0.72, lineCap: .round)
                            )
                            context.fill(
                                Path(ellipseIn: CGRect(
                                    x: head.x - 0.9,
                                    y: head.y - 0.9,
                                    width: 1.8,
                                    height: 1.8
                                )),
                                with: .color(Color.white.opacity(Double(0.55 * flare)))
                            )
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func meteorState(elapsed: TimeInterval) -> BackgroundMeteorState? {
        let period: TimeInterval = 18.4
        let delay: TimeInterval = 3.6
        let duration: TimeInterval = 1.05
        let phase = elapsed.truncatingRemainder(dividingBy: period)
        guard phase >= delay, phase <= delay + duration else { return nil }

        let progress = CGFloat((phase - delay) / duration)
        let cycle = max(0, Int(elapsed / period)) % 4
        let lanes: [BackgroundMeteorState] = [
            .init(progress: progress, startX: 0.08, startY: 0.27, travelX: 0.24, travelY: 0.065, tailLength: 42, warm: false),
            .init(progress: progress, startX: 0.56, startY: 0.46, travelX: 0.20, travelY: 0.052, tailLength: 34, warm: true),
            .init(progress: progress, startX: 0.18, startY: 0.66, travelX: 0.27, travelY: 0.075, tailLength: 48, warm: true),
            .init(progress: progress, startX: 0.63, startY: 0.79, travelX: 0.18, travelY: 0.045, tailLength: 30, warm: false),
        ]
        return lanes[cycle]
    }

    private func activeMeteor(elapsed: TimeInterval) -> BackgroundMeteorState? {
        if ProcessInfo.processInfo.arguments.contains("-ui-test-us-cosmos-preview") {
            return BackgroundMeteorState(
                progress: 0.72,
                startX: 0.11,
                startY: 0.58,
                travelX: 0.23,
                travelY: 0.06,
                tailLength: 40,
                warm: true
            )
        }
        return meteorState(elapsed: elapsed)
    }
}

private struct BackgroundMeteorState {
    let progress: CGFloat
    let startX: CGFloat
    let startY: CGFloat
    let travelX: CGFloat
    let travelY: CGFloat
    let tailLength: CGFloat
    let warm: Bool
}

// MARK: - 柯记着入口

private struct KeRemembersSummary: View {
    @EnvironmentObject private var theme: Theme
    let reminders: [Reminder]
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StarDivider()
                .padding(.bottom, 24)

            ZStack(alignment: .leading) {
                ReminderStarGauze(reduceMotion: reduceMotion)
                    .frame(height: 148)
                    .offset(y: 14)

                VStack(alignment: .leading, spacing: 18) {
                    Text("柯记着")
                        .font(.custom("STSongti-SC-Regular", size: 22, relativeTo: .title3))
                        .tracking(2.0)
                        .foregroundStyle(theme.color.textPrimary)

                    if let nextReminder = reminders.first {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(nextReminder.text)
                                    .font(.custom("STSongti-SC-Light", size: 16.5, relativeTo: .body))
                                    .tracking(0.5)
                                    .lineSpacing(4)
                                    .foregroundStyle(theme.color.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(timeLabel(for: nextReminder))
                                    .font(.custom("STSongti-SC-Light", size: 13.5, relativeTo: .caption))
                                    .tracking(0.7)
                                    .foregroundStyle(theme.effectiveAccent)
                            }
                            .layoutPriority(1)

                            Spacer(minLength: 8)

                            Image(systemName: "arrow.right")
                                .font(.system(size: 18, weight: .ultraLight))
                                .foregroundStyle(theme.effectiveAccent)
                                .frame(width: 44, height: 44)
                                .accessibilityHidden(true)
                        }
                    } else {
                        Text("暂时没有要记着的事")
                            .font(.custom("STSongti-SC-Light", size: 15, relativeTo: .body))
                            .tracking(0.7)
                            .foregroundStyle(theme.color.textSecondary)
                    }
                }
                .padding(.bottom, 18)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let nextReminder = reminders.first else { return "柯记着，暂时没有提醒" }
        return "柯记着，\(nextReminder.text)，\(timeLabel(for: nextReminder))"
    }

    private func timeLabel(for reminder: Reminder) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"

        if Calendar.current.isDateInToday(reminder.dueAt) {
            return "今天 \(formatter.string(from: reminder.dueAt))"
        }
        if Calendar.current.isDateInTomorrow(reminder.dueAt) {
            return "明天 \(formatter.string(from: reminder.dueAt))"
        }

        formatter.dateFormat = "M月d日"
        return formatter.string(from: reminder.dueAt)
    }
}

private struct StarDivider: View {
    var body: some View {
        HStack(spacing: 0) {
            StarDiamond()

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.76, green: 0.58, blue: 0.29).opacity(0.64),
                            Color(red: 0.76, green: 0.58, blue: 0.29).opacity(0.18),
                            Color.clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.65)
        }
        .accessibilityHidden(true)
    }
}

private struct StarDiamond: View {
    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .frame(width: 10, height: 0.7)
            Capsule(style: .continuous)
                .frame(width: 0.7, height: 10)
        }
        .foregroundStyle(Color(red: 0.76, green: 0.58, blue: 0.29).opacity(0.78))
        .frame(width: 12, height: 12)
    }
}

private struct ReminderStarGauze: View {
    let reduceMotion: Bool

    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(startedAt))
            let drift = reduceMotion ? 0 : CGFloat(sin(elapsed * 0.22)) * 7

            Canvas { context, size in
                for index in 0..<7 {
                    let t = CGFloat(index) / 6
                    let baseY = size.height * (0.38 + t * 0.23)
                    var strand = Path()
                    strand.move(to: CGPoint(x: -24 + drift, y: baseY + 9 * t))
                    strand.addCurve(
                        to: CGPoint(x: size.width + 22 + drift, y: baseY - 7 * t),
                        control1: CGPoint(x: size.width * 0.28, y: baseY - 27 + t * 8),
                        control2: CGPoint(x: size.width * 0.69, y: baseY + 31 - t * 9)
                    )

                    let strandColor = index.isMultiple(of: 2)
                        ? Color(red: 0.77, green: 0.70, blue: 0.91)
                        : Color(red: 0.86, green: 0.70, blue: 0.42)
                    context.stroke(
                        strand,
                        with: .color(strandColor.opacity(0.075 - Double(t) * 0.018)),
                        style: StrokeStyle(lineWidth: 0.48, lineCap: .round)
                    )
                }

                let points: [(CGFloat, CGFloat, CGFloat, Bool)] = [
                    (0.08, 0.41, 0.8, true), (0.17, 0.55, 0.55, false),
                    (0.29, 0.36, 0.7, false), (0.41, 0.61, 0.6, true),
                    (0.54, 0.45, 0.85, false), (0.63, 0.57, 0.55, true),
                    (0.76, 0.39, 0.72, false), (0.86, 0.53, 0.65, true),
                    (0.94, 0.43, 0.5, false),
                ]
                for point in points {
                    let center = CGPoint(
                        x: size.width * point.0 + drift * point.1,
                        y: size.height * point.1
                    )
                    let color = point.3
                        ? Color(red: 0.86, green: 0.70, blue: 0.42)
                        : Color(red: 0.76, green: 0.70, blue: 0.91)
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: center.x - point.2,
                            y: center.y - point.2,
                            width: point.2 * 2,
                            height: point.2 * 2
                        )),
                        with: .color(color.opacity(0.19))
                    )
                }

                for index in 0..<3 {
                    let inset = CGFloat(index) * 8
                    let rippleRect = CGRect(
                        x: size.width * 0.70 - inset / 2,
                        y: size.height * 0.59 - inset / 4,
                        width: size.width * 0.22 + inset,
                        height: 9 + inset / 2
                    )
                    context.stroke(
                        Path(ellipseIn: rippleRect),
                        with: .color(Color(red: 0.81, green: 0.65, blue: 0.39).opacity(0.065)),
                        style: StrokeStyle(lineWidth: 0.45)
                    )
                }
            }
        }
        .mask(
            LinearGradient(
                colors: [.clear, .white, .white, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - ViewModel（假数据版）

@MainActor
final class UsViewModel: ObservableObject {
    @Published var reminders: [Reminder] = []
    @Published var anniversaries: [Anniversary] = []
    @Published var thisWeek: [ShiftDay] = []

    var activeReminders: [Reminder] {
        reminders
            .filter { !$0.dismissedByKe && $0.dueAt > Date().addingTimeInterval(-86400) }
            .sorted { $0.dueAt < $1.dueAt }
    }

    init() {
        // 假数据：顺序就是轨道顺序；正式接口返回多少条，轨道就出现多少颗小行星。
        anniversaries = [
            Anniversary(
                id: "mine",
                title: "我的生日",
                date: Date().addingTimeInterval(86400 * 113)
            ),
            Anniversary(
                id: "ours",
                title: "我们的纪念日",
                date: Date().addingTimeInterval(86400 * 28)
            ),
            Anniversary(
                id: "ke",
                title: "柯的生日",
                date: Date().addingTimeInterval(86400 * 204)
            ),
        ]

        reminders = [
            Reminder(
                id: "r1",
                text: "把明天要带的东西放进包里。",
                dueAt: Date().addingTimeInterval(3600),
                category: .other
            ),
            Reminder(
                id: "r2",
                text: "周一有安排，提前半小时出发。",
                dueAt: Date().addingTimeInterval(86400),
                category: .work
            ),
        ]

        let calendar = Calendar.current
        let start = calendar.date(
            byAdding: .day,
            value: -calendar.component(.weekday, from: .now) + 2,
            to: .now
        ) ?? .now
        thisWeek = (0..<7).map { index in
            ShiftDay(
                id: "s\(index)",
                date: calendar.date(byAdding: .day, value: index, to: start) ?? .now,
                kind: [.off, .evening, .evening, .off, .evening, .off, .off][index]
            )
        }
    }

    func daysUntil(_ anniversary: Anniversary) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var target = calendar.startOfDay(for: anniversary.date)

        if anniversary.isYearly {
            let monthAndDay = calendar.dateComponents([.month, .day], from: target)
            var components = monthAndDay
            components.year = calendar.component(.year, from: today)
            target = calendar.date(from: components) ?? target
            if target < today {
                target = calendar.date(byAdding: .year, value: 1, to: target) ?? target
            }
        }

        return max(0, calendar.dateComponents([.day], from: today, to: target).day ?? 0)
    }

    func weekdayLabel(_ date: Date) -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        return names[Calendar.current.component(.weekday, from: date) - 1]
    }

    func shiftLabel(_ kind: ShiftDay.Kind) -> String {
        switch kind {
        case .off: return "休"
        case .day: return "白"
        case .evening: return "晚"
        case .night: return "夜"
        }
    }
}

#Preview {
    UsView().environmentObject(Theme.shared)
}
