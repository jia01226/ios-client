import SwiftUI
import PhotosUI
import UIKit

struct ChatWallpaperSettings: View {
    @ObservedObject var store: ChatWallpaperStore
    @EnvironmentObject private var theme: Theme
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var cropDraft: WallpaperDraft?
    @State private var loading = false
    @State private var error: String?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapM) {
            Text("聊天背景").font(theme.font.body)
            Picker("聊天背景", selection: $store.background) {
                Text("纯色").tag(ChatWallpaperStore.Background.atmosphere)
                if store.image != nil { Text("照片").tag(ChatWallpaperStore.Background.photo) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("chat-background-kind")
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label(loading ? "正在读取照片…" : "从相册选一张照片", systemImage: "photo")
                    .frame(minHeight: theme.metric.touchTarget)
            }
            .accessibilityIdentifier("chat-background-photo")
            .disabled(loading)
            if let source = store.sourceImage {
                Button("调整照片范围") { cropDraft = WallpaperDraft(image: source) }
                    .accessibilityIdentifier("chat-background-crop")
            }
            Toggle("锁屏玻璃", isOn: $theme.lockscreenGlass)
                .accessibilityIdentifier("chat-lockscreen-glass")
            if store.background == .photo {
                slider("背景模糊", value: $store.blur, range: theme.wallpaper.blurRange,
                       label: "\(Int(store.blur.rounded()))", identifier: "chat-background-blur")
                slider("背景压暗", value: $store.dim, range: theme.wallpaper.dimRange,
                       label: "\(Int((store.dim * 100).rounded()))%", identifier: "chat-background-dim")
            }
            if let error { Text(error).font(theme.font.caption).foregroundStyle(theme.color.textSecondary) }
        }
        .font(theme.font.body)
        .foregroundStyle(theme.color.textPrimary)
        .onChange(of: store.background) { old, new in
            if old != .photo && new == .photo { theme.lockscreenGlass = true }
        }
        .onChange(of: selectedPhoto) { _, item in
            loadTask?.cancel()
            guard let item else { return }
            loading = true
            error = nil
            loadTask = Task {
                defer { loading = false; selectedPhoto = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw ChatWallpaperStore.WallpaperError.invalidImage
                    }
                    let image = await Task.detached(priority: .userInitiated) { ChatWallpaperStore.decode(data) }.value
                    try Task.checkCancellation()
                    guard let image else { throw ChatWallpaperStore.WallpaperError.invalidImage }
                    cropDraft = WallpaperDraft(image: image)
                } catch is CancellationError { } catch {
                    self.error = "照片没有读取成功，请检查网络后重新选择。"
                }
            }
        }
        .onDisappear { loadTask?.cancel() }
        .fullScreenCover(item: $cropDraft) { draft in
            WallpaperCropEditor(image: draft.image) { cropped in
                do {
                    let wasPhoto = store.background == .photo
                    try store.save(source: draft.image, cropped: cropped)
                    if !wasPhoto { theme.lockscreenGlass = true }
                    cropDraft = nil
                } catch { self.error = error.localizedDescription; cropDraft = nil }
            } onCancel: { cropDraft = nil }
            .environmentObject(theme)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: theme.metric.gapS) {
            HStack { Text(title); Spacer(); Text(label).font(theme.font.caption) }
            Slider(value: value, in: range)
                .accessibilityLabel(title).accessibilityIdentifier(identifier)
        }
    }
}

private struct WallpaperDraft: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct WallpaperCropEditor: View {
    @EnvironmentObject private var theme: Theme
    let image: UIImage
    let onSave: (UIImage) -> Void
    let onCancel: () -> Void
    @State private var cropView: WallpaperCropScrollView?

    var body: some View {
        GeometryReader { geometry in
            let aspect = UIScreen.main.bounds.width / UIScreen.main.bounds.height
            let width = min(geometry.size.width - theme.wallpaper.editorPadding * 2,
                            max(1, geometry.size.height - theme.metric.touchTarget * 3) * aspect)
            VStack(spacing: theme.wallpaper.editorGap) {
                Text("拖动、双指缩放，选取聊天背景")
                    .font(theme.font.body).multilineTextAlignment(.center)
                WallpaperCropSurface(image: image, maximumZoom: theme.wallpaper.editorZoom) { cropView = $0 }
                    .frame(width: width, height: width / aspect)
                    .clipShape(RoundedRectangle(cornerRadius: theme.wallpaper.editorRadius))
                    .accessibilityIdentifier("chat-wallpaper-crop-preview")
                HStack {
                    Button("取消", action: onCancel)
                    Spacer()
                    Button("使用照片") {
                        guard let cropped = cropView?.croppedImage() else { return }
                        onSave(cropped)
                    }.accessibilityIdentifier("chat-wallpaper-save")
                }
                .frame(minHeight: theme.metric.touchTarget)
            }
            .padding(theme.wallpaper.editorPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.color.bg.ignoresSafeArea())
        .foregroundStyle(theme.color.textPrimary)
    }
}

private struct WallpaperCropSurface: UIViewRepresentable {
    let image: UIImage
    let maximumZoom: CGFloat
    let onReady: (WallpaperCropScrollView) -> Void
    func makeUIView(context: Context) -> WallpaperCropScrollView {
        let view = WallpaperCropScrollView(image: image, zoomLimit: maximumZoom)
        DispatchQueue.main.async { onReady(view) }
        return view
    }
    func updateUIView(_ uiView: WallpaperCropScrollView, context: Context) { }
}

final class WallpaperCropScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView: UIImageView
    private let zoomLimit: CGFloat
    private var previousSize: CGSize = .zero

    init(image: UIImage, zoomLimit: CGFloat) {
        imageView = UIImageView(image: image)
        self.zoomLimit = zoomLimit
        super.init(frame: .zero)
        delegate = self
        addSubview(imageView)
        imageView.frame = CGRect(origin: .zero, size: image.size)
        contentSize = image.size
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bounces = false
        bouncesZoom = false
        contentInsetAdjustmentBehavior = .never
        isAccessibilityElement = true
        accessibilityLabel = "照片取景范围"
        accessibilityHint = "拖动照片，双指缩放"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != previousSize, bounds.width > 0, bounds.height > 0,
              let image = imageView.image else { return }
        previousSize = bounds.size
        let minimum = max(bounds.width / image.size.width, bounds.height / image.size.height)
        minimumZoomScale = minimum
        maximumZoomScale = minimum * zoomLimit
        zoomScale = minimum
        contentOffset = CGPoint(x: max(0, (contentSize.width - bounds.width) / 2),
                                y: max(0, (contentSize.height - bounds.height) / 2))
    }

    func croppedImage() -> UIImage? {
        guard let image = imageView.image, bounds.width > 0, bounds.height > 0 else { return nil }
        let visible = CGRect(x: contentOffset.x / zoomScale, y: contentOffset.y / zoomScale,
                             width: bounds.width / zoomScale, height: bounds.height / zoomScale)
        // Draw using image coordinates; this also normalizes camera/EXIF orientation.
        let outputWidth: CGFloat = 1440
        let output = CGSize(width: outputWidth, height: outputWidth * bounds.height / bounds.width)
        let factor = output.width / visible.width
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: output, format: format).image { _ in
            image.draw(in: CGRect(x: -visible.minX * factor, y: -visible.minY * factor,
                                  width: image.size.width * factor, height: image.size.height * factor))
        }
    }
}
