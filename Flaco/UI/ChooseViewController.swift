import UIKit

/// What to download from the server: everything, or artists, albums and songs ticked one by one. The choice is
/// a draft until the button at the bottom, which says what it will download and remove.
final class ChooseViewController: CardPage, UITableViewDataSource, UITableViewDelegate {
    private enum Facet: String, CaseIterable {
        case artists = "ARTISTS", albums = "ALBUMS", songs = "SONGS"
    }

    private struct Group {
        let key: Selection.Key
        let title: String
        let detail: String
        let cover: String?
        let songs: [Server.Song]
    }

    private let mode = SettingsRow(.choice("Download", ["EVERYTHING", "CHOOSE"]))
    private lazy var modeCard = SettingsCard(rows: [mode])
    private let chips = Facet.allCases.map { ChipButton($0.rawValue) }
    private let table = UITableView(frame: .zero, style: .plain)
    private let message = UILabel(font: Fonts.text(14), alignment: .center)
    private let bottom = UIView()
    private let bottomLine = UIView()
    private let summary = UILabel(font: Fonts.mono(11.5, .medium))
    private let detail = UILabel(font: Fonts.mono(10.5))
    private let button = UIButton(type: .custom)

    private var draft: Selection
    /// A first choice starts from nothing ticked; changing an existing "everything" starts from all ticked.
    private let startsEmpty: Bool
    private var facet = Facet.albums
    private var groups: [Facet: [Group]] = [:]

