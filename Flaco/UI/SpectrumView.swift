import UIKit

/// The analyzer drawn as bars with falling peak caps, or as a line. Levels rise at once and fall smoothly, so
/// the 47 analysis frames a second read well at 60 frames.
final class SpectrumView: UIView {
    var style = SpectrumStyle.bars { didSet { setNeedsDisplay() } }
    var barColor = UIColor.white
    var capColor = UIColor.white
    var showsCaps = true
    private(set) var isSettled = true

    private let barWidth: CGFloat
    private var levels: [Float]
    private var peaks: [Float]
    private var holds: [CFTimeInterval]

    init(bands: Int, barWidth: CGFloat) {
        self.barWidth = barWidth
        levels = [Float](repeating: 0, count: bands)
        peaks = levels
        holds = [CFTimeInterval](repeating: 0, count: bands)
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ input: [Float]?, now: CFTimeInterval, dt: CFTimeInterval) {
        let fall = Float(dt) * 1.6
        let capFall = Float(dt) * 0.5
        var moving = false
        for i in levels.indices {
            let target = input.map { Self.band(i, of: levels.count, from: $0) } ?? 0
            levels[i] = target >= levels[i] ? target : max(target, levels[i] - fall)
            if levels[i] >= peaks[i] {
                peaks[i] = levels[i]
                holds[i] = now + 0.5
            } else if now > holds[i] {
                peaks[i] = max(levels[i], peaks[i] - capFall)
            }
            if levels[i] > 0.001 || peaks[i] > 0.001 { moving = true }
        }
        isSettled = !moving
        setNeedsDisplay()
    }

    /// Fewer bars than bands take the loudest band of their group.
    private static func band(_ i: Int, of count: Int, from bands: [Float]) -> Float {
        guard count != bands.count else { return bands[i] }
        let low = i * bands.count / count
        let high = max(low + 1, (i + 1) * bands.count / count)
        return bands[low..<high].max() ?? 0
    }

    override func draw(_ rect: CGRect) {
        guard style != .off, let context = UIGraphicsGetCurrentContext() else { return }
        let count = levels.count
        let height = bounds.height
        let gap = count > 1 ? (bounds.width - CGFloat(count) * barWidth) / CGFloat(count - 1) : 0
        let reach = height - (showsCaps ? 4 : 0)

        if style == .line {
            let path = UIBezierPath()
            for i in 0..<count {
                let point = CGPoint(x: CGFloat(i) * (barWidth + gap) + barWidth / 2, y: height - CGFloat(levels[i]) * reach - 1)
                i == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            path.lineWidth = 1.5
            path.lineJoinStyle = .round
            barColor.setStroke()
            path.stroke()
            return
        }

        for i in 0..<count {
            let x = CGFloat(i) * (barWidth + gap)
            let level = CGFloat(levels[i])
            if level > 0.002 {
                let h = max(2, level * reach)
                context.setFillColor(barColor.withAlphaComponent(0.45 + 0.55 * level).cgColor)
                context.fill(CGRect(x: x, y: height - h, width: barWidth, height: h))
            }
            if showsCaps, peaks[i] > 0.002 {
                let top = height - max(2, CGFloat(peaks[i]) * reach) - 3
                context.setFillColor(capColor.cgColor)
                context.fill(CGRect(x: x, y: max(0, top), width: barWidth, height: 2))
            }
        }
    }
}
