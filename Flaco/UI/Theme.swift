import UIKit

/// The interface's colors, all taken from the playing cover: a dark ground in the cover's main hue, and an
/// accent from its most vivid other color.
struct Theme: Codable, Equatable {
    struct RGB: Codable, Equatable {
        var r: CGFloat
        var g: CGFloat
        var b: CGFloat

        init(r: CGFloat, g: CGFloat, b: CGFloat) {
            self.r = r
            self.g = g
            self.b = b
        }

        init(hex: UInt32) {
            self.init(r: CGFloat(hex >> 16 & 0xFF) / 255, g: CGFloat(hex >> 8 & 0xFF) / 255, b: CGFloat(hex & 0xFF) / 255)
        }

        init(h: CGFloat, s: CGFloat, l: CGFloat) {
            let c = (1 - abs(2 * l - 1)) * s
            let sector = h * 6
            let x = c * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
            let rgb: (CGFloat, CGFloat, CGFloat)
            switch sector {
            case ..<1: rgb = (c, x, 0)
            case ..<2: rgb = (x, c, 0)
            case ..<3: rgb = (0, c, x)
            case ..<4: rgb = (0, x, c)
            case ..<5: rgb = (x, 0, c)
            default: rgb = (c, 0, x)
            }
            let m = l - c / 2
            self.init(r: rgb.0 + m, g: rgb.1 + m, b: rgb.2 + m)
        }

        var hsl: (h: CGFloat, s: CGFloat, l: CGFloat) {
            let high = max(r, g, b), low = min(r, g, b)
            let l = (high + low) / 2
            let d = high - low
            guard d > 0.0001 else { return (0, 0, l) }
            let s = min(1, d / (1 - abs(2 * l - 1)))
            var h: CGFloat
            if high == r {
                h = ((g - b) / d).truncatingRemainder(dividingBy: 6)
            } else if high == g {
                h = (b - r) / d + 2
            } else {
                h = (r - g) / d + 4
            }
            h /= 6
            return (h < 0 ? h + 1 : h, s, l)
        }

        func color(_ alpha: CGFloat = 1) -> UIColor {
            UIColor(red: r, green: g, blue: b, alpha: alpha)
        }

        func mix(_ other: RGB, _ t: CGFloat) -> RGB {
            RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
        }
    }

    var background: RGB
    var glow: RGB
    var panel: RGB
    var line: RGB
    var accent: RGB
    var text: RGB

    var ground: UIColor { background.color() }
    var tint: UIColor { accent.color(0.16) }
    var secondary: UIColor { text.color(0.62) }
    var faint: UIColor { text.color(0.22) }

    /// For covers with no color to speak of, and for no cover at all.
    static let neutral = Theme(
        background: RGB(hex: 0x101010), glow: RGB(hex: 0x272727), panel: RGB(hex: 0x171717),
        line: RGB(hex: 0x282828), accent: RGB(hex: 0xE4E4E4), text: RGB(hex: 0xF2F2F2))

    init(background: RGB, glow: RGB, panel: RGB, line: RGB, accent: RGB, text: RGB) {
        self.background = background
        self.glow = glow
        self.panel = panel
        self.line = line
        self.accent = accent
        self.text = text
    }

    init(hue: CGFloat, saturation: CGFloat, accent: RGB) {
        let s = min(max(saturation, 0.2), 0.6)
        background = RGB(h: hue, s: s * 0.45, l: 0.065)
        glow = RGB(h: hue, s: s * 0.55, l: 0.16)
        panel = RGB(h: hue, s: s * 0.42, l: 0.095)
        line = RGB(h: hue, s: s * 0.32, l: 0.155)
        text = RGB(h: hue, s: 0.25, l: 0.93)
        self.accent = accent
    }

    func mix(_ other: Theme, _ t: CGFloat) -> Theme {
        Theme(
            background: background.mix(other.background, t), glow: glow.mix(other.glow, t),
            panel: panel.mix(other.panel, t), line: line.mix(other.line, t),
            accent: accent.mix(other.accent, t), text: text.mix(other.text, t))
    }

