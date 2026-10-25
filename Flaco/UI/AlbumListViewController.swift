import UIKit

/// The whole library as one playlist, album by album: each cover on the left with its tracks beside it.
/// Playing a track carries on into the albums after it.
final class AlbumListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, Themeable {
    var onImport: (() -> Void)?
    var onConnect: (() -> Void)?
    var onShowDownloads: (() -> Void)?

    private let table = UITableView(frame: .zero, style: .plain)
    private let empty = EmptyLibraryView()
    private var albums: [Album] = []
    private var theme = Theme.neutral

    override func viewDidLoad() {
        super.viewDidLoad()
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.indicatorStyle = .white
        table.estimatedRowHeight = 0
        table.contentInset.bottom = 16
        table.register(AlbumCell.self, forCellReuseIdentifier: AlbumCell.reuse)
        table.frame = view.bounds
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(table)

        empty.frame = view.bounds
        empty.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        empty.button.addTarget(self, action: #selector(importTapped), for: .touchUpInside)
        empty.secondButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            Server.shared.isConfigured ? self.onShowDownloads?() : self.onConnect?()
        }, for: .touchUpInside)
        view.addSubview(empty)

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(reload), name: Library.didChange, object: nil)
        center.addObserver(self, selector: #selector(refreshCurrent), name: Player.didChange, object: nil)
        center.addObserver(self, selector: #selector(refreshEmpty), name: Sync.didChange, object: nil)
        ThemeCenter.shared.register(self)
        reload()
    }

    @objc private func reload() {
        albums = Library.shared.albums
        table.reloadData()
        empty.isHidden = !albums.isEmpty
        refreshEmpty()
    }

    @objc private func refreshEmpty() {
        guard !empty.isHidden else { return }
        let sync = Sync.shared
        switch sync.phase {
        case .checking:
            empty.show(scanning: Library.shared.isScanning, sync: "Checking the server…")
        case .downloading:
            empty.show(scanning: false, sync: "\(Sync.bytes(sync.bytesDone)) of \(Sync.bytes(sync.bytesTotal)) · \(Sync.rate(sync.speed))")
        default:
            empty.show(scanning: Library.shared.isScanning, sync: nil)
        }
    }

    @objc private func refreshCurrent() {
        let path = Player.shared.current?.path
        for case let cell as AlbumCell in table.visibleCells {
            cell.setCurrent(path)
        }
    }

    @objc private func importTapped() {
        onImport?()
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        for case let cell as AlbumCell in table.visibleCells {
            cell.apply(theme)
        }
        empty.apply(theme)
    }

    func scroll(toAlbum key: String) {
        guard let row = albums.firstIndex(where: { $0.key == key }) else { return }
        table.scrollToRow(at: IndexPath(row: row, section: 0), at: .top, animated: true)
    }

    func scrollToCurrent() {
        guard let track = Player.shared.current else { return }
        scroll(toAlbum: track.albumKey)
    }

    private func play(_ track: Track) {
        let all = Library.shared.tracks
        guard let index = all.firstIndex(of: track) else { return }
        Player.shared.play(all, from: index, name: "All")
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        albums.count
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        AlbumCell.height(for: albums[indexPath.row], first: indexPath.row == 0)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: AlbumCell.reuse, for: indexPath) as! AlbumCell
        cell.configure(albums[indexPath.row], first: indexPath.row == 0, current: Player.shared.current?.path, theme: theme)
        cell.onPlay = { [weak self] track in self?.play(track) }
        return cell
    }
}

final class AlbumCell: UITableViewCell, UIContextMenuInteractionDelegate {
    static let reuse = "album"

    var onPlay: ((Track) -> Void)?

    private let cover = CoverView(radius: 3)
    private let title = UILabel(font: Fonts.text(15, .semibold))
    private let artist = UILabel(font: Fonts.text(13))
    private let summary = UILabel(font: Fonts.mono(10.5))
    private let format = UILabel(font: Fonts.mono(10.5))
    private let line = UIView()
    private var rows: [TrackRow] = []
    private var count = 0
    private var top: CGFloat = 8

