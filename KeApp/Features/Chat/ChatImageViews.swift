import SwiftUI
import UIKit
import ImageIO

// 136 她：「现在发图片很大块，我发一张图片过去小一点，不是压缩图片」。
// 聊天里的图改成像 QQ、微信那样：不套气泡色块，单独一块圆角小图，按原比例不裁；
// 高度固定（加载出来时聊天不往回跳），宽度跟着比例走。几张图排成小方格；塔罗牌一横排小牌，牌名写在下面。
// 点开看原图：双指缩放、双击放大、左右翻到同一条里的下一张。原图不动，发给柯的还是原图；聊天里只按小尺寸解码。

enum ChatImageMetrics {
    /// 一张图在聊天里的高度：加载前后都一样
    static let height: CGFloat = 168
    static let minWidth: CGFloat = 96
    static let maxWidth: CGFloat = 224
    /// 好几张图时的小方格
    static let tile: CGFloat = 92
    /// 塔罗小牌的宽，高按牌的比例
    static let tarotWidth: CGFloat = 72
    static let tarotAspect: CGFloat = 0.58
    static let corner: CGFloat = 12
    static let gap: CGFloat = 6

    static func width(for aspect: CGFloat?) -> CGFloat {
        guard let aspect, aspect.isFinite, aspect > 0 else { return height * 0.8 }
        return min(maxWidth, max(minWidth, height * aspect))
    }
}

extension ChatAttachment {
    /// 服务器挂上的塔罗牌面（她「交给柯」时）或柯抽的牌
    var isTarotCard: Bool {
        isImage && (url.contains("/tarot/cards/") || name.hasSuffix("·正位") || name.hasSuffix("·逆位"))
    }
    var isTarotReversed: Bool { name.hasSuffix("（逆位）") || name.hasSuffix("·逆位") }
    /// 「过去(根源/背景)·圣杯二（逆位）」→「圣杯二」；「月亮·正位」→「月亮」
    var tarotCardName: String {
        var parts = name.components(separatedBy: "·")
        if let last = parts.last, last == "正位" || last == "逆位" { parts.removeLast() }
        let card = (parts.last ?? name).replacingOccurrences(of: "（逆位）", with: "")
        return card.trimmingCharacters(in: .whitespaces)
    }
    /// 「过去(根源/背景)·圣杯二（逆位）」→「过去」；没写牌位就空
    var tarotPosition: String {
        guard url.contains("/tarot/cards/"), name.contains("·") else { return "" }
        let head = name.components(separatedBy: "·").first ?? ""
        return head.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? head
    }
}