    init() {
        let current = Sync.shared.selection
        startsEmpty = current.mode == .undecided
        draft = current
        if current.mode == .undecided { draft.mode = .everything }
        super.init(title: "Download")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        scroll.isHidden = true
        mode.onChoice = { [weak self] in self?.choose(everything: $0 == 0) }
        for (chip, facet) in zip(chips, Facet.allCases) {
            chip.addAction(UIAction { [weak self] _ in
                self?.facet = facet
                self?.refresh(reload: true)
            }, for: .touchUpInside)
        }
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.indicatorStyle = .white
        table.dataSource = self
        table.delegate = self
        table.register(ChooseCell.self, forCellReuseIdentifier: ChooseCell.reuse)
        message.numberOfLines = 0
        button.titleLabel?.font = Fonts.text(16, .semibold)
        button.layer.cornerRadius = 12
        button.layer.cornerCurve = .continuous
        button.addAction(UIAction { [weak self] _ in self?.commit() }, for: .touchUpInside)
        for view in [modeCard, table, message, bottom] as [UIView] { self.view.addSubview(view) }
        chips.forEach(view.addSubview)
        for view in [bottomLine, summary, detail, button] as [UIView] { bottom.addSubview(view) }
        NotificationCenter.default.addObserver(self, selector: #selector(catalogChanged), name: Sync.catalogDidChange, object: nil)
        catalogChanged()
        apply(theme)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        var y = contentTop + 12
        modeCard.frame = CGRect(x: 12, y: y, width: width - 24, height: 48)
        y += 48 + 12
        var x: CGFloat = 12
        for chip in chips {
            let size = chip.sizeThatFits(.zero)
            chip.frame = CGRect(x: x, y: y + 9, width: size.width, height: size.height)
            x += size.width + 4
        }
        let bottomHeight = 112 + view.safeAreaInsets.bottom
        bottom.frame = CGRect(x: 0, y: view.bounds.height - bottomHeight, width: width, height: bottomHeight)
        bottomLine.frame = CGRect(x: 0, y: 0, width: width, height: UIView.hairline)
        summary.frame = CGRect(x: 16, y: 12, width: width - 32, height: 16)
        detail.frame = CGRect(x: 16, y: 30, width: width - 32, height: 14)
        button.frame = CGRect(x: 16, y: 54, width: width - 32, height: 46)
        let listTop = draft.mode == .chosen ? y + 44 : y
        table.frame = CGRect(x: 0, y: listTop, width: width, height: bottom.frame.minY - listTop)
        message.frame = CGRect(x: 32, y: y + 24, width: width - 64, height: 80)
    }

    // MARK: Data

    @objc private func catalogChanged() {
        let catalog = Sync.shared.catalog
        var byArtist: [String: [Server.Song]] = [:]
        var byAlbum: [String: [Server.Song]] = [:]
        for song in catalog {
            byArtist[song.albumArtist, default: []].append(song)
            byAlbum[song.albumID, default: []].append(song)
        }
        groups[.artists] = byArtist
            .sorted { Library.sortName($0.key) < Library.sortName($1.key) }
            .map { name, songs in
                let albums = Set(songs.map(\.albumID)).count
                return Group(key: .artist(name), title: name.isEmpty ? "Unknown artist" : name,
                             detail: "\(albums) \(albums == 1 ? "ALBUM" : "ALBUMS") · \(Self.size(songs))", cover: nil, songs: songs)
            }
        groups[.albums] = byAlbum.values
            .sorted { a, b in
                let x = Library.sortName(a[0].albumArtist), y = Library.sortName(b[0].albumArtist)
                return x != y ? x < y : (a[0].year, a[0].album) < (b[0].year, b[0].album)
            }
            .map { songs in
                let first = songs[0]
                let year = first.year > 0 ? " · \(first.year)" : ""
                return Group(key: .album(first.albumID), title: first.album,
                             detail: "\(first.albumArtist)\(year) · \(Self.size(songs))", cover: first.coverArt, songs: songs)
            }
        groups[.songs] = catalog.map {
            Group(key: .song($0.id), title: $0.title, detail: "\($0.artist) · \(Sync.bytes($0.size))", cover: nil, songs: [$0])
        }
        refresh(reload: true)
    }

    private static func size(_ songs: [Server.Song]) -> String {
        Sync.bytes(songs.reduce(0) { $0 + $1.size })
    }

    // MARK: Choosing

    private func choose(everything: Bool) {
        if everything {
            draft.mode = .everything
        } else if draft.mode != .chosen {
            draft.mode = .chosen
            draft.artists = startsEmpty ? [] : Set(Sync.shared.catalog.map(\.albumArtist))
            draft.albums = []
            draft.songs = []
        }
        refresh(reload: true)
        view.setNeedsLayout()
    }

    private func refresh(reload: Bool) {
        let sync = Sync.shared
        let catalog = sync.catalog
        let choosing = draft.mode == .chosen
        mode.selected = choosing ? 1 : 0
        for (chip, facet) in zip(chips, Facet.allCases) {
            chip.isOn = facet == self.facet
            chip.isHidden = !choosing
        }
        table.isHidden = !choosing || catalog.isEmpty
        message.isHidden = !table.isHidden
        if catalog.isEmpty {
            message.text = sync.phase == .checking ? "Checking the server…" : "The server has no music yet."
        } else {
            message.text = "All \(catalog.count) songs, \(Sync.bytes(sync.serverBytes)), and whatever is added to the server later."
        }
        if reload { table.reloadData() } else {
            for case let cell as ChooseCell in table.visibleCells {
                if let path = table.indexPath(for: cell) { cell.setState(draft.state(of: rows[path.row].songs)) }
            }
        }

        let wanted = catalog.filter(draft.wants)
        let downloads = wanted.filter { sync.status(of: $0) != .onPhone }.reduce(0) { $0 + $1.size }
        let removes = catalog.filter { sync.status(of: $0) == .onPhone && !draft.wants($0) }.reduce(0) { $0 + $1.size }
        let free = Sync.freeSpace
        summary.text = "\(wanted.count) \(wanted.count == 1 ? "SONG" : "SONGS") · \(Self.size(wanted))"
        let tooBig = downloads + 300_000_000 > free + removes && downloads > 0
        if tooBig {
            detail.text = "NEEDS \(Sync.bytes(downloads)) · \(Sync.bytes(free)) FREE"
        } else {
            detail.text = [downloads > 0 ? "DOWNLOADS \(Sync.bytes(downloads))" : nil,
                           removes > 0 ? "REMOVES \(Sync.bytes(removes))" : nil,
                           "\(Sync.bytes(free)) FREE"].compactMap { $0 }.joined(separator: " · ")
        }
        detail.textColor = tooBig ? theme.accent.color() : theme.secondary
        button.setTitle(downloads > 0 ? "Download" : removes > 0 ? "Remove from phone" : "Done", for: .normal)
        button.isEnabled = !catalog.isEmpty && !tooBig
        button.alpha = button.isEnabled ? 1 : 0.4
    }

    private var rows: [Group] { groups[facet] ?? [] }

    private func commit() {
        let removes = Sync.shared.catalog.filter { Sync.shared.status(of: $0) == .onPhone && !draft.wants($0) }
        let apply = { [weak self] in
            guard let self else { return }
            Sync.shared.selection = self.draft
            Sync.shared.start()
            self.navigationController?.popToRootViewController(animated: true)
        }
        guard !removes.isEmpty else { return apply() }
        let size = Self.size(removes)
        let sheet = UIAlertController(title: "Remove \(size) from this phone?", message: "It stays on the server, and you can tick it again any time.", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Remove \(size)", style: .destructive) { _ in apply() })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    // MARK: Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        facet == .albums ? 64 : 54
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ChooseCell.reuse, for: indexPath) as! ChooseCell
        let group = rows[indexPath.row]
        cell.configure(title: group.title, detail: group.detail, cover: facet == .albums ? group.cover ?? "" : nil, theme: theme)
        cell.setState(draft.state(of: group.songs))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        let group = rows[indexPath.row]
        draft.toggle(group.key, group: group.songs, in: Sync.shared.catalog)
        refresh(reload: false)
    }

    override func apply(_ theme: Theme) {
        super.apply(theme)
        modeCard.apply(theme)
        for chip in chips { chip.apply(theme) }
        message.textColor = theme.secondary
        bottom.backgroundColor = theme.panel.color()
        bottomLine.backgroundColor = theme.line.color()
        summary.textColor = theme.text.color()
        detail.textColor = theme.secondary
        button.backgroundColor = theme.accent.color()
        button.setTitleColor(theme.background.color(), for: .normal)
        for case let cell as ChooseCell in table.visibleCells { cell.apply(theme) }
    }
}

final class ChooseCell: UITableViewCell {
    static let reuse = "choose"

