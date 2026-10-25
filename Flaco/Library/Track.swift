import Foundation

/// One audio file in the library: its tags, its stream, and where it lives under Documents.
struct Track: Codable, Hashable {
    var path: String
    var title: String
    var artist: String
    var album: String
    var albumArtist: String
    var number: Int
    var disc: Int
    var year: String
    var duration: Double
    var sampleRate: Double
    /// 0 for lossy codecs.
    var bitDepth: Int
    var channels: Int
    /// Averaged over the whole file, in kbps.
    var bitrate: Int
    var codec: String
    var trackGain: Double?
    var trackPeak: Double?
    var albumGain: Double?
    var albumPeak: Double?
    var size: Int64
    var modified: Double

    var url: URL { Library.documents.appendingPathComponent(path) }
    var albumKey: String { albumArtist.lowercased() + "\u{1F}" + album.lowercased() }
    var coverID: String { Library.hash(albumKey) }

    /// Bit depth over sample rate, "24/96", or the bitrate of a lossy file.
    var resolution: String {
        bitDepth > 0 ? "\(bitDepth)/\(Int(sampleRate / 1000))" : "\(bitrate)k"
    }

    var kilohertz: String { Track.kilohertz(sampleRate) }

    var isHiRes: Bool { bitDepth > 16 || sampleRate > 48000 }

    /// The foobar-style status line: FLAC | 2814 kbps | 96 kHz | 24 bit.
    var status: String {
        var parts = [codec, "\(bitrate) kbps", "\(kilohertz) kHz"]
        if bitDepth > 0 { parts.append("\(bitDepth) bit") }
        return parts.joined(separator: " | ")
    }

    static func kilohertz(_ rate: Double) -> String {
        let khz = rate / 1000
        return khz == khz.rounded() ? String(Int(khz)) : String(format: "%.1f", khz)
    }

    static func == (a: Track, b: Track) -> Bool { a.path == b.path }
    func hash(into hasher: inout Hasher) { hasher.combine(path) }
}

/// Every track of one album, in disc and track order.
struct Album {
    let key: String
    let title: String
    let artist: String
    let year: String
    let tracks: [Track]
    let added: Double

    var coverID: String { Library.hash(key) }
    var duration: Double { tracks.reduce(0) { $0 + $1.duration } }
    var isHiRes: Bool { tracks.contains { $0.isHiRes } }

    /// The finest resolution among its tracks.
    var resolution: String {
        let best = tracks.max { ($0.bitDepth, $0.sampleRate) < ($1.bitDepth, $1.sampleRate) }
        return best?.resolution ?? ""
    }
}

/// A folder at the top of Documents, as Finder or the Files app put it there.
struct Folder {
    let name: String
    let tracks: [Track]
    var size: Int64 { tracks.reduce(0) { $0 + $1.size } }
}

extension Double {
    /// 4:32, or 1:04:32 past an hour.
    var clock: String {
        let total = Swift.max(0, Int(self))
        let hours = total / 3600, minutes = (total / 60) % 60, seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
