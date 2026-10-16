import SwiftUI

/// 112：「让柯换个窗」之前，挑好要带走哪几轮。
/// 像聊天一样从早到晚排；她的话在右、柯的在左，字小一点。点一轮的任何地方就整轮勾上或去掉。
/// 默认勾好最近 20 轮和所有钉住的轮（钉住的锁着，只能去换窗页取消）。
struct KeWindowPickerView: View {
    @ObservedObject var store: KeWindowStore
    let onBack: () -> Void
    let onFinished: () -> Void

    @AppStorage(CamelliaPalette.storageKey) private var savedPalette = CamelliaPalette.defaultPalette.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 按 start_id 从早到晚
    @State private var rounds: [KeRound] = []
    @State private var selected: Set<Int> = []
    @State private var nextBefore: Int?
    /// 翻页真正读到过的最早一轮；比它更早的只有钉住的那几轮，中间省略了多少不知道。
    @State private var loadedFloor: Int?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var didLoad = false
    @State private var scrollTarget: Int?
    @State private var confirming = false
    @State private var notice: String?
    @State private var finished = false

    private var palette: CamelliaPalette { .resolve(savedPalette) }

    private var pinnedIDs: Set<Int> {
        store.pinnedStartIDs.union(rounds.filter(\.pinned).map(\.startID))
    }

    private var picks: Set<Int> { selected.union(pinnedIDs) }

    private var pickedChars: Int {
        rounds.filter { picks.contains($0.startID) }.reduce(0) { $0 + $1.chars }
    }

