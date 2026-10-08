import SwiftUI
import UIKit

/// The same production back is used for the deck, shuffle, dealt cards and picker.
struct TarotBackArtwork: View {
    let back: TarotBack
    let tint: Color
    var body: some View {
        if back.id == "moonlight" {
            Image("MoonTarotBack").resizable().scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.35), lineWidth: 1))
                .overlay(Image(systemName: back.icon).font(.system(size: 22, weight: .ultraLight)).foregroundStyle(tint.opacity(0.6)))
        }
    }
}

/// Inspect the original result; opening, paging and zooming never draw again or change orientation.
struct TarotCardInspector: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss
    let cards: [TarotCard]
    let api: APIClient
    @State private var index: Int
    @State private var image: UIImage?
    @State private var failure = false
    @State private var retry = 0

    init(cards: [TarotCard], initialCard: TarotCard, api: APIClient) {
        self.cards = cards.isEmpty ? [initialCard] : cards
        self.api = api
        _index = State(initialValue: cards.firstIndex { $0.id == initialCard.id } ?? 0)
    }
    private var card: TarotCard { cards[index] }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(card.cn + " · " + (card.reversed ? "逆位" : "正位"))
                        .font(Moonlight.serif(22)).accessibilityIdentifier("tarot-inspector-title")
                    Text(card.position).font(Moonlight.serif(13)).foregroundStyle(theme.pageColor.textSecondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .light)).frame(width: 44, height: 44)
                }.accessibilityLabel("收起牌面").accessibilityIdentifier("tarot-inspector-close")
            }.padding(.horizontal, 22)
            Group {
                if let image {
                    TarotZoomImage(image: image).accessibilityIdentifier("tarot-card-zoom")
                } else if failure {
                    Button("牌面未载入，点这里重试") { retry += 1 }
                        .accessibilityIdentifier("tarot-image-retry")
                } else { ProgressView("正在拿出这张牌") }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 26) {
                Button { index -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .disabled(index == 0).accessibilityLabel("上一张牌").accessibilityIdentifier("tarot-previous")
                Text("\(index + 1) / \(cards.count)").font(Moonlight.serif(15))
                Button { index += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .disabled(index == cards.count - 1).accessibilityLabel("下一张牌").accessibilityIdentifier("tarot-next")
            }
            Text("双指放大 · 双击还原").font(Moonlight.serif(13))
                .foregroundStyle(theme.pageColor.textSecondary).padding(.bottom, 12)
        }.padding(.top, 8).foregroundStyle(theme.pageColor.textPrimary).buttonStyle(.plain)
            .background(theme.pageBackground.ignoresSafeArea())
            .task(id: "\(index)-\(retry)") {
                image = nil; failure = false
                do {
                    let result = try await api.fetchAttachmentData(at: card.image)
                    try Task.checkCancellation()
                    guard let decoded = UIImage(data: result) else { failure = true; return }
                    if card.reversed, let cg = decoded.cgImage {
                        image = UIImage(cgImage: cg, scale: decoded.scale, orientation: .down)
                    } else { image = decoded }
                } catch is CancellationError {
                } catch let error as URLError where error.code == .cancelled {
                } catch { failure = true }
            }
    }
}

/// UIKit provides pinch, pan and edge clamping at the image's actual resolution.
private struct TarotZoomImage: UIViewRepresentable {
    let image: UIImage
    func makeUIView(context: Context) -> TarotZoomScrollView { TarotZoomScrollView() }
    func updateUIView(_ view: TarotZoomScrollView, context: Context) { view.display(image) }
}

private final class TarotZoomScrollView: UIScrollView, UIScrollViewDelegate {
    private let picture = UIImageView()
    private var previousSize = CGSize.zero
    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self; minimumZoomScale = 1; maximumZoomScale = 4
        showsVerticalScrollIndicator = false; showsHorizontalScrollIndicator = false
        bouncesZoom = true; contentInsetAdjustmentBehavior = .never
        picture.contentMode = .scaleAspectFit
        addSubview(picture)
        let twice = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        twice.numberOfTapsRequired = 2; addGestureRecognizer(twice)
        accessibilityIdentifier = "tarot-card-zoom"; accessibilityLabel = "牌面，可双指放大"
        accessibilityValue = "1.0"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func display(_ image: UIImage) {
        guard picture.image !== image else { return }
        setZoomScale(1, animated: false); picture.image = image; previousSize = .zero; setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != previousSize else { return }
        previousSize = bounds.size
        setZoomScale(1, animated: false)
        picture.frame = CGRect(origin: .zero, size: bounds.size)
        contentSize = bounds.size
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { picture }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        accessibilityValue = String(format: "%.1f", zoomScale)
    }
    @objc private func doubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1.05 { setZoomScale(1, animated: true) }
        else {
            let point = gesture.location(in: picture)
            let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: true)
        }
    }
}
