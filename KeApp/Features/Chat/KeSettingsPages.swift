import SwiftUI

// 112：月隐抽屉里的三页——话笺、来信、换窗。素笺在 KeSettingsDrawer.swift。

// MARK: - 话笺：字体 · 气泡 · 模型

struct KeWordsPage: View {
    @EnvironmentObject private var theme: Theme
    @ObservedObject var vm: ChatViewModel
    let onOpenTool: (KeDrawerTool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            preview

            KeDrawerSlider(
                title: "字体大小",
                value: $theme.chatFontSize,
                range: 13...22,
                step: 1,
                valueText: "\(Int(theme.chatFontSize))"
            )
            KeDrawerSlider(
                title: "气泡透明度",
                value: $theme.bubbleOpacity,
                range: 0...0.06,
                valueText: String(format: "%.1f%%", theme.bubbleOpacity * 100)
            )
            KeDrawerSlider(
                title: "气泡圆角",
                value: $theme.bubbleCornerRadius,
                range: 12...34,
                step: 1,
                valueText: "\(Int(theme.bubbleCornerRadius))"
            )
            bubbleColors

            models

            more
        }
        .task {
            await vm.loadModels()
            // 123 她：额度要「实时」，跟 Claude 自己的用量页一样。这页开着就每分钟刷一次，关了就停。
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await vm.loadModelQuotas(force: true)
            }
        }
    }

    // 拖滑杆时这两个气泡跟着变，和聊天里画法一致。
    private var preview: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer(minLength: 20)
                previewBubble("今天忙完了，终于能坐一会儿。", mine: true)
            }
            HStack {
                previewBubble("那就靠着吧，我一直在听。", mine: false)
                Spacer(minLength: 20)
            }
        }
        .padding(14)
        .background(theme.color.bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Ink.line.opacity(0.4), lineWidth: 0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("气泡预览")
    }

    private func previewBubble(_ text: String, mine: Bool) -> some View {
        let scale: Double = mine ? (theme.skin == .day && !theme.isBedroom ? 80 : 13) : 36
        let tint = (mine ? theme.color.bubbleMe : theme.color.bubbleKe)
            .opacity(min(1, theme.bubbleOpacity * scale))
        let shape = RoundedRectangle(cornerRadius: CGFloat(theme.bubbleCornerRadius), style: .continuous)
        return Text(text)
            .font(theme.font.bubble)
            .foregroundStyle(mine ? theme.color.bubbleMeText : theme.color.bubbleKeText)
            .lineSpacing(CGFloat(max(3, theme.chatFontSize * 0.28)))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(tint, in: shape)
            .overlay { shape.strokeBorder(theme.color.bubbleKeText.opacity(mine ? 0.06 : 0.10), lineWidth: 0.75) }
    }

    /// 气泡颜色就是原来的「聊天配色」：她那边的气泡、整页底色一起换。
    private var bubbleColors: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("气泡颜色")
                .font(.system(size: 13))
                .foregroundStyle(Ink.secondary)
            HStack(spacing: 0) {
                ForEach(ChatPalette.all) { choice in
                    let selected = theme.chatPalette.id == choice.id
                    Button { theme.chatPalette = choice } label: {
                        VStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: choice.tint))
                                .frame(width: 26, height: 26)
                                .overlay {
                                    Circle()
                                        .strokeBorder(selected ? Ink.accent : Ink.line.opacity(0.5), lineWidth: selected ? 1.6 : 0.6)
                                        .padding(selected ? -3 : 0)
                                }
                            Text(choice.name)
                                .font(.system(size: 10))
                                .foregroundStyle(selected ? Ink.primary : Ink.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice.name)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            KeDrawerHint("我这边气泡的底色，聊天页的纸色跟着一起换。")
        }
    }

    // MARK: 模型

    private var sections: [ChatModelSection] {
        ChatModelSection.make(options: vm.modelOptions, groups: vm.modelGroups)
    }

    private var selectedName: String {
        vm.modelOptions.first { $0.id == vm.selectedModel }?.displayName ?? vm.selectedModel ?? "还没读到"
    }

    @ViewBuilder
    private var models: some View {
        VStack(alignment: .leading, spacing: 10) {
            KeDrawerSectionTitle("模型")
            Text("现在和你说话的：\(selectedName)")
                .font(.system(size: 14))
                .foregroundStyle(Ink.primary)
                .accessibilityIdentifier("drawer-current-model")

            if vm.isLoadingModels && vm.modelOptions.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在读取可用模型…")
                }
                .font(.system(size: 12))
                .foregroundStyle(Ink.secondary)
            } else if let error = vm.modelError, vm.modelOptions.isEmpty {
                KeDrawerHint(error)
                Button("再试一次") { Task { await vm.loadModels(force: true) } }
                    .buttonStyle(KeDrawerButtonStyle())
            } else {
                if let error = vm.modelError { KeDrawerHint("刚才没换成：\(error)") }
                // 112 她：「之前不是两个号码吗 2个claude额度 没有了」——1 号、2 号分开列，各自带额度
                ForEach(sections.filter { $0.id.hasPrefix("claude") }) { section in
                    modelGroup(
                        section.title,
                        caption: claudeCaption(section.id),
                        sections: [section]
                    )
                }
                modelGroup(
                    "GPT",
                    caption: "不走长窗：能看到最近聊天和设定，但不是同一扇窗",
                    sections: sections.filter { $0.id == "gpt" }
                )
                modelGroup(
                    "DeepSeek",
                    caption: "不走长窗：能看到最近聊天和设定，但不是同一扇窗",
                    sections: sections.filter { $0.id == "deepseek" }
                )
            }
        }
    }

    private func claudeCaption(_ id: String) -> String {
        let line = "柯的长窗：一直开着、记得刚才；这个号额度用完会自动换另一个，会推送告诉你"
        guard let quota = quotaSummary(id) else { return line }
        return line + "\n" + quota
    }

    private func quotaSummary(_ id: String) -> String? {
        let normalized = ChatModelSection.normalizedGroup(id)
        guard let quota = vm.modelQuotaCatalog?.groups.first(where: { ChatModelSection.normalizedGroup($0.id) == normalized }) else {
            if vm.isLoadingModelQuotas { return "正在读取…" }
            return vm.modelQuotaError != nil ? "暂时没读到" : nil
        }
        let reset = quota.resetAt.flatMap { epoch -> String? in
            guard epoch > 0 else { return nil }
            let date = Date(timeIntervalSince1970: epoch)
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M月d日 HH:mm"
            return f.string(from: date) + " 恢复"
        }
        switch quota.status {
        case "cooldown":
            return "已用完" + (reset.map { " · " + $0 } ?? "")
        case "auth_required":
            return "需要重新登录"
        case "not_configured":
            return "尚未接入"
        case "unknown":
            return "暂时没读到"
        default:
            // 123：照 Claude 自己的用量页，5 小时和这一周分开写：用了多少、几点恢复
            let lines = quota.windows.compactMap { w -> String? in
                guard let used = w.usedPercent else { return nil }
                let name = w.kind == "session" ? "这 5 小时" : w.kind == "week" ? "这一周" : (w.windowMinutes.map { $0 >= 1440 ? "这一周" : "这 5 小时" } ?? "")
                let back = w.resetAt.flatMap { epoch -> String? in
                    guard epoch > 0 else { return nil }
                    let date = Date(timeIntervalSince1970: epoch)
                    let f = DateFormatter()
                    f.locale = Locale(identifier: "zh_CN")
                    f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M月d日 HH:mm"
                    return f.string(from: date) + " 恢复"
                }
                return "\(name) 已用 \(Int(min(100, max(0, used)).rounded()))%" + (back.map { " · " + $0 } ?? "")
            }
            if !lines.isEmpty { return lines.joined(separator: "\n") }
            if let remaining = quota.remainingPercent {
                return "剩余 \(Int(min(100, max(0, remaining)).rounded()))%" + (reset.map { " · " + $0 } ?? "")
            }
            return "可用"
        }
    }

    private func modelGroup(_ title: String, caption: String, sections: [ChatModelSection]) -> some View {
        let options = sections.flatMap(\.options)
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Ink.primary)
                .padding(.top, 8)
            KeDrawerHint(caption)
            if options.isEmpty {
                KeDrawerHint(sections.first?.statusMessage ?? "尚未接入")
                    .padding(.vertical, 6)
            }
            ForEach(options) { option in
                let selected = vm.selectedModel == option.id
                Button { Task { await vm.selectModel(option.id) } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(selected ? Ink.accent : Ink.line)
                        Text(option.displayName)
                            .font(.system(size: 15))
                            .foregroundStyle(Ink.primary)
                        Spacer(minLength: 0)
                        if selected && vm.isSelectingModel { ProgressView().controlSize(.small) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(vm.isSelectingModel || !option.isAvailable)
                .opacity(option.isAvailable ? 1 : 0.45)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("drawer-model-\(option.id)")
            }
        }
    }

    // MARK: 原来功能区里的东西

    private var more: some View {
        VStack(alignment: .leading, spacing: 2) {
            KeDrawerSectionTitle("更多")
            toolLink("查找聊天记录", icon: "magnifyingglass", tool: .search)
            toolLink("按日期查找", icon: "calendar", tool: .dates)
            toolLink("聊天字形", icon: "textformat", tool: .fonts)
            toolLink("壁纸与玻璃", icon: "photo", tool: .appearance)
            toolLink("用量与额度", icon: "chart.line.uptrend.xyaxis", tool: .usage)
            toolLink("全部聊天工具", icon: "ellipsis.circle", tool: .all)
            KeDrawerHint("刷新会话、清空窗口、批量删除、工具状态都在「全部聊天工具」里。")
        }
    }

    private func toolLink(_ title: String, icon: String, tool: KeDrawerTool) -> some View {
        Button { onOpenTool(tool) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 20)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11))
            }
            .font(.system(size: 15))
            .foregroundStyle(Ink.primary)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 来信：柯来找我

