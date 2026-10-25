import UIKit

/// Every audio file under Documents, indexed by tags and grouped into albums. Files arrive through Finder,
/// the Files app or "Open in"; the index is kept on disk so launch shows the library before the scan ends.
final class Library {
    static let shared = Library()
    static let didChange = Notification.Name("FlacoLibraryDidChange")

    static let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let support: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Flaco", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let audioExtensions: Set<String> = ["flac", "m4a", "alac", "mp3", "wav", "aif", "aiff", "aac", "caf"]
    private static let coverNames: Set<String> = ["cover", "folder", "front", "albumart", "album"]

    /// Album by album, in display order.
    private(set) var tracks: [Track] = []
    private(set) var albums: [Album] = []
    private(set) var folders: [Folder] = []
    private(set) var isScanning = false

    private var palettes: [String: Theme] = [:]
    private var byPath: [String: Track] = [:]
    private var albumByKey: [String: Album] = [:]

    private let queue = DispatchQueue(label: "flaco.library", qos: .utility)
    private var watcher: DispatchSourceFileSystemObject?
    private var scanToken = 0
    // Library queue only.
    private var triedCovers: Set<String> = []

    private var indexURL: URL { Library.support.appendingPathComponent("library.json") }
    private var palettesURL: URL { Library.support.appendingPathComponent("palettes.json") }

    func load() {
        if let data = try? Data(contentsOf: palettesURL),
           let saved = try? JSONDecoder().decode([String: Theme].self, from: data) {
            palettes = saved
        }
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? JSONDecoder().decode([Track].self, from: data) {
            publish(saved)
        }
        watch()
    }

    func scan() {
        queue.async { self.performScan() }
    }

    func track(at path: String) -> Track? { byPath[path] }
    func album(for track: Track) -> Album? { albumByKey[track.albumKey] }

    /// The colors of a track's cover; neutral when it has none.
    func theme(for track: Track?) -> Theme {
        guard let track else { return .neutral }
        return palettes[track.coverID] ?? .neutral
    }

