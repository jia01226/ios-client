import SwiftUI
import PhotosUI

// 11-17 她发来别人做的「奶茶本本」：「奶茶那个还要改一下，改成这种可以吗」。
// 日历「奶茶」那面：每天挂品牌小圆章（品牌第一个字，不用各家 logo），一天几杯右上角写数；
// 日历下面：本月几杯、花了多少、多少千卡；她定的预算（每月多少钱、每周几杯）还剩多少；
// 点哪天就在下面列那天的几杯，「记一杯」：日期、品牌、饮品、照片、评分、热量、价格、甜度、冰。
// 热量她不填就空着，柯上网查了填上（她：「让柯联网搜多少卡路里记住」）。预算快到线时柯轻轻提一句。

enum TeaStyle {
    static let sugars = ["无糖", "三分糖", "五分糖", "七分糖", "全糖"]
    static let ices = ["去冰", "少冰", "正常冰", "温", "热"]
    static let chip = Color(hex: 0xEFE2D2)
    static let chipInk = Color(hex: 0x8A6A4F)
}

/// 品牌小圆章
struct TeaBadge: View {
    let text: String
    var size: CGFloat = 16
    var body: some View {
        Text(text).font(.custom("NotoSerifSC-Regular", size: size * 0.6))
            .foregroundStyle(TeaStyle.chipInk)
            .frame(width: size, height: size)
            .background(Circle().fill(TeaStyle.chip))
            .accessibilityHidden(true)
    }
}

/// 奶茶那面的一格：数字、底下品牌小圆章；选中的那天描一圈，一天不止一杯右上角写几杯
struct TeaDayCell: View {
    let date: Date
    let cups: [TeaCup]
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        let isToday = Calendar.current.isDateInToday(date)
        Button(action: onTap) {
            VStack(spacing: 1) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(Cool.didot(17, .body)).monospacedDigit()
                    .foregroundStyle(isToday ? Cool.ink : Cool.number)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(cups.isEmpty ? (isToday ? Cool.today : .clear) : TeaStyle.chip.opacity(0.55)))
                    .overlay(Circle().stroke(selected ? Cool.mauve : .clear, lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        if cups.count > 1 {
                            Text("\(cups.count)").font(.system(size: 9, weight: .medium)).foregroundStyle(.white)
                                .frame(width: 14, height: 14).background(Circle().fill(Cool.mauve)).offset(x: 6, y: -4)
                        }
                    }
                HStack(spacing: -4) {
                    ForEach(Array(cups.prefix(2).enumerated()), id: \.offset) { _, cup in TeaBadge(text: cup.badge, size: 15) }
                }
                .frame(height: 16)
            }
            .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Calendar.current.component(.month, from: date)) 月 \(Calendar.current.component(.day, from: date)) 日，"
                            + (cups.isEmpty ? "没喝奶茶" : "\(cups.count) 杯：" + cups.map(\.title).joined(separator: "、")))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 日历下面：这个月的数、预算、那天的几杯
struct TeaPanel: View {
    @ObservedObject var store: BodyLogStore
    let month: Date
    let day: Date
    var onAdd: () -> Void
    var onEdit: (TeaCup) -> Void
    var onBudget: () -> Void

