import AVFoundation

/// The loudness outline of a track for the seekbar: 100 RMS levels on a fixed decibel scale, so a bar's height
/// means the same in every song. Each track is decoded once and kept in Caches. The one being heard is drawn
/// bar by bar as it decodes; the rest of the library is worked through in the background.
final class Waveforms {
    static let shared = Waveforms()
    static let didUpdate = Notification.Name("FlacoWaveformDidUpdate")
    static let count = 100
    /// A bar not decoded yet.
    static let unknown: Float = -1

    // Main thread.
    private var levels: [String: [Float]] = [:]
    private var working: Set<String> = []
    private var finished: Set<String> = []
    private var libraryRunning = false

    private let heard = DispatchQueue(label: "flaco.waveforms", qos: .userInitiated)
    private let library = DispatchQueue(label: "flaco.waveforms.library", qos: .utility)
    private let lock = NSLock()
    private var heardJobs = 0
    private var heardBusy: Bool { lock.sync { heardJobs > 0 } }

    private let directory: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Waveforms", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func levels(for track: Track) -> [Float]? {
        levels[track.path]
    }

    /// For the track being heard: from disk if it was done before, else decoded now, bar by bar.
    func prepare(_ track: Track) {
        let path = track.path
        guard !finished.contains(path), !working.contains(path) else { return }
        working.insert(path)
        lock.sync { heardJobs += 1 }
        heard.async {
            defer { self.lock.sync { self.heardJobs -= 1 } }
            if let saved = self.load(track) {
                self.publish(saved, for: path, done: true)
                return
            }
            let started = Date()
            let computed = Self.compute(track) { partial in self.publish(partial, for: path, done: false) }
            self.store(computed, for: track)
            self.publish(computed, for: path, done: true)
            Log.write(String(format: "waveform in %.2f s: %@", Date().timeIntervalSince(started), track.title))
        }
    }

    /// Works through the library from the track being heard onward, one file at a time, giving way whenever
    /// the heard track needs decoding.
    func prepareLibrary() {
        guard !libraryRunning else { return }
        libraryRunning = true
        nextInLibrary()
    }

    private func nextInLibrary() {
        let tracks = Library.shared.tracks
        let start = Player.shared.current.flatMap { tracks.firstIndex(of: $0) } ?? 0
        let order = tracks.indices.map { tracks[(start + $0) % tracks.count] }
        guard let track = order.first(where: { !finished.contains($0.path) && !working.contains($0.path) }) else {
            libraryRunning = false
            return
        }
        working.insert(track.path)
        library.async {
            while self.heardBusy { Thread.sleep(forTimeInterval: 0.5) }
            var result = self.load(track)
            if result == nil {
                let started = Date()
                result = Self.compute(track, progress: nil)
                self.store(result, for: track)
                Log.write(String(format: "waveform in %.2f s (library): %@", Date().timeIntervalSince(started), track.title))
            }
            self.publish(result, for: track.path, done: true)
            DispatchQueue.main.async { self.nextInLibrary() }
        }
    }

    private func publish(_ result: [Float]?, for path: String, done: Bool) {
        DispatchQueue.main.async {
            if done {
                self.working.remove(path)
                self.finished.insert(path)
            }
            guard let result else { return }
            self.levels[path] = result
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

    private func store(_ levels: [Float]?, for track: Track) {
        guard let levels else { return }
        try? levels.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: file(for: track), options: .atomic)
    }

    // MARK: Decoding

    /// RMS per bar from every fourth frame, as 16-bit integers straight from the decoder. `progress` gets the
    /// bars so far about ten times along the way, the rest `unknown`.
    private static func compute(_ track: Track, progress: (([Float]) -> Void)?) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: track.url, commonFormat: .pcmFormatInt16, interleaved: true),
              file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 32768) else { return nil }
        let total = file.length
        let channels = Int(file.processingFormat.channelCount)
        var sums = [Double](repeating: 0, count: count)
        var counts = [Int](repeating: 0, count: count)
        var position: AVAudioFramePosition = 0
        var reported = 0

        while position < total {
            guard (try? file.read(into: buffer)) != nil, buffer.frameLength > 0,
                  let samples = buffer.int16ChannelData?[0] else { break }
            let frames = Int(buffer.frameLength)
            for i in stride(from: 0, to: frames, by: 4) {
                var value: Int32 = 0
                for channel in 0..<channels { value += Int32(samples[i * channels + channel]) }
                let mono = Double(value) / Double(channels * 32768)
                let bin = min(count - 1, Int((position + AVAudioFramePosition(i)) * AVAudioFramePosition(count) / total))
                sums[bin] += mono * mono
                counts[bin] += 1
            }
            position += AVAudioFramePosition(frames)
            let complete = Int(position * AVAudioFramePosition(count) / total)
            if let progress, complete >= reported + 10, complete < count {
                reported = complete
                progress((0..<count).map { $0 < complete ? level(sums[$0], counts[$0]) : unknown })
            }
        }
        return (0..<count).map { level(sums[$0], counts[$0]) }
    }

    /// −33 dBFS RMS and below draws as a sliver, −3 dBFS and above full height.
    private static func level(_ sum: Double, _ count: Int) -> Float {
        guard count > 0 else { return 0 }
        let decibels = 10 * log10(max(sum / Double(count), 1e-10))
        return Float(min(max((decibels + 33) / 30, 0.03), 1))
    }
}
