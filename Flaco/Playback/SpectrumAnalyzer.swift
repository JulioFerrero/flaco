import AVFoundation
import Accelerate

/// A 40-band spectrum of the audio as it's decoded, stamped with the sample time it will play at, so the
/// display can show exactly what is being heard however far ahead the decoder runs.
final class SpectrumAnalyzer {
    static let bandCount = 40

    private let size = 2048
    private let hop = 1024
    private let log2n: vDSP_Length = 11
    private let setup: FFTSetup
    private let window: [Float]
    private var ranges: [Range<Int>] = []
    private var tilt: [Float] = []

    // Decoder queue only.
    private var pending: [Float] = []
    private var pendingStart: AVAudioFramePosition = 0
    private var real: [Float]
    private var imaginary: [Float]
    private var power: [Float]

    private let lock = NSLock()
    private var frames: [(sample: AVAudioFramePosition, bands: [Float])] = []

    init() {
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        real = [Float](repeating: 0, count: size / 2)
        imaginary = [Float](repeating: 0, count: size / 2)
        power = [Float](repeating: 0, count: size / 2)
        configure(sampleRate: 48000)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// Bands spaced evenly in pitch from 40 Hz to 16 kHz.
    func configure(sampleRate: Double) {
        let binWidth = sampleRate / Double(size)
        let low = 40.0, high = min(16000, sampleRate / 2)
        ranges = (0..<Self.bandCount).map { band in
            let f0 = low * pow(high / low, Double(band) / Double(Self.bandCount))
            let f1 = low * pow(high / low, Double(band + 1) / Double(Self.bandCount))
            let lo = max(1, Int(f0 / binWidth))
            return lo..<min(max(lo + 1, Int(f1 / binWidth)), size / 2)
        }
        // Music falls off toward the treble; lift it 3 dB an octave above 1 kHz so the top bands move too.
        tilt = (0..<Self.bandCount).map { band in
            let center = low * pow(high / low, (Double(band) + 0.5) / Double(Self.bandCount))
            return Float(3 * log2(center / 1000))
        }
    }

    func reset() {
        pending.removeAll(keepingCapacity: true)
        lock.sync { frames.removeAll() }
    }

    func analyze(_ buffer: AVAudioPCMBuffer, at start: AVAudioFramePosition) {
        guard let channels = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        if pending.isEmpty { pendingStart = start }
        let stereo = buffer.format.channelCount > 1
        pending.reserveCapacity(pending.count + count)
        for i in 0..<count {
            pending.append(stereo ? (channels[0][i] + channels[1][i]) * 0.5 : channels[0][i])
        }

        var produced: [(AVAudioFramePosition, [Float])] = []
        while pending.count >= size {
            produced.append((pendingStart + AVAudioFramePosition(size / 2), bands()))
            pending.removeFirst(hop)
            pendingStart += AVAudioFramePosition(hop)
        }
        guard !produced.isEmpty else { return }
        lock.sync {
            frames.append(contentsOf: produced.map { (sample: $0.0, bands: $0.1) })
            if frames.count > 400 { frames.removeFirst(frames.count - 400) }
        }
    }

    /// The bands of the analysis window centered nearest before `sample`.
    func bands(at sample: AVAudioFramePosition) -> [Float]? {
        lock.sync {
            var low = 0, high = frames.count - 1, found = -1
            while low <= high {
                let mid = (low + high) / 2
                if frames[mid].sample <= sample {
                    found = mid
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            return found >= 0 ? frames[found].bands : nil
        }
    }

    private func bands() -> [Float] {
        var windowed = [Float](repeating: 0, count: size)
        vDSP_vmul(pending, 1, window, 1, &windowed, 1, vDSP_Length(size))
        let half = size / 2
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { samples in
                    samples.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                power.withUnsafeMutableBufferPointer { powerPointer in
                    vDSP_zvmags(&split, 1, powerPointer.baseAddress!, 1, vDSP_Length(half))
                }
            }
        }
        // A full-scale sine peaks at (size / 2)² after the windowed real FFT.
        let fullScale = Float(half * half)
        return ranges.enumerated().map { band, range in
            var sum: Float = 0
            for bin in range { sum += power[bin] }
            let decibels = 10 * log10(max(sum / Float(range.count) / fullScale, 1e-12)) + tilt[band]
            return min(max((decibels + 66) / 60, 0), 1)
        }
    }
}