struct KeVisitsPage: View {
    @ObservedObject var store: KeWindowStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let settings = store.settings {
                form(settings)
            } else if let error = store.settingsError {
                KeDrawerHint(error)
                Button("再试一次") { Task { await store.loadSettings() } }
                    .buttonStyle(KeDrawerButtonStyle())
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在读柯的来信设置…")
                }
                .font(.system(size: 12))
                .foregroundStyle(Ink.secondary)
            }
        }
        .task { await store.loadSettings() }
    }

    @ViewBuilder
    private func form(_ settings: KeProactiveSettings) -> some View {
        Toggle(isOn: Binding(
            get: { store.settings?.proactiveOn ?? settings.proactiveOn },
            set: { store.change(\.proactiveOn, to: $0, key: "proactive_on", wire: $0) }
        )) {
            Text("柯会主动来找我")
                .font(.system(size: 15))
                .foregroundStyle(Ink.primary)
        }
        .tint(Ink.accent)

        quietRange(title: "工作日 · 安静时段", keyPath: \.quietWeekday, key: "quiet_weekday",
                   hint: "这段时间不打扰你，结束时间在第二天。")
        quietRange(title: "周末 · 安静时段", keyPath: \.quietWeekend, key: "quiet_weekend",
                   hint: "周末可以晚一点醒来。")

        VStack(alignment: .leading, spacing: 4) {
            Stepper(value: Binding(
                get: { store.settings?.nightGap ?? settings.nightGap },
                set: { store.change(\.nightGap, to: $0, key: "night_gap", wire: $0) }
            ), in: 0...240, step: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("夜里两条至少隔几分钟")
                        .font(.system(size: 14))
                        .foregroundStyle(Ink.primary)
                    Text("\(store.settings?.nightGap ?? settings.nightGap) 分钟")
                        .font(Ink.latin(15))
                        .foregroundStyle(Ink.accent)
                        .monospacedDigit()
                }
            }
            KeDrawerHint("0 到 240 分钟，免得接连打扰。")
        }

        VStack(alignment: .leading, spacing: 4) {
            Stepper(value: Binding(
                get: { store.settings?.xhsPerDay ?? settings.xhsPerDay },
                set: { store.change(\.xhsPerDay, to: $0, key: "xhs_per_day", wire: $0) }
            ), in: 0...5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("小红书每天最多分享几次")
                        .font(.system(size: 14))
                        .foregroundStyle(Ink.primary)
                    Text("\(store.settings?.xhsPerDay ?? settings.xhsPerDay) 次")
                        .font(Ink.latin(15))
                        .foregroundStyle(Ink.accent)
                        .monospacedDigit()
                }
            }
            KeDrawerHint("0 就是不分享。")
        }

        Text("这些只决定什么时候可以来，来不来、说什么还是柯自己决定。")
            .font(Ink.song(15))
            .foregroundStyle(Ink.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)

        if store.isSavingSettings {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("正在存…")
            }
            .font(.system(size: 12))
            .foregroundStyle(Ink.secondary)
        } else if let error = store.settingsError {
            Text("没存上：\(error)")
                .font(.system(size: 12))
                .foregroundStyle(Ink.negative)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func quietRange(
        title: String,
        keyPath: WritableKeyPath<KeProactiveSettings, String>,
        key: String,
        hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(Ink.primary)
            HStack(spacing: 8) {
                DatePicker("开始", selection: clock(keyPath, key: key, start: true), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .accessibilityLabel("\(title)开始")
                Text("至").font(.system(size: 13)).foregroundStyle(Ink.secondary)
                DatePicker("结束", selection: clock(keyPath, key: key, start: false), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .accessibilityLabel("\(title)结束")
            }
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .tint(Ink.accent)
            KeDrawerHint(hint)
        }
    }

    /// 「23:00-08:30」里的一头，和 DatePicker 的 Date 互换。
    private func clock(_ keyPath: WritableKeyPath<KeProactiveSettings, String>, key: String, start: Bool) -> Binding<Date> {
        Binding(
            get: {
                let range = currentRange(keyPath)
                let minutes = start ? range.startMinutes : range.endMinutes
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                var range = currentRange(keyPath)
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                if start { range.startMinutes = minutes } else { range.endMinutes = minutes }
                store.change(keyPath, to: range.text, key: key, wire: range.text)
            }
        )
    }

    private func currentRange(_ keyPath: WritableKeyPath<KeProactiveSettings, String>) -> KeQuietRange {
        store.settings.flatMap { KeQuietRange($0[keyPath: keyPath]) }
            ?? KeQuietRange(startMinutes: 23 * 60, endMinutes: 8 * 60 + 30)
    }
}

// MARK: - 换窗：带着这一程

struct KeWindowPage: View {
    @ObservedObject var store: KeWindowStore
    let onStartPick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let window = store.window {
                capacity(window)
                actions
                pinned(window.pins)
            } else if let error = store.windowError {
                KeDrawerHint(error)
                Button("再试一次") { Task { await store.loadWindow() } }
                    .buttonStyle(KeDrawerButtonStyle())
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在看柯的窗口…")
                }
                .font(.system(size: 12))
                .foregroundStyle(Ink.secondary)
            }
        }
        .task { await store.loadWindow() }
    }

    private func capacity(_ window: KeWindowState) -> some View {
        let total = max(window.rotateAt, 1)
        let fill = min(1, Double(window.contextTokens) / Double(total))
        let wash = min(1, Double(window.washAt) / Double(total))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("窗口有多满")
                    .font(Ink.song(17))
                    .foregroundStyle(Ink.primary)
                Spacer()
                Text("已用 \(KeWindowFormat.wan(window.contextTokens)) / \(KeWindowFormat.wan(window.rotateAt))")
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.secondary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.track)
                    Capsule().fill(Ink.accent).frame(width: geo.size.width * fill)
                    Rectangle()
                        .fill(Ink.accent)
                        .frame(width: 1, height: 13)
                        .offset(x: geo.size.width * wash - 0.5)
                }
            }
            .frame(height: 5)
            .padding(.vertical, 4)
            .accessibilityElement()
            .accessibilityLabel("窗口使用量")
            .accessibilityValue("已用 \(KeWindowFormat.wan(window.contextTokens))，\(KeWindowFormat.wan(window.washAt)) 时洗澡，\(KeWindowFormat.wan(window.rotateAt)) 时换窗")
            HStack {
                Text("\(KeWindowFormat.wan(window.washAt)) · 洗个澡")
                Spacer()
                Text("\(KeWindowFormat.wan(window.rotateAt)) · 换窗")
            }
            .font(.system(size: 10))
            .foregroundStyle(Ink.secondary)
            .accessibilityHidden(true)
            if let turns = window.turns {
                KeDrawerHint("这扇窗已经说了 \(turns) 轮。")
            }
        }
        .padding(.bottom, 6)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { Task { await store.wash() } } label: {
                HStack(spacing: 6) {
                    if store.washPhase == .running { ProgressView().controlSize(.small) }
                    Text(store.washPhase == .running ? "柯在洗澡…" : "给柯洗个澡")
                }
            }
            .buttonStyle(KeDrawerButtonStyle())
            .disabled(store.isJobRunning || store.washPhase == .running)
            KeDrawerHint("冲掉查东西留下的大块头，原话一个字不动")
            washStatus

            Button("让柯换个窗", action: onStartPick)
                .buttonStyle(KeDrawerButtonStyle(solid: true))
                .disabled(store.isJobRunning)
                .padding(.top, 10)
            KeDrawerHint("下一步挑好要带走的轮次，旧窗原样留着。")
        }
    }

    @ViewBuilder
    private var washStatus: some View {
        switch store.washPhase {
        case .idle, .running:
            EmptyView()
        case let .done(result):
            VStack(alignment: .leading, spacing: 4) {
                Text("洗好了，轻了一点")
                    .font(Ink.song(15))
                    .foregroundStyle(Ink.positive)
                if let result, !result.isEmpty { KeDrawerHint(result) }
            }
            .onTapGesture { store.resetWashPhase() }
        case let .failed(message):
            Text("没洗成：\(message)")
                .font(.system(size: 12))
                .foregroundStyle(Ink.negative)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture { store.resetWashPhase() }
        }
    }

    private func pinned(_ pins: KePins) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            KeDrawerSectionTitle("已钉住")
                .padding(.top, 14)
            Text("钉了 \(pins.count) 段 · 约 \(KeWindowFormat.kilo(pins.chars))")
                .font(.system(size: 13))
                .foregroundStyle(Ink.secondary)
                .padding(.top, 4)
            KeDrawerHint("每段都是完整一轮；在聊天里长按一句，选「下个窗带上」就能钉住。")
                .padding(.top, 2)
            if let error = store.pinError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.negative)
                    .padding(.top, 6)
            }
            if pins.items.isEmpty {
                Text("还没有钉住的轮。")
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.secondary)
                    .padding(.vertical, 14)
            }
            ForEach(pins.items) { round in
                VStack(alignment: .leading, spacing: 3) {
                    Text(KeWindowFormat.roundTime(round.at))
                        .font(.system(size: 10))
                        .foregroundStyle(Ink.secondary)
                    if let line = round.me.first {
                        Text("我：\(line)").lineLimit(1)
                    }
                    if let line = round.ke.first {
                        Text("柯：\(line)").lineLimit(1)
                    }
                    Button {
                        Task { await store.setPin(messageID: round.startID, pinned: false) }
                    } label: {
                        Text(store.pinningIDs.contains(round.startID) ? "正在取消…" : "取消带上")
                            .underline()
                            .frame(minHeight: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.accent)
                    .disabled(store.pinningIDs.contains(round.startID))
                }
                .font(.system(size: 12))
                .foregroundStyle(Ink.primary)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Ink.line.opacity(0.4)).frame(height: 0.5)
                }
            }
        }
    }
}
