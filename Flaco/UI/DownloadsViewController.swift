import UIKit

/// Every song on the server as a sheet, album by album, each with where it stands: on the phone, waiting, or
/// coming down with its megabytes counting up. Rows update in place; the list itself only changes when the
/// server's does.
final class DownloadsViewController: UIViewController, Themeable, UITableViewDataSource, UITableViewDelegate {
    private let titleLabel = UILabel(font: Fonts.text(16, .semibold))
    private let countLabel = UILabel(font: Fonts.mono(10.5))
    private let syncButton = UIButton(type: .system)
    private let status = UILabel(font: Fonts.mono(11))
    private let track = UIView()
    private let fill = UIView()
    private let table = UITableView(frame: .zero, style: .plain)
    private var theme = Theme.neutral
    private var albums: [[Server.Song]] = []

    /// As a sheet that opens halfway, like the queue.
    static func sheet() -> DownloadsViewController {
        let downloads = DownloadsViewController()
        downloads.modalPresentationStyle = .pageSheet
        if let sheet = downloads.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 14
        }
        return downloads
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.text = "On server"
        syncButton.setTitle("Sync", for: .normal)
        syncButton.titleLabel?.font = Fonts.text(15)
        syncButton.addAction(UIAction { _ in Sync.shared.start() }, for: .touchUpInside)
        track.layer.cornerRadius = 1.5
        track.clipsToBounds = true
        track.addSubview(fill)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.indicatorStyle = .white
        table.sectionHeaderTopPadding = 0
        table.dataSource = self
        table.delegate = self
        table.register(DownloadCell.self, forCellReuseIdentifier: DownloadCell.reuse)
        table.register(SearchHeader.self, forHeaderFooterViewReuseIdentifier: "album")
        for view in [titleLabel, countLabel, syncButton, status, track, table] as [UIView] {
            self.view.addSubview(view)
        }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(reload), name: Sync.catalogDidChange, object: nil)
        center.addObserver(self, selector: #selector(progress), name: Sync.didChange, object: nil)
        ThemeCenter.shared.register(self)
        reload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        titleLabel.frame = CGRect(x: 16, y: 20, width: 100, height: 44)
        countLabel.frame = CGRect(x: 112, y: 20, width: width - 112 - 80, height: 44)
        syncButton.frame = CGRect(x: width - 76, y: 20, width: 68, height: 44)
        status.frame = CGRect(x: 16, y: 62, width: width - 32, height: 16)
        track.frame = CGRect(x: 16, y: 86, width: width - 32, height: 3)
        layoutFill()
        table.frame = CGRect(x: 0, y: 100, width: width, height: view.bounds.height - 100)
    }

    private func layoutFill() {
        let sync = Sync.shared
        let fraction = sync.phase == .downloading && sync.bytesTotal > 0 ? Double(sync.bytesDone) / Double(sync.bytesTotal) : 0
        fill.frame = CGRect(x: 0, y: 0, width: track.bounds.width * CGFloat(min(fraction, 1)), height: 3)
    }

    @objc private func reload() {
        let catalog = Sync.shared.catalog
        var groups: [[Server.Song]] = []
        var folder: String?
        for song in catalog {
            let parent = (song.path as NSString).deletingLastPathComponent
            if parent == folder, !groups.isEmpty {
                groups[groups.count - 1].append(song)
            } else {
                groups.append([song])
                folder = parent
            }
        }
        albums = groups
        countLabel.text = catalog.isEmpty ? "" : "\(catalog.count) TRACKS · \(Sync.bytes(Sync.shared.serverBytes))"
        table.reloadData()
        progress()
    }

    /// The live part: the summary line and the rows on screen.
    @objc private func progress() {
        let sync = Sync.shared
        syncButton.isHidden = !Server.shared.isConfigured || sync.phase == .checking || sync.phase == .downloading
        track.isHidden = sync.phase != .downloading
        switch sync.phase {
        case .downloading:
            status.text = "\(Sync.bytes(sync.bytesDone)) OF \(Sync.bytes(sync.bytesTotal)) · \(Sync.rate(sync.speed))"
        case .checking:
            status.text = "CHECKING \(Server.shared.host.uppercased())"
        case .failed(let message):
            status.text = message.uppercased()
        case .idle:
            let here = sync.catalog.filter { sync.status(of: $0) == .onPhone }.count
            status.text = !Server.shared.isConfigured ? "NO SERVER SET UP"
                : here == sync.catalog.count ? "ALL ON THIS PHONE" : "\(here) OF \(sync.catalog.count) ON THIS PHONE"
        }
        layoutFill()
        for case let cell as DownloadCell in table.visibleCells {
            guard let path = table.indexPath(for: cell) else { continue }
            let song = albums[path.section][path.row]
            cell.update(sync.status(of: song), size: song.size)
        }
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        view.backgroundColor = theme.panel.color()
        titleLabel.textColor = theme.text.color()
        countLabel.textColor = theme.secondary
        syncButton.tintColor = theme.accent.color()
        status.textColor = theme.secondary
        track.backgroundColor = theme.line.color()
        fill.backgroundColor = theme.accent.color()
        for case let cell as DownloadCell in table.visibleCells { cell.apply(theme) }
        for section in 0..<albums.count { (table.headerView(forSection: section) as? SearchHeader)?.apply(theme) }
    }

    func numberOfSections(in tableView: UITableView) -> Int { albums.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { albums[section].count }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 52 }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { 36 }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: "album") as? SearchHeader
        let first = albums[section][0]
        header?.label.text = [first.album, first.artist].filter { !$0.isEmpty }.joined(separator: " · ").uppercased()
        header?.apply(theme)
        return header
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DownloadCell.reuse, for: indexPath) as! DownloadCell
        let song = albums[indexPath.section][indexPath.row]
        cell.configure(song, theme: theme)
        cell.update(Sync.shared.status(of: song), size: song.size)
        return cell
    }
}

