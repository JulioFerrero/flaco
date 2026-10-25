import UIKit

/// Playlist tabs in mono with an accent underline, and the search and settings buttons.
final class TabsBar: UIView {
    enum Tab {
        case all, library
    }

    let allButton = TabsBar.tab("All")
    let libraryButton = TabsBar.tab("Library")
    let searchButton = Icon.button("magnifyingglass", 16, "Search")
    let settingsButton = Icon.button("slider.horizontal.3", 16, "Settings")
    var selected = Tab.all { didSet { restyle() } }

    private let underline = UIView()
    private let line = UIView()
    private var theme = Theme.neutral

    private static func tab(_ title: String) -> UIButton {
        let button = UIButton(type: .custom)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = Fonts.mono(11)
        return button
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        for view in [allButton, libraryButton, searchButton, settingsButton, underline, line] as [UIView] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var x: CGFloat = 2
        for button in [allButton, libraryButton] {
            let width = ceil(button.titleLabel?.intrinsicContentSize.width ?? 0) + 20
            button.frame = CGRect(x: x, y: 0, width: width, height: 44)
            x += width
        }
        settingsButton.frame = CGRect(x: bounds.width - 46, y: 0, width: 44, height: 44)
        searchButton.frame = CGRect(x: bounds.width - 90, y: 0, width: 44, height: 44)
        let active = selected == .all ? allButton : libraryButton
        underline.frame = CGRect(x: active.frame.minX, y: 42, width: active.frame.width, height: 2)
        line.frame = CGRect(x: 0, y: 44, width: bounds.width, height: UIView.hairline)
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        restyle()
    }

    private func restyle() {
        allButton.setTitleColor(selected == .all ? theme.text.color() : theme.secondary, for: .normal)
        libraryButton.setTitleColor(selected == .library ? theme.text.color() : theme.secondary, for: .normal)
        searchButton.tintColor = theme.text.color()
        settingsButton.tintColor = theme.text.color()
        underline.backgroundColor = theme.accent.color()
        line.backgroundColor = theme.line.color()
        setNeedsLayout()
    }
}

/// The search field that takes the tabs' place while searching.
final class SearchBar: UIView {
    let field = UITextField()
    let cancelButton = UIButton(type: .system)
    private let icon = UIImageView(image: Icon.image("magnifyingglass", 14, .medium))

    override init(frame: CGRect) {
        super.init(frame: frame)
        field.font = Fonts.text(15)
        field.placeholder = "Artists, albums, songs"
        field.returnKeyType = .search
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.clearButtonMode = .whileEditing
        field.layer.cornerRadius = 8
        field.layer.borderWidth = UIView.hairline
        field.accessibilityLabel = "Search your library"
        let holder = UIView(frame: CGRect(x: 0, y: 0, width: 34, height: 40))
        icon.frame = CGRect(x: 11, y: 12, width: 16, height: 16)
        icon.contentMode = .center
        holder.addSubview(icon)
        field.leftView = holder
        field.leftViewMode = .always
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = Fonts.text(15)
        addSubview(field)
        addSubview(cancelButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let cancelWidth: CGFloat = 70
        field.frame = CGRect(x: 12, y: 2, width: bounds.width - 12 - cancelWidth, height: 40)
        cancelButton.frame = CGRect(x: bounds.width - cancelWidth, y: 0, width: cancelWidth, height: 44)
    }

    func apply(_ theme: Theme) {
        field.backgroundColor = theme.panel.color()
        field.layer.borderColor = theme.line.color().cgColor
        field.textColor = theme.text.color()
        field.tintColor = theme.accent.color()
        field.attributedPlaceholder = NSAttributedString(
            string: "Artists, albums, songs", attributes: [.foregroundColor: theme.text.color(0.45)])
        icon.tintColor = theme.secondary
        cancelButton.tintColor = theme.accent.color()
    }
}

/// Transport buttons in foobar's order, with the format and time in a mono status line underneath.
final class TransportBar: UIView {
    static let height: CGFloat = 84

    let stopButton = Icon.button("stop.fill", 15, "Stop")
    let previousButton = Icon.button("backward.end.fill", 17, "Previous")
    let playButton = Icon.button("play.fill", 21, "Play")
    let nextButton = Icon.button("forward.end.fill", 17, "Next")
    let queueButton = Icon.button("list.bullet", 16, "Queue")
    let shuffleButton = Icon.button("shuffle", 15, "Shuffle")
    let repeatButton = Icon.button("repeat", 15, "Repeat")

    private let status = UILabel(font: Fonts.mono(10))
    private let time = UILabel(font: Fonts.mono(10), alignment: .right)
    private let line = UIView()
    private var theme = Theme.neutral
    private var isPlaying = false
    private var shuffle = false
    private var repeatMode = RepeatMode.off
    private var shownTime = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        for view in [line, stopButton, previousButton, playButton, nextButton, queueButton, shuffleButton, repeatButton, status, time] as [UIView] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        line.frame = CGRect(x: 0, y: 0, width: width, height: UIView.hairline)
        for (i, button) in [stopButton, previousButton, playButton, nextButton].enumerated() {
            button.frame = CGRect(x: 4 + CGFloat(i) * 44, y: 6, width: 44, height: 44)
        }
        for (i, button) in [repeatButton, shuffleButton, queueButton].enumerated() {
            button.frame = CGRect(x: width - 48 - CGFloat(i) * 44, y: 6, width: 44, height: 44)
        }
        status.frame = CGRect(x: 12, y: 54, width: width - 130, height: 22)
        time.frame = CGRect(x: width - 132, y: 54, width: 120, height: 22)
    }

    func show(_ track: Track?, playing: Bool, shuffle: Bool, repeatMode: RepeatMode) {
        status.text = track?.status ?? ""
        isPlaying = playing
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        playButton.setImage(Icon.image(playing ? "pause.fill" : "play.fill", 21), for: .normal)
        playButton.accessibilityLabel = playing ? "Pause" : "Play"
        repeatButton.setImage(Icon.image(repeatMode == .one ? "repeat.1" : "repeat", 15), for: .normal)
        repeatButton.accessibilityValue = repeatMode.rawValue
        shuffleButton.accessibilityValue = shuffle ? "on" : "off"
        restyle()
    }

    func setTime(_ position: Double, _ duration: Double) {
        let text = duration > 0 ? "\(position.clock) / \(duration.clock)" : ""
        guard text != shownTime else { return }
        shownTime = text
        time.text = text
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        restyle()
    }

    private func restyle() {
        backgroundColor = theme.panel.color()
        line.backgroundColor = theme.line.color()
        for button in [stopButton, previousButton, nextButton, queueButton] {
            button.tintColor = theme.text.color()
        }
        playButton.tintColor = theme.accent.color()
        shuffleButton.tintColor = shuffle ? theme.accent.color() : theme.secondary
        repeatButton.tintColor = repeatMode == .off ? theme.secondary : theme.accent.color()
        status.textColor = theme.secondary
        time.textColor = theme.text.color()
    }
}
