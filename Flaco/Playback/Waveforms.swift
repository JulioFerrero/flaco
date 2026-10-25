import AVFoundation

/// The loudness outline of a track for the seekbar: 100 RMS levels, computed once in the background and kept
/// in Caches.
final class Waveforms {
    static let shared = Waveforms()
    static let didUpdate = Notification.Name("FlacoWaveformDidUpdate")
    static let count = 100

    private var levels: [String: [Float]] = [:]
    private var working: Set<String> = []
    private let queue = DispatchQueue(label: "flaco.waveforms", qos: .utility)
    private let directory: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Waveforms", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func levels(for track: Track) -> [Float]? {
        levels[track.path]
    }

    func prepare(_ track: Track) {
        guard levels[track.path] == nil, !working.contains(track.path) else { return }
        working.insert(track.path)
        let file = directory.appendingPathComponent(Library.hash("\(track.path)|\(track.modified)") + ".wave")
        queue.async {
            var result = Self.load(file)
            if result == nil, let computed = Self.compute(track) {
                result = computed
                let data = computed.withUnsafeBufferPointer { Data(buffer: $0) }
                try? data.write(to: file, options: .atomic)
            }
            DispatchQueue.main.async {
                self.working.remove(track.path)
                guard let result else { return }
                self.levels[track.path] = result
                NotificationCenter.default.post(name: Self.didUpdate, object: track.path)
            }
        }
    }

    private static func load(_ url: URL) -> [Float]? {
        guard let data = try? Data(contentsOf: url), data.count == count * MemoryLayout<Float>.size else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    private static func compute(_ track: Track) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: track.url),
              file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 65536) else { return nil }
        let total = file.length
        let channels = Int(file.processingFormat.channelCount)
        var sums = [Double](repeating: 0, count: count)
        var counts = [Int](repeating: 0, count: count)
        var position: AVAudioFramePosition = 0

        while position < total {
            do {
                try file.read(into: buffer)
            } catch {
                break
            }
            let frames = Int(buffer.frameLength)
            guard frames > 0, let data = buffer.floatChannelData else { break }
            // Every fourth frame is plenty for a 100-bar outline.
            for i in stride(from: 0, to: frames, by: 4) {
                var value: Float = 0
                for channel in 0..<channels { value += data[channel][i] }
                value /= Float(channels)
                let bin = min(count - 1, Int((position + AVAudioFramePosition(i)) * AVAudioFramePosition(count) / total))
                sums[bin] += Double(value * value)
                counts[bin] += 1
            }
            position += AVAudioFramePosition(frames)
        }

        let rms = zip(sums, counts).map { $1 > 0 ? Float(($0 / Double($1)).squareRoot()) : 0 }
        guard let loudest = rms.max(), loudest > 0 else { return rms }
        return rms.map { pow($0 / loudest, 0.8) }
    }
}
