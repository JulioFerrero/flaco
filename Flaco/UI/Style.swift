import UIKit

enum Fonts {
    static func text(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        .systemFont(ofSize: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }
}

enum Icon {
    static func image(_ name: String, _ size: CGFloat, _ weight: UIImage.SymbolWeight = .regular) -> UIImage? {
        UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: weight))
    }

    static func button(_ name: String, _ size: CGFloat, _ label: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(image(name, size), for: .normal)
        button.accessibilityLabel = label
        return button
    }
}

extension UILabel {
    convenience init(font: UIFont, alignment: NSTextAlignment = .natural) {
        self.init()
        self.font = font
        textAlignment = alignment
    }
}

extension UIView {
    /// One device pixel.
    static var hairline: CGFloat { 1 / UIScreen.main.scale }
}

/// The cover's main hue as a soft wash at the top of the screen, fading into the ground.
final class GlowView: UIView {
    private let fade = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        fade.colors = [UIColor.black.cgColor, UIColor.clear.cgColor]
        layer.mask = fade
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fade.frame = bounds
    }
}

/// A pill-shaped mono chip, for facets and filters.
final class ChipButton: UIButton {
    var isOn = false { didSet { restyle() } }
    private var theme = Theme.neutral

    init(_ title: String) {
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        titleLabel?.font = Fonts.mono(10.5)
        layer.cornerRadius = 13
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The chip is drawn 26 pt tall inside a 44 pt touch target.
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let width = (title(for: .normal) as NSString?)?.size(withAttributes: [.font: Fonts.mono(10.5)]).width ?? 0
        return CGSize(width: ceil(width) + 20, height: 26)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -2, dy: -9).contains(point)
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        restyle()
    }

    private func restyle() {
        backgroundColor = isOn ? theme.tint : .clear
        setTitleColor(isOn ? theme.accent.color() : theme.secondary, for: .normal)
    }
}
