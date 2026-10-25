import UIKit

/// Server, output, playback, look and library, as cards of rows in the cover's colors.
final class SettingsViewController: UIViewController, Themeable {
    private let scroll = UIScrollView()
    private let glow = GlowView()
    private let topBar = UIView()
    private let topLine = UIView()
    private let back = Icon.button("chevron.left", 18, "Back")
    private let heading = UILabel(font: Fonts.text(17, .semibold))
    private var cards: [SettingsCard] = []
    private var labels: [UILabel] = []
    private var notes: [UILabel] = []
    private var theme = Theme.neutral

    private let server = SettingsRow(.value("Server"))
    private let syncNow = SettingsRow(.action("Sync now"))
    private let onServer = SettingsRow(.value("On server"))
    private let onPhone = SettingsRow(.value("On this phone"))
    private let autoSync = SettingsRow(.toggle("Sync when opened"))
    private let cellular = SettingsRow(.toggle("Download on cellular"))
    private let syncNote = UILabel()
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
        // Fixed above the scrolling cards, so they pass under it rather than under the status bar.
        view.addSubview(topBar)
        topBar.addSubview(back)
        topBar.addSubview(heading)
        topBar.addSubview(topLine)
        scroll.delegate = self

        section("SERVER", [server, syncNow, onServer, onPhone, autoSync, cellular], note: syncNote)
        section("OUTPUT", [device, rate], note: outputNote)
        section("PLAYBACK", [replayGain, clipping, resume])
        section("LOOK", [colors, spectrum, waveform])
        let libraryNote = UILabel()
        libraryNote.text = "Or drop files on Flaco in Finder, in your iPhone's Files tab."
        section("LIBRARY", [add, rescan], note: libraryNote)

        let settings = Settings.shared
        server.onAction = { [weak self] in self?.editServer() }
        syncNow.onAction = { Sync.shared.start() }
        autoSync.onToggle = { settings.autoSync = $0 }
        cellular.onToggle = { settings.cellular = $0 }
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
        for name in [Settings.didChange, Library.didChange, Player.didChange, Sync.didChange] {
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
        refreshSync()
        device.value = player.outputName
        rate.value = "\(Track.kilohertz(player.outputSampleRate)) kHz"
        outputNote.text = "Files play at their own rate where the output allows it, and are resampled otherwise."
        replayGain.selected = ReplayGainMode.allCases.firstIndex(of: settings.replayGain) ?? 0
        clipping.isOn = settings.preventClipping
        resume.isOn = settings.resume
        colors.isOn = settings.coverColors
        spectrum.selected = SpectrumStyle.allCases.firstIndex(of: settings.spectrum) ?? 0
        waveform.isOn = settings.waveform
        rescan.value = Library.shared.isScanning ? "SCANNING" : "\(Library.shared.tracks.count) TRACKS"
        view.setNeedsLayout()
    }

    private func refreshSync() {
        let sync = Sync.shared
        let configured = Server.shared.isConfigured
        server.value = configured ? Server.shared.host : "SET UP"
        syncNow.isEnabled = configured && sync.phase != .checking
        syncNow.bar = nil
        switch sync.phase {
        case .idle:
            syncNow.value = sync.lastSynced == nil ? "" : "UP TO DATE"
            syncNote.text = sync.lastSynced.map { "Synced \(Self.when($0))." }
                ?? (configured ? "" : "Connect a Navidrome or Subsonic server to keep your music in step with it.")
        case .checking:
            syncNow.value = "CHECKING"
        case .downloading:
            syncNow.value = "\(sync.filesDone) / \(sync.filesTotal)"
            syncNow.bar = sync.bytesTotal > 0 ? [Double(sync.bytesDone) / Double(sync.bytesTotal)] : nil
            syncNote.text = "Downloading \(Sync.bytes(sync.bytesDone)) of \(Sync.bytes(sync.bytesTotal)). It carries on with Flaco closed."
        case .failed(let message):
            syncNow.value = "FAILED"
            syncNote.text = message
        }
        onServer.value = sync.server.map { "\($0.tracks) TRACKS · \(Sync.bytes($0.bytes))" } ?? "—"
        let music = Library.shared.tracks.reduce(0) { $0 + $1.size }
        let free = Sync.freeSpace, capacity = Sync.capacity
        onPhone.value = "\(Sync.bytes(music)) · \(Sync.bytes(free)) FREE"
        // Flaco's music, then everything else on the phone; the rest of the track is free space.
        onPhone.bar = capacity > 0 ? [Double(music) / Double(capacity), Double(max(capacity - free - music, 0)) / Double(capacity)] : nil
        autoSync.isOn = Settings.shared.autoSync
        cellular.isOn = Settings.shared.cellular
    }

