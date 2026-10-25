import UIKit

/// Output, playback, look and library, as cards of rows in the cover's colors.
final class SettingsViewController: UIViewController, Themeable {
    private let scroll = UIScrollView()
    private let glow = GlowView()
    private let back = Icon.button("chevron.left", 18, "Back")
    private let heading = UILabel(font: Fonts.text(17, .semibold))
    private var cards: [SettingsCard] = []
    private var labels: [UILabel] = []
    private var notes: [UILabel] = []
    private var theme = Theme.neutral

    private let device = SettingsRow(.value("Device"))
    private let rate = SettingsRow(.value("Output rate"))
    private let replayGain = SettingsRow(.choice("ReplayGain", ReplayGainMode.allCases.map { $0.rawValue.uppercased() }))
    private let clipping = SettingsRow(.toggle("Prevent clipping"))
    private let resume = SettingsRow(.toggle("Resume on launch"))
    private let colors = SettingsRow(.toggle("Colors from cover"))
    private let spectrum = SettingsRow(.choice("Spectrum", SpectrumStyle.allCases.map { $0.rawValue.uppercased() }))
    private let waveform = SettingsRow(.toggle("Waveform seekbar"))
    private let add = SettingsRow(.action("Add music"))
    private let rescan = SettingsRow(.action("Rescan library"))
    private let outputNote = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(glow)
        scroll.alwaysBounceVertical = true
        scroll.indicatorStyle = .white
        view.addSubview(scroll)
        back.addAction(UIAction { [weak self] _ in self?.navigationController?.popViewController(animated: true) }, for: .touchUpInside)
        heading.text = "Settings"
        scroll.addSubview(back)
        scroll.addSubview(heading)

        section("OUTPUT", [device, rate], note: outputNote)
        section("PLAYBACK", [replayGain, clipping, resume])
        section("LOOK", [colors, spectrum, waveform])
        let libraryNote = UILabel()
        libraryNote.text = "Or drop files on Flaco in Finder, in your iPhone's Files tab."
        section("LIBRARY", [add, rescan], note: libraryNote)

        let settings = Settings.shared
        replayGain.onChoice = { settings.replayGain = ReplayGainMode.allCases[$0] }
        clipping.onToggle = { settings.preventClipping = $0 }
        resume.onToggle = { settings.resume = $0 }
        colors.onToggle = { settings.coverColors = $0 }
        spectrum.onChoice = { settings.spectrum = SpectrumStyle.allCases[$0] }
        waveform.onToggle = { settings.waveform = $0 }
        add.onAction = { [weak self] in
            guard let self else { return }
            Importer.present(from: self)
        }
        rescan.onAction = { Library.shared.scan() }

        let center = NotificationCenter.default
        for name in [Settings.didChange, Library.didChange, Player.didChange] {
            center.addObserver(self, selector: #selector(refresh), name: name, object: nil)
        }
        ThemeCenter.shared.register(self)
        refresh()
    }

    private func section(_ title: String, _ rows: [SettingsRow], note: UILabel? = nil) {
        let label = UILabel(font: Fonts.mono(10.5))
        label.attributedText = NSAttributedString(string: title, attributes: [.kern: 1.0])
        labels.append(label)
        scroll.addSubview(label)
        let card = SettingsCard(rows: rows)
        cards.append(card)
        scroll.addSubview(card)
        if let note {
            note.font = Fonts.text(12.5)
            note.numberOfLines = 0
            note.tag = cards.count - 1
            notes.append(note)
            scroll.addSubview(note)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        glow.frame = CGRect(x: 0, y: 0, width: width, height: 300)
        scroll.frame = view.bounds
        let top = view.safeAreaInsets.top + 4
        back.frame = CGRect(x: 4, y: top, width: 44, height: 44)
        heading.frame = CGRect(x: 48, y: top, width: 200, height: 44)
        var y = top + 44
        for (i, card) in cards.enumerated() {
            y += 20
            labels[i].frame = CGRect(x: 16, y: y, width: width - 32, height: 14)
            y += 22
            let height = CGFloat(card.rows.count) * 48
            card.frame = CGRect(x: 12, y: y, width: width - 24, height: height)
            y += height
            if let note = notes.first(where: { $0.tag == i }) {
                let size = note.sizeThatFits(CGSize(width: width - 32, height: 200))
                note.frame = CGRect(x: 16, y: y + 8, width: width - 32, height: ceil(size.height))
                y += 8 + ceil(size.height)
            }
        }
        scroll.contentSize = CGSize(width: width, height: y + 32)
    }

    @objc private func refresh() {
        let settings = Settings.shared
        let player = Player.shared
        device.value = player.outputName
        rate.value = "\(Track.kilohertz(player.outputSampleRate)) kHz"
        outputNote.text = "Files above \(Track.kilohertz(player.outputSampleRate)) kHz are resampled to the iPhone's output."
        replayGain.selected = ReplayGainMode.allCases.firstIndex(of: settings.replayGain) ?? 0
        clipping.isOn = settings.preventClipping
        resume.isOn = settings.resume
        colors.isOn = settings.coverColors
        spectrum.selected = SpectrumStyle.allCases.firstIndex(of: settings.spectrum) ?? 0
        waveform.isOn = settings.waveform
        rescan.value = Library.shared.isScanning ? "SCANNING" : "\(Library.shared.tracks.count) TRACKS"
        view.setNeedsLayout()
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        view.backgroundColor = theme.background.color()
        glow.backgroundColor = theme.glow.color()
        back.tintColor = theme.text.color()
        heading.textColor = theme.text.color()
        for label in labels { label.textColor = theme.secondary }
        for note in notes { note.textColor = theme.secondary }
        for card in cards { card.apply(theme) }
    }
}

final class SettingsCard: UIView {
    let rows: [SettingsRow]
    private var lines: [UIView] = []

