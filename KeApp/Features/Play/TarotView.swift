import SwiftUI

struct TarotView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let line: ChatLine
    @State private var api: APIClient
    init(line: ChatLine) {
        self.line = line
        _api = State(initialValue: APIClient(baseURL: line.apiBaseURL))
    }
    @State private var question = ""
    @State private var spread = "three"
    @State private var deal: TarotDeal?
    @State private var selection = TarotSelection(deckSize: 78, requiredCount: 3)
    @State private var cast: TarotCast?
    @State private var revealed = 0
    @State private var didHandOff = false
    @State private var phase: Phase = .idle
    @State private var fanOpen = false
    @State private var shuffleOffset = false
    @State private var error: String?
    @State private var operation: Task<Void, Never>?
    @State private var inspectedCard: TarotCard?
    @State private var showBacks = false
    @State private var showHistory = false
    @State private var confirmRestart = false
    @State private var accessibleIndex = 39
    @State private var draggedIndex: Int?
    @State private var dragOffset = CGSize.zero
    /// 122：「夜里」哪几格的长解读展开着（按牌位）
    @State private var openedNight: Set<Int> = []
    /// 120：手指在牌扇上这一下滑没滑过——只记不画，改它不会重画 78 张牌
    @State private var fanTouch = FanTouch()
    private final class FanTouch {
        var movedAt = Date.distantPast
        var start: CGPoint?
        var scrubbing = false
    }
    @AppStorage("tarot.tableBack.v91") private var backID = "butterfly"
    @FocusState private var questionFocused: Bool
    private enum Phase { case idle, shuffling, selecting, submitting, revealing, done }
    private var busy: Bool { phase == .shuffling || phase == .submitting || phase == .revealing }
    private var positions: [String] {
        deal?.positions ?? TarotSpread.positions(spread)
    }
    private var isNight: Bool { spread == TarotSpread.night }
    private var reduceMotion: Bool {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-test-reduce-motion") { return true }
#endif
        return systemReduceMotion
    }
    private var motion: Animation? { reduceMotion ? nil : .easeInOut(duration: TarotTableStyle.moveDuration) }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: TarotTableStyle.gap) {
                    header
                    spreadPicker
                    if !TarotSpread.asksQuestion(spread) {
                        // 122：「夜里」不是算命，不放问题框；留一行轻轻的字，页面不跳
                        Text("不用问问题，凭感觉抽三张：身份 · 关系 · 玩法")
                            .font(TarotTableStyle.caption).foregroundStyle(TarotTableStyle.muted)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: TarotTableStyle.controlHeight)
                            .accessibilityIdentifier("tarot-night-hint")
                    } else {
                        HStack(alignment: .top, spacing: TarotTableStyle.smallGap) {
                            TextField("想问的问题（可不填）", text: $question, axis: .vertical)
                                .font(TarotTableStyle.body).lineLimit(1...3)
                                .padding(TarotTableStyle.gap).background(TarotTableStyle.panel, in: RoundedRectangle(cornerRadius: TarotTableStyle.radius))
                                .overlay {
                                    RoundedRectangle(cornerRadius: TarotTableStyle.radius)
                                        .stroke(TarotTableStyle.border, lineWidth: TarotTableStyle.hairline)
                                        .allowsHitTesting(false)
                                }
                                .contentShape(Rectangle())
                                .simultaneousGesture(TapGesture().onEnded { questionFocused = true })
                                .focused($questionFocused).disabled(busy || selection.submitted)
                                .submitLabel(.done).onSubmit { questionFocused = false }
                                .accessibilityIdentifier("tarot-question")
                            if questionFocused {
                                Button("完成") { questionFocused = false }
                                    .font(TarotTableStyle.caption)
                                    .frame(minHeight: TarotTableStyle.controlHeight)
                                    .accessibilityIdentifier("tarot-question-done")
                            }
                        }
                    }
                    table(width: geometry.size.width - TarotTableStyle.padding * 2)
                    if isNight, let cast, revealed > 0 { nightReadings(cast) }
                    // 136：翻开以后桌子底下直接写牌义，不用等柯
                    if !isNight, phase == .done, let cast, let objective = cast.objective, !objective.isEmpty {
                        TarotMeaningPanel(cast: cast, objective: objective) { inspectedCard = $0 }
                    }
                    status
                    if let error {
                        Text(error).font(TarotTableStyle.caption).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("tarot-error")
                    }
                    primaryAction
                    if deal != nil && !busy {
                        Button("重新洗牌") { confirmRestart = true }
                            .font(TarotTableStyle.caption).frame(minHeight: TarotTableStyle.controlHeight)
                            .accessibilityIdentifier("tarot-restart")
                    }
                    // 122：「夜里」翻开后上面那几格已经写了牌名正逆，这张清单就不重复了
                    if (spread == "celtic" || typeSize.isAccessibilitySize), deal != nil, !(isNight && revealed > 0) {
                        VStack(alignment: .leading, spacing: TarotTableStyle.smallGap) {
                            ForEach(Array(positions.enumerated()), id: \.offset) { index, position in
                                Text("\(index + 1) · \(position)\(cardDescription(index))")
                                    .font(TarotTableStyle.caption).fixedSize(horizontal: false, vertical: true)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, TarotTableStyle.padding).padding(.bottom, TarotTableStyle.padding)
            }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(TarotTableStyle.ink).buttonStyle(.plain)
        .background {
            GeometryReader { geometry in
                Image("TarotLavenderCloth").resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    .overlay(theme.skin == .night ? TarotTableStyle.nightShade : .clear)
                    // 122：「夜里」桌布暗一层
                    .overlay(isNight ? TarotTableStyle.nightSpreadShade : .clear)
                    .animation(motion, value: isNight)
            }.ignoresSafeArea()
        }
        .background(TarotTableStyle.cloth.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .confirmationDialog("重新洗牌会收回桌上的牌，并重新开始。", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("重新开始") { reset() }
            Button("继续这一次", role: .cancel) { }
        }
        .sheet(isPresented: $showBacks) { backPicker }
        .sheet(isPresented: $showHistory) { TarotHistoryView(api: api).environmentObject(theme) }
        .fullScreenCover(item: $inspectedCard) { card in
            TarotCardInspector(cards: cast?.cards ?? [card], initialCard: card, api: api).environmentObject(theme)
                // 118：看大牌时从左边缘右划，先收这张牌，回到牌桌
                .swipeBackToClose { inspectedCard = nil }
        }
        .onDisappear { operation?.cancel() }
    }

    private var header: some View {
        ZStack {
            Text("塔罗").font(TarotTableStyle.title)
            HStack(spacing: 4) {
                Button { operation?.cancel(); dismiss() } label: {
                    Image(systemName: "chevron.left").frame(width: TarotTableStyle.controlHeight, height: TarotTableStyle.controlHeight)
                }.accessibilityLabel("返回").accessibilityIdentifier("tarot-close")
                Spacer()
                // 136：以前抽过的牌
                Button("记录") { questionFocused = false; showHistory = true }.font(TarotTableStyle.caption)
                    .frame(minWidth: TarotTableStyle.controlHeight, minHeight: TarotTableStyle.controlHeight)
                    .accessibilityIdentifier("tarot-history")
                Button("牌背") { showBacks = true }.font(TarotTableStyle.caption)
                    .frame(minWidth: TarotTableStyle.controlHeight, minHeight: TarotTableStyle.controlHeight)
                    .accessibilityIdentifier("tarot-theme")
            }
        }
    }
    private var spreadPicker: some View {
        // 122：多了「夜里」，四个一行；字放得很大挤不下时改成能左右划
        ViewThatFits(in: .horizontal) {
            HStack(spacing: TarotTableStyle.padding) { spreadButtons }
            ScrollView(.horizontal) {
                HStack(spacing: TarotTableStyle.padding) { spreadButtons }
            }.scrollIndicators(.hidden)
        }.frame(minHeight: TarotTableStyle.controlHeight)
    }
    private var spreadButtons: some View {
        ForEach(TarotSpread.all, id: \.self) { key in
            Button {
                guard spread != key else { return }
                spread = key
                if !TarotSpread.asksQuestion(key) { questionFocused = false }
                // Choosing another spread starts a fresh round with the same question.
                reset()
            } label: {
                Text(TarotSpread.title(key))
                    .font(TarotTableStyle.body).padding(.vertical, TarotTableStyle.smallGap)
                    .overlay(alignment: .bottom) {
                        if spread == key { Rectangle().fill(TarotTableStyle.ink).frame(height: TarotTableStyle.hairline) }
                    }
            }.disabled(busy).accessibilityIdentifier("tarot-spread-\(key)")
                .accessibilityAddTraits(spread == key ? .isSelected : [])
        }
    }

    private func table(width: CGFloat) -> some View {
        let height = width * (spread == "celtic" ? TarotTableStyle.celticStageHeight : spread == "one" ? TarotTableStyle.singleStageHeight : TarotTableStyle.stageHeight)
        return ZStack(alignment: .topLeading) {
            ForEach(positions.indices, id: \.self) { slot in
                let point = slotPoint(slot, width: width)
                let cardWidth = slotWidth(width)
                RoundedRectangle(cornerRadius: TarotTableStyle.cardRadius)
                    .stroke(TarotTableStyle.slotBorder, style: StrokeStyle(lineWidth: TarotTableStyle.hairline, dash: [TarotTableStyle.smallGap]))
                    .frame(width: cardWidth, height: cardWidth / TarotTableStyle.cardAspect)
                    .rotationEffect(.degrees(spread == "celtic" && slot == 1 ? 90 : 0))
                    .position(point)
                    .accessibilityHidden(true)
                if spread != "celtic" {
                    if !typeSize.isAccessibilitySize {
                    Text(shortPosition(positions[slot])).font(TarotTableStyle.body)
                        .frame(width: width / CGFloat(positions.count))
                        .position(x: point.x, y: width * TarotTableStyle.slotLabelY)
                    }
                    if !typeSize.isAccessibilitySize, slot < revealed, let card = cast?.cards[slot] {
                        Text("\(card.cn)\n\(card.reversed ? "逆位" : "正位")")
                            .font(TarotTableStyle.caption).multilineTextAlignment(.center)
                            .frame(width: width / CGFloat(positions.count)).fixedSize(horizontal: false, vertical: true)
                            .position(x: point.x, y: width * (spread == "one" ? TarotTableStyle.singleCardLabelY : TarotTableStyle.cardLabelY))
                            .accessibilityHidden(true)
                    }
                } else if slot != 1 && !typeSize.isAccessibilitySize {
                    // The crossed pair shares a label; staff numbers sit beside their cards.
                    Text(slot == 0 ? "1 · 2" : "\(slot + 1)").font(TarotTableStyle.tiny)
                        .position(x: slot >= 6 ? point.x - cardWidth / 2 - TarotTableStyle.gap : point.x,
                                  y: slot >= 6 ? point.y : point.y - cardWidth / TarotTableStyle.cardAspect / 2 - TarotTableStyle.smallGap)
                        .accessibilityHidden(true)
                }
            }
            // 122：这一副几张就摆几张（夜里 22 张大牌）
            ForEach(0..<selection.deckSize, id: \.self) { index in
                deckCard(index, width: width, height: height)
            }
            // 120：认牌照着画出来的样子找「手指下最上面那张」（TarotFan.card），不再按角度四舍五入。
            // 点和滑分开认：点用系统的轻点，页面上下滚的时候不会被当成一下点；
            // 左右滑才换抬起的那张；滑过的这一下抬手不算点，不会顺手把牌放上桌。
            Rectangle().fill(.clear).contentShape(Rectangle())
                .frame(width: width, height: width * (TarotTableStyle.fanHitHeight))
                // Attach gestures to the fan's own bounds, before position expands its layout.
                .onTapGesture(coordinateSpace: .named("tarot-table")) { location in
                    guard Date().timeIntervalSince(fanTouch.movedAt) > TarotTableStyle.tapAfterSlide,
                          phase == .selecting, !selection.submitted,
                          let index = fanCard(location, width: width, height: height, liftAware: true) else { return }
                    tap(index)
                }
                // Simultaneous recognition lets a vertical drag scroll the ten-card table.
                .simultaneousGesture(DragGesture(minimumDistance: TarotTableStyle.gap, coordinateSpace: .named("tarot-table"))
                    .onChanged { value in
                        fanTouch.movedAt = Date()
                        // 这一下一开始往哪边走就定了：横着走是换牌，竖着走是在翻页面
                        if fanTouch.start != value.startLocation {
                            fanTouch.start = value.startLocation
                            fanTouch.scrubbing = abs(value.translation.width) > abs(value.translation.height)
                        }
                        guard fanTouch.scrubbing, phase == .selecting, !selection.submitted,
                              let index = fanCard(value.location, width: width, height: height, liftAware: false),
                              index != selection.preview else { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: TarotTableStyle.liftDuration)) { selection.previewCard(index) }
                    }
                    .onEnded { _ in
                        fanTouch.movedAt = Date(); fanTouch.start = nil; fanTouch.scrubbing = false
                    })
                .accessibilityElement().accessibilityLabel("半圆牌扇，\(selection.deckSize) 张牌")
                .accessibilityValue("第 \(accessibleIndex + 1) 张，已选 \(selection.picks.count) 张")
                .accessibilityHint("上下轻扫换牌，轻点两次抬起，再轻点两次放到桌上")
                .accessibilityAdjustableAction { direction in
                    let step = direction == .increment ? 1 : -1
                    accessibleIndex = min(selection.deckSize - 1, max(0, accessibleIndex + step))
                }
                .accessibilityAction { tap(accessibleIndex) }
                .accessibilityIdentifier("tarot-fan")
                .allowsHitTesting(phase == .selecting && !selection.submitted)
                .position(x: width / 2, y: height - width * TarotTableStyle.fanHitHeight / 2)
        }
        .frame(width: width, height: height).coordinateSpace(name: "tarot-table")
        // 120：抬起的那张一换就轻轻震一下，左右滑的时候一张一张数得出来
        .sensoryFeedback(.selection, trigger: selection.preview)
        .padding(.top, TarotTableStyle.gap)
    }

    private func deckCard(_ index: Int, width: CGFloat, height: CGFloat) -> some View {
        let slot = selection.picks.firstIndex(of: index)
        let lifted = selection.preview == index
        // 120：和认牌用同一套摆法（TarotFan），画在哪就认在哪
        let (fanPoint, angle) = TarotFan.placement(index, width: width, height: height, lifted: lifted, deckSize: selection.deckSize)
        let stackPoint = CGPoint(x: width / 2 + (shuffleOffset ? (index.isMultiple(of: 2) ? width * TarotTableStyle.shuffleSeparation : -width * TarotTableStyle.shuffleSeparation) : 0),
                                 y: height - width * TarotTableStyle.stackY + CGFloat(index % 4) * TarotTableStyle.hairline)
        let point = slot.map { slotPoint($0, width: width) } ?? (fanOpen ? fanPoint : stackPoint)
        let cardWidth = slot == nil ? width * (fanOpen ? TarotTableStyle.fanCardWidth : TarotTableStyle.stackCardWidth) : slotWidth(width)
        let rotation = slot == nil ? (fanOpen ? angle * 180 / .pi - 270 : (shuffleOffset ? Double(index % 5 - 2) * 3 : 0)) : (spread == "celtic" && slot == 1 ? 90.0 : 0.0)
        let card = slot.flatMap { cast?.cards.indices.contains($0) == true ? cast?.cards[$0] : nil }
        let faceUp = slot.map { $0 < revealed } ?? false
        return TarotTableCard(backID: backID, card: card, api: api, faceUp: faceUp)
            .frame(width: cardWidth, height: cardWidth / TarotTableStyle.cardAspect)
            .contentShape(RoundedRectangle(cornerRadius: TarotTableStyle.cardRadius))
            .shadow(color: TarotTableStyle.shadow, radius: TarotTableStyle.shadowRadius, y: TarotTableStyle.shadowY)
            .onTapGesture { if faceUp, let card { inspectedCard = card } }
            .gesture(DragGesture(minimumDistance: TarotTableStyle.gap, coordinateSpace: .named("tarot-table"))
                .onChanged { value in
                    guard slot != nil, !selection.submitted else { return }
                    draggedIndex = index; dragOffset = value.translation
                }
                .onEnded { value in
                    defer { withAnimation(motion) { draggedIndex = nil; dragOffset = .zero } }
                    guard slot != nil, !selection.submitted,
                          value.location.y > height - width * (TarotTableStyle.fanRadius + TarotTableStyle.fanBottom + TarotTableStyle.previewLift) else { return }
                    withAnimation(motion) { selection.returnCard(index) }
                })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((faceUp ? card : nil).map { "\($0.position)，\($0.cn)，\($0.reversed ? "逆位" : "正位")，点开大图" } ?? "第 \((slot ?? 0) + 1) 个位置，背面朝上")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if faceUp, let card { inspectedCard = card }
                else if slot != nil { withAnimation(motion) { selection.returnCard(index) } }
            }
            .accessibilityAction(named: "放回牌扇") { withAnimation(motion) { selection.returnCard(index) } }
            .accessibilityIdentifier(slot.map { "tarot-card-\($0)" } ?? "tarot-deck-\(index)")
            .accessibilityHidden(slot == nil)
            .allowsHitTesting(slot != nil)
            // Keep the card's tap/drag region local; positioned wrappers otherwise cover the fan.
            .rotationEffect(.degrees(rotation))
            .position(x: point.x + (draggedIndex == index ? dragOffset.width : 0),
                      y: point.y + (draggedIndex == index ? dragOffset.height : 0))
            .zIndex(slot.map { Double(100 + $0) } ?? (lifted ? 90 : Double(index)))
    }

    /// 122：「夜里」翻开一张，桌子底下就多一格：栏目（身份/关系/玩法）+ 牌名正逆 + 那一句场景（正文字号，最显眼）；
    /// 长的解读收在「展开」后面，三格都摊开也不会一下子满屏是字。点格子上的牌名能看大牌。
    private func nightReadings(_ cast: TarotCast) -> some View {
        VStack(spacing: TarotTableStyle.gap) {
            ForEach(Array(cast.cards.prefix(revealed).enumerated()), id: \.offset) { slot, card in
                if let night = card.night, !night.summary.isEmpty {
                    nightReading(slot: slot, card: card, night: night)
                }
            }
        }
    }
    private func nightReading(slot: Int, card: TarotCard, night: TarotNight) -> some View {
        let open = openedNight.contains(slot)
        return VStack(alignment: .leading, spacing: TarotTableStyle.smallGap) {
            HStack(spacing: TarotTableStyle.smallGap) {
                if !night.displayLabel.isEmpty {
                    Text(night.displayLabel).font(TarotTableStyle.caption)
                        .padding(.horizontal, TarotTableStyle.smallGap)
                        .overlay(Capsule().stroke(TarotTableStyle.border, lineWidth: TarotTableStyle.hairline))
                }
                Button { inspectedCard = card } label: {
                    Text("\(card.cn) · \(card.reversed ? "逆位" : "正位")").font(TarotTableStyle.caption)
                        .foregroundStyle(TarotTableStyle.muted)
                        .frame(minHeight: TarotTableStyle.controlHeight)
                }.accessibilityHint("点开大图")
                Spacer(minLength: 0)
                if !night.more.isEmpty {
                    Button {
                        withAnimation(motion) {
                            if open { openedNight.remove(slot) } else { openedNight.insert(slot) }
                        }
                    } label: {
                        Text(open ? "收起" : "展开").font(TarotTableStyle.caption).foregroundStyle(TarotTableStyle.muted)
                            .frame(minWidth: TarotTableStyle.controlHeight, minHeight: TarotTableStyle.controlHeight, alignment: .trailing)
                    }.accessibilityIdentifier("tarot-night-more-\(slot)")
                }
            }
            Text(night.summary).font(TarotTableStyle.body).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("tarot-night-desc-\(slot)")
            if open && !night.more.isEmpty {
                Text(night.more).font(TarotTableStyle.caption).foregroundStyle(TarotTableStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("tarot-night-interpret-\(slot)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TarotTableStyle.gap).padding(.bottom, TarotTableStyle.gap)
        .background(TarotTableStyle.panel, in: RoundedRectangle(cornerRadius: TarotTableStyle.radius))
        .overlay {
            RoundedRectangle(cornerRadius: TarotTableStyle.radius)
                .stroke(TarotTableStyle.border, lineWidth: TarotTableStyle.hairline)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tarot-night-\(slot)")
    }

    private var status: some View {
        VStack(spacing: TarotTableStyle.smallGap) {
            Text("已选 \(selection.picks.count) / \(positions.count)")
                .font(TarotTableStyle.caption).accessibilityIdentifier("tarot-selection-count")
            if let preview = selection.preview {
                Button("第 \(preview + 1) 张 · 再点一下放上桌") { tap(preview) }
                    .accessibilityIdentifier("tarot-confirm-preview")
            } else {
                Text(phase == .idle ? "先洗牌，再凭感觉选。" : phase == .shuffling ? "洗牌中…" : phase == .done ? "牌已翻开，交给柯来解。" : selection.submitted ? "牌已经选定，正在等它翻开。" : selection.isFull ? "拖回牌扇可以重选" : "点一下抬起，再点它放上桌；左右滑可以换")
            }
        }.font(TarotTableStyle.caption).foregroundStyle(TarotTableStyle.muted)
            .frame(minHeight: TarotTableStyle.controlHeight)
    }
    @ViewBuilder private var primaryAction: some View {
        if phase == .done, let cast {
            actionButton("交给柯  →", id: "tarot-ask-ke") { askKe(cast) }.disabled(didHandOff)
        } else if deal == nil {
            actionButton(phase == .shuffling ? "洗牌中…" : "洗牌", id: "tarot-draw") { operation = Task { await shuffle() } }.disabled(busy)
        } else {
            actionButton(phase == .submitting ? "翻牌中…" : phase == .revealing ? "正在翻开…" : selection.submitted ? "重试翻牌" : "翻牌", id: "tarot-flip") {
                operation = Task { await flip() }
            }.disabled(!selection.isFull || busy)
        }
    }
    private func actionButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(TarotTableStyle.body).frame(maxWidth: .infinity)
                .frame(minHeight: TarotTableStyle.controlHeight).padding(.vertical, TarotTableStyle.smallGap)
                .background(TarotTableStyle.panel, in: Capsule())
                .overlay(Capsule().stroke(TarotTableStyle.border, lineWidth: TarotTableStyle.hairline))
        }.accessibilityIdentifier(id)
    }
    private var backPicker: some View {
        ScrollView {
            VStack(spacing: TarotTableStyle.padding) {
                Text("牌背").font(TarotTableStyle.title)
                ForEach(["butterfly"] + TarotBack.all.map(\.id), id: \.self) { id in
                    Button { backID = id; showBacks = false } label: {
                        HStack(spacing: TarotTableStyle.padding) {
                            TarotTableCard.back(id).frame(width: TarotTableStyle.controlHeight, height: TarotTableStyle.controlHeight / TarotTableStyle.cardAspect)
                            Text(id == "butterfly" ? "灰紫月蝶" : TarotBack.find(id).name).font(TarotTableStyle.body)
                            Spacer()
                            if id == backID { Image(systemName: "checkmark") }
                        }
                    }
                }
            }.padding(TarotTableStyle.padding)
        }.foregroundStyle(TarotTableStyle.ink).background(TarotTableStyle.cloth)
            .presentationDetents([.medium, .large])
    }
    private func slotWidth(_ width: CGFloat) -> CGFloat {
        width * (spread == "celtic" ? TarotTableStyle.celticSlotWidth : spread == "one" ? TarotTableStyle.singleSlotWidth : TarotTableStyle.slotWidth)
    }
    private func slotPoint(_ slot: Int, width: CGFloat) -> CGPoint {
        if spread == "celtic" {
            return CGPoint(x: width * TarotTableStyle.celticX[slot], y: width * TarotTableStyle.celticY[slot])
        }
        return CGPoint(x: width * CGFloat(2 * slot + 1) / CGFloat(positions.count * 2), y: width * (spread == "one" ? TarotTableStyle.singleSlotY : TarotTableStyle.slotY))
    }
    private func fanCard(_ point: CGPoint, width: CGFloat, height: CGFloat, liftAware: Bool) -> Int? {
        TarotFan.card(at: point, width: width, height: height,
                      picks: selection.picks, preview: selection.preview, liftAware: liftAware, deckSize: selection.deckSize)
    }
    private func tap(_ index: Int) {
        guard phase == .selecting else { return }
        let duration = selection.preview == index ? TarotTableStyle.moveDuration : TarotTableStyle.liftDuration
        withAnimation(reduceMotion ? nil : .easeInOut(duration: duration)) { selection.tap(index) }
    }
    private func shortPosition(_ text: String) -> String { String(text.prefix { $0 != "(" && $0 != "（" }) }
    private func cardDescription(_ index: Int) -> String {
        guard index < revealed, let card = cast?.cards[index] else { return "" }
        return " · \(card.cn) · \(card.reversed ? "逆位" : "正位")"
    }
    private func pause(_ seconds: Double) async throws {
        try Task.checkCancellation()
        if !reduceMotion { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    }
    @MainActor private func shuffle() async {
        guard !busy else { return }
        questionFocused = false; phase = .shuffling; error = nil
        do {
            // A single network shuffle locks the deck. Animation never reshuffles server state.
            // 122：「夜里」不带问题（问题框藏着，之前别的牌阵填的也不发）
            let asked = TarotSpread.asksQuestion(spread) ? question.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            async let response = api.shuffleTarot(question: asked, spread: spread)
            for _ in 0..<4 {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: TarotTableStyle.shuffleDuration)) { shuffleOffset.toggle() }
                try await pause(TarotTableStyle.shuffleDuration)
            }
            let newDeal = try await response
            try Task.checkCancellation()
            deal = newDeal
            selection = TarotSelection(deckSize: newDeal.deck_size, requiredCount: newDeal.positions.count)
            accessibleIndex = newDeal.deck_size / 2
            withAnimation(reduceMotion ? nil : .easeInOut(duration: TarotTableStyle.unfoldDuration)) { fanOpen = true; shuffleOffset = false }
            try await pause(TarotTableStyle.unfoldDuration)
            phase = .selecting
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled else { return }
            self.error = "没能洗好牌，请再试一次。\(error.localizedDescription)"
            phase = .idle; shuffleOffset = false
        }
    }
    @MainActor private func flip() async {
        guard !busy, let deal, selection.freeze() else { return }
        questionFocused = false
        phase = .submitting; error = nil
        do {
            let result = try await api.pickTarot(deal: deal, picks: selection.picks)
            try Task.checkCancellation()
            cast = result; phase = .revealing
            for count in 1...result.cards.count {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: TarotTableStyle.flipDuration)) { revealed = count }
                try await pause(TarotTableStyle.flipDuration)
            }
            phase = .done
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled else { return }
            self.error = "\(error.localizedDescription)\n重试会保留这次选牌；若已超过一小时，请重新洗牌。"
            phase = .selecting
        }
    }
    private func reset() {
        operation?.cancel(); deal = nil; cast = nil; revealed = 0; error = nil; phase = .idle; didHandOff = false
        openedNight = []; accessibleIndex = TarotSpread.deckSize(spread) / 2
        withAnimation(motion) {
            selection = TarotSelection(deckSize: TarotSpread.deckSize(spread), requiredCount: TarotSpread.cardCount(spread) ?? 3)
            fanOpen = false
        }
    }
    private func askKe(_ cast: TarotCast) {
        guard !didHandOff else { return }
        didHandOff = true
        // The deal locks cards at shuffle time; edits to the question never reshuffle them.
        NotificationCenter.default.post(name: .tarotReadingRequest,
                                        object: ChatHandoff(text: cast.readingMessage(question: question), attachments: cast.chatAttachments))
        dismiss()
    }
}

