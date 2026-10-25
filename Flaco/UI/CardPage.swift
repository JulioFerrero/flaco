import UIKit

/// A pushed screen of titled cards under a fixed top bar, in the cover's colors: Settings and the server setup.
class CardPage: UIViewController, Themeable {
    let scroll = UIScrollView()
    private(set) var theme = Theme.neutral

    private let glow = GlowView()
    private let topBar = UIView()
    private let topLine = UIView()
    private let back = Icon.button("chevron.left", 18, "Back")
    private let heading = UILabel(font: Fonts.text(17, .semibold))
    private var cards: [SettingsCard] = []
    private var labels: [UILabel] = []
    private var notes: [UILabel] = []

    /// Where the space under the top bar starts, for pages that lay out their own content.
    var contentTop: CGFloat { scroll.frame.minY }

    init(title: String) {
        super.init(nibName: nil, bundle: nil)
        heading.text = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(glow)
        scroll.alwaysBounceVertical = true
        scroll.indicatorStyle = .white
        scroll.keyboardDismissMode = .interactive
        scroll.delegate = self
        view.addSubview(scroll)
        back.addAction(UIAction { [weak self] _ in self?.navigationController?.popViewController(animated: true) }, for: .touchUpInside)
        // Fixed above the scrolling cards, so they pass under it rather than under the status bar.
        view.addSubview(topBar)
        topBar.addSubview(back)
        topBar.addSubview(heading)
        topBar.addSubview(topLine)
        ThemeCenter.shared.register(self)
    }

    /// Adds a titled card; the note, if any, sits under it and may change length.
    func section(_ title: String, _ rows: [SettingsRow], note: UILabel? = nil) {
        let label = UILabel(font: Fonts.mono(10.5))
        label.attributedText = NSAttributedString(string: title, attributes: [.kern: 1.0])
        label.textColor = theme.secondary
        labels.append(label)
        scroll.addSubview(label)
        let card = SettingsCard(rows: rows)
        cards.append(card)
        scroll.addSubview(card)
        if let note {
            note.font = Fonts.text(12.5)
            note.numberOfLines = 0
            note.tag = cards.count - 1
            note.textColor = theme.secondary
            notes.append(note)
            scroll.addSubview(note)
        }
        card.apply(theme)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        glow.frame = CGRect(x: 0, y: 0, width: width, height: 300)
        let top = view.safeAreaInsets.top + 4
        topBar.frame = CGRect(x: 0, y: 0, width: width, height: top + 44)
        back.frame = CGRect(x: 4, y: top, width: 44, height: 44)
        heading.frame = CGRect(x: 48, y: top, width: 200, height: 44)
        topLine.frame = CGRect(x: 0, y: topBar.bounds.height - UIView.hairline, width: width, height: UIView.hairline)
        scroll.frame = CGRect(x: 0, y: topBar.frame.maxY, width: width, height: view.bounds.height - topBar.frame.maxY)
        var y: CGFloat = -8
        for (i, card) in cards.enumerated() {
            y += 20
            labels[i].frame = CGRect(x: 16, y: y, width: width - 32, height: 14)
            y += 22
            let height = card.height
            card.frame = CGRect(x: 12, y: y, width: width - 24, height: height)
            card.setNeedsLayout()
            y += height
            if let note = notes.first(where: { $0.tag == i }), !(note.text ?? "").isEmpty {
                let size = note.sizeThatFits(CGSize(width: width - 32, height: 200))
                note.frame = CGRect(x: 16, y: y + 8, width: width - 32, height: ceil(size.height))
                y += 8 + ceil(size.height)
            }
        }
        scroll.contentSize = CGSize(width: width, height: y + 32)
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        view.backgroundColor = theme.background.color()
        glow.backgroundColor = theme.glow.color()
        topBar.backgroundColor = theme.glow.mix(theme.background, 0.12).color()
        topLine.backgroundColor = theme.line.color()
        back.tintColor = theme.text.color()
        heading.textColor = theme.text.color()
        for label in labels { label.textColor = theme.secondary }
        for note in notes { note.textColor = theme.secondary }
        for card in cards { card.apply(theme) }
    }
}

extension CardPage: UIScrollViewDelegate {
    /// The bar's line shows once something has scrolled under it.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        topLine.alpha = scrollView.contentOffset.y > 1 ? 1 : 0
    }
}
