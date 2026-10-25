import Foundation

enum ReplayGainMode: String, CaseIterable {
    case off, track, album
}

enum SpectrumStyle: String, CaseIterable {
    case bars, line, off
}

/// The listener's choices, kept in UserDefaults.
final class Settings {
    static let shared = Settings()
    static let didChange = Notification.Name("FlacoSettingsDidChange")

    private let defaults = UserDefaults.standard

    var replayGain: ReplayGainMode {
        get { ReplayGainMode(rawValue: defaults.string(forKey: "replayGain") ?? "") ?? .album }
        set { store(newValue.rawValue, "replayGain") }
    }

    /// Lowers the gain where ReplayGain would push a track's peak past full scale.
    var preventClipping: Bool {
        get { flag("preventClipping", true) }
        set { store(newValue, "preventClipping") }
    }

    var resume: Bool {
        get { flag("resume", true) }
        set { store(newValue, "resume") }
    }

    var coverColors: Bool {
        get { flag("coverColors", true) }
        set { store(newValue, "coverColors") }
    }

    var spectrum: SpectrumStyle {
        get { SpectrumStyle(rawValue: defaults.string(forKey: "spectrum") ?? "") ?? .bars }
        set { store(newValue.rawValue, "spectrum") }
    }

    var waveform: Bool {
        get { flag("waveform", true) }
        set { store(newValue, "waveform") }
    }

    private func flag(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