    /// The cover with the album's details beside it, then its tracks across the full width.
    static func height(for album: Album, first: Bool) -> CGFloat {
        (first ? 8 : 20) + 88 + 8 + CGFloat(album.tracks.count) * 44
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        title.numberOfLines = 2
        for view in [line, cover, title, artist, summary, format] as [UIView] {
            contentView.addSubview(view)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ album: Album, first: Bool, current: String?, theme: Theme) {
        top = first ? 8 : 20
        line.isHidden = first
        title.text = album.title
        artist.text = album.artist
        let tracks = album.tracks.count == 1 ? "1 TRACK" : "\(album.tracks.count) TRACKS"
        summary.text = [album.year, tracks, album.duration.clock].filter { !$0.isEmpty }.joined(separator: " · ")
        format.text = [album.resolution, Self.size(album.size)].joined(separator: " · ")
        cover.show(album.coverID)
        count = album.tracks.count
        while rows.count < count {
            let row = TrackRow()
            row.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)
            row.addInteraction(UIContextMenuInteraction(delegate: self))
            contentView.addSubview(row)
            rows.append(row)
        }
        for (i, row) in rows.enumerated() {
            row.isHidden = i >= count
            if i < count { row.show(album.tracks[i], position: i + 1) }
        }
        setCurrent(current)
        apply(theme)
        setNeedsLayout()
    }

    private static func size(_ bytes: Int64) -> String {
        let megabytes = Double(bytes) / 1_000_000
        return megabytes >= 1000 ? String(format: "%.1f GB", megabytes / 1000) : String(format: "%.0f MB", megabytes)
    }

    func setCurrent(_ path: String?) {
        for row in rows.prefix(count) {
            row.isCurrent = row.track?.path == path
        }
    }

    func apply(_ theme: Theme) {
        title.textColor = theme.text.color()
        artist.textColor = theme.secondary
        summary.textColor = theme.secondary
        format.textColor = theme.secondary
        line.backgroundColor = theme.line.color()
        cover.backgroundColor = theme.line.color()
        for row in rows { row.apply(theme) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width
        line.frame = CGRect(x: 12, y: 0, width: width - 24, height: UIView.hairline)
        cover.frame = CGRect(x: 12, y: top, width: 88, height: 88)
        let x: CGFloat = 112, textWidth = width - x - 12
        let titleHeight = min(ceil(title.sizeThatFits(CGSize(width: textWidth, height: 100)).height), 38)
        title.frame = CGRect(x: x, y: top + 1, width: textWidth, height: titleHeight)
        artist.frame = CGRect(x: x, y: title.frame.maxY + 1, width: textWidth, height: 17)
        format.frame = CGRect(x: x, y: top + 88 - 15, width: textWidth, height: 15)
        summary.frame = CGRect(x: x, y: format.frame.minY - 16, width: textWidth, height: 15)
        for (i, row) in rows.prefix(count).enumerated() {
            row.frame = CGRect(x: 8, y: top + 96 + CGFloat(i) * 44, width: width - 16, height: 44)
        }
    }

    @objc private func rowTapped(_ row: TrackRow) {
        if let track = row.track { onPlay?(track) }
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let track = (interaction.view as? TrackRow)?.track else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(children: [
                UIAction(title: "Play next", image: UIImage(systemName: "text.insert")) { _ in
                    Player.shared.queue.enqueue([track], next: true)
                },
                UIAction(title: "Add to queue", image: UIImage(systemName: "text.append")) { _ in
                    Player.shared.queue.enqueue([track], next: false)
                },
            ])
        }
    }
}

/// One track in an album group: number, title, length. The playing one is tinted with a play mark.
final class TrackRow: UIControl {
    private(set) var track: Track?
    var isCurrent = false { didSet { if isCurrent != oldValue { restyle() } } }

    private let number = UILabel(font: Fonts.mono(11), alignment: .right)
    private let mark = UIImageView(image: Icon.image("play.fill", 9))
    private let title = UILabel(font: Fonts.text(13.5))
    private let duration = UILabel(font: Fonts.mono(11.5), alignment: .right)
    private let highlight = UIView()
    private var theme = Theme.neutral

