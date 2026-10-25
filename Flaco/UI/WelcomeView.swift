import UIKit

/// What an empty Flaco shows instead of the player: two ways to bring music in, or, while the first sync
/// fills the library, how far it has come.
final class WelcomeView: UIView {
    let settingsButton = Icon.button("slider.horizontal.3", 16, "Settings")
    let serverCard = WelcomeCard(symbol: "server.rack")
    let filesCard = WelcomeCard(symbol: "folder")
    let songsButton = UIButton(type: .system)

    private let mark = UIImageView(image: UIImage(named: "Mark"))
    private let title = UILabel(font: Fonts.text(22, .semibold), alignment: .center)
    private let footer = UILabel(font: Fonts.text(12.5), alignment: .center)
    private let amount = UILabel(font: Fonts.mono(15, .medium), alignment: .center)
    private let detail = UILabel(font: Fonts.mono(11), alignment: .center)
    private let track = UIView()
    private let fill = UIView()
    private var downloading = false
    private var fraction: CGFloat = 0
    private var theme = Theme.neutral

    override init(frame: CGRect) {
        super.init(frame: frame)
        mark.layer.cornerRadius = 17
        mark.layer.cornerCurve = .continuous
        mark.clipsToBounds = true
        filesCard.title.text = "Choose files"
        filesCard.subtitle.text = "FLAC · ALAC · WAV · AIFF · MP3"
        footer.text = "Or drop files on Flaco in Finder."
        songsButton.setTitle("See every song", for: .normal)
        songsButton.titleLabel?.font = Fonts.text(15)
        track.layer.cornerRadius = 2
        track.clipsToBounds = true
        track.addSubview(fill)
        for view in [mark, title, serverCard, filesCard, footer, amount, detail, track, songsButton, settingsButton] as [UIView] {
            addSubview(view)
        }
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Follows the server and the sync.
    func refresh() {
        let sync = Sync.shared
        let server = Server.shared
        downloading = sync.phase == .checking || sync.phase == .downloading
        title.text = downloading ? "Downloading your music" : "Add your music"
        if server.isConfigured {
            serverCard.title.text = server.host
            if case .failed(let message) = sync.phase {
                serverCard.subtitle.text = message.uppercased()
            } else if sync.selection.mode == .undecided {
                serverCard.subtitle.text = "CHOOSE WHAT TO DOWNLOAD"
            } else {
                serverCard.subtitle.text = sync.catalog.isEmpty ? "NO MUSIC ON THE SERVER YET" : "TAP TO SYNC"
            }
        } else {
            serverCard.title.text = "Connect a server"
            serverCard.subtitle.text = "NAVIDROME · SUBSONIC"
        }
        if sync.phase == .downloading {
            amount.text = "\(Sync.bytes(sync.bytesDone)) of \(Sync.bytes(sync.bytesTotal))"
            detail.text = "\(Sync.rate(sync.speed).uppercased()) · \(sync.filesDone) OF \(sync.filesTotal) SONGS"
            fraction = sync.bytesTotal > 0 ? CGFloat(min(Double(sync.bytesDone) / Double(sync.bytesTotal), 1)) : 0
        } else {
            amount.text = "Checking \(server.host)"
            detail.text = ""
            fraction = 0
        }
        for view in [serverCard, filesCard, footer] as [UIView] { view.isHidden = downloading }
        for view in [amount, detail, track, songsButton] as [UIView] { view.isHidden = !downloading }
        songsButton.isHidden = sync.phase != .downloading
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let top = safeAreaInsets.top
        settingsButton.frame = CGRect(x: width - 46, y: top + 4, width: 44, height: 44)

        // The block sits a little above the middle.
        let blockHeight: CGFloat = downloading ? 76 + 24 + 30 + 28 + 22 + 30 + 44 : 76 + 24 + 30 + 28 + 72 + 12 + 72 + 20 + 16
        var y = max(top + 56, (bounds.height - blockHeight) / 2 - 24)
        mark.frame = CGRect(x: (width - 76) / 2, y: y, width: 76, height: 76)
        y += 76 + 24
        title.frame = CGRect(x: 16, y: y, width: width - 32, height: 30)
        y += 30 + 28
        if downloading {
            amount.frame = CGRect(x: 16, y: y, width: width - 32, height: 22)
            y += 22 + 6
            detail.frame = CGRect(x: 16, y: y, width: width - 32, height: 16)
            y += 16 + 18
            track.frame = CGRect(x: 32, y: y, width: width - 64, height: 4)
            fill.frame = CGRect(x: 0, y: 0, width: track.bounds.width * fraction, height: 4)
            y += 4 + 20
            songsButton.frame = CGRect(x: 16, y: y, width: width - 32, height: 44)
        } else {
            serverCard.frame = CGRect(x: 16, y: y, width: width - 32, height: 72)
            y += 72 + 12
            filesCard.frame = CGRect(x: 16, y: y, width: width - 32, height: 72)
            y += 72 + 20
            footer.frame = CGRect(x: 16, y: y, width: width - 32, height: 16)
        }
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        title.textColor = theme.text.color()
        footer.textColor = theme.secondary
        amount.textColor = theme.text.color()
        detail.textColor = theme.secondary
        track.backgroundColor = theme.line.color()
        fill.backgroundColor = theme.accent.color()
        songsButton.tintColor = theme.accent.color()
        settingsButton.tintColor = theme.text.color()
        serverCard.apply(theme)
        filesCard.apply(theme)
    }
}

/// One of the welcome's choices: a glass panel with a symbol, a name and a mono line under it.
final class WelcomeCard: UIControl {
    let title = UILabel(font: Fonts.text(15.5, .semibold))
    let subtitle = UILabel(font: Fonts.mono(10.5))

    private let glass = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let tintLayer = UIView()
    private let symbol: UIImageView
    private let chevron = UIImageView(image: Icon.image("chevron.right", 12, .semibold))

    init(symbol name: String) {
        symbol = UIImageView(image: Icon.image(name, 19))
        super.init(frame: .zero)
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderWidth = UIView.hairline
        clipsToBounds = true
        symbol.contentMode = .center
        chevron.contentMode = .center
        for view in [glass, tintLayer, symbol, title, subtitle, chevron] as [UIView] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        glass.frame = bounds
        tintLayer.frame = bounds
        symbol.frame = CGRect(x: 14, y: 18, width: 36, height: 36)
        title.frame = CGRect(x: 62, y: 16, width: width - 62 - 40, height: 21)
        subtitle.frame = CGRect(x: 62, y: 39, width: width - 62 - 40, height: 15)
        chevron.frame = CGRect(x: width - 34, y: 0, width: 20, height: bounds.height)
        accessibilityLabel = [title.text, subtitle.text?.lowercased()].compactMap { $0 }.joined(separator: ", ")
    }

    func apply(_ theme: Theme) {
        tintLayer.backgroundColor = theme.panel.color().withAlphaComponent(0.45)
        layer.borderColor = theme.text.color(0.1).cgColor
        symbol.tintColor = theme.accent.color()
        title.textColor = theme.text.color()
        subtitle.textColor = theme.secondary
        chevron.tintColor = theme.faint
    }
}