    private static let dayTitle: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日"; return f
    }()

    var body: some View {
        let cups = store.teaCups(on: day)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                stat("\(store.teaMonth(month))", "本月杯数")
                stat("¥" + Self.money(store.teaSpend(month)), "本月花费")
                stat(store.teaKcal(month) > 0 ? "\(store.teaKcal(month))" : "—", "本月千卡")
            }
            budgetRow
            HStack {
                Text(Self.dayTitle.string(from: day) + " · \(cups.count) 杯").font(Cool.song(14, .subheadline)).foregroundStyle(Cool.ink)
                Spacer()
                Button(action: onAdd) {
                    Text("记一杯").font(Cool.song(13, .subheadline)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(minHeight: 32)
                        .background(Capsule().fill(Cool.mauve))
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tea-add")
            }
            if cups.isEmpty {
                Text("这天没喝。").font(Cool.tiny()).foregroundStyle(Cool.secondary)
            }
            ForEach(cups) { cup in
                Button { onEdit(cup) } label: { row(cup) }.buttonStyle(.plain)
            }
            if let error = store.error {
                Text(error).font(Cool.tiny()).foregroundStyle(Cool.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(Cool.didot(18, .title3)).foregroundStyle(Cool.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(Cool.tiny()).foregroundStyle(Cool.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Cool.line.opacity(0.35)))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var budgetRow: some View {
        let b = store.teaBudget
        Button(action: onBudget) {
            HStack(spacing: 8) {
                if b?.month_budget == nil && b?.week_cups == nil {
                    Text("设个预算").font(Cool.song(13, .subheadline)).foregroundStyle(Cool.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .light)).foregroundStyle(Cool.secondary)
                } else {
                    if let m = b?.month_budget {
                        let left = m - store.teaSpend(.now)
                        budgetItem("本月预算", left >= 0 ? "还剩 ¥" + Self.money(left) : "超了 ¥" + Self.money(-left), warn: left < m * 0.15)
                    }
                    if let w = b?.week_cups {
                        let left = w - store.teaWeek
                        budgetItem("本周上限", left > 0 ? "还能喝 \(left) 杯" : "这周喝满了", warn: left <= 0)
                    }
                }
            }
            .frame(minHeight: 40).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("改预算")
    }

    private func budgetItem(_ label: String, _ value: String, warn: Bool) -> some View {
        HStack {
            Text(label).font(Cool.tiny()).foregroundStyle(Cool.secondary)
            Spacer(minLength: 4)
            Text(value).font(Cool.song(12, .caption)).foregroundStyle(warn ? Cool.heart : Cool.mauve)
        }
        .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 36)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Cool.line, lineWidth: 0.8))
    }

    private func row(_ cup: TeaCup) -> some View {
        HStack(alignment: .center, spacing: 12) {
            TeaBadge(text: cup.badge, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(cup.title).font(Cool.song(14, .subheadline)).foregroundStyle(Cool.ink).lineLimit(1)
                let detail = [cup.options, cup.rating.map { String(repeating: "★", count: $0) } ?? ""].filter { !$0.isEmpty }.joined(separator: "  ")
                if !detail.isEmpty { Text(detail).font(Cool.tiny()).foregroundStyle(Cool.secondary).lineLimit(1) }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                if let p = cup.price { Text("¥" + Self.money(p)).font(Cool.didot(15, .subheadline)).foregroundStyle(Cool.ink) }
                Text(cup.kcal.map { "约 \($0) kcal" } ?? "热量等柯查").font(Cool.tiny()).foregroundStyle(Cool.secondary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("改这一杯")
    }

    static func money(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

// MARK: - 记一杯 / 改一杯

struct TeaCupEditor: View {
    @State var cup: TeaCup
    let isNew: Bool
    let recentBrands: [String]
    var upload: (Data) async -> String?
    var onSave: (TeaCup) -> Void
    var onDelete: (TeaCup) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var priceText: String
    @State private var kcalText: String
    @State private var photoItem: PhotosPickerItem?
    @State private var photoPreview: UIImage?
    @State private var uploading = false
    @State private var confirmDelete = false

    init(cup: TeaCup, isNew: Bool, recentBrands: [String], upload: @escaping (Data) async -> String?,
         onSave: @escaping (TeaCup) -> Void, onDelete: @escaping (TeaCup) -> Void) {
        _cup = State(initialValue: cup)
        self.isNew = isNew; self.recentBrands = recentBrands; self.upload = upload
        self.onSave = onSave; self.onDelete = onDelete
        let p = cup.day.prefix(10).split(separator: "-").compactMap { Int($0) }
        _date = State(initialValue: p.count == 3 ? Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) ?? .now : .now)
        _priceText = State(initialValue: cup.price.map { TeaPanel.money($0) } ?? "")
        _kcalText = State(initialValue: cup.kcal.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                    TextField("品牌，比如 喜茶", text: binding(\.brand))
                    if !recentBrands.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(recentBrands, id: \.self) { b in
                                    Button { cup.brand = b } label: {
                                        Text(b).font(Ink.song(13)).padding(.horizontal, 12).frame(minHeight: 32)
                                            .background(Capsule().fill(cup.brand == b ? TeaStyle.chip : Color.clear))
                                            .overlay(Capsule().stroke(Ink.line, lineWidth: 0.7))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    TextField("喝的什么，比如 多肉葡萄", text: binding(\.drink))
                }
                Section("照片") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ZStack {
                            if let photoPreview {
                                Image(uiImage: photoPreview).resizable().scaledToFill()
                            } else if let url = cup.photo {
                                ChatImageTile(attachment: ChatAttachment(url: url, name: "奶茶照片", kind: "image"), width: 120, height: 120)
                            } else {
                                VStack(spacing: 6) {
                                    Image(systemName: "plus").font(.system(size: 18, weight: .light))
                                    Text("加照片").font(Ink.song(13))
                                }
                                .foregroundStyle(Ink.accent)
                            }
                            if uploading { ProgressView() }
                        }
                        .frame(width: 120, height: 120)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Ink.line.opacity(0.25)))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Section("评分") {
                    HStack(spacing: 14) {
                        ForEach(1...5, id: \.self) { n in
                            Button { cup.rating = cup.rating == n ? nil : n } label: {
                                Image(systemName: (cup.rating ?? 0) >= n ? "star.fill" : "star")
                                    .font(.system(size: 20, weight: .light)).foregroundStyle(Ink.accent)
                                    .frame(width: 36, height: 36).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(n) 颗星")
                        }
                    }
                }
                Section {
                    HStack {
                        Text("价格")
                        TextField("元", text: $priceText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("热量")
                        TextField("空着让柯上网查", text: $kcalText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text(cup.kcal_by == "ke" ? "热量是柯上网查的大概数，可以改。" : "热量不知道就空着，柯会上网查个大概填上。")
                }
                Section("甜度") { chips(TeaStyle.sugars, \.sugar) }
                Section("冰") { chips(TeaStyle.ices, \.ice) }
                Section("备注") {
                    TextField("小料、口感、下次还点不点…", text: binding(\.note), axis: .vertical).lineLimit(1...4)
                }
                if !isNew {
                    Section { Button("删掉这一杯", role: .destructive) { confirmDelete = true } }
                }
            }
            .font(Ink.song(15))
            .scrollContentBackground(.hidden)
            .background(CamelliaPalette.stored().paper)
            .navigationTitle(isNew ? "记一杯奶茶" : "这一杯").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("好了") { save() }.disabled(uploading)
                }
            }
            .confirmationDialog("删掉这一杯？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删掉", role: .destructive) { onDelete(cup); dismiss() }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                    photoPreview = image
                    uploading = true
                    let jpeg = image.jpegData(compressionQuality: 0.8) ?? data
                    if let url = await upload(jpeg) { cup.photo = url }
                    uploading = false
                }
            }
        }
        .tint(Ink.accent)
        .foregroundStyle(Ink.primary)
    }

    private func binding(_ key: WritableKeyPath<TeaCup, String?>) -> Binding<String> {
        Binding(get: { cup[keyPath: key] ?? "" }, set: { cup[keyPath: key] = $0.isEmpty ? nil : $0 })
    }

    private func chips(_ items: [String], _ key: WritableKeyPath<TeaCup, String?>) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.self) { item in
                let on = cup[keyPath: key] == item
                Button { cup[keyPath: key] = on ? nil : item } label: {
                    Text(item).font(Ink.song(13)).foregroundStyle(on ? Color.white : Ink.primary)
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
        cup.day = HomeReminderCoordinator.dayKey(date)
        cup.price = Double(priceText.trimmingCharacters(in: .whitespaces))
        let k = Int(kcalText.trimmingCharacters(in: .whitespaces))
        if k != cup.kcal { cup.kcal = k; cup.kcal_by = k == nil ? nil : "me" }
        onSave(cup)
        dismiss()
    }
}

// MARK: - 预算

struct TeaBudgetSheet: View {
    let budget: TeaBudget?
    var onSave: (Double?, Int?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var monthText = ""
    @State private var week = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("每个月")
                        TextField("不设", text: $monthText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        Text("元")
                    }
                    Stepper(week == 0 ? "每周：不设" : "每周最多 \(week) 杯", value: $week, in: 0...14)
                } footer: {
                    Text("快到线的时候，柯会轻轻提一句，不拦你。都不设就不提。")
                }
            }
            .font(Ink.song(15))
            .scrollContentBackground(.hidden)
            .background(CamelliaPalette.stored().paper)
            .navigationTitle("奶茶预算").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("好了") {
                        onSave(Double(monthText.trimmingCharacters(in: .whitespaces)), week == 0 ? nil : week)
                        dismiss()
                    }
                }
            }
            .onAppear {
                monthText = budget?.month_budget.map { TeaPanel.money($0) } ?? ""
                week = budget?.week_cups ?? 0
            }
        }
        .tint(Ink.accent)
        .foregroundStyle(Ink.primary)
        .presentationDetents([.medium])
    }
}
