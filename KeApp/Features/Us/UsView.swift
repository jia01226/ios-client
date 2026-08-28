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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: theme.metric.gapM) {
                pageHeader

                MoonOrbitSelector(
                    events: vm.anniversaries,
                    selectedIndex: $selectedAnniversaryIndex
                )
                .frame(height: 300)
                .clipped()

                if let selectedAnniversary {
                    countdown(for: selectedAnniversary)
                }

                remindersSection
                shiftSection
            }
            .padding(.horizontal, theme.metric.pagePadding)
            .padding(.top, theme.metric.gapM)
            .padding(.bottom, theme.metric.gapXL)
        }
        .scrollContentBackground(.hidden)
        .background(theme.effectiveBackground.ignoresSafeArea())
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
        VStack(alignment: .leading, spacing: theme.metric.gapM) {
            Text("柯替你记得")
                .font(.custom("STSongti-SC-Regular", size: 24, relativeTo: .title2))
                .tracking(1.8)
                .foregroundStyle(theme.color.textPrimary)

            VStack(spacing: 0) {
                ForEach(vm.activeReminders) { reminder in
                    ReminderRow(reminder: reminder)
                        .padding(.vertical, theme.metric.gapS)
                }
            }
            .overlay(alignment: .topTrailing) {
                Image("CamelliaMoonlight")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150)
                    .opacity(0.045)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
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
            let center = CGPoint(x: width - 36, y: 150)
            let orbitRadius = CGSize(width: 158, height: 126)
            let moonSize: CGFloat = 278

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
    let activeProgress: CGFloat
    let selected: Bool

    var body: some View {
        let diameter = 12 + 11 * CGFloat(pow(Double(activeProgress), 1.35))

        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.96),
                        theme.color.accentSoft.opacity(0.92),
                        theme.effectiveAccent.opacity(0.78),
                        theme.color.textPrimary.opacity(0.46),
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: diameter
                )
            )
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.74), lineWidth: 0.7)
            }
            .frame(width: diameter, height: diameter)
            .opacity(0.42 + activeProgress * 0.58)
            .shadow(
                color: theme.effectiveAccent.opacity(selected ? 0.42 : 0),
                radius: selected ? 9 : 0
            )
            .scaleEffect(selected ? 1.04 : 1)
            .animation(.easeOut(duration: 0.14), value: selected)
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

// MARK: - 柯替你记得

private struct ReminderRow: View {
    @EnvironmentObject private var theme: Theme
    let reminder: Reminder

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(theme.effectiveAccent.opacity(0.82))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(reminder.text)
                .font(.custom("STSongti-SC-Light", size: 15.5, relativeTo: .body))
                .tracking(0.45)
                .lineSpacing(3)
                .foregroundStyle(theme.color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            Spacer(minLength: theme.metric.gapS)

            Text(timeLabel)
                .font(.custom("STSongti-SC-Light", size: 13, relativeTo: .caption))
                .tracking(0.5)
                .foregroundStyle(theme.effectiveAccent)
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .combine)
    }

    private var timeLabel: String {
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
