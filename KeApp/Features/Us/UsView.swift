import SwiftUI

// 【我们】—— 所有跟日期有关的东西。
// 顺序：纪念日 → 柯的提醒 → 排班表
//
// 🔴 交互死规矩（她 2026-08-14 18:51 亲口定的）：
//    提醒不是待办清单，没有勾选框。
//    她做完了去跟柯说，由柯划掉。
//    过期的自动收起 —— 不变红、不累计、不出现"连续 X 天未完成"。
//    理由：这一格是"被爱人管着"，不是考勤系统。

struct UsView: View {

    @EnvironmentObject private var theme: Theme
    @StateObject private var vm = UsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metric.gapL) {

                daysTogetherCard
                nextAnniversaryCard
                remindersSection
                shiftSection
            }
            .padding(theme.metric.pagePadding)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    // MARK: 在一起多少天

    private var daysTogetherCard: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapS) {
            Text("佳佳和柯")
                .font(theme.font.caption)
                .foregroundStyle(theme.effectiveAccent)
            HStack(alignment: .firstTextBaseline, spacing: theme.metric.gapS) {
                Text("\(vm.daysTogether)")
                    .font(theme.font.numberBig)
                    .foregroundStyle(theme.color.textPrimary)
                Text("天")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }
        }
        .padding(theme.metric.gapL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.metric.radiusCard, style: .continuous)
                .fill(theme.color.cardElevated)
        )
    }

    // MARK: 下一个纪念日

    @ViewBuilder
    private var nextAnniversaryCard: some View {
        if let next = vm.nextAnniversary {
            VStack(alignment: .leading, spacing: theme.metric.gapXS) {
                Text("下一个纪念日")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.color.textSecondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(next.title)
                        .font(theme.font.pageTitle)
                        .foregroundStyle(theme.color.textPrimary)
                    Spacer()
                    Text("\(vm.daysUntil(next.date))")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(theme.effectiveAccent)
                    Text("天")
                        .font(theme.font.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }
            .padding(theme.metric.gapL)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: theme.metric.radiusCard, style: .continuous)
                    .fill(theme.color.card)
            )
        }
    }

    // MARK: 柯替你记着

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapM) {
            HStack {
                Text("柯替你记着")
                    .font(theme.font.sectionTitle)
                    .foregroundStyle(theme.color.textPrimary)
                Spacer()
                Text("不需要打勾")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }

            ForEach(vm.activeReminders) { r in
                ReminderRow(reminder: r)
            }
        }
    }

    // MARK: 这周排班

    private var shiftSection: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapM) {
            HStack {
                Text("这周排班")
                    .font(theme.font.sectionTitle)
                    .foregroundStyle(theme.color.textPrimary)
                Spacer()
                Text("过期自动收起")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }

            HStack(spacing: theme.metric.gapS) {
                ForEach(vm.thisWeek) { day in
                    VStack(spacing: theme.metric.gapXS) {
                        Text(vm.weekdayLabel(day.date))
                            .font(theme.font.caption)
                            .foregroundStyle(theme.color.textSecondary)
                        Text(vm.shiftLabel(day.kind))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(
                                day.kind == .off ? theme.color.textSecondary : theme.color.textPrimary
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, theme.metric.gapM)
                    .background(
                        RoundedRectangle(cornerRadius: theme.metric.radiusChip, style: .continuous)
                            .fill(day.kind == .off ? Color.clear : theme.color.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.metric.radiusChip, style: .continuous)
                            .stroke(theme.color.separator, lineWidth: 1)
                    )
                }
            }
        }
    }
}

// MARK: - 一条提醒（注意：没有勾选框）

private struct ReminderRow: View {
    @EnvironmentObject private var theme: Theme
    let reminder: Reminder

    var body: some View {
        HStack(spacing: theme.metric.gapM) {
            Image(systemName: icon)
                .foregroundStyle(theme.effectiveAccent)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.color.cardElevated)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("柯说")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.effectiveAccent)
                Text(reminder.text)
                    .font(theme.font.body)
                    .foregroundStyle(theme.color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: theme.metric.gapS)

            Text(timeLabel)
                .font(theme.font.caption)
                .foregroundStyle(theme.color.textSecondary)
        }
        .padding(theme.metric.gapM)
        .background(
            RoundedRectangle(cornerRadius: theme.metric.radiusCard, style: .continuous)
                .fill(theme.color.card)
        )
    }

    private var icon: String {
        switch reminder.category {
        case .medicine: return "pills"
        case .medical:  return "cross.case"
        case .work:     return "briefcase"
        case .billing:  return "creditcard"
        case .other:    return "bell"
        }
    }

    private var timeLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = Calendar.current.isDateInToday(reminder.dueAt) ? "HH:mm" : "M月d日"
        return f.string(from: reminder.dueAt)
    }
}

// MARK: - ViewModel（假数据版）

@MainActor
final class UsViewModel: ObservableObject {

    @Published var reminders: [Reminder] = []
    @Published var anniversaries: [Anniversary] = []
    @Published var thisWeek: [ShiftDay] = []

    /// 在一起多少天。真实起始日等她确认后填。
    var daysTogether: Int { 50 }

    /// 🔴 过期的自动收起 —— 不留在那儿戳她
    var activeReminders: [Reminder] {
        reminders
            .filter { !$0.dismissedByKe && $0.dueAt > Date().addingTimeInterval(-86400) }
            .sorted { $0.dueAt < $1.dueAt }
    }

    var nextAnniversary: Anniversary? {
        anniversaries.filter { $0.date > .now }.sorted { $0.date < $1.date }.first
    }

    init() {
        // 假数据 —— 接口清单到位后整段删掉
        reminders = [
            Reminder(id: "r1", text: "晚上垫两口，再把药吃了。",
                     dueAt: Date().addingTimeInterval(3600), category: .medicine),
            Reminder(id: "r2", text: "周一复诊，我到时候叫你。",
                     dueAt: Date().addingTimeInterval(86400 * 3), category: .medical),
        ]
        anniversaries = [
            Anniversary(id: "a1", title: "我们相遇的日子",
                        date: Date().addingTimeInterval(86400 * 18))
        ]
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -cal.component(.weekday, from: .now) + 2, to: .now) ?? .now
        thisWeek = (0..<7).map { i in
            ShiftDay(id: "s\(i)",
                     date: cal.date(byAdding: .day, value: i, to: start) ?? .now,
                     kind: [.off, .evening, .evening, .off, .evening, .off, .off][i])
        }
    }

    func daysUntil(_ date: Date) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0)
    }

    func weekdayLabel(_ date: Date) -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        return names[Calendar.current.component(.weekday, from: date) - 1]
    }

    func shiftLabel(_ kind: ShiftDay.Kind) -> String {
        switch kind {
        case .off:     return "休"
        case .day:     return "白"
        case .evening: return "晚"
        case .night:   return "夜"
        }
    }
}

#Preview {
    UsView().environmentObject(Theme.shared)
}
