import UIKit

/// Searches as you type across artists, albums and songs, with the match drawn in the accent.
final class SearchViewController: UIViewController, Themeable, UITableViewDataSource, UITableViewDelegate {
    enum Scope: String, CaseIterable {
        case all = "ALL", artists = "ARTISTS", albums = "ALBUMS", songs = "SONGS"
    }

    private enum Section {
        case recent([String])
        case artists([(name: String, album: Album)])
        case albums([Album])
        case songs([Track])
    }

    var onShowAlbum: ((Album) -> Void)?
    var onShowArtist: ((String) -> Void)?

    var query = "" { didSet { refresh() } }

    private var scope = Scope.all
    private var sections: [Section] = []
    private var theme = Theme.neutral
    private let chips = Scope.allCases.map { ChipButton($0.rawValue) }
    private let table = UITableView(frame: .zero, style: .plain)
    private let nothing = UILabel(font: Fonts.mono(11), alignment: .center)

    private var recents: [String] {
        get { UserDefaults.standard.stringArray(forKey: "recentSearches") ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(6)), forKey: "recentSearches") }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        for (chip, scope) in zip(chips, Scope.allCases) {
            chip.addAction(UIAction { [weak self] _ in
                self?.scope = scope
                self?.refresh()
            }, for: .touchUpInside)
            view.addSubview(chip)
        }
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.indicatorStyle = .white
        table.keyboardDismissMode = .onDrag
        table.sectionHeaderTopPadding = 0
        table.dataSource = self
        table.delegate = self
        table.register(SearchRowCell.self, forCellReuseIdentifier: SearchRowCell.reuse)
        view.addSubview(table)
        nothing.text = "NO MATCHES"
        view.addSubview(nothing)

        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: Library.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboard(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        ThemeCenter.shared.register(self)
        refresh()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        var x: CGFloat = 10
        for chip in chips {
            let size = chip.sizeThatFits(.zero)
            chip.frame = CGRect(x: x, y: 9, width: size.width, height: size.height)
            x += size.width + 4
        }
        table.frame = CGRect(x: 0, y: 44, width: view.bounds.width, height: view.bounds.height - 44)
        nothing.frame = CGRect(x: 0, y: 92, width: view.bounds.width, height: 16)
    }

    /// Keeps the last results above the keyboard.
    @objc private func keyboard(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let local = table.convert(frame, from: nil)
        table.contentInset.bottom = max(0, table.bounds.maxY - local.minY)
        table.verticalScrollIndicatorInsets.bottom = table.contentInset.bottom
    }

    func remember() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        recents = [text] + recents.filter { $0.caseInsensitiveCompare(text) != .orderedSame }
    }

    @objc private func refresh() {
        guard isViewLoaded else { return }
        for (chip, scope) in zip(chips, Scope.allCases) { chip.isOn = scope == self.scope }
        let text = query.trimmingCharacters(in: .whitespaces)
        sections = []
        if text.isEmpty {
            if !recents.isEmpty { sections = [.recent(recents)] }
        } else {
            let library = Library.shared
            let wants = { (scope: Scope) in self.scope == .all || self.scope == scope }
            var seen = Set<String>()
            let artists = library.albums.compactMap { album -> (name: String, album: Album)? in
                guard Self.match(album.artist, text) != nil, seen.insert(album.artist).inserted else { return nil }
                return (album.artist, album)
            }
            let albums = library.albums.filter { Self.match($0.title, text) != nil }
            let songs = Array(library.tracks.filter { Self.match($0.title, text) != nil }.prefix(60))
            if wants(.artists), !artists.isEmpty { sections.append(.artists(artists)) }
            if wants(.albums), !albums.isEmpty { sections.append(.albums(albums)) }
            if wants(.songs), !songs.isEmpty { sections.append(.songs(songs)) }
        }
        nothing.isHidden = text.isEmpty || !sections.isEmpty
        table.reloadData()
    }

    static func match(_ text: String, _ query: String) -> NSRange? {
        let range = (text as NSString).range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
        return range.location == NSNotFound ? nil : range
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        for chip in chips { chip.apply(theme) }
        nothing.textColor = theme.secondary
        for case let cell as SearchRowCell in table.visibleCells { cell.apply(theme) }
        for section in 0..<sections.count {
            (table.headerView(forSection: section) as? SearchHeader)?.apply(theme)
        }
    }

    private func highlighted(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [.foregroundColor: theme.text.color()])
        if let range = Self.match(text, query.trimmingCharacters(in: .whitespaces)) {
            result.addAttribute(.foregroundColor, value: theme.accent.color(), range: range)
        }
        return result
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .recent(let items): return items.count
        case .artists(let items): return items.count
        case .albums(let items): return items.count
        case .songs(let items): return items.count
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch sections[indexPath.section] {
        case .recent: return 44
        case .artists: return 56
        case .albums: return 64
        case .songs: return 52
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        34
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = (tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as? SearchHeader) ?? SearchHeader(reuseIdentifier: "header")
        switch sections[section] {
        case .recent: header.label.text = "RECENT"
        case .artists(let items): header.label.text = "ARTISTS · \(items.count)"
        case .albums(let items): header.label.text = "ALBUMS · \(items.count)"
        case .songs(let items): header.label.text = "SONGS · \(items.count)"
        }
        header.apply(theme)
        return header
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SearchRowCell.reuse, for: indexPath) as! SearchRowCell
        switch sections[indexPath.section] {
        case .recent(let items):
            cell.configure(title: NSAttributedString(string: items[indexPath.row], attributes: [.foregroundColor: theme.text.color()]),
                           detail: nil, trailing: nil, cover: nil, side: 0, symbol: "clock", theme: theme)
        case .artists(let items):
            let item = items[indexPath.row]
            cell.configure(title: highlighted(item.name), detail: "ARTIST", trailing: nil, cover: item.album.coverID, side: 40, symbol: nil, theme: theme)
        case .albums(let items):
            let album = items[indexPath.row]
            let detail = [album.artist, album.year, album.resolution].filter { !$0.isEmpty }.joined(separator: " · ")
            cell.configure(title: highlighted(album.title), detail: detail, trailing: nil, cover: album.coverID, side: 48, symbol: nil, theme: theme)
        case .songs(let items):
            let track = items[indexPath.row]
            cell.configure(title: highlighted(track.title), detail: "\(track.artist) · \(track.album)",
                           trailing: track.duration.clock, cover: track.coverID, side: 36, symbol: nil, theme: theme)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section] {
        case .recent(let items):
            NotificationCenter.default.post(name: SearchViewController.fillQuery, object: items[indexPath.row])
        case .artists(let items):
            remember()
            onShowArtist?(items[indexPath.row].name)
        case .albums(let items):
            remember()
            onShowAlbum?(items[indexPath.row])
        case .songs(let items):
            remember()
            let track = items[indexPath.row]
            guard let album = Library.shared.album(for: track), let index = album.tracks.firstIndex(of: track) else { return }
            Player.shared.play(album.tracks, from: index, name: album.title)
        }
    }

    static let fillQuery = Notification.Name("FlacoFillQuery")
}

