import Foundation

/// Keeps the phone's copy of the server's music: downloads what's new or changed and removes what the server no
/// longer has. Only files that came from the server are ever removed; music added to the phone by hand stays.
/// Downloads run in a background session, so they carry on with Flaco closed.
final class Sync: NSObject {
    static let shared = Sync()
    static let didChange = Notification.Name("FlacoSyncDidChange")

    enum Phase: Equatable {
        case idle, checking, downloading
        case failed(String)
    }

    struct Stats: Codable {
        var tracks = 0
        var albums = 0
        var bytes: Int64 = 0
    }

    /// A file the server gave us, by server id.
    private struct Entry: Codable {
        let path: String
        let size: Int64
    }

    /// What a download task is for, carried in its description so it survives a relaunch.
    private struct Job {
        let id: String
        let size: Int64
        let path: String

        init(_ song: Server.Song) {
            id = song.id
            size = song.size
            path = song.path
        }

        init?(_ task: URLSessionTask) {
            let parts = (task.taskDescription ?? "").split(separator: "\n", maxSplits: 2).map(String.init)
            guard parts.count == 3, let size = Int64(parts[1]) else { return nil }
            id = parts[0]
            self.size = size
            path = parts[2]
        }

        var description: String { "\(id)\n\(size)\n\(path)" }
    }

    // Main thread, like the session's delegate calls.
    private(set) var phase = Phase.idle
    private(set) var server: Stats?
    private(set) var filesDone = 0
    private(set) var filesTotal = 0
    private(set) var bytesTotal: Int64 = 0
    private(set) var lastSynced: Date?
    var backgroundCompletion: (() -> Void)?

    var bytesDone: Int64 { bytesFinished + written.values.reduce(0, +) }

    private var manifest: [String: Entry] = [:]
    private var active: Set<String> = []
    private var written: [String: Int64] = [:]
    private var bytesFinished: Int64 = 0
    private var failures = 0
    private var started = Date()
    private var lastNotice = Date.distantPast
    private var scanPending = false
    private var connected = false