    init(rows: [SettingsRow]) {
        self.rows = rows
        super.init(frame: .zero)
        layer.cornerRadius = 8
        layer.borderWidth = UIView.hairline
        clipsToBounds = true
        for (i, row) in rows.enumerated() {
            addSubview(row)
            if i > 0 {
                let line = UIView()
                lines.append(line)
                addSubview(line)
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (i, row) in rows.enumerated() {
            row.frame = CGRect(x: 0, y: CGFloat(i) * 48, width: bounds.width, height: 48)
            if i > 0 { lines[i - 1].frame = CGRect(x: 0, y: CGFloat(i) * 48, width: bounds.width, height: UIView.hairline) }
        }
    }

    func apply(_ theme: Theme) {
        backgroundColor = theme.panel.color()
        layer.borderColor = theme.line.color().cgColor
        for line in lines { line.backgroundColor = theme.line.color() }
        for row in rows { row.apply(theme) }
    }
}

final class SettingsRow: UIView {
    enum Kind {
        case value(String), toggle(String), choice(String, [String]), action(String)
    }

    var onToggle: ((Bool) -> Void)?
    var onChoice: ((Int) -> Void)?
    var onAction: (() -> Void)?

    var value: String? {
        get { valueLabel.text }
        set { valueLabel.text = newValue; setNeedsLayout() }
    }

    var isOn: Bool {
        get { toggle.isOn }
        set { toggle.isOn = newValue }
    }

    var selected = 0 { didSet { restyle() } }

    private let kind: Kind
    private let label = UILabel(font: Fonts.text(14.5))
    private let valueLabel = UILabel(font: Fonts.mono(11.5), alignment: .right)
    private let toggle = UISwitch()
    private var options: [ChipButton] = []
    private let button = UIButton(type: .custom)
    private var theme = Theme.neutral

    init(_ kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        addSubview(label)
        switch kind {
        case .value(let title):
            label.text = title
            addSubview(valueLabel)
        case .toggle(let title):
            label.text = title
            toggle.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.onToggle?(self.toggle.isOn)
            }, for: .valueChanged)
            addSubview(toggle)
        case .choice(let title, let names):
            label.text = title
            options = names.map { ChipButton($0) }
            for (i, option) in options.enumerated() {
                option.layer.cornerRadius = 5
                option.addAction(UIAction { [weak self] _ in
                    self?.selected = i
                    self?.onChoice?(i)
                }, for: .touchUpInside)
                addSubview(option)
            }
        case .action(let title):
            label.text = title
            addSubview(valueLabel)
            button.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .touchUpInside)
            addSubview(button)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width, height = bounds.height
        label.frame = CGRect(x: 14, y: 0, width: width * 0.55, height: height)
        valueLabel.frame = CGRect(x: width * 0.4, y: 0, width: width * 0.6 - 14, height: height)
        toggle.frame.origin = CGPoint(x: width - 14 - toggle.bounds.width, y: (height - toggle.bounds.height) / 2)
        button.frame = bounds
        var x = width - 8
        for option in options.reversed() {
            let size = option.sizeThatFits(.zero)
            x -= size.width
            option.frame = CGRect(x: x, y: (height - size.height) / 2, width: size.width, height: size.height)
            x -= 2
        }
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        restyle()
    }

    private func restyle() {
        if case .action = kind {
            label.textColor = theme.accent.color()
        } else {
            label.textColor = theme.text.color()
        }
        valueLabel.textColor = theme.secondary
        toggle.onTintColor = theme.accent.color()
        for (i, option) in options.enumerated() {
            option.isOn = i == selected
            option.apply(theme)
        }
    }
}
