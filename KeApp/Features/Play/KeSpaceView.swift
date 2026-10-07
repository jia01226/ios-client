import SwiftUI

struct KeSpaceView: View {
    @EnvironmentObject private var theme: Theme
    let line: ChatLine
    @State private var diary = true
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MoonlightHeader(title: "柯的").padding(.horizontal, 26)
            HStack(spacing: 28) {
                section("日记", selected: diary) { diary = true }
                section("抽屉", selected: !diary) { diary = false }
                Spacer()
            }.padding(.horizontal, 28).padding(.bottom, 14)
            if diary { MoonDiaryView(line: line) }
            else { MoonDrawerView(line: line) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(theme.pageColor.textPrimary).background(theme.pageBackground.ignoresSafeArea())
    }
    private func section(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Text(title).font(Moonlight.serif(23))
                Circle().fill(theme.pageAccent.opacity(selected ? 1 : 0)).frame(width: 5, height: 5)
            }.foregroundStyle(selected ? theme.pageAccent : theme.pageColor.textPrimary).frame(minHeight: 44)
        }.buttonStyle(.plain).accessibilityIdentifier(title == "日记" ? "ke-diary-tab" : "ke-drawer-tab")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct MoonDiaryView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var store: KeDiaryStore
    @State private var selected = CompanionDate.calendar.startOfDay(for: .now)
    @State private var selectedOnce = false
    @State private var open = false
    @State private var datePicker = false
    init(line: ChatLine) { _store = StateObject(wrappedValue: KeDiaryStore(api: APIClient(baseURL: line.apiBaseURL))) }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    HStack(alignment: .center, spacing: 8) {
                        ZStack {
                            DiaryCurlReader(date: $selected, pages: store.pages, theme: theme, reduceMotion: reduceMotion)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .opacity(open ? 1 : 0).allowsHitTesting(open).accessibilityHidden(!open)
                            cover
                                .rotation3DEffect(.degrees(open && !reduceMotion ? -105 : 0), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.4)
                                .opacity(open ? 0 : 1).allowsHitTesting(!open).accessibilityHidden(open)
                        }.frame(maxWidth: .infinity).frame(height: min(460, max(355, geometry.size.height - 132)))
                        MoonlightDateRail(date: $selected, showPicker: $datePicker)
                            .frame(width: 83)
                    }.padding(.horizontal, 17).padding(.top, 10)
                    Button {
                        withAnimation(reduceMotion ? .linear(duration: 0.1) : .easeInOut(duration: 0.7)) { open.toggle() }
                    } label: {
                        Text(open ? "轻轻合上  ←" : "翻开 \(selected.formatted(.dateTime.month(.defaultDigits).day()).replacingOccurrences(of: "/", with: "·")) 这一页  →")
                            .font(Moonlight.serif(17)).underline(color: theme.pageAccent.opacity(0.5))
                            .padding(.vertical, 12)
                    }.buttonStyle(.plain).foregroundStyle(theme.pageAccent).accessibilityIdentifier("diary-open-close")
                    if store.loading { ProgressView().tint(theme.pageAccent) }
                    if let error = store.error {
                        Button(error) { Task { await store.load() } }.font(Moonlight.serif(12)).foregroundStyle(theme.pageColor.textSecondary)
                    }
                }.padding(.bottom, 18).frame(minHeight: geometry.size.height, alignment: .center)
            }.scrollIndicators(.hidden)
        }
        .task { await store.load(); if !selectedOnce { selected = store.pages.last?.date ?? selected; selectedOnce = true } }
        .sheet(isPresented: $datePicker) {
            MoonDiaryDatePicker(date: $selected, markedDates: store.pages.map(\.date))
        }
    }
    private var cover: some View {
        GeometryReader { g in
            Image("MoonDiaryCover").resizable().scaledToFit()
                .opacity(theme.skin == .day ? 1 : 0.48)
                .frame(width: g.size.width, height: g.size.height)
                .overlay {
                    VStack(spacing: 9) {
                        Text("dear diary").font(Moonlight.script(min(32, g.size.width * 0.12))).tracking(1)
                        Text("柯的日记").font(Moonlight.serif(12)).tracking(3)
                        Text("\(CompanionDate.calendar.component(.year, from: selected))").font(Moonlight.serif(9)).tracking(2)
                    }.foregroundStyle(theme.skin == .day ? Moonlight.deepRose : theme.pageColor.textPrimary)
                        .position(x: g.size.width * 0.52, y: g.size.height * 0.72)
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(reduceMotion ? .linear(duration: 0.1) : .easeInOut(duration: 0.7)) { open = true } }
                .accessibilityElement(children: .ignore).accessibilityLabel("柯的日记，轻点翻开")
                .accessibilityAddTraits(.isButton).accessibilityIdentifier("diary-cover")
        }
    }
}

