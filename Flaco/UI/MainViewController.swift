import UIKit

/// The one window, foobar-style: the player on top, the playlist, library or search in the middle, and the
/// transport bar at the bottom. Everything takes its colors from the playing cover.
final class MainViewController: UIViewController, Themeable {
    private enum Mode {
        case playlist, library, search
    }

    private var mode = Mode.playlist
    private var modeBeforeSearch = Mode.playlist

    private let glow = GlowView()
    private let header = PlayerHeaderView()
    private let strip = NowPlayingStrip()
    private let tabs = TabsBar()
    private let searchBar = SearchBar()
    private let content = UIView()
    private let transport = TransportBar()

    private let albumList = AlbumListViewController()
    private let library = LibraryViewController()
    private let search = SearchViewController()

    private var link: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0
    private var scrubbing = false

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        for view in [glow, header, strip, tabs, searchBar, content, transport] as [UIView] {
            self.view.addSubview(view)
        }
        for child in [albumList, library, search] {
            addChild(child)
            child.view.frame = content.bounds
            child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            content.addSubview(child.view)
            child.didMove(toParent: self)
        }
        content.clipsToBounds = true
        wire()
        observe()
        ThemeCenter.shared.register(self)
        updateTheme(animated: false)
        applySettings()
        playerChanged()
        show(.playlist, animated: false)
        Waveforms.shared.prepareLibrary()

        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layout()
    }

    private func layout() {
        let width = view.bounds.width
        let top = view.safeAreaInsets.top + 4
        let expanded = mode == .playlist
        let headerHeight = expanded ? PlayerHeaderView.height : NowPlayingStrip.height
        glow.frame = CGRect(x: 0, y: 0, width: width, height: 340)
        header.frame = CGRect(x: 0, y: top, width: width, height: PlayerHeaderView.height)
        strip.frame = CGRect(x: 0, y: top, width: width, height: NowPlayingStrip.height)
        header.alpha = expanded ? 1 : 0
        strip.alpha = expanded ? 0 : 1
        let barsY = top + headerHeight + (expanded ? 6 : 0)
        tabs.frame = CGRect(x: 0, y: barsY, width: width, height: 45)
        searchBar.frame = tabs.frame
        tabs.alpha = mode == .search ? 0 : 1
        searchBar.alpha = mode == .search ? 1 : 0
        let transportHeight = TransportBar.height + view.safeAreaInsets.bottom
        transport.frame = CGRect(x: 0, y: view.bounds.height - transportHeight, width: width, height: transportHeight)
        content.frame = CGRect(x: 0, y: tabs.frame.maxY, width: width, height: transport.frame.minY - tabs.frame.maxY)
    }

    private func show(_ mode: Mode, animated: Bool = true) {
        let previous = self.mode
        self.mode = mode
        if mode == .search {
            if previous != .search { modeBeforeSearch = previous }
            searchBar.field.becomeFirstResponder()
        } else if previous == .search {
            searchBar.field.resignFirstResponder()
            searchBar.field.text = ""
            search.query = ""
        }
        tabs.selected = mode == .library ? .library : .all
        albumList.view.isHidden = mode != .playlist
        library.view.isHidden = mode != .library
        search.view.isHidden = mode != .search
        header.isUserInteractionEnabled = mode == .playlist
        strip.isUserInteractionEnabled = mode != .playlist
        link?.isPaused = false
        UIView.animate(withDuration: animated ? 0.3 : 0, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.layout()
        }
    }

    // MARK: Wiring

    private func wire() {
        let player = Player.shared
        header.onCoverTap = { [weak self] in self?.albumList.scrollToCurrent() }
        header.waveform.onScrub = { [weak self] fraction in
            guard let self else { return }
            self.scrubbing = fraction != nil
            if let fraction, let duration = player.current?.duration {
                self.transport.setTime(fraction * duration, duration)
            }
        }
        header.waveform.onSeek = { fraction in
            guard let duration = player.current?.duration else { return }
            player.seek(to: fraction * duration)
        }
        strip.addAction(UIAction { [weak self] _ in self?.show(.playlist) }, for: .touchUpInside)

        tabs.allButton.addAction(UIAction { [weak self] _ in self?.show(.playlist) }, for: .touchUpInside)
        tabs.libraryButton.addAction(UIAction { [weak self] _ in self?.show(.library) }, for: .touchUpInside)
        tabs.searchButton.addAction(UIAction { [weak self] _ in self?.show(.search) }, for: .touchUpInside)
        tabs.settingsButton.addAction(UIAction { [weak self] _ in
            self?.navigationController?.pushViewController(SettingsViewController(), animated: true)
        }, for: .touchUpInside)

        searchBar.field.addAction(UIAction { [weak self] _ in
            self?.search.query = self?.searchBar.field.text ?? ""
        }, for: .editingChanged)
        searchBar.field.addAction(UIAction { [weak self] _ in
            self?.searchBar.field.resignFirstResponder()
            self?.search.remember()
        }, for: .editingDidEndOnExit)
        searchBar.cancelButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.show(self.modeBeforeSearch)
        }, for: .touchUpInside)

        transport.stopButton.addAction(UIAction { _ in player.stop() }, for: .touchUpInside)
        transport.previousButton.addAction(UIAction { _ in player.previous() }, for: .touchUpInside)
        transport.playButton.addAction(UIAction { _ in player.toggle() }, for: .touchUpInside)
        transport.nextButton.addAction(UIAction { _ in player.next() }, for: .touchUpInside)
        transport.shuffleButton.addAction(UIAction { _ in player.queue.shuffle.toggle() }, for: .touchUpInside)
        transport.repeatButton.addAction(UIAction { _ in
            let queue = player.queue
            queue.repeatMode = queue.repeatMode == .off ? .all : queue.repeatMode == .all ? .one : .off
        }, for: .touchUpInside)
        transport.queueButton.addAction(UIAction { [weak self] _ in self?.presentQueue() }, for: .touchUpInside)

        albumList.onImport = { [weak self] in
            guard let self else { return }
            Importer.present(from: self)
        }
        albumList.onConnect = { [weak self] in
            self?.navigationController?.pushViewController(ServerViewController(), animated: true)
        }
        albumList.onShowDownloads = { [weak self] in self?.presentDownloads() }
        tabs.syncButton.addAction(UIAction { [weak self] _ in self?.presentDownloads() }, for: .touchUpInside)
        library.onShowAlbum = { [weak self] album in self?.showAlbum(album) }
        search.onShowAlbum = { [weak self] album in self?.showAlbum(album) }
        search.onShowArtist = { [weak self] name in
            self?.show(.library)
            self?.library.showArtist(name)
        }
    }

    private func observe() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(playerChanged), name: Player.didChange, object: nil)
        center.addObserver(self, selector: #selector(queueChanged), name: PlayQueue.didChange, object: nil)
        center.addObserver(self, selector: #selector(libraryChanged), name: Library.didChange, object: nil)
        center.addObserver(self, selector: #selector(settingsChanged), name: Settings.didChange, object: nil)
        center.addObserver(self, selector: #selector(waveformReady(_:)), name: Waveforms.didUpdate, object: nil)
        center.addObserver(self, selector: #selector(fillQuery(_:)), name: SearchViewController.fillQuery, object: nil)
        center.addObserver(self, selector: #selector(syncChanged), name: Sync.didChange, object: nil)
    }

    private func showAlbum(_ album: Album) {
        show(.playlist)
        DispatchQueue.main.async { self.albumList.scroll(toAlbum: album.key) }
    }

    private func presentDownloads() {
        guard presentedViewController == nil else { return }
        present(DownloadsViewController.sheet(), animated: true)
    }

    @objc private func syncChanged() {
        let sync = Sync.shared
        switch sync.phase {
        case .checking: tabs.showSync("")
        case .downloading: tabs.showSync(sync.bytesTotal > 0 ? "\(Int(Double(sync.bytesDone) * 100 / Double(sync.bytesTotal)))%" : "")
        default: tabs.showSync(nil)
        }
    }

    private func presentQueue() {
        let queue = QueueViewController()
        queue.modalPresentationStyle = .pageSheet
        if let sheet = queue.sheetPresentationController {
            sheet.detents = [.large(), .medium()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 14
        }
        present(queue, animated: true)
    }

    // MARK: Updates

    @objc private func playerChanged() {
        let player = Player.shared
        header.show(player.current)
        strip.show(player.current)
        queueChanged()
        updateTheme(animated: true)
        link?.isPaused = false
    }

    @objc private func queueChanged() {
        let player = Player.shared
        let track = player.current
        let tagged = track.map { $0.trackGain != nil || $0.albumGain != nil } ?? false
        let gain = Settings.shared.replayGain != .off && tagged ? player.gain : nil
        transport.show(track, gain: gain, playing: player.state == .playing,
                       shuffle: player.queue.shuffle, repeatMode: player.queue.repeatMode)
    }

    @objc private func libraryChanged() {
        updateTheme(animated: true)
        Waveforms.shared.prepareLibrary()
    }

    @objc private func settingsChanged() {
        applySettings()
        updateTheme(animated: true)
        header.show(Player.shared.current)
        queueChanged()
    }

    @objc private func waveformReady(_ note: Notification) {
        guard let path = note.object as? String, let track = Player.shared.current, track.path == path else { return }
        UIView.transition(with: header.waveform, duration: 0.25, options: .transitionCrossDissolve) {
            self.header.waveform.levels = Waveforms.shared.levels(for: track)
        }
    }

    @objc private func fillQuery(_ note: Notification) {
        guard let text = note.object as? String else { return }
        searchBar.field.text = text
        search.query = text
    }

    private func applySettings() {
        let settings = Settings.shared
        header.spectrum.style = settings.spectrum
        strip.spectrum.style = settings.spectrum
        header.waveform.showsOutline = settings.waveform
    }

    private func updateTheme(animated: Bool) {
        let theme = Settings.shared.coverColors ? Library.shared.theme(for: Player.shared.current) : .neutral
        ThemeCenter.shared.set(theme, animated: animated && view.window != nil)
    }

    func apply(_ theme: Theme) {
        view.backgroundColor = theme.background.color()
        glow.backgroundColor = theme.glow.color()
        header.apply(theme)
        strip.apply(theme)
        tabs.apply(theme)
        searchBar.apply(theme)
        transport.apply(theme)
    }

    /// Spectrum, seekbar and clock, every frame while playing; idle otherwise.
    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastFrame == 0 ? 1.0 / 60 : min(now - lastFrame, 0.1)
        lastFrame = now
        let player = Player.shared
        let duration = player.current?.duration ?? 0
        let position = player.position
        let bands = Settings.shared.spectrum == .off ? nil : player.spectrumNow()
        if mode == .playlist {
            header.spectrum.update(bands, now: now, dt: dt)
            header.waveform.progress = duration > 0 ? position / duration : 0
        } else {
            strip.spectrum.update(bands, now: now, dt: dt)
        }
        strip.setProgress(position, duration)
        if !scrubbing { transport.setTime(position, duration) }
        if player.state != .playing, header.spectrum.isSettled, strip.spectrum.isSettled {
            link.isPaused = true
            lastFrame = 0
        }
    }
}
