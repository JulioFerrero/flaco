import Foundation

/// What to keep on the phone from the server: everything, or the artists, albums and songs ticked. An artist or
/// album stays ticked as a whole, so music added to it on the server later comes down too.
struct Selection: Codable, Equatable {
    enum Mode: String, Codable {
        /// Connected, but nothing chosen yet: nothing downloads and nothing is removed.
        case undecided
        case everything
        case chosen
    }

    enum Key {
        case artist(String), album(String), song(String)
    }

    enum State {
        case all, some, none
    }

    var mode = Mode.undecided
    var artists: Set<String> = []
    var albums: Set<String> = []
    var songs: Set<String> = []

    func wants(_ song: Server.Song) -> Bool {
        switch mode {
        case .undecided: return false
        case .everything: return true
        case .chosen: return songs.contains(song.id) || albums.contains(song.albumID) || artists.contains(song.albumArtist)
        }
    }

    func state(of group: [Server.Song]) -> State {
        let wanted = group.filter(wants).count
        return wanted == 0 ? .none : wanted == group.count ? .all : .some
    }

    /// Ticks the group if any of it is unticked, else unticks it. Unticking part of something ticked as a whole
    /// first spells out the rest of it, so only this part goes.
    mutating func toggle(_ key: Key, group: [Server.Song], in catalog: [Server.Song]) {
        if mode != .chosen {
            // Leaving "everything" starts from every artist ticked, so nothing goes until unticked.
            artists = mode == .everything ? Set(catalog.map(\.albumArtist)) : []
            albums = []
            songs = []
            mode = .chosen
        }
        guard state(of: group) == .all else {
            switch key {
            case .artist(let name): artists.insert(name)
            case .album(let id): albums.insert(id)
            case .song(let id): songs.insert(id)
            }
            return
        }
        let ids = Set(group.map(\.id))
        switch key {
        case .artist(let name):
            artists.remove(name)
            albums.subtract(group.map(\.albumID))
        case .album(let id):
            if let artist = group.first?.albumArtist, artists.remove(artist) != nil {
                albums.formUnion(catalog.filter { $0.albumArtist == artist && $0.albumID != id }.map(\.albumID))
            }
            albums.remove(id)
        case .song:
            guard let song = group.first else { return }
            if artists.remove(song.albumArtist) != nil {
                albums.formUnion(catalog.filter { $0.albumArtist == song.albumArtist }.map(\.albumID))
            }
            if albums.remove(song.albumID) != nil {
                songs.formUnion(catalog.filter { $0.albumID == song.albumID }.map(\.id))
            }
        }
        songs.subtract(ids)
    }
}
