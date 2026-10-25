import UIKit

/// The library browser: albums as a cover grid, artists, and folders as they sit on disk.
final class LibraryViewController: UIViewController, Themeable {
    enum Facet: String, CaseIterable {
        case albums = "ALBUMS", artists = "ARTISTS", folders = "FOLDERS"
    }

    enum Sort: String, CaseIterable {
        case title = "A–Z", artist = "ARTIST", year = "YEAR", added = "ADDED"
    }

    var onShowAlbum: ((Album) -> Void)?

    private var facet = Facet.albums
    private var sort = Sort.title
    private var artistFilter: String?
    private var theme = Theme.neutral

    private let bar = UIView()
    private let chips = Facet.allCases.map { ChipButton($0.rawValue) }
    private let filterChip = ChipButton("")
    private let sortButton = UIButton(type: .custom)
    private lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private let list = UITableView(frame: .zero, style: .plain)

    private var albums: [Album] = []
    private var artists: [(name: String, albums: [Album])] = []
    private var folders: [Folder] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        for (chip, facet) in zip(chips, Facet.allCases) {
            chip.addAction(UIAction { [weak self] _ in self?.select(facet) }, for: .touchUpInside)
            bar.addSubview(chip)
        }
        filterChip.isOn = true
        filterChip.isHidden = true
        filterChip.addAction(UIAction { [weak self] _ in
            self?.artistFilter = nil
            self?.reload()
        }, for: .touchUpInside)
        bar.addSubview(filterChip)
        sortButton.titleLabel?.font = Fonts.mono(10.5)
        sortButton.addAction(UIAction { [weak self] _ in self?.cycleSort() }, for: .touchUpInside)
        bar.addSubview(sortButton)
        view.addSubview(bar)

        grid.backgroundColor = .clear
        grid.indicatorStyle = .white
        grid.alwaysBounceVertical = true
        grid.dataSource = self
        grid.delegate = self
        grid.register(AlbumGridCell.self, forCellWithReuseIdentifier: AlbumGridCell.reuse)
        view.addSubview(grid)

