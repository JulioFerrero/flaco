import ImageIO
import UIKit

/// Album covers on disk: a 1000 px copy for the lock screen, a 240 px thumbnail for lists, and the palette the
/// interface takes its colors from.
enum Covers {
    static let directory: URL = {
        let url = Library.support.appendingPathComponent("Covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static let thumbs = NSCache<NSString, UIImage>()
    private static let loader = DispatchQueue(label: "flaco.covers", qos: .userInitiated, attributes: .concurrent)

    static func thumbURL(_ id: String) -> URL { directory.appendingPathComponent(id + "-t.jpg") }
    static func fullURL(_ id: String) -> URL { directory.appendingPathComponent(id + ".jpg") }
    static func exists(_ id: String) -> Bool { FileManager.default.fileExists(atPath: thumbURL(id).path) }

    /// Saves a cover from its image data and returns its palette.
    static func store(_ data: Data, id: String) -> Theme? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let full = downsample(source, to: 1000),
              let thumb = downsample(source, to: 240) else { return nil }
        try? UIImage(cgImage: full).jpegData(compressionQuality: 0.88)?.write(to: fullURL(id), options: .atomic)
        try? UIImage(cgImage: thumb).jpegData(compressionQuality: 0.85)?.write(to: thumbURL(id), options: .atomic)
        thumbs.removeObject(forKey: id as NSString)
        return Theme.palette(from: thumb)
    }

    static func cachedThumb(_ id: String) -> UIImage? {
        thumbs.object(forKey: id as NSString)
    }

    static func loadThumb(_ id: String, completion: @escaping (UIImage?) -> Void) {
        loader.async {
            let image = UIImage(contentsOfFile: thumbURL(id).path)?.preparingForDisplay()
            if let image { thumbs.setObject(image, forKey: id as NSString) }
            DispatchQueue.main.async { completion(image) }
        }
    }

    static func full(_ id: String) -> UIImage? {
        UIImage(contentsOfFile: fullURL(id).path)
    }

    private static func downsample(_ source: CGImageSource, to pixels: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// A cover that loads its thumbnail off the main thread and ignores a load that lands after reuse.
final class CoverView: UIImageView {
    private(set) var coverID: String?

    init(radius: CGFloat) {
        super.init(frame: .zero)
        contentMode = .scaleAspectFill
        clipsToBounds = true
        layer.cornerRadius = radius
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ id: String?) {
        guard id != coverID else { return }
        coverID = id
        image = nil
        guard let id else { return }
        if let cached = Covers.cachedThumb(id) {
            image = cached
            return
        }
        Covers.loadThumb(id) { [weak self] image in
            guard let self, self.coverID == id else { return }
            self.image = image
        }
    }
}