    private static func when(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "'at' HH:mm" : "d MMM 'at' HH:mm"
        return formatter.string(from: date)
    }

    private func editServer() {
        let current = Server.shared
        let alert = UIAlertController(title: "Music server", message: current.isConfigured ? "Leave the password empty to keep the saved one." : nil, preferredStyle: .alert)
        alert.addTextField {
            $0.placeholder = "music.example.com"
            $0.text = current.address
            $0.keyboardType = .URL
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
        }
        alert.addTextField {
            $0.placeholder = "User"
            $0.text = current.user
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
        }
        alert.addTextField {
            $0.placeholder = "Password"
            $0.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Connect", style: .default) { [weak alert] _ in
            guard let fields = alert?.textFields, fields.count == 3 else { return }
            let password = fields[2].text ?? ""
            current.connect(address: fields[0].text ?? "", user: fields[1].text ?? "", password: password.isEmpty ? nil : password)
            Sync.shared.start()
            NotificationCenter.default.post(name: Sync.didChange, object: nil)
        })
        present(alert, animated: true)
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

extension SettingsViewController: UIScrollViewDelegate {
    /// The bar's line shows once something has scrolled under it.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        topLine.alpha = scrollView.contentOffset.y > 1 ? 1 : 0
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

    var height: CGFloat { rows.reduce(0) { $0 + $1.height } }

    override func layoutSubviews() {
        super.layoutSubviews()
        var y: CGFloat = 0
        for (i, row) in rows.enumerated() {
            row.frame = CGRect(x: 0, y: y, width: bounds.width, height: row.height)
            if i > 0 { lines[i - 1].frame = CGRect(x: 0, y: y, width: bounds.width, height: UIView.hairline) }
            y += row.height
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
    var onAction: (() -> Void)? { didSet { restyle() } }

    var isEnabled = true {
        didSet {
            button.isEnabled = isEnabled
            label.alpha = isEnabled ? 1 : 0.4
        }
    }

    /// A thin bar under the row, filled left to right by these fractions in turn.
    var bar: [Double]? {
        didSet {
            if (bar == nil) != (oldValue == nil) { superview?.superview?.setNeedsLayout() }
            barTrack.isHidden = bar == nil
            setNeedsLayout()
        }
    }

    var height: CGFloat { bar == nil ? 48 : 60 }

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
    private let barTrack = UIView()
    private let barFills = [UIView(), UIView()]
    private var theme = Theme.neutral

    init(_ kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        addSubview(label)
        barTrack.isHidden = true
        barTrack.layer.cornerRadius = 1.5
        barTrack.clipsToBounds = true
        barFills.forEach(barTrack.addSubview)
        addSubview(barTrack)
        switch kind {
        case .value(let title):
            label.text = title
            addSubview(valueLabel)
            button.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .touchUpInside)
            addSubview(button)
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
        let width = bounds.width
        let height = bar == nil ? bounds.height : 44
        label.frame = CGRect(x: 14, y: 0, width: width * 0.55, height: height)
        valueLabel.frame = CGRect(x: width * 0.4, y: 0, width: width * 0.6 - 14, height: height)
        barTrack.frame = CGRect(x: 14, y: 44, width: width - 28, height: 3)
        var filled: CGFloat = 0
        for (i, fill) in barFills.enumerated() {
            let value = bar.map { i < $0.count ? $0[i] : 0 } ?? 0
            let fraction = CGFloat(min(max(value, 0), 1))
            fill.frame = CGRect(x: filled, y: 0, width: barTrack.bounds.width * fraction, height: 3)
            filled += fill.frame.width
        }
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
        if case .value = kind, onAction != nil {
            valueLabel.textColor = theme.accent.color()
        } else {
            valueLabel.textColor = theme.secondary
        }
        barTrack.backgroundColor = theme.line.color()
        barFills[0].backgroundColor = theme.accent.color()
        barFills[1].backgroundColor = theme.text.color(0.3)
        toggle.onTintColor = theme.accent.color()
        for (i, option) in options.enumerated() {
            option.isOn = i == selected
            option.apply(theme)
        }
    }
}