        list.backgroundColor = .clear
        list.separatorStyle = .none
        list.indicatorStyle = .white
        list.rowHeight = 56
        list.dataSource = self
        list.delegate = self
        list.register(LibraryRowCell.self, forCellReuseIdentifier: LibraryRowCell.reuse)
        view.addSubview(list)

        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: Library.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshCurrent), name: Player.didChange, object: nil)
        ThemeCenter.shared.register(self)
        reload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        bar.frame = CGRect(x: 0, y: 0, width: width, height: 44)
        var x: CGFloat = 10
        for chip in chips {
            let size = chip.sizeThatFits(.zero)
            chip.frame = CGRect(x: x, y: 9, width: size.width, height: size.height)
            x += size.width + 4
        }
        let sortWidth = ceil(sortButton.titleLabel?.intrinsicContentSize.width ?? 0) + 20
        sortButton.frame = CGRect(x: width - sortWidth - 4, y: 0, width: sortWidth, height: 44)
        if !filterChip.isHidden {
            let size = filterChip.sizeThatFits(.zero)
            filterChip.frame = CGRect(x: x + 4, y: 9, width: min(size.width, sortButton.frame.minX - x - 8), height: size.height)
        }
        let content = CGRect(x: 0, y: 44, width: width, height: view.bounds.height - 44)
        grid.frame = content
        list.frame = content
        if let layout = grid.collectionViewLayout as? UICollectionViewFlowLayout {
            let side = floor((width - 24 - 20) / 3)
            layout.itemSize = CGSize(width: side, height: side + 6 + 16 + 15 + 4)
            layout.minimumInteritemSpacing = 10
            layout.minimumLineSpacing = 14
            layout.sectionInset = UIEdgeInsets(top: 6, left: 12, bottom: 16, right: 12)
        }
    }

    func showArtist(_ name: String) {
        artistFilter = name
        facet = .albums
        reload()
    }

    private func select(_ facet: Facet) {
        self.facet = facet
        if facet != .albums { artistFilter = nil }
        reload()
    }

    private func cycleSort() {
        let all = Sort.allCases
        sort = all[(all.firstIndex(of: sort)! + 1) % all.count]
        reload()
    }

    @objc private func reload() {
        let library = Library.shared
        var albums = library.albums
        if let artistFilter { albums = albums.filter { $0.artist == artistFilter } }
        switch sort {
        case .title: albums.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist: break
        case .year: albums.sort { $0.year > $1.year }
        case .added: albums.sort { $0.added > $1.added }
        }
        self.albums = albums
        var byArtist: [String: [Album]] = [:]
        for album in library.albums { byArtist[album.artist, default: []].append(album) }
        artists = byArtist.map { (name: $0.key, albums: $0.value) }
            .sorted { Library.sortName($0.name) < Library.sortName($1.name) }
        folders = library.folders

        for (chip, facet) in zip(chips, Facet.allCases) { chip.isOn = facet == self.facet }
        filterChip.isHidden = artistFilter == nil
        filterChip.setTitle("× " + (artistFilter ?? "").uppercased(), for: .normal)
        sortButton.setTitle(sort.rawValue, for: .normal)
        sortButton.isHidden = facet != .albums
        grid.isHidden = facet != .albums
        list.isHidden = facet == .albums
        grid.reloadData()
        list.reloadData()
        view.setNeedsLayout()
    }

    @objc private func refreshCurrent() {
        for case let cell as AlbumGridCell in grid.visibleCells {
            cell.setCurrent(Player.shared.current?.albumKey)
        }
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        for chip in chips + [filterChip] { chip.apply(theme) }
        sortButton.setTitleColor(theme.secondary, for: .normal)
        for case let cell as AlbumGridCell in grid.visibleCells { cell.apply(theme) }
        for case let cell as LibraryRowCell in list.visibleCells { cell.apply(theme) }
    }

    private func menu(for tracks: [Track], name: String) -> UIMenu {
        UIMenu(children: [
            UIAction(title: "Play", image: UIImage(systemName: "play")) { _ in
                Player.shared.play(tracks, from: 0, name: name)
            },
            UIAction(title: "Play next", image: UIImage(systemName: "text.insert")) { _ in
                Player.shared.queue.enqueue(tracks, next: true)
            },
            UIAction(title: "Add to queue", image: UIImage(systemName: "text.append")) { _ in
                Player.shared.queue.enqueue(tracks, next: false)
            },
        ])
    }
}

extension LibraryViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        albums.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AlbumGridCell.reuse, for: indexPath) as! AlbumGridCell
        cell.configure(albums[indexPath.item], current: Player.shared.current?.albumKey, theme: theme)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onShowAlbum?(albums[indexPath.item])
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let album = albums[indexPath.item]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            self?.menu(for: album.tracks, name: album.title)
        }
    }
}

extension LibraryViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        facet == .artists ? artists.count : folders.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: LibraryRowCell.reuse, for: indexPath) as! LibraryRowCell
        if facet == .artists {
            let artist = artists[indexPath.row]
            let trackCount = artist.albums.reduce(0) { $0 + $1.tracks.count }
            let albumWord = artist.albums.count == 1 ? "ALBUM" : "ALBUMS"
            cell.configure(title: artist.name, detail: "\(artist.albums.count) \(albumWord) · \(trackCount) TRACKS",
                           cover: artist.albums.first?.coverID, folder: false, theme: theme)
        } else {
            let folder = folders[indexPath.row]
            let megabytes = Double(folder.size) / 1_000_000
            cell.configure(title: folder.name, detail: String(format: "%d files · %.0f MB", folder.tracks.count, megabytes),
                           cover: nil, folder: true, theme: theme)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if facet == .artists {
            showArtist(artists[indexPath.row].name)
        } else {
            let folder = folders[indexPath.row]
            Player.shared.play(folder.tracks, from: 0, name: folder.name)
        }
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let tracks: [Track], name: String
        if facet == .artists {
            tracks = artists[indexPath.row].albums.flatMap(\.tracks)
            name = artists[indexPath.row].name
        } else {
            tracks = folders[indexPath.row].tracks
            name = folders[indexPath.row].name
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            self?.menu(for: tracks, name: name)
        }
    }
}

final class AlbumGridCell: UICollectionViewCell {
    static let reuse = "grid"

