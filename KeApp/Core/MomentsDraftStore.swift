import Foundation
import Combine

/// Unsent words belong to the selected line and survive leaving the play tab.
/// Photos have separate files, referenced only by an atomically saved manifest.
@MainActor
final class MomentsDraftStore: ObservableObject {
    @Published var text: String { didSet { if text != oldValue && !updatingPost { saveMetadata() } } }
    @Published var imageData: Data? {
        didSet {
            guard imageData != oldValue, !updatingPost else { return }
            updatingPost = true
            uploadedImage = ""
            updatingPost = false
            saveImage()
        }
    }
    @Published var uploadedImage: String { didSet { if uploadedImage != oldValue && !updatingPost { saveMetadata() } } }
    @Published var textDrafts: [String: String] { didSet { if textDrafts != oldValue { saveMetadata() } } }
    @Published private(set) var persistenceError: String?

    private struct Metadata: Codable {
        var text = ""
        var uploadedImage = ""
        var textDrafts: [String: String] = [:]
        var photoFileName: String?
    }
    private let directory: URL
    private var metadataURL: URL { directory.appendingPathComponent("draft.json") }
    private var photoFileName: String?
    private var updatingPost = false
    private var metadataFailed = false
    private var imageFailed = false

    init(scope: String, rootDirectory: URL? = nil) {
        let root = rootDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MomentsDrafts", isDirectory: true)
        let key = scope.utf8.map { String(format: "%02x", $0) }.joined()
        let draftDirectory = root.appendingPathComponent(key.isEmpty ? "default" : key, isDirectory: true)
        directory = draftDirectory
        let metadataURL = draftDirectory.appendingPathComponent("draft.json")
        let metadata = (try? Data(contentsOf: metadataURL))
            .flatMap { try? JSONDecoder().decode(Metadata.self, from: $0) } ?? Metadata()
        // Unreferenced images must never resurrect a cleared or already published draft.
        let name = metadata.photoFileName.flatMap { $0 == URL(fileURLWithPath: $0).lastPathComponent ? $0 : nil }
        let photo = name.flatMap { try? Data(contentsOf: draftDirectory.appendingPathComponent($0)) }
        text = metadata.text
        imageData = photo
        photoFileName = photo == nil ? nil : name
        uploadedImage = photo == nil ? "" : metadata.uploadedImage
        textDrafts = metadata.textDrafts
    }

    /// A confirmed publication clears its draft, preserving unfinished comments.
    func clearPost() {
        let oldPhoto = photoFileName
        updatingPost = true
        text = ""; imageData = nil; uploadedImage = ""; photoFileName = nil
        updatingPost = false
        imageFailed = false
        if saveMetadata() { removePhoto(oldPhoto) }
    }

    @discardableResult private func saveMetadata() -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if text.isEmpty && uploadedImage.isEmpty && textDrafts.isEmpty && photoFileName == nil {
                if FileManager.default.fileExists(atPath: metadataURL.path) {
                    try FileManager.default.removeItem(at: metadataURL)
                }
            } else {
                let metadata = Metadata(text: text, uploadedImage: uploadedImage,
                                        textDrafts: textDrafts, photoFileName: photoFileName)
                try JSONEncoder().encode(metadata).write(to: metadataURL, options: .atomic)
            }
            metadataFailed = false
        } catch { metadataFailed = true }
        updateError()
        return !metadataFailed
    }

    private func saveImage() {
        let oldPhoto = photoFileName
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let imageData {
                let name = UUID().uuidString + ".jpg"
                try imageData.write(to: directory.appendingPathComponent(name), options: .atomic)
                photoFileName = name
            } else { photoFileName = nil }
            imageFailed = false
            // Install the new reference only after its image exists. Cleanup is safe
            // after the manifest changes, including when the app stops between steps.
            if saveMetadata() { removePhoto(oldPhoto) }
        } catch {
            imageFailed = true
            // Do not present the previous photo as the newly selected one on restart.
            photoFileName = nil
            saveMetadata()
        }
        updateError()
    }

    private func removePhoto(_ name: String?) {
        guard let name, name != photoFileName else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    private func updateError() {
        persistenceError = metadataFailed || imageFailed
            ? "草稿暂时没有存到本机，请先留在这一页。" : nil
    }
}
