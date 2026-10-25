import UIKit

/// Server, output, playback, look and library, as cards of rows in the cover's colors.
final class SettingsViewController: CardPage {

    private let server = SettingsRow(.value("Server"))
    private let download = SettingsRow(.value("Download"))
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

    init() {
        super.init(title: "Settings")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        section("SERVER", [server, download, syncNow, onServer, onPhone, autoSync, cellular], note: syncNote)
        section("OUTPUT", [device, rate], note: outputNote)
        section("PLAYBACK", [replayGain, clipping, resume])
        section("LOOK", [colors, spectrum, waveform])
        let libraryNote = UILabel()
        libraryNote.text = "Or drop files on Flaco in Finder, in your iPhone's Files tab."
        section("LIBRARY", [add, rescan], note: libraryNote)

        let settings = Settings.shared
        server.onAction = { [weak self] in self?.navigationController?.pushViewController(ServerViewController(), animated: true) }
        onServer.onAction = { [weak self] in self?.present(DownloadsViewController.sheet(), animated: true) }
        download.onAction = { [weak self] in
            guard Server.shared.isConfigured else { return }
            self?.navigationController?.pushViewController(ChooseViewController(), animated: true)
        }
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
        refresh()
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
        switch sync.selection.mode {
        case _ where !configured: download.value = "—"
        case .undecided: download.value = "CHOOSE"
        case .everything: download.value = "EVERYTHING"
        case .chosen:
            let wanted = sync.catalog.filter(sync.selection.wants)
            download.value = "\(wanted.count) SONGS · \(Sync.bytes(wanted.reduce(0) { $0 + $1.size }))"
        }
        syncNow.isEnabled = configured && sync.phase != .checking && sync.phase != .downloading
        syncNow.bar = nil
        switch sync.phase {
        case .idle:
            syncNow.value = sync.lastSynced == nil ? "" : "UP TO DATE"
            syncNote.text = !configured ? "Connect a Navidrome or other Subsonic server, and Flaco keeps a copy of its music here."
                : sync.lastSynced.map { "Synced \(Self.when($0))." } ?? ""
        case .checking:
            syncNow.value = "CHECKING"
            syncNote.text = ""
        case .downloading:
            syncNow.value = "\(Sync.bytes(sync.bytesDone)) / \(Sync.bytes(sync.bytesTotal))"
            syncNow.bar = sync.bytesTotal > 0 ? [Double(sync.bytesDone) / Double(sync.bytesTotal)] : nil
            syncNote.text = "\(Sync.rate(sync.speed)) · \(sync.filesDone) of \(sync.filesTotal) songs. Carries on with Flaco closed."
        case .failed(let message):
            syncNow.value = "FAILED"
            syncNote.text = message
        }
        onServer.value = sync.catalog.isEmpty ? "—" : "\(sync.catalog.count) TRACKS · \(Sync.bytes(sync.serverBytes))"
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
        case value(String), toggle(String), choice(String, [String]), action(String), field(String)
    }

    /// The text field of a `.field` row.
    let field = UITextField()

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
        case .field(let title):
            label.text = title
            field.font = Fonts.mono(13)
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
            addSubview(field)
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
        field.frame = CGRect(x: 104, y: 0, width: width - 104 - 8, height: height)
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
        field.textColor = theme.text.color()
        field.tintColor = theme.accent.color()
        if let placeholder = field.placeholder {
            field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: theme.faint])
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
