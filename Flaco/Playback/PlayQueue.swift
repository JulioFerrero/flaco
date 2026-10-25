import Foundation

enum RepeatMode: String {
    case off, all, one
}

/// What plays next: the list playback started from, shuffled or not, with the listener's queue in front of
/// it. The decoder asks ahead with `next(after:)`; the queue moves only when a track is actually heard.
final class PlayQueue {
    static let didChange = Notification.Name("FlacoQueueDidChange")

    private let lock = NSLock()
    private var original: [Track] = []
    private var order: [Track] = []
    private var index = 0
    private var queued: [Track] = []
    private var listName = ""
    private var shuffled = false
    private var repeating = RepeatMode.off

    var name: String { lock.sync { listName } }
    var upNext: [Track] { lock.sync { queued } }

    /// The rest of the list after the current track.
    var upcoming: [Track] {
        lock.sync { index + 1 < order.count ? Array(order[(index + 1)...].prefix(50)) : [] }
    }

    var shuffle: Bool {
        get { lock.sync { shuffled } }
        set {
            lock.sync {
                guard newValue != shuffled else { return }
                shuffled = newValue
                let current = order.indices.contains(index) ? order[index] : nil
                if newValue {
                    var rest = original
                    if let current, let i = rest.firstIndex(of: current) { rest.remove(at: i) }
                    order = (current.map { [$0] } ?? []) + rest.shuffled()
                    index = 0
                } else {
                    order = original
                    index = current.flatMap { original.firstIndex(of: $0) } ?? 0
                }
            }
            changed()
        }
    }

    var repeatMode: RepeatMode {
        get { lock.sync { repeating } }
        set {
            lock.sync { repeating = newValue }
            changed()
        }
    }

    func set(_ tracks: [Track], start: Int, name: String) {
        lock.sync {
            original = tracks
            listName = name
            if shuffled {
                var rest = tracks
                let first = rest.remove(at: start)
                order = [first] + rest.shuffled()
                index = 0
            } else {
                order = tracks
                index = start
            }
        }
        changed()
    }

    /// What follows `track`. A manual skip ignores repeat-one.
    func next(after track: Track, manual: Bool = false) -> Track? {
        lock.sync {
            if repeating == .one, !manual { return track }
            if let i = queued.firstIndex(of: track) {
                return i + 1 < queued.count ? queued[i + 1] : after(index)
            }
            if let first = queued.first { return first }
            return after(position(of: track) ?? index)
        }
    }

    func previous(before track: Track) -> Track? {
        lock.sync {
            let i = position(of: track) ?? index + 1
            if i > 0, i - 1 < order.count { return order[i - 1] }
            return repeating == .all ? order.last : nil
        }
    }

    /// The track became audible: move to it in the list, or take it off the queue.
    func didStart(_ track: Track) {
        lock.sync {
            if queued.first == track {
                queued.removeFirst()
            } else if let i = position(of: track) {
                index = i
            }
        }
        changed()
    }

    func enqueue(_ tracks: [Track], next: Bool) {
        lock.sync {
            if next {
                queued.insert(contentsOf: tracks, at: 0)
            } else {
                queued.append(contentsOf: tracks)
            }
        }
        changed()
    }

    @discardableResult
    func removeUpNext(at i: Int) -> Track? {
        let track: Track? = lock.sync { queued.indices.contains(i) ? queued.remove(at: i) : nil }
        changed()
        return track
    }

    func moveUpNext(from source: Int, to destination: Int) {
        lock.sync {
            guard queued.indices.contains(source) else { return }
            let track = queued.remove(at: source)
            queued.insert(track, at: min(destination, queued.count))
        }
        changed()
    }

    func clearUpNext() {
        lock.sync { queued.removeAll() }
        changed()
    }

    // MARK: Saving

    var snapshot: [String: Any] {
        lock.sync {
            [
                "original": original.map(\.path), "order": order.map(\.path), "index": index,
                "queued": queued.map(\.path), "name": listName, "shuffle": shuffled, "repeat": repeating.rawValue,
            ]
        }
    }

    func restore(_ saved: [String: Any], lookup: (String) -> Track?) {
        lock.sync {
            original = (saved["original"] as? [String] ?? []).compactMap(lookup)
            order = (saved["order"] as? [String] ?? []).compactMap(lookup)
            index = min(saved["index"] as? Int ?? 0, max(order.count - 1, 0))
            queued = (saved["queued"] as? [String] ?? []).compactMap(lookup)
            listName = saved["name"] as? String ?? ""
            shuffled = saved["shuffle"] as? Bool ?? false
            repeating = RepeatMode(rawValue: saved["repeat"] as? String ?? "") ?? .off
        }
    }

    // MARK: Private, under the lock

    private func position(of track: Track) -> Int? {
        if order.indices.contains(index), order[index] == track { return index }
        return order.firstIndex(of: track)
    }

    private func after(_ i: Int) -> Track? {
        if i + 1 < order.count { return order[i + 1] }
        return repeating == .all ? order.first : nil
    }

    private func changed() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        } else {
            DispatchQueue.main.async { NotificationCenter.default.post(name: Self.didChange, object: nil) }
        }
    }
}

extension NSLock {
    func sync<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
