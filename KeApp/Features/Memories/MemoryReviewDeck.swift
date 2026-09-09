import SwiftUI

struct MemoryReviewDeck: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: MemoryReviewStore
    @State private var showDeferred = false
    @State private var editing: ReviewCard?
    @State private var reading: ReviewCard?
    @State private var translation = CGSize.zero
    @State private var isDeparting = false
    @State private var departingCard: ReviewCard?
    @State private var showConflict = false

    private var cards: [ReviewCard] { showDeferred ? store.deferred : store.pending }
    private var current: ReviewCard? { departingCard ?? cards.first }
    private var previewAction: ReviewAction? {
        ReviewGesture.action(x: translation.width, y: translation.height, threshold: theme.metric.reviewSwipeThreshold)
    }
    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: theme.metric.gapM) {
                HStack {
                    Text(store.line.title).font(theme.font.reviewCaption)
                    Spacer()
                    Text(store.syncLabel).font(theme.font.reviewCaption)
                }.foregroundStyle(theme.reviewSecondary)
                Picker("审核队列", selection: $showDeferred) {
                    Text("待审 \(store.pending.count)").tag(false)
                    Text("暂缓 \(store.deferred.count)").tag(true)
                }.pickerStyle(.segmented)
                if let error = store.error {
                    HStack(alignment: .top) {
                        Text(error).font(theme.font.reviewCaption)
                        Spacer()
                        Button(store.blockedOperation == nil ? "重试" : "核对") {
                            if store.blockedOperation != nil { showConflict = true }
                            else { Task { await store.sync() } }
                        }.frame(minHeight: theme.metric.touchTarget)
                    }
                }
                if let card = current {
                    ZStack {
                        if cards.count > 1 {
                            RoundedRectangle(cornerRadius: theme.metric.radiusCard)
                                .fill(theme.color.card)
                                .padding(.horizontal, theme.metric.gapM)
                                .offset(y: theme.metric.gapS)
                                .accessibilityHidden(true)
                        }
                        cardFace(card)
                            .overlay(alignment: .topTrailing) {
                                if let action = previewAction {
                                    Text(action.label)
                                        .font(theme.font.sectionTitle)
                                        .padding(theme.metric.gapM)
                                        .background(theme.color.cardElevated, in: Capsule())
                                        .padding(theme.metric.gapM)
                                        .accessibilityHidden(true)
                                }
                            }
                            .offset(translation)
                            .rotationEffect(.degrees(reduceMotion ? 0 : Double(translation.width / 24)))
                            .gesture(DragGesture(minimumDistance: 18)
                                .onChanged { value in
                                    guard !isDeparting, store.canReview else { return }
                                    translation = CGSize(width: value.translation.width, height: value.translation.height)
                                }
                                .onEnded { value in
                                    guard !isDeparting else { return }
                                    if let action = ReviewGesture.action(x: value.translation.width, y: value.translation.height,
                                                                          threshold: theme.metric.reviewSwipeThreshold) {
                                        commit(action, card: card, width: geometry.size.width)
                                    } else { withAnimation(spring) { translation = .zero } }
                                })
                            .accessibilityAction(named: "收下") { commit(.accept, card: card, width: geometry.size.width) }
                            .accessibilityAction(named: "不对") { commit(.reject, card: card, width: geometry.size.width) }
                            .accessibilityAction(named: "备注") { editing = card }
                            .accessibilityAction(named: "暂缓") { commit(.defer, card: card, width: geometry.size.width) }
                            .accessibilityAction(named: "情况变了") { commit(.changed, card: card, width: geometry.size.width) }
                    }
                    .frame(maxHeight: .infinity)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("review-card")
                    HStack(spacing: theme.metric.gapM) {
                        actionButton("不对", icon: "xmark", id: "review-reject") { commit(.reject, card: card, width: geometry.size.width) }
                        actionButton("备注", icon: "square.and.pencil", id: "review-note") { editing = card }
                        actionButton("收下", icon: "checkmark", id: "review-accept") { commit(.accept, card: card, width: geometry.size.width) }
                            .disabled(!card.can_accept)
                            .opacity(card.can_accept ? 1 : 0.35)
                    }
                    .disabled(isDeparting || !store.canReview)
                    .opacity(store.canReview && !isDeparting ? 1 : 0.35)
                    Text("左划不对 · 右划收下\n上划暂缓 · 填好现在的情况下划更新")
                        .font(theme.font.reviewCaption).foregroundStyle(theme.reviewSecondary)
                        .multilineTextAlignment(.center)
                } else {
                    Spacer()
                    Image(systemName: "rectangle.stack.badge.checkmark").font(theme.font.pageTitle)
                    Text(store.archive.storeID == nil ? "等记忆过来" : showDeferred ? "暂时没有搁下的卡" : "这一叠看完了")
                        .font(theme.font.sectionTitle)
                    Text(store.archive.storeID == nil ? "连上网络后，待审记忆会出现在这里。" : "有新的待审记忆时，再来一起核对。")
                        .font(theme.font.reviewBody).foregroundStyle(theme.reviewSecondary)
                        .multilineTextAlignment(.center)
                    Button("刷新") { Task { await store.sync() } }.frame(minHeight: theme.metric.touchTarget)
                    Spacer()
                }
                Button {
                    store.undo()
                    showDeferred = store.archive.cards.first?.deferred ?? false
                    Task { await store.sync() }
                } label: {
                    Label("撤销上一张", systemImage: "arrow.uturn.backward")
                        .frame(minHeight: theme.metric.touchTarget)
                }
                    .disabled(!store.canUndo || isDeparting)
                    .opacity(store.canUndo && !isDeparting ? 1 : 0.35)
                    .accessibilityIdentifier("review-undo")
            }
            .padding(theme.metric.pagePadding)
            .foregroundStyle(theme.color.textPrimary)
            .background(theme.color.bg)
        }
        .navigationTitle("核对记忆")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: $editing) { card in ReviewNoteEditor(store: store, card: card) }
        .sheet(item: $reading) { card in ReviewOriginalView(card: card) }
        .sheet(isPresented: $showConflict) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: theme.metric.gapL) {
                        Text(store.error ?? "这张卡已有其他修改，请重新核对。")
                        if let operation = store.blockedOperation {
                            Text("本次判定 · \(operation.verdict.label)")
                            Text(operation.note.isEmpty ? "没有附加备注" : operation.note)
                        }
                        Button("撤回这张卡的本地操作，保留备注并刷新", role: .destructive) {
                            Task { await store.discardBlockedOperation(); showConflict = false }
                        }
                    }.padding(theme.metric.pagePadding)
                }.navigationTitle("待同步记录")
                    .toolbar { Button("关闭") { showConflict = false } }
            }
        }
        .onChange(of: current?.id) { _, _ in translation = .zero }
    }

    private func cardFace(_ card: ReviewCard) -> some View {
        VStack(alignment: .leading, spacing: theme.metric.gapM) {
            HStack {
                Text(card.category).font(theme.font.reviewCaption)
                Spacer()
                Text("待你核对").font(theme.font.reviewCaption)
            }.foregroundStyle(theme.reviewSecondary)
            Text(card.fact).font(theme.font.reviewFact)
                .lineLimit(7).accessibilityIdentifier("review-fact")
            Text("引证原话").font(theme.font.reviewCaption).foregroundStyle(theme.reviewSecondary)
            Text("“\(card.quote)”").font(theme.font.reviewBody).lineLimit(5)
            Spacer(minLength: theme.metric.gapS)
            if !store.draft(for: card).isEmpty {
                Text("\(store.hasDraft(for: card) ? "本机草稿，尚未提交" : "备注") · \(store.draft(for: card))")
                    .font(theme.font.reviewCaption).lineLimit(3)
            }
            Text(card.validation.isEmpty ? "引证匹配原文" : card.validation.joined(separator: "；"))
                .font(theme.font.reviewCaption).foregroundStyle(theme.reviewSecondary)
            Text(card.sources.map { "\($0.label) · \($0.occurred_at ?? card.observed_at)" }.joined(separator: "\n"))
                .font(theme.font.reviewCaption).foregroundStyle(theme.reviewSecondary).lineLimit(2)
            Button { reading = card } label: {
                Label("看完整事实与原文", systemImage: "text.alignleft")
                    .frame(minHeight: theme.metric.touchTarget)
            }
                .accessibilityIdentifier("review-original")
        }
        .padding(theme.metric.gapL)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.color.cardElevated, in: RoundedRectangle(cornerRadius: theme.metric.radiusCard))
        .contentShape(RoundedRectangle(cornerRadius: theme.metric.radiusCard))
    }

    private func actionButton(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: theme.metric.gapS) {
                Image(systemName: icon).font(theme.font.sectionTitle)
                Text(title).font(theme.font.reviewCaption)
            }
            .frame(maxWidth: .infinity, minHeight: theme.metric.reviewActionHeight)
            .background(theme.color.card, in: RoundedRectangle(cornerRadius: theme.metric.radiusChip))
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }

    private func commit(_ action: ReviewAction, card: ReviewCard, width: CGFloat) {
        guard !isDeparting else { return }
        if action == .defer && store.draft(for: card).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            withAnimation(spring) { translation = .zero }
            editing = card
            return
        }
        if action == .changed && (store.changeDraft(for: card).fact.isEmpty || store.changeDraft(for: card).when.isEmpty) {
            withAnimation(spring) { translation = .zero }
            editing = card
            return
        }
        departingCard = card
        guard store.act(action, on: card, note: store.draft(for: card)) else {
            departingCard = nil
            withAnimation(spring) { translation = .zero }; return
        }
        isDeparting = true
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22), completionCriteria: .logicallyComplete) {
            translation = reduceMotion ? .zero : CGSize(width: action == .accept ? width * 1.3 : action == .reject ? -width * 1.3 : 0,
                                                        height: action == .defer ? -width * 2 : action == .changed ? width * 2 : translation.height)
        } completion: {
            departingCard = nil
            translation = .zero
            isDeparting = false
            Task { await store.sync() }
        }
    }
}