    var body: some View {
        ZStack {
            palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                list
                footer
            }
            if confirming { confirmCard }
        }
        .task { await initialLoad() }
        .task(id: store.rotatePhase) {
            // 换好了先让她看一眼「柯换好了」，再自己收起来。
            guard case .done = store.rotatePhase else { return }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            finish()
        }
    }

    // MARK: 顶上：返回、标题、已选几轮（一直钉在顶上）

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(action: onBack) {
                    Text("返回")
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Ink.accent)
                Spacer()
                Text("挑选带走")
                    .font(Ink.song(19))
                    .foregroundStyle(Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("整轮同行")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay { Capsule().strokeBorder(Ink.line, lineWidth: 0.6) }
                    .frame(minWidth: 44, alignment: .trailing)
            }
            Text("已选 \(picks.count) 轮 · 约 \(KeWindowFormat.kilo(pickedChars))")
                .font(Ink.song(15))
                .foregroundStyle(Ink.primary)
                .monospacedDigit()
                .accessibilityAddTraits(.updatesFrequently)
            Text(notice ?? "最近 20 轮已选好；钉住的轮锁着勾选")
                .font(.system(size: 12))
                .foregroundStyle(notice == nil ? Ink.secondary : Ink.accent)
                .animation(nil, value: notice)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.line.opacity(0.35)).frame(height: 0.6)
        }
    }

    // MARK: 中间：一轮一轮

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    earlierControl
                    ForEach(Array(rounds.enumerated()), id: \.element.startID) { index, round in
                        if let text = gapText(at: index) {
                            Text("—— \(text) ——")
                                .font(.system(size: 10))
                                .foregroundStyle(Ink.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                        }
                        roundRow(round).id(round.startID)
                    }
                    if rounds.isEmpty, didLoad, !isLoading, loadError == nil {
                        Text("还没有可以带走的聊天。")
                            .font(.system(size: 13))
                            .foregroundStyle(Ink.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                proxy.scrollTo(target, anchor: .top)
                scrollTarget = nil
            }
        }
    }

    @ViewBuilder
    private var earlierControl: some View {
        if isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在翻…")
            }
            .font(.system(size: 12))
            .foregroundStyle(Ink.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
        } else if let loadError {
            VStack(spacing: 6) {
                Text(loadError)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.negative)
                    .multilineTextAlignment(.center)
                Button("再试一次") { Task { if loadedFloor == nil { await loadFirstPage() } else { await loadEarlier() } } }
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.accent)
                    .frame(minHeight: 44)
            }
            .frame(maxWidth: .infinity)
        } else if nextBefore != nil {
            Button { Task { await loadEarlier() } } label: {
                Text("加载更早的")
                    .underline()
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func roundRow(_ round: KeRound) -> some View {
        let pinned = pinnedIDs.contains(round.startID)
        let checked = pinned || selected.contains(round.startID)
        return HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .strokeBorder(checked ? Ink.accent : Ink.line, lineWidth: 1)
                    .background(Circle().fill(checked ? Ink.accent : Color.clear))
                if checked {
                    Image(systemName: pinned ? "lock.fill" : "checkmark")
                        .font(.system(size: pinned ? 9 : 10, weight: .semibold))
                        .foregroundStyle(palette.paper)
                }
            }
            .frame(width: 22, height: 22)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                Text(KeWindowFormat.roundTime(round.at))
                    .font(.system(size: 10))
                    .foregroundStyle(Ink.secondary)
                ForEach(Array(round.me.enumerated()), id: \.offset) { _, line in
                    HStack {
                        Spacer(minLength: 28)
                        bubble(line, mine: true)
                    }
                }
                ForEach(Array(round.ke.enumerated()), id: \.offset) { _, line in
                    HStack {
                        bubble(line, mine: false)
                        Spacer(minLength: 28)
                    }
                }
                if pinned {
                    Text("已钉住 · 到换窗页「已钉住」里取消")
                        .font(.system(size: 10))
                        .foregroundStyle(Ink.secondary)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            checked ? Ink.accent.opacity(0.06) : Color.clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture { toggle(round, pinned: pinned) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(pinned ? "已钉住，锁定勾选" : (checked ? "已选" : "未选"))
    }

    private func bubble(_ text: String, mine: Bool) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(mine ? Ink.meText : Ink.keText)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(mine ? Ink.meFill : Ink.keFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 两段勾选之间隔着没选的轮时，画一条细线写清楚隔了多久、省略了几轮。
    private func gapText(at index: Int) -> String? {
        guard picks.contains(rounds[index].startID),
              let previous = rounds[..<index].lastIndex(where: { picks.contains($0.startID) }) else { return nil }
        let skipped = index - previous - 1
        let gap = KeWindowFormat.gap(from: rounds[previous].at, to: rounds[index].at)
        // 上一段在翻页读到的范围之外（只是钉住的老轮）：中间到底省略了多少还不知道，只说隔了多久。
        if let loadedFloor, rounds[previous].startID < loadedFloor {
            guard let gap, let start = rounds[previous].at, let end = rounds[index].at,
                  end.timeIntervalSince(start) >= 3600 else { return nil }
            return "中间隔了 \(gap)"
        }
        guard skipped > 0 else { return nil }
        if let gap { return "中间隔了 \(gap)，省略了 \(skipped) 轮" }
        return "中间省略了 \(skipped) 轮"
    }

    private var segmentCount: Int {
        guard !picks.isEmpty else { return 0 }
        return 1 + rounds.indices.filter { gapText(at: $0) != nil }.count
    }

    // MARK: 底下：确认换窗

    private var footer: some View {
        VStack(spacing: 6) {
            Button("确认换窗") { confirming = true }
                .buttonStyle(KeDrawerButtonStyle(solid: true))
                .disabled(picks.isEmpty || store.isJobRunning)
            Text("先核对带走内容，确认后才换；旧窗原样保留")
                .font(.system(size: 11))
                .foregroundStyle(Ink.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(Ink.line.opacity(0.35)).frame(height: 0.6)
        }
    }

    private var confirmCard: some View {
        ZStack {
            Ink.primary.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture { closeCardIfIdle() }
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                switch store.rotatePhase {
                case .idle:
                    Text("带着这些，换个窗")
                        .font(Ink.song(20))
                        .foregroundStyle(Ink.primary)
                    Text("带走 \(picks.count) 轮，分成 \(segmentCount) 段，约 \(KeWindowFormat.kilo(pickedChars))。")
                        .font(.system(size: 14))
                        .foregroundStyle(Ink.primary)
                        .multilineTextAlignment(.center)
                    Text("旧窗会原样留着，可以随时回看。")
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.secondary)
                    HStack(spacing: 10) {
                        Button("再挑一下") { confirming = false }
                            .buttonStyle(KeDrawerButtonStyle())
                        Button("确认带走") {
                            let ordered = picks.sorted()
                            Task { await store.rotate(picks: ordered) }
                        }
                        .buttonStyle(KeDrawerButtonStyle(solid: true))
                    }
                    .padding(.top, 4)
                case .running:
                    ProgressView().tint(Ink.accent)
                    Text("柯正在换窗…")
                        .font(Ink.song(17))
                        .foregroundStyle(Ink.primary)
                    Text("带走的轮正一句一句搬过去，稍等一下。")
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.secondary)
                        .multilineTextAlignment(.center)
                case let .done(result):
                    Text("柯换好了")
                        .font(Ink.song(22))
                        .foregroundStyle(Ink.primary)
                    Text("Settled in.")
                        .font(Ink.script(20))
                        .foregroundStyle(Ink.secondary)
                    Text(result?.isEmpty == false ? result! : "选中的轮已带上，旧窗原样留着。")
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.secondary)
                        .multilineTextAlignment(.center)
                    Button("好") { finish() }
                        .buttonStyle(KeDrawerButtonStyle(solid: true))
                case let .failed(message):
                    Text("这次没换成")
                        .font(Ink.song(19))
                        .foregroundStyle(Ink.primary)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.negative)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 10) {
                        Button("再挑一下") {
                            store.resetRotatePhase()
                            confirming = false
                        }
                        .buttonStyle(KeDrawerButtonStyle())
                        Button("再试一次") {
                            let ordered = picks.sorted()
                            Task { await store.rotate(picks: ordered) }
                        }
                        .buttonStyle(KeDrawerButtonStyle(solid: true))
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(22)
            .frame(maxWidth: 320)
            .background(palette.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Ink.line.opacity(0.5), lineWidth: 0.6)
            }
            .shadow(color: Ink.primary.opacity(0.12), radius: 22, y: 8)
            .padding(.horizontal, 24)
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
    }

    // MARK: 动作

    private func toggle(_ round: KeRound, pinned: Bool) {
        if pinned {
            notice = "这一轮已钉住，要去换窗页「已钉住」里取消"
            Task {
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                notice = nil
            }
            return
        }
        if selected.contains(round.startID) {
            selected.remove(round.startID)
        } else {
            selected.insert(round.startID)
        }
    }

    private func closeCardIfIdle() {
        switch store.rotatePhase {
        case .idle, .failed:
            store.resetRotatePhase()
            confirming = false
        case .running, .done:
            break
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        store.resetRotatePhase()
        onFinished()
    }

    private func initialLoad() async {
        guard !didLoad else { return }
        didLoad = true
        isLoading = true
        store.resetRotatePhase()
        if store.window == nil { await store.loadWindow() }
        merge(store.window?.pins.items ?? [])
        await loadFirstPage()
    }

    private func loadFirstPage() async {
        let page = await loadPage(before: nil)
        // 最近 20 轮先勾好
        let recent = page.sorted { $0.startID > $1.startID }.prefix(20)
        selected.formUnion(recent.map(\.startID))
        if let oldest = recent.last?.startID {
            await Task.yield()
            scrollTarget = oldest
        }
    }

    private func loadEarlier() async {
        guard !isLoading else { return }
        let anchor = rounds.first(where: { $0.startID >= (loadedFloor ?? Int.min) })?.startID
        _ = await loadPage(before: nextBefore ?? loadedFloor)
        if let anchor {
            await Task.yield()
            scrollTarget = anchor
        }
    }

    private func loadPage(before: Int?) async -> [KeRound] {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let page = try await store.fetchRounds(before: before)
            merge(page.items)
            nextBefore = page.nextBefore
            if let oldest = page.items.map(\.startID).min() {
                loadedFloor = min(loadedFloor ?? oldest, oldest)
            }
            return page.items
        } catch {
            loadError = KeWindowStore.message(for: error)
            return []
        }
    }

    private func merge(_ items: [KeRound]) {
        var byID = Dictionary(uniqueKeysWithValues: rounds.map { ($0.startID, $0) })
        for item in items { byID[item.startID] = item }
        rounds = byID.values.sorted { $0.startID < $1.startID }
    }
}
