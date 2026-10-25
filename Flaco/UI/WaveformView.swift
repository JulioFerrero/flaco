import UIKit

/// The seekbar: the track's loudness outline, played part bright, with a playhead. Drag to scrub, lift to seek.
final class WaveformView: UIView {
    var levels: [Float]? { didSet { setNeedsDisplay() } }
    var showsOutline = true { didSet { setNeedsDisplay() } }
    var playedColor = UIColor.white
    var idleColor = UIColor.gray
    var headColor = UIColor.white

    /// Called while scrubbing with the fraction under the finger, and with nil when it lifts.
    var onScrub: ((Double?) -> Void)?
    var onSeek: ((Double) -> Void)?

    var progress: Double = 0 {
        didSet {
            guard scrub == nil, abs(progress - drawn) * Double(bounds.width) >= 0.5 else { return }
            setNeedsDisplay()
        }
    }

    private var drawn: Double = 0
    private var scrub: Double?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned)))
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        isAccessibilityElement = true
        accessibilityLabel = "Position"
        accessibilityTraits = .adjustable
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func fraction(_ gesture: UIGestureRecognizer) -> Double {
        min(max(Double(gesture.location(in: self).x / max(bounds.width, 1)), 0), 1)
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            scrub = fraction(gesture)
            onScrub?(scrub)
            setNeedsDisplay()
        case .ended:
            let target = fraction(gesture)
            scrub = nil
            progress = target
            onScrub?(nil)
            onSeek?(target)
            setNeedsDisplay()
        default:
            scrub = nil
            onScrub?(nil)
            setNeedsDisplay()
        }
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let target = fraction(gesture)
        progress = target
        onSeek?(target)
    }

    override func accessibilityIncrement() { onSeek?(min(progress + 0.05, 1)) }
    override func accessibilityDecrement() { onSeek?(max(progress - 0.05, 0)) }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let shown = scrub ?? progress
        drawn = progress
        let width = bounds.width, height = bounds.height

        if showsOutline {
            let count = levels?.count ?? Waveforms.count
            let barWidth: CGFloat = 2
            let gap = (width - CGFloat(count) * barWidth) / CGFloat(max(count - 1, 1))
            for i in 0..<count {
                let value = levels?[i] ?? Waveforms.unknown
                let known = value >= 0
                let h = max(2, CGFloat(known ? value : 0) * (height - 2))
                let played = (Double(i) + 0.5) / Double(count) < shown
                // Bars still decoding wait as faint slivers.
                context.setFillColor((played && known ? playedColor : idleColor).cgColor)
                context.fill(CGRect(x: CGFloat(i) * (barWidth + gap), y: (height - h) / 2, width: barWidth, height: h))
            }
        } else {
            let track = CGRect(x: 0, y: height / 2 - 1.5, width: width, height: 3)
            context.setFillColor(idleColor.cgColor)
            context.fill(track)
            context.setFillColor(playedColor.cgColor)
            context.fill(CGRect(x: 0, y: track.minY, width: width * CGFloat(shown), height: 3))
        }

        context.setFillColor(headColor.cgColor)
        context.fill(CGRect(x: min(max(width * CGFloat(shown) - 0.75, 0), width - 1.5), y: 0, width: 1.5, height: height))
    }
}