private struct MoonlightDateRail: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var date: Date
    @Binding var showPicker: Bool
    @State private var glowing = false
    private var calendar: Calendar { CompanionDate.calendar }
    var body: some View {
        VStack(spacing: 5) {
            MoonCrescent().fill(LinearGradient(colors: [Moonlight.pearl, theme.pageAccent.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 43, height: 43).shadow(color: theme.pageAccent.opacity(glowing ? 0.32 : 0.12), radius: glowing ? 15 : 8)
                .padding(.bottom, 5).accessibilityHidden(true)
            Text("a day\nwith you").font(Moonlight.script(20)).multilineTextAlignment(.center).foregroundStyle(theme.pageAccent)
            Button { showPicker = true } label: {
                VStack(spacing: 12) {
                    Text(String(calendar.component(.year, from: date)) + "⌄")
                    Text("\(calendar.component(.month, from: date))月 ⌄")
                }.font(Moonlight.serif(14)).padding(.vertical, 15)
            }.accessibilityLabel("选择日记年月").accessibilityIdentifier("diary-year-month")
            ForEach(-2...2, id: \.self) { offset in
                if let day = calendar.date(byAdding: .day, value: offset, to: date), day <= .now {
                    Button { date = day } label: {
                        Text(String(format: "%02d", calendar.component(.day, from: day)))
                            .font(Moonlight.numeral(offset == 0 ? 26 : 21)).frame(width: 44, height: 44)
                            .foregroundStyle(offset == 0 ? theme.pageAccent : theme.pageColor.textPrimary)
                            .background(theme.pageAccent.opacity(offset == 0 ? 0.05 : 0), in: Circle())
                            .overlay(Circle().stroke(theme.pageAccent.opacity(offset == 0 ? 0.8 : 0), lineWidth: 0.6))
                    }.accessibilityLabel(day.formatted(date: .long, time: .omitted))
                        .accessibilityIdentifier("diary-rail-\(offset)")
                }
            }
            Button("选日期") { showPicker = true }.font(Moonlight.serif(12)).frame(minHeight: 44).accessibilityIdentifier("diary-date-picker")
        }
        .frame(maxWidth: .infinity).buttonStyle(.plain)
        .background {
            ZStack {
                MoonlightBeam().fill(LinearGradient(colors: [Moonlight.pearl.opacity(0.85), theme.pageAccent.opacity(0.06), Moonlight.pearl.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .blur(radius: 6)
                MoonlightBeam().stroke(Moonlight.pearl.opacity(glowing ? 0.85 : 0.45), lineWidth: 1).blur(radius: 0.4)
            }.padding(.top, 42).opacity(theme.skin == .day ? 1 : 0.1).allowsHitTesting(false)
        }
        .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 3.8).repeatForever(autoreverses: true)) { glowing = true } } }
        .gesture(DragGesture(minimumDistance: 28).onEnded { value in
            guard abs(value.translation.height) > abs(value.translation.width), let day = calendar.date(byAdding: .day, value: value.translation.height < 0 ? 1 : -1, to: date), day <= .now else { return }
            date = day
        })
        .accessibilityIdentifier("diary-moonlight-dates")
    }
}

private struct MoonlightBeam: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.midX - 3, y: 0))
            p.addCurve(to: CGPoint(x: 4, y: r.maxY), control1: CGPoint(x: r.midX - 8, y: r.height * 0.3), control2: CGPoint(x: -15, y: r.height * 0.6))
            p.addLine(to: CGPoint(x: r.maxX - 4, y: r.maxY))
            p.addCurve(to: CGPoint(x: r.midX + 3, y: 0), control1: CGPoint(x: r.maxX + 20, y: r.height * 0.55), control2: CGPoint(x: r.midX + 3, y: r.height * 0.25))
            p.closeSubpath()
        }
    }
}

private struct MoonDiaryDatePicker: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    @Binding var date: Date
    let markedDates: [Date]
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("a day with you").font(Moonlight.script(36)).foregroundStyle(theme.pageAccent)
                DatePicker("翻到这一天", selection: $date, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical).environment(\.calendar, CompanionDate.calendar)
                    .environment(\.timeZone, CompanionDate.calendar.timeZone).environment(\.locale, Locale(identifier: "zh_CN"))
                    .accessibilityIdentifier("diary-calendar-picker")
                if !markedDates.isEmpty {
                    Menu("翻到有日记的日子") {
                        ForEach(markedDates.reversed(), id: \.self) { day in
                            Button(day.formatted(date: .long, time: .omitted)) { date = day; dismiss() }
                        }
                    }.font(Moonlight.serif(15)).accessibilityIdentifier("diary-written-days")
                }
                Button("就这一天") { dismiss() }.font(Moonlight.serif(18)).frame(minHeight: 44)
                    .accessibilityIdentifier("diary-date-done")
                Spacer(minLength: 0)
            }.padding(22).background(theme.pageBackground)
                .navigationTitle("月光里的日子").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("收起") { dismiss() } } }
        }.tint(theme.pageAccent).presentationDetents([.large])
    }
}
