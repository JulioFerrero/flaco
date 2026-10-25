import AVFoundation
import Accelerate

/// A run of files with the same stream format, decoded through one converter. The resampler's filter carries
/// across each track boundary, so joins inside an album stay seamless even when the output runs at another rate.
/// ReplayGain is applied to the samples, so a change of gain lands exactly where the next track begins.
final class Source {
    struct Boundary {
        /// Output frames from this source's first frame.
        let frame: AVAudioFramePosition
        let track: Track
        let gain: Double
    }

    /// The file being fed to the converter now; at the end, the last one.
    private(set) var track: Track
    private(set) var isFinished = false
    /// Tracks whose first frame was produced during the last read.
    private(set) var crossed: [Boundary] = []

    private let following: (Track) -> Track?
    private let gainFor: (Track) -> (decibels: Double, linear: Float)
    private var file: AVAudioFile
    private let inputFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private let input: AVAudioPCMBuffer
    private let ratio: Double
    private var fed: AVAudioFramePosition = 0
    private var produced: AVAudioFramePosition = 0
    private var gains: [(from: AVAudioFramePosition, linear: Float)]
    private var upcoming: [Boundary] = []
    private var inputDone = false

    init?(track: Track, format: AVAudioFormat, at seconds: Double,
          following: @escaping (Track) -> Track?, gain: @escaping (Track) -> (decibels: Double, linear: Float)) {
        guard let file = try? AVAudioFile(forReading: track.url),
              let converter = AVAudioConverter(from: file.processingFormat, to: format),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192) else { return nil }
        if file.processingFormat.channelCount == 1 {
            converter.channelMap = [0, 0]
        }
        converter.sampleRateConverterQuality = AVAudioQuality.high.rawValue
        let start = AVAudioFramePosition(seconds * file.processingFormat.sampleRate)
        if start > 0 {
            file.framePosition = min(start, file.length)
        }
        self.track = track
        self.following = following
        gainFor = gain
        self.file = file
        inputFormat = file.processingFormat
        self.converter = converter
        self.input = input
        ratio = format.sampleRate / file.processingFormat.sampleRate
        gains = [(0, gain(track).linear)]
    }

    /// Fills `buffer` as far as the files go. After the last frames, `isFinished` is true.
    func read(into buffer: AVAudioPCMBuffer) {
        buffer.frameLength = 0
        crossed = []
        guard !isFinished else { return }
        var error: NSError?
        let status = converter.convert(to: buffer, error: &error) { [self] count, status in
            guard let data = pull(count) else {
                status.pointee = .endOfStream
                return nil
            }
            status.pointee = .haveData
            return data
        }
        if status == .endOfStream || status == .error {
            isFinished = true
        }
        let start = produced
        produced += AVAudioFramePosition(buffer.frameLength)
        while let next = upcoming.first, next.frame < produced {
            crossed.append(next)
            upcoming.removeFirst()
        }
        applyGain(buffer, from: start)
    }

    /// The next stretch of input, moving on to the following file when this one runs out and has the same format.
    private func pull(_ count: AVAudioPacketCount) -> AVAudioPCMBuffer? {
        guard !inputDone else { return nil }
        input.frameLength = 0
        try? file.read(into: input, frameCount: min(count, input.frameCapacity))
        if input.frameLength == 0, chainNext() {
            try? file.read(into: input, frameCount: min(count, input.frameCapacity))
        }
        guard input.frameLength > 0 else {
            inputDone = true
            return nil
        }
        fed += AVAudioFramePosition(input.frameLength)
        return input
    }

    private func chainNext() -> Bool {
        guard let next = following(track),
              let nextFile = try? AVAudioFile(forReading: next.url),
              nextFile.processingFormat.sampleRate == inputFormat.sampleRate,
              nextFile.processingFormat.channelCount == inputFormat.channelCount else { return false }
        let frame = AVAudioFramePosition((Double(fed) * ratio).rounded())
        let gain = gainFor(next)
        upcoming.append(Boundary(frame: frame, track: next, gain: gain.decibels))
        gains.append((frame, gain.linear))
        file = nextFile
        track = next
        return true
    }

    private func applyGain(_ buffer: AVAudioPCMBuffer, from start: AVAudioFramePosition) {
        guard let channels = buffer.floatChannelData else { return }
        let end = start + AVAudioFramePosition(buffer.frameLength)
        for (i, step) in gains.enumerated() {
            let stepEnd = i + 1 < gains.count ? gains[i + 1].from : end
            let low = max(step.from, start), high = min(stepEnd, end)
            guard high > low, step.linear != 1 else { continue }
            var gain = step.linear
            for channel in 0..<Int(buffer.format.channelCount) {
                vDSP_vsmul(channels[channel] + Int(low - start), 1, &gain, channels[channel] + Int(low - start), 1, vDSP_Length(high - low))
            }
        }
        // Steps wholly in the past are done with.
        while gains.count > 1, gains[1].from <= end { gains.removeFirst() }
    }
}
