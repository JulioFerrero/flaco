import UIKit

/// The queue as a sheet over the player: what's playing, what you queued, and what follows in the list.
/// Queued songs reorder by dragging and come off with a swipe.
final class QueueViewController: UIViewController, Themeable, UITableViewDataSource, UITableViewDelegate,
    UITableViewDragDelegate, UITableViewDropDelegate {
    private let titleLabel = UILabel(font: Fonts.text(16, .semibold))
    private let countLabel = UILabel(font: Fonts.mono(10.5))
    private let clearButton = UIButton(type: .system)
    private let table = UITableView(frame: .zero, style: .plain)
    private var theme = Theme.neutral
    private var upNext: [Track] = []
    private var upcoming: [Track] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.text = "Queue"
        clearButton.setTitle("Clear", for: .normal)
        clearButton.titleLabel?.font = Fonts.text(15)
        clearButton.addAction(UIAction { _ in Player.shared.queue.clearUpNext() }, for: .touchUpInside)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.indicatorStyle = .white
        table.sectionHeaderTopPadding = 0
        table.dataSource = self
        table.delegate = self
        table.dragDelegate = self
        table.dropDelegate = self
        table.dragInteractionEnabled = true
        table.register(QueueRowCell.self, forCellReuseIdentifier: QueueRowCell.reuse)
        for view in [titleLabel, countLabel, clearButton, table] as [UIView] {
            self.view.addSubview(view)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: PlayQueue.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: Player.didChange, object: nil)
        ThemeCenter.shared.register(self)
        reload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        titleLabel.frame = CGRect(x: 16, y: 20, width: 70, height: 44)
        countLabel.frame = CGRect(x: 86, y: 20, width: width - 86 - 80, height: 44)
        clearButton.frame = CGRect(x: width - 76, y: 20, width: 68, height: 44)
        table.frame = CGRect(x: 0, y: 68, width: width, height: view.bounds.height - 68)
    }

    @objc private func reload() {
        let queue = Player.shared.queue
        upNext = queue.upNext
        upcoming = queue.upcoming
        let length = upNext.reduce(0) { $0 + $1.duration }
        countLabel.text = upNext.isEmpty ? "0 NEXT" : "\(upNext.count) NEXT · \(length.clock)"
        clearButton.isHidden = upNext.isEmpty
        table.reloadData()
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        view.backgroundColor = theme.panel.color()
        titleLabel.textColor = theme.text.color()
        countLabel.textColor = theme.secondary
        clearButton.tintColor = theme.accent.color()
        for case let cell as QueueRowCell in table.visibleCells { cell.apply(theme) }
        for section in 0..<3 { (table.headerView(forSection: section) as? SearchHeader)?.apply(theme) }
    }

    func numberOfSections(in tableView: UITableView) -> Int { 3 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return Player.shared.current == nil ? 0 : 1
        case 1: return max(upNext.count, 1)
        default: return upcoming.count
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        indexPath.section == 0 ? 60 : 52
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        section == 2 && upcoming.isEmpty ? 0 : 34
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = (tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as? SearchHeader) ?? SearchHeader(reuseIdentifier: "header")
        let name = Player.shared.queue.name
        header.label.text = ["NOW", "NEXT", name.isEmpty ? "THEN" : "THEN FROM \(name.uppercased())"][section]
        header.apply(theme)
        return header
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: QueueRowCell.reuse, for: indexPath) as! QueueRowCell
        switch indexPath.section {
        case 0:
            let player = Player.shared
            cell.configure(player.current, remaining: player.current.map { "−" + ($0.duration - player.position).clock }, mode: .now, theme: theme)
        case 1 where upNext.isEmpty:
            cell.configure(nil, remaining: nil, mode: .empty, theme: theme)
        case 1:
            cell.configure(upNext[indexPath.row], remaining: nil, mode: .queued, theme: theme)
        default:
            cell.configure(upcoming[indexPath.row], remaining: nil, mode: .list, theme: theme)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch indexPath.section {
        case 1 where !upNext.isEmpty: Player.shared.playUpNext(at: indexPath.row)
        case 2: Player.shared.jump(to: upcoming[indexPath.row])
        default: break
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1, !upNext.isEmpty else { return nil }
        let remove = UIContextualAction(style: .destructive, title: "Remove") { _, _, done in
            Player.shared.queue.removeUpNext(at: indexPath.row)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [remove])
    }

    // MARK: Reordering

    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard indexPath.section == 1, !upNext.isEmpty else { return [] }
        return [UIDragItem(itemProvider: NSItemProvider())]
    }

    func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destination: IndexPath?) -> UITableViewDropProposal {
        guard session.localDragSession != nil, destination?.section == 1 else {
            return UITableViewDropProposal(operation: .forbidden)
        }
        return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {}

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == 1 && !upNext.isEmpty
    }

    func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt source: IndexPath, toProposedIndexPath proposed: IndexPath) -> IndexPath {
        guard proposed.section == 1 else {
            return IndexPath(row: proposed.section < 1 ? 0 : upNext.count - 1, section: 1)
        }
        return proposed
    }

    func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
        let track = upNext.remove(at: source.row)
        upNext.insert(track, at: destination.row)
        Player.shared.queue.moveUpNext(from: source.row, to: destination.row)
    }
}

