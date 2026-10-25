import AVFoundation

/// The loudness outline of a track for the seekbar: 100 RMS levels, computed once in the background and kept
/// in Caches.
final class Waveforms {
    static let shared = Waveforms()
    static let didUpdate = Notification.Name("FlacoWaveformDidUpdate")
    static let count = 100

    private var levels: [String: [Float]] = [:]
    private var exact: Set<String> = []
    private var working: Set<String> = []
    private let quick = DispatchQueue(label: "flaco.waveforms.quick", qos: .userInitiated)
    private let full = DispatchQueue(label: "flaco.waveforms.full", qos: .utility)
    private let directory: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Waveforms", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func levels(for track: Track) -> [Float]? {
        levels[track.path]
    }

    /// A track about to be heard gets a sampled outline at once and the exact one after; a track `ahead`
    /// in the queue gets only the exact one, in the background.
    func prepare(_ track: Track, ahead: Bool = false) {
        let path = track.path
        guard !exact.contains(path), !working.contains(path) else { return }
        working.insert(path)
        let file = directory.appendingPathComponent(Library.hash("\(track.path)|\(track.modified)") + ".wave")
        (ahead ? full : quick).async {
            if let saved = Self.load(file) {
                self.publish(saved, for: path, exact: true)
                return
            }
            let started = Date()
            if !ahead, let sampled = Self.compute(track, sampled: true) {
                self.publish(sampled, for: path, exact: false)
                Log.write(String(format: "waveform sampled in %.2f s: %@", Date().timeIntervalSince(started), track.title))
            }
            self.full.async {
                let started = Date()
                let computed = Self.compute(track, sampled: false)
                Log.write(String(format: "waveform exact in %.2f s%@: %@", Date().timeIntervalSince(started), ahead ? " (ahead)" : "", track.title))
                if let computed {
                    try? computed.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: file, options: .atomic)
                }
                self.publish(computed, for: path, exact: true)
            }
        }
    }

    private func publish(_ result: [Float]?, for path: String, exact isExact: Bool) {
        DispatchQueue.main.async {
            if isExact { self.working.remove(path) }
            guard let result, !self.exact.contains(path) else { return }
            self.levels[path] = result
            if isExact { self.exact.insert(path) }
            NotificationCenter.default.post(name: Self.didUpdate, object: path)
        }
    }

    private static func load(_ url: URL) -> [Float]? {
        guard let data = try? Data(contentsOf: url), data.count == count * MemoryLayout<Float>.size else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    /// RMS per bar, from every fourth frame, or `sampled` from eight short slices of each bar's stretch:
    /// several times quicker, and within a few percent of the exact outline.
    private static func compute(_ track: Track, sampled: Bool) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: track.url), file.length > 0 else { return nil }
        let total = file.length
        let channels = Int(file.processingFormat.channelCount)
        let slices = 8
        let capacity: AVAudioFrameCount = sampled ? 2048 : 65536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity) else { return nil }
        var sums = [Double](repeating: 0, count: count)
        var counts = [Int](repeating: 0, count: count)

        func add(_ frames: Int, at position: AVAudioFramePosition, step: Int) {
            guard let data = buffer.floatChannelData else { return }
            for i in stride(from: 0, to: frames, by: step) {
                var value: Float = 0
                for channel in 0..<channels { value += data[channel][i] }
                value /= Float(channels)
                let bin = min(count - 1, Int((position + AVAudioFramePosition(i)) * AVAudioFramePosition(count) / total))
                sums[bin] += Double(value * value)
                counts[bin] += 1
            }
        }

        if sampled {
            for slice in 0..<count * slices {
                let start = total * AVAudioFramePosition(slice) / AVAudioFramePosition(count * slices)
                file.framePosition = start
                guard (try? file.read(into: buffer, frameCount: capacity)) != nil else { continue }
                add(Int(buffer.frameLength), at: start, step: 2)
            }
        } else {
            var position: AVAudioFramePosition = 0
            while position < total {
                guard (try? file.read(into: buffer)) != nil, buffer.frameLength > 0 else { break }
                add(Int(buffer.frameLength), at: position, step: 4)
                position += AVAudioFramePosition(buffer.frameLength)
            }
        }

        let rms = zip(sums, counts).map { $1 > 0 ? Float(($0 / Double($1)).squareRoot()) : 0 }
        guard let loudest = rms.max(), loudest > 0 else { return rms }
        return rms.map { pow($0 / loudest, 0.8) }
    }
}