final class SearchHeader: UITableViewHeaderFooterView {
    let label = UILabel(font: Fonts.mono(10))
    private let line = UIView()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        backgroundView = UIView()
        contentView.addSubview(label)
        contentView.addSubview(line)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = CGRect(x: 12, y: 12, width: bounds.width - 24, height: 16)
        line.frame = CGRect(x: 0, y: bounds.height - UIView.hairline, width: bounds.width, height: UIView.hairline)
    }

    func apply(_ theme: Theme) {
        backgroundView?.backgroundColor = theme.background.color()
        label.textColor = theme.secondary
        line.backgroundColor = theme.line.color()
    }
}

final class SearchRowCell: UITableViewCell {
    static let reuse = "result"

    private let cover = CoverView(radius: 3)
    private let symbol = UIImageView()
    private let title = UILabel(font: Fonts.text(14))
    private let detail = UILabel()
    private let trailing = UILabel(font: Fonts.mono(11.5), alignment: .right)
    private let line = UIView()
    private var side: CGFloat = 0
    private var monoDetail = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectedBackgroundView = UIView()
        symbol.contentMode = .center
        for view in [cover, symbol, title, detail, trailing, line] as [UIView] {
            contentView.addSubview(view)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: NSAttributedString, detail: String?, trailing: String?, cover id: String?, side: CGFloat, symbol name: String?, theme: Theme) {
        self.title.attributedText = title
        self.detail.text = detail
        self.trailing.text = trailing
        self.side = side
        monoDetail = trailing == nil
        self.detail.font = monoDetail ? Fonts.mono(10.5) : Fonts.text(12)
        cover.isHidden = id == nil && side == 0
        cover.show(id)
        symbol.image = name.flatMap { Icon.image($0, 13) }
        symbol.isHidden = name == nil
        apply(theme)
        setNeedsLayout()
    }

    func apply(_ theme: Theme) {
        detail.textColor = theme.secondary
        trailing.textColor = theme.secondary
        symbol.tintColor = theme.secondary
        cover.backgroundColor = theme.panel.color()
        line.backgroundColor = theme.line.color()
        selectedBackgroundView?.backgroundColor = theme.text.color(0.06)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width, height = contentView.bounds.height
        let hasDetail = !(detail.text ?? "").isEmpty
        var x: CGFloat = 12
        if !symbol.isHidden {
            symbol.frame = CGRect(x: 12, y: 0, width: 18, height: height)
            x = 42
        } else if side > 0 {
            cover.frame = CGRect(x: 12, y: (height - side) / 2, width: side, height: side)
            x = 12 + side + 12
        }
        let trailingWidth: CGFloat = trailing.text == nil ? 0 : 48
        trailing.frame = CGRect(x: width - 12 - trailingWidth, y: 0, width: trailingWidth, height: height)
        let textWidth = width - x - 12 - (trailingWidth > 0 ? trailingWidth + 8 : 0)
        if hasDetail {
            title.frame = CGRect(x: x, y: height / 2 - 18, width: textWidth, height: 19)
            detail.frame = CGRect(x: x, y: height / 2 + 1, width: textWidth, height: 16)
        } else {
            title.frame = CGRect(x: x, y: 0, width: textWidth, height: height)
            detail.frame = .zero
        }
        line.frame = CGRect(x: 0, y: height - UIView.hairline, width: width, height: UIView.hairline)
    }
}