    private let cover = UIImageView()
    private let title = UILabel(font: Fonts.text(14.5))
    private let detail = UILabel(font: Fonts.text(12))
    private let check = UIImageView()
    private var coverID: String?
    private var state = Selection.State.none
    private var theme = Theme.neutral

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectedBackgroundView = UIView()
        cover.layer.cornerRadius = 3
        cover.clipsToBounds = true
        cover.contentMode = .scaleAspectFill
        check.contentMode = .center
        for view in [cover, title, detail, check] as [UIView] { contentView.addSubview(view) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width, height = contentView.bounds.height
        let x: CGFloat = cover.isHidden ? 16 : 70
        cover.frame = CGRect(x: 16, y: (height - 44) / 2, width: 44, height: 44)
        title.frame = CGRect(x: x, y: height / 2 - 19, width: width - x - 56, height: 19)
        detail.frame = CGRect(x: x, y: height / 2 + 1, width: width - x - 56, height: 16)
        check.frame = CGRect(x: width - 48, y: 0, width: 36, height: height)
    }

    /// A nil cover means a row without one; an empty id means a cover that the server doesn't have.
    func configure(title text: String, detail line: String, cover id: String?, theme: Theme) {
        title.text = text
        detail.text = line
        cover.isHidden = id == nil
        coverID = id
        cover.image = nil
        if let id, !id.isEmpty {
            RemoteCovers.load(id) { [weak self] image in
                guard self?.coverID == id else { return }
                self?.cover.image = image
            }
        }
        apply(theme)
        setNeedsLayout()
    }

    func setState(_ state: Selection.State) {
        self.state = state
        let name = state == .all ? "checkmark.circle.fill" : state == .some ? "minus.circle.fill" : "circle"
        check.image = Icon.image(name, 20)
        check.accessibilityLabel = state == .all ? "Downloading" : state == .some ? "Partly" : "Not downloading"
        restyle()
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        restyle()
    }

    private func restyle() {
        title.textColor = state == .none ? theme.text.color(0.7) : theme.text.color()
        detail.textColor = theme.secondary
        cover.backgroundColor = theme.line.color()
        check.tintColor = state == .none ? theme.faint : theme.accent.color()
    }
}

/// Album covers from the server for music not on the phone yet, kept in memory while Flaco runs.
enum RemoteCovers {
    private static let cache = NSCache<NSString, UIImage>()

    static func load(_ id: String, _ done: @escaping (UIImage?) -> Void) {
        if let image = cache.object(forKey: id as NSString) { return done(image) }
        guard let url = Server.shared.coverURL(id, size: 132) else { return done(nil) }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let image = data.flatMap(UIImage.init(data:))
            if let image { cache.setObject(image, forKey: id as NSString) }
            DispatchQueue.main.async { done(image) }
        }.resume()
    }
}
