import UIKit

/// The top of the player: cover and tags, the spectrum panel, and the waveform seekbar.
final class PlayerHeaderView: UIView {
    static let height: CGFloat = 170

    let spectrum = SpectrumView(bands: SpectrumAnalyzer.bandCount, barWidth: 5)
    let waveform = WaveformView()
    var onCoverTap: (() -> Void)?

    private let cover = CoverView(radius: 3)
    private let title = UILabel(font: Fonts.text(15, .semibold))
    private let subtitle = UILabel(font: Fonts.text(12.5))
    private let tech = UILabel(font: Fonts.mono(10.5))
    private let panel = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        panel.layer.cornerRadius = 4
        panel.layer.borderWidth = 1
        cover.isUserInteractionEnabled = true
        cover.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(coverTapped)))
        cover.accessibilityLabel = "Show in list"
        cover.isAccessibilityElement = true
        for view in [cover, title, subtitle, tech, panel, spectrum, waveform] as [UIView] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        cover.frame = CGRect(x: 12, y: 0, width: 64, height: 64)
        let x: CGFloat = 88
        title.frame = CGRect(x: x, y: 6, width: width - x - 12, height: 20)
        subtitle.frame = CGRect(x: x, y: 26, width: width - x - 12, height: 17)
        tech.frame = CGRect(x: x, y: 43, width: width - x - 12, height: 15)
        panel.frame = CGRect(x: 12, y: 74, width: width - 24, height: 48)
        spectrum.frame = panel.frame.insetBy(dx: 7, dy: 5)
        waveform.frame = CGRect(x: 12, y: 130, width: width - 24, height: 40)
    }

    @objc private func coverTapped() {
        onCoverTap?()
    }

    func show(_ track: Track?, gain: Double) {
        cover.show(track?.coverID)
        title.text = track?.title ?? "Nothing playing"
        subtitle.text = track.map { "\($0.artist) — \($0.album)" } ?? ""
        guard let track else {
            tech.text = ""
            return
        }
        var parts = [track.codec, track.resolution, "\(track.bitrate) kbps"]
        if Settings.shared.replayGain != .off, track.trackGain != nil || track.albumGain != nil {
            parts.append(String(format: "RG %@%.1f dB", gain < 0 ? "−" : "+", abs(gain)))
        }
        tech.text = parts.joined(separator: " · ")
        waveform.levels = Waveforms.shared.levels(for: track)
    }

    func apply(_ theme: Theme) {
        title.textColor = theme.text.color()
        subtitle.textColor = theme.secondary
        tech.textColor = theme.secondary
        cover.backgroundColor = theme.line.color()
        panel.backgroundColor = theme.panel.color()
        panel.layer.borderColor = theme.line.color().cgColor
        spectrum.barColor = theme.accent.color()
        spectrum.capColor = theme.text.color(0.7)
        spectrum.setNeedsDisplay()
        waveform.playedColor = theme.text.color(0.9)
        waveform.idleColor = theme.faint
        waveform.headColor = theme.accent.color()
        waveform.setNeedsDisplay()
    }
}

/// The player folded to one line, over the library and search: tap it to unfold.
final class NowPlayingStrip: UIControl {
    static let height: CGFloat = 58

    let spectrum = SpectrumView(bands: 14, barWidth: 3)
    private let cover = CoverView(radius: 3)
    private let title = UILabel(font: Fonts.text(14, .semibold))
    private let detail = UILabel(font: Fonts.mono(10.5))
    private let rail = UIView()
    private let fill = UIView()
    private var progress: CGFloat = 0
    private var artist = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        spectrum.showsCaps = false
        for view in [cover, title, detail, spectrum, rail, fill] as [UIView] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        isAccessibilityElement = true
        accessibilityLabel = "Open player"
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        cover.frame = CGRect(x: 12, y: 6, width: 40, height: 40)
        let spectrumWidth: CGFloat = 14 * 3 + 13 * 2
        spectrum.frame = CGRect(x: width - 12 - spectrumWidth, y: 16, width: spectrumWidth, height: 24)
        let textWidth = spectrum.frame.minX - 10 - 62
        title.frame = CGRect(x: 62, y: 8, width: textWidth, height: 18)
        detail.frame = CGRect(x: 62, y: 26, width: textWidth, height: 15)
        rail.frame = CGRect(x: 12, y: 54, width: width - 24, height: 2)
        fill.frame = CGRect(x: 12, y: 54, width: (width - 24) * progress, height: 2)
    }

    func show(_ track: Track?) {
        cover.show(track?.coverID)
        title.text = track?.title ?? "Nothing playing"
        artist = track?.artist ?? ""
    }

    func setTime(_ position: Double, _ duration: Double) {
        let text = artist.isEmpty ? "" : "\(artist) · \(position.clock) / \(duration.clock)"
        if text != detail.text { detail.text = text }
        progress = duration > 0 ? CGFloat(min(position / duration, 1)) : 0
        fill.frame.size.width = (bounds.width - 24) * progress
    }

    func apply(_ theme: Theme) {
        title.textColor = theme.text.color()
        detail.textColor = theme.secondary
        cover.backgroundColor = theme.line.color()
        rail.backgroundColor = theme.line.color()
        fill.backgroundColor = theme.accent.color()
        spectrum.barColor = theme.accent.color()
        spectrum.setNeedsDisplay()
    }
}
