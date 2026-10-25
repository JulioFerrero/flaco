import AVFoundation

/// The loudness outline of a track for the seekbar: 100 RMS levels on a fixed decibel scale, so a bar's height
/// means the same in every song. Each track is decoded once and kept in Caches.
///
/// Decoding goes in slices of about 50 ms. Before each slice the worker picks what matters most: the track
/// being heard, drawn bar by bar as it fills, and otherwise the rest of the library from there on. A track
/// skipped halfway keeps what it has and is finished later, so skipping never queues up work.
final class Waveforms {
    static let shared = Waveforms()
    static let didUpdate = Notification.Name("FlacoWaveformDidUpdate")
    static let count = 100
    /// A bar not decoded yet.
    static let unknown: Float = -1

    // Main thread.
    private var levels: [String: [Float]] = [:]
    private var finished: Set<String> = []

    // Worker queue.
    private let worker = DispatchQueue(label: "flaco.waveforms")
    private var heard: Track?
    private var library: [Track] = []
    private var jobs: [String: Job] = [:]
    private var done: Set<String> = []
    private var scheduled = false
    private var paused = false

    private let directory: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Waveforms", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func levels(for track: Track) -> [Float]? {
        levels[track.path]
    }

    /// The track now being heard comes first.
    func prepare(_ track: Track) {
        guard !finished.contains(track.path) else { return }
        worker.async {
            self.heard = track
            self.jobs[track.path]?.reported = -1
            self.kick()
        }
    }

    /// Everything else, from the heard track onward.
    func prepareLibrary() {
        let tracks = Library.shared.tracks
        let start = Player.shared.current.flatMap { tracks.firstIndex(of: $0) } ?? 0
        let order = tracks.indices.map { tracks[(start + $0) % tracks.count] }.filter { !finished.contains($0.path) }
        worker.async {
            self.library = order
            self.kick()
        }
    }

    /// Paused while Flaco is out of sight: nobody sees a waveform there, and iOS ends a background app that
    /// keeps the CPU busy for a minute.
    func setPaused(_ paused: Bool) {
        worker.async {
            self.paused = paused
            self.kick()
        }
    }

    // MARK: Worker

    private func kick() {
        guard !scheduled, !paused else { return }
        let urgent = heard.map { !done.contains($0.path) } ?? false
        guard urgent || !library.isEmpty else { return }
        scheduled = true
        worker.async(qos: urgent ? .userInitiated : .utility, flags: .enforceQoS) {
            self.scheduled = false
            self.work()
            self.kick()
        }
    }

    private func work() {
        var track: Track
        var isHeard = false
        if let heard, !done.contains(heard.path) {
            track = heard
            isHeard = true
        } else {
            while let first = library.first, done.contains(first.path) { library.removeFirst() }
            guard let first = library.first else { return }
            track = first
        }

        guard let job = jobs[track.path] ?? start(track) else { return }
        let slice = Date()
        var complete = false
        repeat {
            complete = job.step()
        } while !complete && Date().timeIntervalSince(slice) < 0.05
        job.seconds += Date().timeIntervalSince(slice)

        if complete {
            jobs[track.path] = nil
            store(job.levels, for: track)
            finish(track, job.levels)
            Log.write(String(format: "waveform in %.2f s of decoding%@: %@", job.seconds, isHeard ? "" : " (library)", track.title))
        } else if isHeard, job.filled >= job.reported + 5 || job.reported < 0 {
            job.reported = job.filled
            publish(job.levels, for: track.path)
        }
    }

    /// A job for a track not seen yet, or nil when it's already on disk or can't be read.
    private func start(_ track: Track) -> Job? {
        if let saved = load(track) {
            finish(track, saved)
            return nil
        }
        guard let job = Job(track) else {
            finish(track, nil)
            return nil
        }
        // Skipped tracks keep their progress, but only a few files stay open.
        if jobs.count >= 6, let stale = jobs.keys.first(where: { $0 != heard?.path }) {
            jobs[stale] = nil
        }
        jobs[track.path] = job
        return job
    }

    private func finish(_ track: Track, _ result: [Float]?) {
        done.insert(track.path)
        let path = track.path
        DispatchQueue.main.async {
            self.finished.insert(path)
            guard let result else { return }
            self.levels[path] = result
            NotificationCenter.default.post(name: Self.didUpdate, object: path)
        }
    }

    private func publish(_ partial: [Float], for path: String) {
        DispatchQueue.main.async {
            guard !self.finished.contains(path) else { return }
            self.levels[path] = partial
            NotificationCenter.default.post(name: Self.didUpdate, object: path)
        }
    }

    // MARK: Files

    private func file(for track: Track) -> URL {
        directory.appendingPathComponent(Library.hash("\(track.path)|\(track.modified)") + ".outline")
    }

    private func load(_ track: Track) -> [Float]? {
        guard let data = try? Data(contentsOf: file(for: track)),
              data.count == Self.count * MemoryLayout<Float>.size else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    private func store(_ levels: [Float], for track: Track) {
        try? levels.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: file(for: track), options: .atomic)
    }

    // MARK: Decoding

    /// One track's outline in progress: RMS per bar from every fourth frame, read as 16-bit straight from the
    /// decoder.
    private final class Job {
        var reported = -1
        var seconds: TimeInterval = 0

        private let file: AVAudioFile
        private let buffer: AVAudioPCMBuffer
        private let channels: Int
        private let total: AVAudioFramePosition
        private var sums = [Double](repeating: 0, count: Waveforms.count)
        private var counts = [Int](repeating: 0, count: Waveforms.count)
        private var position: AVAudioFramePosition = 0
        private var ended = false

        init?(_ track: Track) {
            guard let file = try? AVAudioFile(forReading: track.url, commonFormat: .pcmFormatInt16, interleaved: true),
                  file.length > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16384) else { return nil }
            self.file = file
            self.buffer = buffer
            channels = Int(file.processingFormat.channelCount)
            total = file.length
        }

        /// Bars fully decoded so far.
        var filled: Int {
            ended ? Waveforms.count : Int(position * AVAudioFramePosition(Waveforms.count) / total)
        }

        var levels: [Float] {
            let filled = self.filled
            return (0..<Waveforms.count).map { $0 < filled ? Self.level(sums[$0], counts[$0]) : Waveforms.unknown }
        }

        /// Decodes one buffer. True once the whole file is in.
        func step() -> Bool {
            guard !ended else { return true }
            guard (try? file.read(into: buffer)) != nil, buffer.frameLength > 0,
                  let samples = buffer.int16ChannelData?[0] else {
                ended = true
                return true
            }
            let frames = Int(buffer.frameLength)
            let count = AVAudioFramePosition(Waveforms.count)
            for i in stride(from: 0, to: frames, by: 4) {
                var value: Int32 = 0
                for channel in 0..<channels { value += Int32(samples[i * channels + channel]) }
                let mono = Double(value) / Double(channels * 32768)
                let bin = min(Waveforms.count - 1, Int((position + AVAudioFramePosition(i)) * count / total))
                sums[bin] += mono * mono
                counts[bin] += 1
            }
            position += AVAudioFramePosition(frames)
            if position >= total { ended = true }
            return ended
        }

        /// −33 dBFS RMS and below draws as a sliver, −3 dBFS and above full height.
        private static func level(_ sum: Double, _ count: Int) -> Float {
            guard count > 0 else { return 0.03 }
            let decibels = 10 * log10(max(sum / Double(count), 1e-10))
            return Float(min(max((decibels + 33) / 30, 0.03), 1))
        }
    }
}
