import Foundation

/// Keeps the phone's copy of the server's music: downloads what's new or changed and removes what the server no
/// longer has. Only files that came from the server are ever removed; music added to the phone by hand stays.
/// Downloads run in a background session, so they carry on with Flaco closed.
final class Sync: NSObject {
    static let shared = Sync()
    static let didChange = Notification.Name("FlacoSyncDidChange")
    /// The list of songs on the server changed, not just the progress.
    static let catalogDidChange = Notification.Name("FlacoSyncCatalogDidChange")

    enum Phase: Equatable {
        case idle, checking, downloading
        case failed(String)
    }

    enum Status: Equatable {
        case onPhone, waiting, failed, notDownloaded
        case downloading(Int64)
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
    /// Everything on the server at the last check, in folder order.
    private(set) var catalog: [Server.Song] = []
    private(set) var filesDone = 0
    private(set) var filesTotal = 0
    private(set) var bytesTotal: Int64 = 0
    private(set) var lastSynced: Date?
    var backgroundCompletion: (() -> Void)?

    var bytesDone: Int64 { bytesFinished + written.values.reduce(0, +) }
    var serverBytes: Int64 { catalog.reduce(0) { $0 + $1.size } }

    /// Bytes per second over the last few seconds.
    var speed: Double {
        guard let first = samples.first, let last = samples.last, last.time > first.time else { return 0 }
        return Double(last.bytes - first.bytes) / last.time.timeIntervalSince(first.time)
    }

    private var manifest: [String: Entry] = [:]
    private var active: Set<String> = []
    private var written: [String: Int64] = [:]
    private var failed: Set<String> = []
    private var bytesFinished: Int64 = 0
    private var samples: [(time: Date, bytes: Int64)] = []
    private var started = Date()
    private var lastNotice = Date.distantPast
    private var lastScan = Date.distantPast
    private var scanPending = false
    private var connected = false

    private let manifestURL = Library.support.appendingPathComponent("sync.json")
    private let catalogURL = Library.support.appendingPathComponent("catalog.json")
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
        if let data = try? Data(contentsOf: catalogURL),
           let saved = try? JSONDecoder().decode([Server.Song].self, from: data) {
            catalog = saved
        }
        lastSynced = defaults.object(forKey: "syncLast") as? Date
    }

    func status(of song: Server.Song) -> Status {
        if let bytes = written[song.id] { return .downloading(bytes) }
        if active.contains(song.id) { return .waiting }
        if manifest[song.id] != nil { return .onPhone }
        return failed.contains(song.id) ? .failed : .notDownloaded
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
                self.samples = []
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
        guard Server.shared.isConfigured, phase != .checking, phase != .downloading else { return }
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

    /// Without a server the music stays on the phone, but is no longer treated as the server's.
    func forgetServer() {
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
        manifest = [:]
        catalog = []
        active = []
        written = [:]
        failed = []
        lastSynced = nil
        phase = .idle
        saveManifest()
        try? FileManager.default.removeItem(at: catalogURL)
        defaults.removeObject(forKey: "syncLast")
        NotificationCenter.default.post(name: Self.catalogDidChange, object: nil)
        notify()
    }

    // MARK: Planning

    private func plan(_ listing: Server.Listing, running: Set<String>) {
        let songs = listing.songs.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        catalog = songs
        if let data = try? JSONEncoder().encode(songs) { try? data.write(to: catalogURL, options: .atomic) }

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
                manifest[song.id] = nil
                wanted.append(song)
            }
        }
        saveManifest()
        failed = []
        if removed > 0 { scanSoon() }

        let needed = wanted.filter { !running.contains($0.id) }.reduce(0) { $0 + $1.size }
        let free = Self.freeSpace
        if needed > 0, needed + 300_000_000 > free {
            phase = .failed("Needs \(Self.bytes(needed)), \(Self.bytes(free)) free.")
            Log.write("sync: \(wanted.count) to download (\(Self.bytes(needed))) but only \(Self.bytes(free)) free")
            NotificationCenter.default.post(name: Self.catalogDidChange, object: nil)
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
        samples = []
        started = Date()
        Log.write("sync: \(songs.count) on the server, \(wanted.count) to download (\(Self.bytes(bytesTotal))), \(removed) removed")
        NotificationCenter.default.post(name: Self.catalogDidChange, object: nil)
        if wanted.isEmpty {
            finish()
        } else {
            phase = .downloading
            notify()
        }
    }

    private func finish() {
        saveManifest()
        scanSoon(force: true)
        samples = []
        if !failed.isEmpty {
            phase = .failed(failed.count == 1 ? "1 song didn't download." : "\(failed.count) songs didn't download.")
        } else {
            phase = .idle
            lastSynced = Date()
            defaults.set(lastSynced, forKey: "syncLast")
        }
        if filesTotal > 0 {
            let seconds = Date().timeIntervalSince(started)
            Log.write(String(format: "sync: %d downloaded, %d failed, %@ in %.0f s (%.1f MB/s)", filesDone, failed.count,
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

    /// New songs join the library every ten seconds or so while downloading, not one by one.
    private func scanSoon(force: Bool = false) {
        guard !scanPending else { return }
        let wait = force ? 1 : max(1, 10 - Date().timeIntervalSince(lastScan))
        scanPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            self.scanPending = false
            self.lastScan = Date()
            Library.shared.scan()
        }
    }

    /// At most four times a second, which is what the progress on screen needs.
    private func notify(throttled: Bool = false) {
        let now = Date()
        if throttled, now.timeIntervalSince(lastNotice) < 0.25 { return }
        lastNotice = now
        if phase == .downloading {
            samples.append((now, bytesDone))
            samples.removeAll { now.timeIntervalSince($0.time) > 3 }
        }
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

    /// "21.4 MB/s", or "640 KB/s" when slow.
    static func rate(_ bytesPerSecond: Double) -> String {
        bytes(Int64(bytesPerSecond)) + "/s"
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
            failed.insert(job.id)
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
            failed.insert(job.id)
            Log.write("sync: couldn't place \(job.path): \(error.localizedDescription)")
            return
        }
        manifest[job.id] = Entry(path: job.path, size: job.size)
        filesDone += 1
        bytesFinished += job.size
        if filesDone % 10 == 0 { saveManifest() }
        scanSoon()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let job = Job(task) else { return }
        written[job.id] = nil
        if let error, (error as NSError).code != NSURLErrorCancelled {
            failed.insert(job.id)
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