final class DownloadCell: UITableViewCell {
    static let reuse = "download"

    private let title = UILabel(font: Fonts.text(14))
    private let detail = UILabel(font: Fonts.text(12))
    private let trailing = UILabel(font: Fonts.mono(11), alignment: .right)
    private let check = UIImageView(image: Icon.image("checkmark", 10, .semibold))
    private let track = UIView()
    private let fill = UIView()
    private var state = Sync.Status.notDownloaded
    private var fraction: CGFloat = 0
    private var theme = Theme.neutral

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        check.contentMode = .center
        track.layer.cornerRadius = 1
        track.clipsToBounds = true
        track.addSubview(fill)
        for view in [title, detail, trailing, check, track] as [UIView] {
            contentView.addSubview(view)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width
        let trailingWidth: CGFloat = 132
        title.frame = CGRect(x: 16, y: 8, width: width - 32 - trailingWidth, height: 19)
        detail.frame = CGRect(x: 16, y: 27, width: width - 32 - trailingWidth, height: 16)
        trailing.frame = CGRect(x: width - 16 - trailingWidth, y: 8, width: trailingWidth, height: 19)
        let textWidth = ceil(trailing.intrinsicContentSize.width)
        check.frame = CGRect(x: width - 16 - textWidth - 16, y: 8, width: 12, height: 19)
        track.frame = CGRect(x: width - 16 - 90, y: 33, width: 90, height: 2)
        fill.frame = CGRect(x: 0, y: 0, width: track.bounds.width * fraction, height: 2)
    }

    func configure(_ song: Server.Song, theme: Theme) {
        title.text = song.title
        detail.text = song.artist
        apply(theme)
    }

    func update(_ status: Sync.Status, size: Int64) {
        state = status
        switch status {
        case .onPhone, .notDownloaded:
            trailing.text = Sync.bytes(size)
        case .waiting:
            trailing.text = "WAITING"
        case .failed:
            trailing.text = "FAILED"
        case .downloading(let bytes):
            trailing.text = "\(Self.megabytes(bytes)) / \(Sync.bytes(size))"
            fraction = size > 0 ? CGFloat(min(Double(bytes) / Double(size), 1)) : 0
        }
        check.isHidden = status != .onPhone
        if case .downloading = status { track.isHidden = false } else { track.isHidden = true }
        restyle()
        setNeedsLayout()
    }

    /// Without the unit, which the total beside it already shows.
    private static func megabytes(_ bytes: Int64) -> String {
        String(format: "%.1f", locale: .current, Double(bytes) / 1e6)
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        restyle()
    }

    private func restyle() {
        let here = state == .onPhone
        title.textColor = here ? theme.text.color() : theme.text.color(0.6)
        detail.textColor = theme.secondary
        switch state {
        case .downloading: trailing.textColor = theme.text.color()
        case .failed: trailing.textColor = theme.accent.color()
        case .onPhone: trailing.textColor = theme.secondary
        case .waiting, .notDownloaded: trailing.textColor = theme.faint
        }
        check.tintColor = theme.accent.color()
        track.backgroundColor = theme.line.color()
        fill.backgroundColor = theme.accent.color()
    }
}