    private let cover = CoverView(radius: 3)
    private let badge = UILabel(font: Fonts.mono(9), alignment: .center)
    private let title = UILabel(font: Fonts.text(12.5, .medium))
    private let artist = UILabel(font: Fonts.text(11.5))
    private var key = ""
    private var isCurrent = false
    private var theme = Theme.neutral

    override init(frame: CGRect) {
        super.init(frame: frame)
        badge.textColor = UIColor(white: 0.96, alpha: 1)
        badge.backgroundColor = UIColor(white: 0, alpha: 0.6)
        badge.layer.cornerRadius = 3
        badge.clipsToBounds = true
        for view in [cover, badge, title, artist] as [UIView] {
            contentView.addSubview(view)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ album: Album, current: String?, theme: Theme) {
        key = album.key
        cover.show(album.coverID)
        title.text = album.title
        artist.text = album.artist
        badge.text = album.isHiRes ? album.resolution : nil
        badge.isHidden = !album.isHiRes
        isAccessibilityElement = true
        accessibilityLabel = "\(album.title), \(album.artist)"
        setCurrent(current)
        apply(theme)
        setNeedsLayout()
    }

    func setCurrent(_ key: String?) {
        isCurrent = key == self.key
        title.textColor = isCurrent ? theme.accent.color() : theme.text.color()
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        cover.backgroundColor = theme.panel.color()
        title.textColor = isCurrent ? theme.accent.color() : theme.text.color()
        artist.textColor = theme.secondary
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = bounds.width
        cover.frame = CGRect(x: 0, y: 0, width: side, height: side)
        let badgeWidth = ceil(badge.intrinsicContentSize.width) + 8
        badge.frame = CGRect(x: 5, y: side - 5 - 15, width: badgeWidth, height: 15)
        title.frame = CGRect(x: 0, y: side + 6, width: side, height: 16)
        artist.frame = CGRect(x: 0, y: side + 22, width: side, height: 15)
    }
}

/// An artist or a folder: thumbnail or folder icon, name, mono detail, chevron.
final class LibraryRowCell: UITableViewCell {
    static let reuse = "row"

    private let cover = CoverView(radius: 3)
    private let icon = UIImageView(image: Icon.image("folder", 16))
    private let title = UILabel(font: Fonts.text(14, .medium))
    private let detail = UILabel(font: Fonts.mono(10.5))
    private let chevron = UIImageView(image: Icon.image("chevron.right", 11, .semibold))
    private let line = UIView()
    private var isFolder = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectedBackgroundView = UIView()
        icon.contentMode = .center
        chevron.contentMode = .center
        for view in [cover, icon, title, detail, chevron, line] as [UIView] {
            contentView.addSubview(view)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, detail: String, cover id: String?, folder: Bool, theme: Theme) {
        isFolder = folder
        self.title.text = title
        self.title.font = folder ? Fonts.mono(12) : Fonts.text(14, .medium)
        self.detail.text = detail
        cover.isHidden = folder
        icon.isHidden = !folder
        cover.show(id)
        apply(theme)
        setNeedsLayout()
    }

    func apply(_ theme: Theme) {
        title.textColor = theme.text.color()
        detail.textColor = theme.secondary
        icon.tintColor = theme.secondary
        chevron.tintColor = theme.secondary
        cover.backgroundColor = theme.panel.color()
        line.backgroundColor = theme.line.color()
        selectedBackgroundView?.backgroundColor = theme.text.color(0.06)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width, height = contentView.bounds.height
        cover.frame = CGRect(x: 12, y: (height - 40) / 2, width: 40, height: 40)
        icon.frame = CGRect(x: 12, y: (height - 40) / 2, width: 24, height: 40)
        let x: CGFloat = isFolder ? 48 : 64
        title.frame = CGRect(x: x, y: height / 2 - 18, width: width - x - 36, height: 19)
        detail.frame = CGRect(x: x, y: height / 2 + 2, width: width - x - 36, height: 15)
        chevron.frame = CGRect(x: width - 28, y: 0, width: 16, height: height)
        line.frame = CGRect(x: 0, y: height - UIView.hairline, width: width, height: UIView.hairline)
    }
}
