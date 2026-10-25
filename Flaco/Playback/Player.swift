import AVFoundation
import MediaPlayer
import UIKit

/// Gapless playback. Files are decoded about a second ahead and converted to the output format, so one track
/// runs into the next without a seam whatever each file's sample rate. Which track is heard is read back from
/// the player node's sample clock.
final class Player {
    static let shared = Player()
    static let didChange = Notification.Name("FlacoPlayerDidChange")

    enum State {
        case stopped, playing, paused
    }

    private(set) var state = State.stopped
    private(set) var current: Track?
    /// ReplayGain on the current track, in dB.
    private(set) var gain: Double = 0
    let queue = PlayQueue()
    let spectrum = SpectrumAnalyzer()

    var outputSampleRate: Double { format.sampleRate }

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    private let decoder = DispatchQueue(label: "flaco.decoder", qos: .userInitiated)
    private let lock = NSLock()

    // Decoder queue only.
    private var source: Source?
    private var sourceStart: AVAudioFramePosition = 0
    private var pendingSwitch: Track?
    private var scheduled: AVAudioFramePosition = 0
    private var inFlight = 0
    private var generation = 0

    // Under `lock`.
    private var segments: [Segment] = []
    private var wantsPlay = false

    // Main thread.
    private var heldPosition: Double = 0
    private var needsSource = true
    private var resumeAfterInterruption = false
    private var lastSaved = Date.distantPast
    private var timer: Timer?

    /// Where a track starts on the node's clock.
    private struct Segment {
        let track: Track
        let start: AVAudioFramePosition
        let offset: Double
        let gain: Double
    }

    private init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        observe()
        setUpRemoteCommands()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: Control

    func play(_ tracks: [Track], from index: Int, name: String) {
        guard tracks.indices.contains(index) else { return }
        queue.set(tracks, start: index, name: name)
        start(tracks[index], at: 0, playing: true)
    }

    func jump(to track: Track) {
        start(track, at: 0, playing: true)
    }

    func playUpNext(at index: Int) {
        guard let track = queue.removeUpNext(at: index) else { return }
        start(track, at: 0, playing: true)
    }

    func toggle() {
        state == .playing ? pause() : resume()
    }

    func resume() {
        guard let track = current else {
            let all = Library.shared.tracks
            if !all.isEmpty { play(all, from: 0, name: "All") }
            return
        }
        if needsSource || state == .stopped {
            start(track, at: state == .stopped ? 0 : heldPosition, playing: true)
            return
        }
        if prepareOutput(for: track) {
            // The output changed rate while paused: what was decoded is for the old rate.
            start(track, at: heldPosition, playing: true)
            return
        }
        lock.sync { wantsPlay = true }
        startEngine()
        node.play()
        state = .playing
        changed()
    }

    func pause() {
        guard state == .playing else { return }
        heldPosition = position
        lock.sync { wantsPlay = false }
        node.pause()
        engine.pause()
        state = .paused
        changed()
        save()
    }

    func stop() {
        lock.sync { wantsPlay = false }
        decoder.async { self.resetDecoder() }
        engine.pause()
        heldPosition = 0
        needsSource = true
        state = .stopped
        changed()
    }

    func next() {
        guard let track = current, let next = queue.next(after: track, manual: true) else { return }
        start(next, at: 0, playing: state != .paused)
    }

    func previous() {
        guard let track = current else { return }
        if position > 3 {
            seek(to: 0)
        } else if let previous = queue.previous(before: track) {
            start(previous, at: 0, playing: state != .paused)
        } else {
            seek(to: 0)
        }
    }

    func seek(to seconds: Double) {
        guard let track = current else { return }
        let target = min(max(seconds, 0), max(track.duration - 0.5, 0))
        if state == .stopped {
            heldPosition = target
            state = .paused
            needsSource = true
            changed()
            return
        }
        start(track, at: target, playing: state == .playing)
    }

    // MARK: Reading back

    var position: Double {
        guard state == .playing, !needsSource else { return heldPosition }
        guard let sample = sampleTime() else { return heldPosition }
        let rate = format.sampleRate
        let seconds: Double? = lock.sync {
            guard let segment = segments.last(where: { $0.start <= sample }) ?? segments.first else { return nil }
            return segment.offset + Double(max(0, sample - segment.start)) / rate
        }
        return min(seconds ?? heldPosition, current?.duration ?? 0)
    }

    /// The spectrum of what is coming out of the speaker now.
    func spectrumNow() -> [Float]? {
        guard state == .playing, let sample = sampleTime() else { return nil }
        return spectrum.bands(at: sample)
    }

    var outputName: String {
        AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "Speaker"
    }

    // MARK: Decoding