final class QueueRowCell: UITableViewCell {
    static let reuse = "queue"

    enum Mode {
        case now, queued, list, empty
    }

    private let cover = CoverView(radius: 3)
    private let title = UILabel(font: Fonts.text(14))
    private let detail = UILabel(font: Fonts.text(12))
    private let trailing = UILabel(font: Fonts.mono(11.5), alignment: .right)
    private let grip = UIImageView(image: Icon.image("line.3.horizontal", 14))
    private let tintView = UIView()
    private var mode = Mode.list

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectedBackgroundView = UIView()
        tintView.layer.cornerRadius = 6
        grip.contentMode = .center
        for view in [tintView, cover, title, detail, trailing, grip] as [UIView] {
            contentView.addSubview(view)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var duration = ""

    func configure(_ track: Track?, remaining: String?, mode: Mode, theme: Theme) {
        self.mode = mode
        cover.show(track?.coverID)
        cover.isHidden = mode == .empty
        title.text = mode == .empty ? "Nothing queued. Long-press a song to add it." : track?.title
        title.font = mode == .now ? Fonts.text(14, .semibold) : mode == .empty ? Fonts.text(13) : Fonts.text(14)
        title.numberOfLines = mode == .empty ? 2 : 1
        detail.text = track.map { "\($0.artist) · \($0.album)" }
        trailing.text = remaining ?? track?.duration.clock
        grip.isHidden = mode != .queued
        tintView.isHidden = mode != .now
        apply(theme)
        setNeedsLayout()
    }

    func apply(_ theme: Theme) {
        tintView.backgroundColor = theme.tint
        title.textColor = mode == .now ? theme.accent.color() : mode == .empty ? theme.secondary : theme.text.color()
        detail.textColor = theme.secondary
        trailing.textColor = mode == .now ? theme.accent.color() : theme.secondary
        grip.tintColor = theme.secondary
        cover.backgroundColor = theme.line.color()
        selectedBackgroundView?.backgroundColor = theme.text.color(0.06)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width, height = contentView.bounds.height
        if mode == .empty {
            title.frame = CGRect(x: 16, y: 0, width: width - 32, height: height)
            return
        }
        tintView.frame = CGRect(x: 8, y: 2, width: width - 16, height: height - 4)
        let side: CGFloat = mode == .now ? 40 : 36
        cover.frame = CGRect(x: 16, y: (height - side) / 2, width: side, height: side)
        let right: CGFloat = mode == .queued ? 44 : 16
        grip.frame = CGRect(x: width - 44, y: 0, width: 44, height: height)
        trailing.frame = CGRect(x: width - right - 52, y: 0, width: 52, height: height)
        let x = cover.frame.maxX + 12
        let textWidth = trailing.frame.minX - 8 - x
        title.frame = CGRect(x: x, y: height / 2 - 18, width: textWidth, height: 18)
        detail.frame = CGRect(x: x, y: height / 2 + 1, width: textWidth, height: 16)
    }
}