struct ReviewNoteEditor: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: MemoryReviewStore
    let card: ReviewCard
    @State private var note: String = ""
    @State private var change = MemoryChangeDraft()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: theme.metric.gapM) {
                Text("很多事不只分对错").font(theme.font.sectionTitle)
                Text("只保存备注不代表收下。不完全对、还拿不准，可以暂缓；旧情况有变化，填写下方的新情况。")
                    .font(theme.font.reviewBody).foregroundStyle(theme.reviewSecondary)
                TextEditor(text: $note).font(theme.font.reviewBody)
                    .scrollContentBackground(.hidden)
                    .padding(theme.metric.gapS)
                    .background(theme.color.card, in: RoundedRectangle(cornerRadius: theme.metric.radiusCard))
                    .accessibilityIdentifier("review-note-editor")
                TextField("现在的完整情况，例如现在不喜欢蓝莓了", text: $change.fact, axis: .vertical)
                    .lineLimit(1...3).accessibilityIdentifier("review-change-fact")
                TextField("大概什么时候变的？不确定可写时间不详", text: $change.when)
                    .accessibilityIdentifier("review-change-when")
                Text(card.status == "applied" ? "保存现在的情况后，旧状态保留为历史。" : "填好后完成，回到卡片下划更新。旧状态保留为历史。")
                    .font(theme.font.reviewCaption).foregroundStyle(theme.reviewSecondary)
                if let error = store.error { Text(error).font(theme.font.reviewCaption) }
                if card.status == "applied" {
                    Button("保存现在的情况") {
                        if store.act(.changed, on: card, note: note) { dismiss(); Task { await store.sync() } }
                    }.accessibilityIdentifier("review-change-save")
                }
                Button(card.status == "applied" ? "保留草稿" : "只保存备注", action: saveNote)
                    .frame(maxWidth: .infinity, minHeight: theme.metric.touchTarget)
                    .accessibilityIdentifier("review-save-note")
                Button("保存说明，先放着") {
                    if store.act(.defer, on: card, note: note) { dismiss(); Task { await store.sync() } }
                }.frame(maxWidth: .infinity, minHeight: theme.metric.touchTarget)
                    .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
                    .accessibilityIdentifier("review-defer")
                    .disabled(card.status == "applied")
            }
            .padding(theme.metric.pagePadding)
            .foregroundStyle(theme.color.textPrimary)
            .background(theme.color.bg)
            .navigationTitle("备注")
            .toolbar { Button("完成", action: saveNote) }
            .onAppear { note = store.draft(for: card); change = store.changeDraft(for: card) }
            .onChange(of: change.fact) { _, _ in store.saveChangeDraft(change, for: card) }
            .onChange(of: change.when) { _, _ in store.saveChangeDraft(change, for: card) }
            .onChange(of: note) { _, value in store.saveDraft(value, for: card) }
        }.tint(theme.effectiveAccent)
    }

    private func saveNote() {
        if card.status == "applied" { dismiss(); return }
        if store.act(.note, on: card, note: note) {
            dismiss()
            Task { await store.sync() }
        }
    }
}

private struct ReviewOriginalView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    let card: ReviewCard
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metric.gapL) {
                    Text(card.fact).font(theme.font.reviewFact)
                    Text("逐字引证").font(theme.font.reviewCaption)
                    Text(card.quote).font(theme.font.reviewBody)
                    Divider()
                    ForEach(card.sources) { source in
                        Text("\(source.label) · \(source.occurred_at ?? card.observed_at) · \(source.role == "user" ? "你的原话" : "助手原话，仅供核对")")
                            .font(theme.font.reviewCaption).foregroundStyle(theme.reviewSecondary)
                        Text(source.content_raw).font(theme.font.reviewBody)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .textSelection(.enabled)
                .padding(theme.metric.pagePadding)
            }
            .foregroundStyle(theme.color.textPrimary)
            .background(theme.color.bg)
            .navigationTitle("完整原文")
            .toolbar { Button("完成") { dismiss() } }
        }
    }
}