    private func start(_ track: Track, at seconds: Double, playing: Bool) {
        _ = prepareOutput(for: track)
        needsSource = false
        heldPosition = seconds
        setCurrent(track, gain: gainDecibels(for: track))
        state = playing ? .playing : .paused
        lock.sync { wantsPlay = playing }
        if playing { startEngine() }
        changed()

        decoder.async { [self] in
            resetDecoder()
            var candidate: Track? = track
            var offset = seconds
            while let attempt = candidate {
                if let opened = open(attempt, at: offset) {
                    source = opened
                    sourceStart = 0
                    lock.sync { segments = [Segment(track: attempt, start: 0, offset: offset, gain: gainDecibels(for: attempt))] }
                    break
                }
                // Unreadable (deleted or still copying): try the next one.
                candidate = queue.next(after: attempt, manual: true)
                offset = 0
                if candidate == track { candidate = nil }
            }
            guard source != nil else {
                DispatchQueue.main.async { self.stop() }
                return
            }
            fill(generation)
            let play = lock.sync { wantsPlay }
            if play { node.play() }
        }
    }

    private func resetDecoder() {
        generation += 1
        node.stop()
        inFlight = 0
        scheduled = 0
        source = nil
        pendingSwitch = nil
        spectrum.reset()
        lock.sync { segments.removeAll() }
    }

