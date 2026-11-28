import SwiftUI

// 11-17 她：「可以切换日历，正常就是排班日历，然后切换奶茶、粑粑、亲密」「就是完全新的日历，里面放奶茶，
// 另一个切换里面放粑粑」——日历上面一排字，点哪个整张月历换成哪一面，各面只放自己那一样，不堆在一起。
// 她又说：「不要叫粑粑了，好难听，叫出恭吧」「排班、月经、亲密在一起，奶茶和出恭单独一个」——三面：
// 排班那面照旧画班次、月经的粉、亲密的小心；奶茶、出恭各一面。

enum CalendarFace: String, CaseIterable, Identifiable {
    case shift, tea, poop
    var id: String { rawValue }
    var label: String {
        switch self {
        case .shift: return "排班"
        case .tea: return "奶茶"
        case .poop: return "出恭"
        }
    }
    /// 有记的那天，数字底下垫的颜色
    var tint: Color {
        switch self {
        case .shift: return .clear
        case .tea: return Color(hex: 0xEFE2D2)    // 奶茶色
        case .poop: return Color(hex: 0xE6EBDD)   // 淡淡的草绿（顺）
        }
    }
    static func poopTint(_ feel: String?) -> Color {
        switch feel {
        case PoopFeel.hard.rawValue: return Color(hex: 0xF4E4C9)
        case PoopFeel.very_hard.rawValue: return Color(hex: 0xF2D8D8)
        default: return CalendarFace.poop.tint
        }
    }
}

/// 日历顶上那排「排班 · 奶茶 · 出恭」
struct CalendarFacePicker: View {
    @Binding var face: CalendarFace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 16) {
            ForEach(CalendarFace.allCases) { f in
                let on = f == face
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) { face = f }
                } label: {
                    // 11-28 她给的样子：选中的那面加粗、下面一道圆头粗线
                    Text(f.label)
                        .font(.system(size: 17, weight: on ? .semibold : .regular)).tracking(1)
                        .foregroundStyle(on ? Cool.ink : Cool.secondary)
                        .padding(.bottom, 6)
                        .overlay(alignment: .bottom) {
                            Capsule().fill(on ? Cool.mauve : .clear).frame(height: 3)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("calendar-face-\(f.rawValue)")
            }
        }
        .sensoryFeedback(.selection, trigger: face)
    }
}

/// 奶茶 / 出恭那面的一格：Didot 数字，记了的那天垫一层颜色，底下写几杯、几次
struct FaceDayCell: View {
    let date: Date
    let face: CalendarFace
    let count: Int
    var feel: String?
    let onTap: () -> Void

    private var label: String {
        guard count > 0 else { return " " }
        switch face {
        case .tea: return "\(count) 杯"
        case .poop:
            if let f = feel.flatMap(PoopFeel.init(rawValue:)), f != .ok { return f.label }
            return "\(count) 次"
        default: return "\(count) 次"
        }
    }

    var body: some View {
        let isToday = Calendar.current.isDateInToday(date)
        let fill = count > 0 ? (face == .poop ? CalendarFace.poopTint(feel) : face.tint) : (isToday ? Cool.today : .clear)
        Button(action: onTap) {
            VStack(spacing: -3) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(Cool.didot(17, .body)).monospacedDigit()
                    .foregroundStyle(isToday ? Cool.ink : Cool.number)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(fill))
                    .overlay(Circle().stroke(isToday && count > 0 ? Cool.number.opacity(0.45) : .clear, lineWidth: 0.8))
                Text(label).font(Cool.tiny()).tracking(0.5).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(Cool.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 53, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Calendar.current.component(.month, from: date)) 月 \(Calendar.current.component(.day, from: date)) 日，"
                            + (count > 0 ? "\(face.label) \(label)" : "没有\(face.label)记录"))
        .accessibilityHint("改这一天的\(face.label)")
    }
}

/// 点奶茶 / 出恭那面的某一天：一张小弹窗，加减、粑粑顺不顺
struct FaceDaySheet: View {
    let face: CalendarFace
    let date: Date
    let count: Int
    var feel: String?
    let onSet: (Int, PoopFeel?) -> Void
    var error: String?
    @Environment(\.dismiss) private var dismiss

    private static let title: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日 EEE"; return f
    }()
    private var unit: String { face == .tea ? "杯" : "次" }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text(Self.title.string(from: date) + " · " + face.label).font(Ink.song(17)).tracking(1.2)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { dismiss() } label: {
                    Text("好了").font(Ink.song(15)).foregroundStyle(Ink.accent)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 28) {
                Button { onSet(count - 1, nil) } label: {
                    Image(systemName: "minus").font(.system(size: 18, weight: .light))
                        .frame(width: 52, height: 52).background(Circle().stroke(Ink.line, lineWidth: 0.8))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).disabled(count == 0).opacity(count == 0 ? 0.35 : 1)
                .accessibilityLabel("减一\(unit)")
                Text("\(count) \(unit)").font(Cool.didot(30, .title)).monospacedDigit().frame(minWidth: 90)
                    .accessibilityIdentifier("face-day-count")
                Button { onSet(count + 1, nil) } label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .light))
                        .frame(width: 52, height: 52).background(Circle().fill(face.tint))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("加一\(unit)")
            }
            .foregroundStyle(Ink.accent)
            if face == .poop && count > 0 {
                HStack(spacing: 10) {
                    ForEach(PoopFeel.allCases) { f in
                        let on = (feel ?? PoopFeel.ok.rawValue) == f.rawValue
                        Button { onSet(count, f) } label: {
                            Text(f.label).font(Ink.song(14))
                                .foregroundStyle(on ? Ink.primary : Ink.secondary)
                                .padding(.horizontal, 16).frame(minHeight: 40)
                                .background(Capsule().fill(on ? CalendarFace.poopTint(f.rawValue) : .clear))
                                .overlay(Capsule().stroke(Ink.line, lineWidth: on ? 0 : 0.7))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            if let error {
                Text(error).font(Ink.song(12)).foregroundStyle(Ink.secondary)
            }
            Text("柯也看得到。").font(Ink.song(11.5)).foregroundStyle(Ink.secondary)
        }
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 12)
        .presentationDetents([.height(face == .poop ? 300 : 250)])
        .presentationBackground(CamelliaPalette.stored().paper)
        .foregroundStyle(Ink.primary)
    }
}