    override init(frame: CGRect) {
        super.init(frame: frame)
        highlight.layer.cornerRadius = 4
        mark.contentMode = .center
        for view in [highlight, number, mark, title, duration] as [UIView] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool { didSet { restyle() } }

    func show(_ track: Track, position: Int) {
        self.track = track
        number.text = String(track.number > 0 ? track.number : position)
        title.text = track.title
        duration.text = track.duration.clock
        accessibilityLabel = "\(track.title), \(track.duration.clock)"
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        restyle()
    }

    private func restyle() {
        highlight.backgroundColor = isCurrent ? theme.tint : isHighlighted ? theme.text.color(0.06) : .clear
        title.textColor = isCurrent ? theme.accent.color() : theme.text.color()
        number.textColor = theme.secondary
        duration.textColor = theme.secondary
        mark.tintColor = theme.accent.color()
        number.isHidden = isCurrent
        mark.isHidden = !isCurrent
        accessibilityValue = isCurrent ? "Playing" : nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        highlight.frame = bounds
        number.frame = CGRect(x: 4, y: 0, width: 22, height: 44)
        mark.frame = CGRect(x: 14, y: 0, width: 12, height: 44)
        duration.frame = CGRect(x: width - 8 - 48, y: 0, width: 48, height: 44)
        title.frame = CGRect(x: 36, y: 0, width: duration.frame.minX - 8 - 36, height: 44)
    }
}

/// What the list shows before any music is in.
final class EmptyLibraryView: UIView {
    let button = UIButton(type: .custom)
    /// Connect a server, or while downloading, see each song.
    let secondButton = UIButton(type: .system)
    /// While a sync fills the empty library, its progress replaces the instructions.
    func show(scanning: Bool, sync: String?) {
        title.text = sync == nil ? "Add your music" : "Downloading your music"
        body.text = sync ?? (scanning ? "Looking for music…" : EmptyLibraryView.instructions)
        formats.isHidden = sync != nil
        button.isHidden = sync != nil
        let second = sync != nil ? "Show downloads" : Server.shared.isConfigured ? nil : "Connect a server"
        secondButton.isHidden = second == nil
        if secondButton.title(for: .normal) != second { secondButton.setTitle(second, for: .normal) }
        setNeedsLayout()
    }

    private static let instructions = "Drop files on Flaco in Finder, or choose them from Files."
    private let ghosts = (0..<4).map { _ in UIView() }
    private let title = UILabel(font: Fonts.text(20, .semibold), alignment: .center)
    private let body = UILabel(font: Fonts.text(15), alignment: .center)
    private let formats = UILabel(font: Fonts.mono(11), alignment: .center)

    override init(frame: CGRect) {
        super.init(frame: frame)
        title.text = "Add your music"
        body.text = Self.instructions
        body.numberOfLines = 0
        formats.text = "FLAC · ALAC · WAV · AIFF · MP3 · AAC"
        button.setTitle("Choose Files", for: .normal)
        button.titleLabel?.font = Fonts.text(15, .semibold)
        button.layer.cornerRadius = 10
        for ghost in ghosts {
            ghost.layer.cornerRadius = 6
            ghost.layer.borderWidth = 1
            addSubview(ghost)
        }
        secondButton.titleLabel?.font = Fonts.text(15)
        secondButton.isHidden = true
        for view in [title, body, formats, button, secondButton] as [UIView] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 64
        let gridWidth = side * 2 + 12
        let left = (bounds.width - gridWidth) / 2
        var y: CGFloat = 32
        for (i, ghost) in ghosts.enumerated() {
            ghost.frame = CGRect(x: left + CGFloat(i % 2) * (side + 12), y: y + CGFloat(i / 2) * (side + 12), width: side, height: side)
        }
        y += gridWidth + 24
        title.frame = CGRect(x: 24, y: y, width: bounds.width - 48, height: 26)
        y += 32
        let bodyHeight = ceil(body.sizeThatFits(CGSize(width: 290, height: 200)).height)
        body.frame = CGRect(x: (bounds.width - 290) / 2, y: y, width: 290, height: bodyHeight)
        y += bodyHeight + 12
        formats.frame = CGRect(x: 24, y: y, width: bounds.width - 48, height: 14)
        y += 38
        let buttonWidth = ceil(button.titleLabel?.intrinsicContentSize.width ?? 0) + 44
        button.frame = CGRect(x: (bounds.width - buttonWidth) / 2, y: y, width: buttonWidth, height: 44)
        // Under the instructions while downloading, else under the button.
        if !button.isHidden { y += 52 }
        secondButton.frame = CGRect(x: 24, y: y, width: bounds.width - 48, height: 44)
    }

    func apply(_ theme: Theme) {
        title.textColor = theme.text.color()
        body.textColor = theme.secondary
        formats.textColor = theme.secondary
        button.backgroundColor = theme.text.color()
        button.setTitleColor(theme.background.color(), for: .normal)
        secondButton.tintColor = theme.accent.color()
        for (i, ghost) in ghosts.enumerated() {
            ghost.backgroundColor = i == 0 ? .clear : theme.text.color(0.03)
            ghost.layer.borderColor = (i == 0 ? theme.accent.color(0.55) : theme.text.color(0.07)).cgColor
        }
    }
}