    private func fill(_ gen: Int) {
        while gen == generation, inFlight < 4, let buffer = decodeNext() {
            inFlight += 1
            node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                self?.decoder.async { self?.played(gen) }
            }
        }
    }

    private func played(_ gen: Int) {
        guard gen == generation else { return }
        inFlight -= 1
        fill(gen)
        if inFlight == 0, source == nil {
            let next = pendingSwitch
            pendingSwitch = nil
            DispatchQueue.main.async {
                if let next { self.start(next, at: 0, playing: true) } else { self.finished() }
            }
        }
    }

    private func decodeNext() -> AVAudioPCMBuffer? {
        while let current = source {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16384) else { return nil }
            current.read(into: buffer)
            let start = scheduled
            if !current.crossed.isEmpty {
                let began = current.crossed.map { Segment(track: $0.track, start: sourceStart + $0.frame, offset: 0, gain: $0.gain) }
                lock.sync { segments.append(contentsOf: began) }
            }
            scheduled += AVAudioFramePosition(buffer.frameLength)
            if current.isFinished {
                openNext(after: current.track, at: scheduled)
            }
            if buffer.frameLength > 0 {
                spectrum.analyze(buffer, at: start)
                return buffer
            }
        }
        return nil
    }

    /// Opens what follows a run of same-format files, so its first frame is scheduled right after the last
    /// one. A track that wants the other output rate waits until the buffers drain, then starts afresh.
    private func openNext(after track: Track, at start: AVAudioFramePosition) {
        source = nil
        var candidate = queue.next(after: track)
        var attempts = 0
        while let next = candidate, attempts < 20 {
            if Self.outputRate(for: next) != format.sampleRate, Self.outputRate(for: next) != Self.outputRate(for: track) {
                pendingSwitch = next
                return
            }
            if let opened = open(next, at: 0) {
                source = opened
                sourceStart = start
                lock.sync { segments.append(Segment(track: next, start: start, offset: 0, gain: gainDecibels(for: next))) }
                return
            }
            candidate = queue.next(after: next)
            attempts += 1
        }
    }

    private func open(_ track: Track, at seconds: Double) -> Source? {
        Source(track: track, format: format, at: seconds,
               following: { [weak self] in self?.queue.next(after: $0) },
               gain: { [weak self] track in
                   let decibels = self?.gainDecibels(for: track) ?? 0
                   return (decibels, Self.linear(decibels, track))
               })
    }

    private func finished() {
        lock.sync { wantsPlay = false }
        engine.pause()
        heldPosition = 0
        needsSource = true
        state = .stopped
        changed()
    }

    private func sampleTime() -> AVAudioFramePosition? {
        guard let nodeTime = node.lastRenderTime, let time = node.playerTime(forNodeTime: nodeTime) else { return nil }
        return time.sampleTime
    }

    /// Notices the moment the next track becomes audible.
    private func tick() {
        guard state == .playing, !needsSource, let sample = sampleTime() else { return }
        let heard: Segment? = lock.sync {
            guard let i = segments.lastIndex(where: { $0.start <= sample }) else { return nil }
            if i > 0 { segments.removeFirst(i) }
            return segments.first
        }
        if let heard, heard.track != current {
            setCurrent(heard.track, gain: heard.gain)
            changed()
        }
        if Date().timeIntervalSince(lastSaved) > 5 { save() }
    }

    private func setCurrent(_ track: Track, gain: Double) {
        let isNew = track != current
        current = track
        self.gain = gain
        if isNew {
            queue.didStart(track)
            Waveforms.shared.prepare(track)
        }
    }

    // MARK: ReplayGain

    private func gainDecibels(for track: Track) -> Double {
        switch Settings.shared.replayGain {
        case .off: return 0
        case .track: return track.trackGain ?? 0
        case .album: return track.albumGain ?? track.trackGain ?? 0
        }
    }

    private static func linear(_ decibels: Double, _ track: Track) -> Float {
        var value = pow(10, decibels / 20)
        if Settings.shared.preventClipping {
            let peak = Settings.shared.replayGain == .track ? track.trackPeak : track.albumPeak ?? track.trackPeak
            if let peak, peak > 0 { value = min(value, 1 / peak) }
        }
        return Float(value)
    }

    // MARK: Session and engine

    /// The iPhone's output runs at 44.1 or 48 kHz. Music of the 44.1 family plays at 44.1 so CD rips go out
    /// without resampling; everything else at 48.
    static func outputRate(for track: Track) -> Double {
        track.sampleRate > 0 && track.sampleRate.truncatingRemainder(dividingBy: 11025) == 0 ? 44100 : 48000
    }

    /// Activates the session at the track's rate and matches the engine to what the output gives.
    /// True when the engine had to change rate.
    private func prepareOutput(for track: Track) -> Bool {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setPreferredSampleRate(Self.outputRate(for: track))
        try? session.setActive(true)
        let rate = session.sampleRate
        guard rate > 0, rate != format.sampleRate else { return false }
        decoder.sync {
            resetDecoder()
            if engine.isRunning { engine.stop() }
            format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
            engine.connect(node, to: engine.mainMixerNode, format: format)
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
            spectrum.configure(sampleRate: rate)
        }
        needsSource = true
        return true
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        engine.prepare()
        try? engine.start()
    }

    private func observe() {
        let center = NotificationCenter.default
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.outputChanged()
        }
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            self?.interrupted(note)
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            // Headphones pulled out: stop rather than play out loud.
            if reason == .oldDeviceUnavailable { self?.pause() }
            self?.changed()
        }
        center.addObserver(forName: Library.didChange, object: nil, queue: .main) { [weak self] _ in
            // The file went away (deleted in Finder, say): let go of it unless it's still being heard.
            guard let self, let track = self.current, self.state != .playing,
                  Library.shared.track(at: track.path) == nil else { return }
            self.current = nil
            self.heldPosition = 0
            self.needsSource = true
            self.state = .stopped
            self.changed()
        }
        center.addObserver(forName: Settings.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self, let track = self.current else { return }
            self.gain = self.gainDecibels(for: track)
        }
    }

    private func outputChanged() {
        guard let track = current, state != .stopped else { return }
        if engine.isRunning, AVAudioSession.sharedInstance().sampleRate == format.sampleRate { return }
        let resumeAt = position
        if state == .playing {
            start(track, at: resumeAt, playing: true)
        } else {
            heldPosition = resumeAt
            needsSource = true
            decoder.async { self.resetDecoder() }
        }
    }

    private func interrupted(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            resumeAfterInterruption = state == .playing
            if state == .playing { pause() }
        case .ended:
            let raw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if resumeAfterInterruption, AVAudioSession.InterruptionOptions(rawValue: raw).contains(.shouldResume) {
                resume()
            }
            resumeAfterInterruption = false
        @unknown default:
            break
        }
    }

    // MARK: Lock screen

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.previous(); return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
    }

    private var artwork: (id: String, artwork: MPMediaItemArtwork)?

    private func updateNowPlaying() {
        guard let track = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
        ]
        if artwork?.id != track.coverID {
            artwork = Covers.full(track.coverID).map { image in
                (track.coverID, MPMediaItemArtwork(boundsSize: image.size) { _ in image })
            }
        }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork.artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func changed() {
        updateNowPlaying()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    // MARK: Resume

    func save() {
        lastSaved = Date()
        guard let track = current else { return }
        UserDefaults.standard.set([
            "track": track.path, "position": position, "queue": queue.snapshot,
        ], forKey: "resume")
    }

    func restore() {
        guard Settings.shared.resume,
              let saved = UserDefaults.standard.dictionary(forKey: "resume"),
              let path = saved["track"] as? String,
              let track = Library.shared.track(at: path) else { return }
        queue.restore(saved["queue"] as? [String: Any] ?? [:]) { Library.shared.track(at: $0) }
        current = track
        gain = gainDecibels(for: track)
        heldPosition = saved["position"] as? Double ?? 0
        needsSource = true
        state = .paused
        Waveforms.shared.prepare(track)
    }
}