    private let manifestURL = Library.support.appendingPathComponent("sync.json")
    private let defaults = UserDefaults.standard

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: (Bundle.main.bundleIdentifier ?? "flaco") + ".sync")
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.httpMaximumConnectionsPerHost = 3
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    override init() {
        super.init()
        if let data = try? Data(contentsOf: manifestURL),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            manifest = saved
        }
        if let data = defaults.data(forKey: "syncServer") { server = try? JSONDecoder().decode(Stats.self, from: data) }
        lastSynced = defaults.object(forKey: "syncLast") as? Date
    }

    /// Picks up downloads left running by an earlier launch.
    func reconnect() {
        guard !connected else { return }
        connected = true
        session.getAllTasks { tasks in
            DispatchQueue.main.async {
                let jobs = tasks.filter { $0.state == .running }.compactMap(Job.init)
                guard !jobs.isEmpty, self.phase == .idle else { return }
                self.active = Set(jobs.map(\.id))
                self.filesDone = 0
                self.filesTotal = jobs.count
                self.bytesFinished = 0
                self.bytesTotal = jobs.reduce(0) { $0 + $1.size }
                self.phase = .downloading
                self.notify()
            }
        }
    }

    /// On opening Flaco, unless a check ran in the last two minutes.
    func startIfDue() {
        guard Settings.shared.autoSync else { return }
        if let lastSynced, Date().timeIntervalSince(lastSynced) < 120 { return }
        start()
    }

    func start() {
        guard Server.shared.isConfigured, phase != .checking else { return }
        reconnect()
        phase = .checking
        notify()
        Task { @MainActor in
            do {
                let listing = try await Server.shared.listing()
                let running = await session.allTasks.filter { $0.state == .running }
                plan(listing, running: Set(running.compactMap(Job.init).map(\.id)))
            } catch {
                phase = .failed(error.localizedDescription)
                notify()
            }
        }
    }

    /// Changing servers keeps the music on the phone, but stops treating it as the old server's.
    func forgetServer() {
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
        manifest = [:]
        active = []
        server = nil
        lastSynced = nil
        phase = .idle
        saveManifest()
        defaults.removeObject(forKey: "syncServer")
        defaults.removeObject(forKey: "syncLast")
        notify()
    }

    // MARK: Planning

    private func plan(_ listing: Server.Listing, running: Set<String>) {
        let songs = listing.songs
        server = Stats(tracks: songs.count, albums: Set(songs.map(\.album)).count, bytes: songs.reduce(0) { $0 + $1.size })
        if let data = try? JSONEncoder().encode(server) { defaults.set(data, forKey: "syncServer") }

        // A server that lists nothing, or is mid-scan, may be wrong about what's gone.
        var removed = 0
        if !songs.isEmpty, !listing.scanning {
            let remote = Dictionary(songs.map { ($0.id, $0.path) }, uniquingKeysWith: { a, _ in a })
            for (id, entry) in manifest where remote[id] != entry.path {
                remove(entry.path)
                manifest[id] = nil
                removed += 1
            }
        }

        var wanted: [Server.Song] = []
        for song in songs {
            if Self.size(of: Library.documents.appendingPathComponent(song.path)) == song.size {
                // Already here, from an earlier sync or copied by hand.
                manifest[song.id] = Entry(path: song.path, size: song.size)
            } else {
                wanted.append(song)
            }
        }
        saveManifest()
        if removed > 0 { scheduleScan() }

        let needed = wanted.filter { !running.contains($0.id) }.reduce(0) { $0 + $1.size }
        let free = Self.freeSpace
        if needed > 0, needed + 300_000_000 > free {
            phase = .failed("Needs \(Self.bytes(needed)), \(Self.bytes(free)) free.")
            Log.write("sync: \(wanted.count) to download (\(Self.bytes(needed))) but only \(Self.bytes(free)) free")
            notify()
            return
        }

        for song in wanted where !running.contains(song.id) {
            guard let url = Server.shared.downloadURL(song.id) else { continue }
            var request = URLRequest(url: url)
            request.allowsCellularAccess = Settings.shared.cellular
            let task = session.downloadTask(with: request)
            task.taskDescription = Job(song).description
            task.countOfBytesClientExpectsToReceive = song.size
            task.resume()
        }
        active = Set(wanted.map(\.id))
        written = [:]
        filesDone = 0
        filesTotal = wanted.count
        bytesFinished = 0
        bytesTotal = wanted.reduce(0) { $0 + $1.size }
        failures = 0
        started = Date()
        Log.write("sync: \(songs.count) on the server, \(wanted.count) to download (\(Self.bytes(bytesTotal))), \(removed) removed")
        if wanted.isEmpty {
            finish()
        } else {
            phase = .downloading
            notify()
        }
    }

    private func finish() {
        saveManifest()
        scheduleScan()
        if failures > 0 {
            phase = .failed(failures == 1 ? "1 file didn't download." : "\(failures) files didn't download.")
        } else {
            phase = .idle
            lastSynced = Date()
            defaults.set(lastSynced, forKey: "syncLast")
        }
        if filesTotal > 0 {
            let seconds = Date().timeIntervalSince(started)
            Log.write(String(format: "sync: %d downloaded, %d failed, %@ in %.0f s (%.1f MB/s)", filesDone, failures,
                             Self.bytes(bytesFinished), seconds, Double(bytesFinished) / max(seconds, 1) / 1e6))
        }
        notify()
    }

    /// Deletes a file the server dropped, and any folders it leaves empty.
    private func remove(_ path: String) {
        let fm = FileManager.default
        var url = Library.documents.appendingPathComponent(path)
        try? fm.removeItem(at: url)
        let root = Library.documents.standardizedFileURL.path
        while true {
            url.deleteLastPathComponent()
            guard url.standardizedFileURL.path.count > root.count,
                  (try? fm.contentsOfDirectory(atPath: url.path))?.isEmpty == true else { break }
            try? fm.removeItem(at: url)
        }
    }

    // MARK: Helpers

    private func saveManifest() {
        if let data = try? JSONEncoder().encode(manifest) { try? data.write(to: manifestURL, options: .atomic) }
    }

    /// New files reach the library a few at a time rather than in one scan at the end.
    private func scheduleScan() {
        guard !scanPending else { return }
        scanPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.scanPending = false
            Library.shared.scan()
        }
    }

    private func notify(throttled: Bool = false) {
        if throttled, Date().timeIntervalSince(lastNotice) < 0.25 { return }
        lastNotice = Date()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    static func size(of url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }.map(Int64.init)
    }

    static var freeSpace: Int64 {
        (try? Library.documents.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
    }

    static var capacity: Int64 {
        Int64((try? Library.documents.resourceValues(forKeys: [.volumeTotalCapacityKey]))?.volumeTotalCapacity ?? 0)
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

extension Sync: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let job = Job(downloadTask) else { return }
        written[job.id] = totalBytesWritten
        notify(throttled: true)
    }

    /// The file has to be moved before this returns, or the system deletes it.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let job = Job(downloadTask) else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        let size = Self.size(of: location) ?? 0
        guard status == 200, size == job.size else {
            failures += 1
            Log.write("sync: \(job.path) came back \(status) with \(size) of \(job.size) bytes")
            return
        }
        let fm = FileManager.default
        let target = Library.documents.appendingPathComponent(job.path)
        try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: target)
        do {
            try fm.moveItem(at: location, to: target)
        } catch {
            failures += 1
            Log.write("sync: couldn't place \(job.path): \(error.localizedDescription)")
            return
        }
        manifest[job.id] = Entry(path: job.path, size: job.size)
        filesDone += 1
        bytesFinished += job.size
        if filesDone % 10 == 0 { saveManifest() }
        scheduleScan()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let job = Job(task) else { return }
        written[job.id] = nil
        if let error, (error as NSError).code != NSURLErrorCancelled {
            failures += 1
            Log.write("sync: \(job.path) failed: \(error.localizedDescription)")
        }
        guard active.remove(job.id) != nil else { return }
        if active.isEmpty, phase == .downloading {
            finish()
        } else {
            notify()
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        backgroundCompletion?()
        backgroundCompletion = nil
    }
}