    private struct Sample {
        let rgb: RGB
        let h: CGFloat
        let s: CGFloat
        let vivid: CGFloat
    }

    /// Reads a cover at 32 × 32. Colors fall into 24 hue bins weighted by chroma: the heaviest bin gives the
    /// ground; the accent is the heaviest bin away from it, lifted until it reads on the dark ground.
    static func palette(from image: CGImage) -> Theme {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return .neutral }

        var bins = [[Sample]](repeating: [], count: 24)
        var weights = [CGFloat](repeating: 0, count: 24)
        var chroma: CGFloat = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let rgb = RGB(r: CGFloat(pixels[i]) / 255, g: CGFloat(pixels[i + 1]) / 255, b: CGFloat(pixels[i + 2]) / 255)
            let hsl = rgb.hsl
            let vivid = hsl.s * (1 - abs(2 * hsl.l - 1))
            let bin = min(23, Int(hsl.h * 24))
            bins[bin].append(Sample(rgb: rgb, h: hsl.h, s: hsl.s, vivid: vivid))
            weights[bin] += vivid
            chroma += vivid
        }
        guard chroma / CGFloat(side * side) > 0.04,
              let base = weights.indices.max(by: { weights[$0] < weights[$1] }) else { return .neutral }

        var total: CGFloat = 0, hue: CGFloat = 0, saturation: CGFloat = 0
        for sample in bins[base] {
            total += sample.vivid
            hue += sample.h * sample.vivid
            saturation += sample.s * sample.vivid
        }
        hue /= max(total, 0.0001)
        saturation /= max(total, 0.0001)

        func score(_ bin: Int) -> CGFloat {
            let d = abs(bin - base)
            return weights[bin] * (0.35 + CGFloat(min(min(d, 24 - d), 6)) / 6)
        }
        let accentBin = weights.indices.max { score($0) < score($1) } ?? base
        let vivid = bins[accentBin].sorted { $0.vivid > $1.vivid }.prefix(max(1, bins[accentBin].count / 5))
        var mean = RGB(r: 0, g: 0, b: 0)
        for sample in vivid {
            mean.r += sample.rgb.r
            mean.g += sample.rgb.g
            mean.b += sample.rgb.b
        }
        let count = CGFloat(max(vivid.count, 1))
        let accent = RGB(r: mean.r / count, g: mean.g / count, b: mean.b / count).hsl
        return Theme(
            hue: hue, saturation: saturation,
            accent: RGB(h: accent.h, s: min(max(accent.s, 0.45), 0.85), l: min(max(accent.l, 0.68), 0.78)))
    }
}

protocol Themeable: AnyObject {
    func apply(_ theme: Theme)
}

/// Holds the current theme and fades every registered view to a new one together.
final class ThemeCenter {
    static let shared = ThemeCenter()
    static let duration: CFTimeInterval = 0.6

    private(set) var theme = Theme.neutral
    private var from = Theme.neutral
    private var to = Theme.neutral
    private var started: CFTimeInterval = 0
    private var link: CADisplayLink?
    private let observers = NSHashTable<AnyObject>.weakObjects()

    func register(_ observer: Themeable) {
        observers.add(observer)
        observer.apply(theme)
    }

    func set(_ target: Theme, animated: Bool) {
        guard target != to else { return }
        to = target
        guard animated else {
            link?.invalidate()
            link = nil
            from = target
            theme = target
            broadcast()
            return
        }
        from = theme
        started = CACurrentMediaTime()
        if link == nil {
            let link = CADisplayLink(target: self, selector: #selector(step))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    @objc private func step() {
        let t = min(1, (CACurrentMediaTime() - started) / Self.duration)
        theme = from.mix(to, CGFloat(t * t * (3 - 2 * t)))
        broadcast()
        if t >= 1 {
            link?.invalidate()
            link = nil
        }
    }

    private func broadcast() {
        for case let observer as Themeable in observers.allObjects {
            observer.apply(theme)
        }
    }
}