private struct TarotTableCard: View {
    let backID: String
    let card: TarotCard?
    let api: APIClient
    let faceUp: Bool
    @ViewBuilder static func back(_ id: String) -> some View {
        if id == "butterfly" { Image("TarotMoonButterflyBack").resizable().scaledToFill().clipped() }
        else { TarotBackArtwork(back: TarotBack.find(id), tint: TarotBack.find(id).tint) }
    }
    var body: some View {
        ZStack {
            Self.back(backID).modifier(TarotFaceVisibility(angle: faceUp ? 180 : 0, front: false))
            if let card {
                CompanionImage(api: api, path: card.image)
                    .rotationEffect(.degrees(card.reversed ? 180 : 0))
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .modifier(TarotFaceVisibility(angle: faceUp ? 180 : 0, front: true))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: TarotTableStyle.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: TarotTableStyle.cardRadius).stroke(TarotTableStyle.border, lineWidth: TarotTableStyle.hairline))
        .rotation3DEffect(.degrees(faceUp ? 180 : 0), axis: (x: 0, y: 1, z: 0))
    }
}

/// Switch the visible face at the edge, instead of dissolving front and back together.
private struct TarotFaceVisibility: AnimatableModifier {
    var angle: Double
    let front: Bool
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }
    func body(content: Content) -> some View {
        content.opacity((angle >= 90) == front ? 1 : 0)
    }
}