    /// Copies files or folders picked elsewhere into Documents/Imported.
    func importFiles(_ urls: [URL]) {
        queue.async {
            let target = Library.documents.appendingPathComponent("Imported", isDirectory: true)
            let fm = FileManager.default
            try? fm.createDirectory(at: target, withIntermediateDirectories: true)
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let inbox = url.path.contains("/Inbox/")
                if url.path.hasPrefix(Library.documents.path), !inbox { continue }
                let destination = Self.free(target.appendingPathComponent(url.lastPathComponent))
                if inbox {
                    try? fm.moveItem(at: url, to: destination)
                } else {
                    try? fm.copyItem(at: url, to: destination)
                }
            }
            self.performScan()
        }
    }

    // MARK: Scanning

    private func performScan() {
        DispatchQueue.main.async { self.isScanning = true }
        moveInbox()
        let known = DispatchQueue.main.sync { byPath }
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        var found: [Track] = []
        var covers: [String: Data] = [:]
        var stillCopying = false

        if let walker = fm.enumerator(at: Library.documents, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
            for case let url as URL in walker {
                if url.lastPathComponent == "Inbox" {
                    walker.skipDescendants()
                    continue
                }
                guard Library.audioExtensions.contains(url.pathExtension.lowercased()),
                      let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                let size = Int64(values.fileSize ?? 0)
                let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
                let path = Self.relativePath(url)
                if let old = known[path], old.size == size, old.modified == modified {
                    found.append(old)
                    continue
                }
                // Finder may still be writing it; the next scan picks it up.
                if Date().timeIntervalSince1970 - modified < 3 {
                    stillCopying = true
                    continue
                }
                guard let read = TagReader.read(url, path: path, size: size, modified: modified) else { continue }
                found.append(read.track)
                if covers[read.track.albumKey] == nil, let cover = read.cover {
                    covers[read.track.albumKey] = cover
                }
            }
        }

        var palettes = DispatchQueue.main.sync { self.palettes }
        var firstOfAlbum: [String: Track] = [:]
        for track in found where firstOfAlbum[track.albumKey] == nil {
            firstOfAlbum[track.albumKey] = track
        }
        for (key, first) in firstOfAlbum {
            let id = Library.hash(key)
            if Covers.exists(id) {
                if palettes[id] == nil { palettes[id] = Covers.full(id)?.cgImage.map(Theme.palette) }
                continue
            }
            guard !triedCovers.contains(id) || covers[key] != nil else { continue }
            triedCovers.insert(id)
            let data = covers[key] ?? TagReader.cover(of: first.url) ?? folderImage(near: first.url)
            if let data, let palette = Covers.store(data, id: id) {
                palettes[id] = palette
            }
        }

        if let data = try? JSONEncoder().encode(found) { try? data.write(to: indexURL, options: .atomic) }
        if let data = try? JSONEncoder().encode(palettes) { try? data.write(to: palettesURL, options: .atomic) }

        DispatchQueue.main.async {
            self.palettes = palettes
            self.isScanning = false
            self.publish(found)
        }
        if stillCopying { scheduleScan(after: 4) }
    }

    private func publish(_ list: [Track]) {
        var grouped: [String: [Track]] = [:]
        for track in list { grouped[track.albumKey, default: []].append(track) }

        var albums: [Album] = grouped.map { key, tracks in
            let sorted = tracks.sorted { ($0.disc, $0.number, $0.path) < ($1.disc, $1.number, $1.path) }
            let first = sorted[0]
            return Album(
                key: key, title: first.album, artist: first.albumArtist,
                year: sorted.first { !$0.year.isEmpty }?.year ?? "",
                tracks: sorted, added: sorted.map(\.modified).max() ?? 0)
        }
        albums.sort {
            let a = Self.sortName($0.artist), b = Self.sortName($1.artist)
            if a != b { return a < b }
            if $0.year != $1.year { return $0.year < $1.year }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }

        var byFolder: [String: [Track]] = [:]
        for track in list {
            let parts = track.path.split(separator: "/")
            byFolder[parts.count > 1 ? String(parts[0]) : "Loose files", default: []].append(track)
        }

        self.albums = albums
        tracks = albums.flatMap(\.tracks)
        folders = byFolder
            .map { Folder(name: $0.key, tracks: $0.value.sorted { $0.path < $1.path }) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        byPath = Dictionary(tracks.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        albumByKey = Dictionary(albums.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// "The Quiet Field" files under Q.
    static func sortName(_ name: String) -> String {
        let lower = name.lowercased()
        return lower.hasPrefix("the ") ? String(lower.dropFirst(4)) : lower
    }

    private func moveInbox() {
        let fm = FileManager.default
        let inbox = Library.documents.appendingPathComponent("Inbox", isDirectory: true)
        guard let items = try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil), !items.isEmpty else { return }
        let target = Library.documents.appendingPathComponent("Imported", isDirectory: true)
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        for item in items {
            try? fm.moveItem(at: item, to: Self.free(target.appendingPathComponent(item.lastPathComponent)))
        }
    }

    private func folderImage(near url: URL) -> Data? {
        let folder = url.deletingLastPathComponent()
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return nil }
        let images = items.filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
        let named = images.first { Self.coverNames.contains($0.deletingPathExtension().lastPathComponent.lowercased()) }
        return (named ?? images.first).flatMap { try? Data(contentsOf: $0) }
    }

    // MARK: Watching Documents

    private func watch() {
        let descriptor = open(Library.documents.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: queue)
        source.setEventHandler { [weak self] in self?.scheduleScan(after: 2) }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    /// Coalesces a burst of changes into one scan.
    private func scheduleScan(after delay: TimeInterval) {
        queue.async {
            self.scanToken += 1
            let token = self.scanToken
            self.queue.asyncAfter(deadline: .now() + delay) {
                if token == self.scanToken { self.performScan() }
            }
        }
    }

    // MARK: Helpers

    static func relativePath(_ url: URL) -> String {
        let base = documents.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : url.lastPathComponent
    }

    /// The URL itself, or "name 2.ext" when it's taken.
    private static func free(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let candidate = url.deletingLastPathComponent().appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    /// FNV-1a, for stable file names from album keys.
    static func hash(_ text: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x100_0000_01b3
        }
        return String(h, radix: 16)
    }
}