/// 聊天正文里给服务器看的「[塔罗#123]」不给她看（发出去的原文一个字不改）
enum ChatTarotTag {
    static func strip(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s*\[塔罗#\d+\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 记住每张图的宽高比和解好的小图：同一张图滑回来不再下载、不再解码、不跳
@MainActor
final class ChatImageCache {
    static let shared = ChatImageCache()
    private let thumbs = NSCache<NSString, UIImage>()
    private var aspects: [String: CGFloat]
    private let key = "chat.image.aspects"

    private init() {
        thumbs.countLimit = 200
        aspects = (UserDefaults.standard.dictionary(forKey: key) as? [String: Double])?.mapValues { CGFloat($0) } ?? [:]
    }

    func aspect(_ url: String) -> CGFloat? { aspects[url] }
    func thumb(_ url: String, _ size: Int) -> UIImage? { thumbs.object(forKey: "\(size)|\(url)" as NSString) }

    func store(_ url: String, _ size: Int, thumb: UIImage, aspect: CGFloat) {
        thumbs.setObject(thumb, forKey: "\(size)|\(url)" as NSString)
        guard aspects[url] == nil else { return }
        aspects[url] = aspect
        if aspects.count > 800 { aspects = Dictionary(uniqueKeysWithValues: aspects.suffix(500).map { ($0.key, $0.value) }) }
        UserDefaults.standard.set(aspects.mapValues { Double($0) }, forKey: key)
    }

    /// 取一张小图：先看记着的，没有再下载、在后台按小尺寸解码
    func load(_ url: String, maxPixel: Int) async throws -> (UIImage, CGFloat) {
        if let cached = thumb(url, maxPixel) { return (cached, aspect(url) ?? cached.size.width / max(1, cached.size.height)) }
        let data = try await APIClient.shared.fetchAttachmentData(at: url)
        guard let (image, ratio) = await Task.detached(priority: .userInitiated, operation: {
            Self.downsample(data, maxPixel: CGFloat(maxPixel))
        }).value else { throw APIError.serverMessage("图片没有解开") }
        store(url, maxPixel, thumb: image, aspect: ratio)
        return (image, ratio)
    }

    /// 按小尺寸解码（不把原图整张解出来），返回小图和原图的宽高比
    nonisolated static func downsample(_ data: Data, maxPixel: CGFloat) -> (UIImage, CGFloat)? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        var aspect: CGFloat = 1
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? CGFloat, let h = props[kCGImagePropertyPixelHeight] as? CGFloat, w > 0, h > 0 {
            let orientation = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
            aspect = (5...8).contains(orientation) ? h / w : w / h
        }
        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else { return nil }
        return (UIImage(cgImage: cg), aspect)
    }
}

/// 一张小图：没出来时是一块淡底和转圈，出来了就是图；解不开写一句
private struct ChatImageTile: View {
    @EnvironmentObject private var theme: Theme
    let attachment: ChatAttachment
    let width: CGFloat
    let height: CGFloat
    var fit = false
    var onLoaded: ((CGFloat) -> Void)?
    /// 记着是哪张图的：格子被别的消息复用时不会先露出上一张
    @State private var loaded: (url: String, image: UIImage)?
    @State private var failedURL: String?
    private var didFail: Bool { failedURL == attachment.url }

    var body: some View {
        ZStack {
            if let shown = loaded?.url == attachment.url ? loaded?.image : ChatImageCache.shared.thumb(attachment.url, Self.pixels) {
                Image(uiImage: shown).resizable().aspectRatio(contentMode: fit ? .fit : .fill)
            } else if didFail {
                Color.primary.opacity(0.06)
                Image(systemName: "photo.badge.exclamationmark").font(theme.font.attachmentIcon)
                    .foregroundStyle(theme.chatTextSecondary)
                    .accessibilityLabel("图片没有加载出来")
            } else {
                Color.primary.opacity(0.06)
                ProgressView().controlSize(.small).tint(theme.chatAccent)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: ChatImageMetrics.corner, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: ChatImageMetrics.corner, style: .continuous))
        .task(id: attachment.url) {
            let url = attachment.url
            if loaded?.url == url { return }
            do {
                let (image, ratio) = try await ChatImageCache.shared.load(url, maxPixel: Self.pixels)
                loaded = (url, image)
                onLoaded?(ratio)
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                failedURL = url
            }
        }
    }

    /// 聊天里最大的那种图（224 点宽）在 3 倍屏上的像素
    static let pixels = Int(ChatImageMetrics.maxWidth * 3)
}

/// 一条消息里的图：一张按比例；几张排小方格；塔罗牌一横排小牌（凯尔特十张时一行五张）
struct ChatImageGroup: View {
    @EnvironmentObject private var theme: Theme
    let attachments: [ChatAttachment]
    let trailing: Bool
    var onTap: (Int) -> Void
    @State private var loadedAspect: (url: String, value: CGFloat)?

    private var isTarot: Bool { attachments.allSatisfy(\.isTarotCard) }

    var body: some View {
        Group {
            if isTarot {
                tarotRows
            } else if attachments.count == 1 {
                let item = attachments[0]
                Button { onTap(0) } label: {
                    let aspect = loadedAspect?.url == item.url ? loadedAspect?.value : ChatImageCache.shared.aspect(item.url)
                ChatImageTile(attachment: item,
                              width: ChatImageMetrics.width(for: aspect),
                              height: ChatImageMetrics.height,
                              onLoaded: { loadedAspect = (item.url, $0) })
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开图片 \(item.name.isEmpty ? "预览" : item.name)")
            } else {
                let columns = Array(repeating: GridItem(.fixed(ChatImageMetrics.tile), spacing: ChatImageMetrics.gap), count: min(3, attachments.count))
                LazyVGrid(columns: columns, alignment: trailing ? .trailing : .leading, spacing: ChatImageMetrics.gap) {
                    ForEach(Array(attachments.enumerated()), id: \.offset) { index, item in
                        Button { onTap(index) } label: {
                            ChatImageTile(attachment: item, width: ChatImageMetrics.tile, height: ChatImageMetrics.tile)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("打开第 \(index + 1) 张图片")
                    }
                }
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }

    private var tarotRows: some View {
        let perRow = attachments.count > 5 ? 5 : attachments.count
        let rows = stride(from: 0, to: attachments.count, by: max(1, perRow)).map { Array($0..<min($0 + perRow, attachments.count)) }
        return VStack(alignment: trailing ? .trailing : .leading, spacing: 10) {
            ForEach(rows, id: \.first) { row in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(row, id: \.self) { index in tarotCard(index) }
                }
            }
        }
    }

    private func tarotCard(_ index: Int) -> some View {
        let item = attachments[index]
        let w = ChatImageMetrics.tarotWidth
        return Button { onTap(index) } label: {
            VStack(spacing: 4) {
                ChatImageTile(attachment: item, width: w, height: w / ChatImageMetrics.tarotAspect, fit: true)
                    .rotationEffect(.degrees(item.isTarotReversed ? 180 : 0))
                Text(item.tarotCardName + (item.isTarotReversed ? " · 逆" : ""))
                    .font(theme.font.caption)
                    .foregroundStyle(theme.chatTextSecondary)
                    .modifier(ChatLegibility())
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .frame(width: w + 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开塔罗牌 \(item.tarotPosition) \(item.tarotCardName)\(item.isTarotReversed ? " 逆位" : " 正位")")
    }
}

/// 点开的那一组图：从哪一张开始
struct ChatImageGallery: Identifiable {
    let id = UUID()
    let items: [ChatAttachment]
    let start: Int
}

/// 聊天格子是 UIKit 里托着的，环境值传不进去；点图时把这一组交到这里，聊天页照着弹出大图
@MainActor
final class ChatImageRouter: ObservableObject {
    static let shared = ChatImageRouter()
    @Published var gallery: ChatImageGallery?
    func open(_ items: [ChatAttachment], at index: Int) {
        guard !items.isEmpty else { return }
        gallery = ChatImageGallery(items: items, start: index)
    }
}

/// 看大图：原图，双指放大、双击放大或还原、左右翻；塔罗逆位的牌倒着放，上面写牌位和牌名
struct AttachmentImageViewer: View {
    let gallery: ChatImageGallery
    let dismiss: () -> Void
    @State private var index: Int

    init(gallery: ChatImageGallery, dismiss: @escaping () -> Void) {
        self.gallery = gallery
        self.dismiss = dismiss
        _index = State(initialValue: min(max(0, gallery.start), max(0, gallery.items.count - 1)))
    }
    /// 以前只看一张的地方（输入框上还没发的附件）
    init(attachment: ChatAttachment, dismiss: @escaping () -> Void) {
        self.init(gallery: ChatImageGallery(items: [attachment], start: 0), dismiss: dismiss)
    }

    private var current: ChatAttachment? { gallery.items.indices.contains(index) ? gallery.items[index] : nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(gallery.items.enumerated()), id: \.offset) { offset, item in
                    ChatZoomPage(attachment: item).tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let current, current.isTarotCard {
                            Text(current.tarotCardName + (current.isTarotReversed ? " · 逆位" : " · 正位"))
                                .font(.custom("NotoSerifSC-Regular", size: 17, relativeTo: .headline))
                            if !current.tarotPosition.isEmpty {
                                Text(current.tarotPosition).font(.system(size: 13)).opacity(0.7)
                            }
                        }
                        if gallery.items.count > 1 {
                            Text("\(index + 1) / \(gallery.items.count)").font(.system(size: 13).monospacedDigit()).opacity(0.7)
                        }
                    }
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.white.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭图片")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.top, 8)
                Spacer()
                Text("双指放大 · 双击放大或还原\(gallery.items.count > 1 ? " · 左右划看下一张" : "")")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                    .padding(.bottom, 14)
            }
        }
        .statusBarHidden()
    }
}

/// 一页大图：按屏幕大小解原图（够放大看清，不把四千像素整张解出来）
private struct ChatZoomPage: View {
    let attachment: ChatAttachment
    @State private var image: UIImage?
    @State private var didFail = false
    @State private var retry = 0

    var body: some View {
        Group {
            if let image {
                TarotZoomImage(image: image)
            } else if didFail {
                Button("图片没有加载出来，点这里再试") { didFail = false; retry += 1 }
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(attachment.url)-\(retry)") {
            do {
                let data = try await APIClient.shared.fetchAttachmentData(at: attachment.url)
                guard let (decoded, _) = await Task.detached(priority: .userInitiated, operation: {
                    ChatImageCache.downsample(data, maxPixel: 2800)
                }).value else { didFail = true; return }
                if attachment.isTarotReversed, let cg = decoded.cgImage {
                    image = UIImage(cgImage: cg, scale: decoded.scale, orientation: .down)
                } else {
                    image = decoded
                }
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                didFail = true
            }
        }
    }
}
