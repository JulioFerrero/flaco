import AVFoundation

/// Reads a file's tags and stream format into a Track. FLAC is parsed directly; the formats Core Audio tags
/// itself (ALAC, AAC, MP3, WAV, AIFF) go through AVFoundation.
enum TagReader {
    static func read(_ url: URL, path: String, size: Int64, modified: Double) -> (track: Track, cover: Data?)? {
        var track = Track(
            path: path, title: "", artist: "", album: "", albumArtist: "", number: 0, disc: 1, year: "",
            duration: 0, sampleRate: 0, bitDepth: 0, channels: 2, bitrate: 0, codec: "",
            trackGain: nil, trackPeak: nil, albumGain: nil, albumPeak: nil, size: size, modified: modified)
        var cover: Data?

        if url.pathExtension.lowercased() == "flac", let meta = FLACMetadata(url: url) {
            track.codec = "FLAC"
            track.sampleRate = Double(meta.sampleRate)
            track.channels = meta.channels
            track.bitDepth = meta.bitsPerSample
            if meta.totalSamples > 0 {
                track.duration = Double(meta.totalSamples) / Double(meta.sampleRate)
            }
            apply(meta.comments, to: &track)
            cover = meta.picture
        } else if !readAsset(url, into: &track, cover: &cover) {
            return nil
        }

        if track.duration <= 0, let file = try? AVAudioFile(forReading: url) {
            track.duration = Double(file.length) / file.fileFormat.sampleRate
        }
        guard track.duration > 0 else { return nil }
        track.bitrate = Int((Double(size) * 8 / track.duration / 1000).rounded())
        fillGaps(&track, url: url)
        return (track, cover)
    }

    /// The embedded cover alone, for an album whose tracks are already indexed.
    static func cover(of url: URL) -> Data? {
        if url.pathExtension.lowercased() == "flac" {
            return FLACMetadata(url: url)?.picture
        }
        return AVURLAsset(url: url).commonMetadata.first { $0.commonKey == .commonKeyArtwork }?.dataValue
    }

    private static func apply(_ c: [String: String], to t: inout Track) {
        t.title = c["TITLE"] ?? ""
        t.artist = c["ARTIST"] ?? ""
        t.album = c["ALBUM"] ?? ""
        t.albumArtist = c["ALBUMARTIST"] ?? c["ALBUM ARTIST"] ?? c["ALBUM_ARTIST"] ?? ""
        t.number = leadingNumber(c["TRACKNUMBER"]) ?? 0
        t.disc = leadingNumber(c["DISCNUMBER"]) ?? 1
        t.year = String((c["DATE"] ?? c["YEAR"] ?? "").prefix(4))
        t.trackGain = decibels(c["REPLAYGAIN_TRACK_GAIN"])
        t.trackPeak = number(c["REPLAYGAIN_TRACK_PEAK"])
        t.albumGain = decibels(c["REPLAYGAIN_ALBUM_GAIN"])
        t.albumPeak = number(c["REPLAYGAIN_ALBUM_PEAK"])
    }

    private static func readAsset(_ url: URL, into t: inout Track, cover: inout Data?) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else { return false }
        let format = file.fileFormat
        let description = format.streamDescription.pointee
        t.sampleRate = format.sampleRate
        t.channels = Int(format.channelCount)
        t.duration = Double(file.length) / format.sampleRate

        switch description.mFormatID {
        case kAudioFormatAppleLossless:
            t.codec = "ALAC"
            t.bitDepth = [1: 16, 2: 20, 3: 24, 4: 32][Int(description.mFormatFlags)] ?? 16
        case kAudioFormatFLAC:
            t.codec = "FLAC"
            t.bitDepth = [1: 16, 2: 20, 3: 24, 4: 32][Int(description.mFormatFlags)] ?? 16
        case kAudioFormatLinearPCM:
            t.codec = url.pathExtension.lowercased().hasPrefix("aif") ? "AIFF" : "WAV"
            t.bitDepth = Int(description.mBitsPerChannel)
        case kAudioFormatMPEGLayer3:
            t.codec = "MP3"
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2:
            t.codec = "AAC"
        default:
            t.codec = url.pathExtension.uppercased()
        }

        let asset = AVURLAsset(url: url)
        for item in asset.commonMetadata {
            switch item.commonKey {
            case .commonKeyTitle?: t.title = item.stringValue ?? t.title
            case .commonKeyArtist?: t.artist = item.stringValue ?? t.artist
            case .commonKeyAlbumName?: t.album = item.stringValue ?? t.album
            case .commonKeyCreationDate?: t.year = String((item.stringValue ?? "").prefix(4))
            case .commonKeyArtwork?: cover = cover ?? item.dataValue
            default: break
            }
        }
        for item in asset.metadata {
            switch item.identifier {
            case .iTunesMetadataTrackNumber?:
                t.number = packedNumber(item.dataValue) ?? t.number
            case .iTunesMetadataDiscNumber?:
                t.disc = packedNumber(item.dataValue) ?? t.disc
            case .id3MetadataTrackNumber?:
                t.number = leadingNumber(item.stringValue) ?? t.number
            case .id3MetadataPartOfASet?:
                t.disc = leadingNumber(item.stringValue) ?? t.disc
            case .iTunesMetadataAlbumArtist?, .id3MetadataBand?:
                t.albumArtist = item.stringValue ?? t.albumArtist
            case .iTunesMetadataReleaseDate?, .id3MetadataYear?, .id3MetadataRecordingTime?:
                if t.year.isEmpty { t.year = String((item.stringValue ?? "").prefix(4)) }
            default:
                break
            }
        }
        return true
    }

    /// What tags leave out comes from the file and folder names: "03 - Title.flac" in "Artist - Album".
    private static func fillGaps(_ t: inout Track, url: URL) {
        let name = url.deletingPathExtension().lastPathComponent
        if t.number == 0 { t.number = leadingNumber(name) ?? 0 }
        if t.title.isEmpty {
            let stripped = name.drop { $0.isNumber || $0 == " " || $0 == "." || $0 == "-" || $0 == "_" }
            t.title = stripped.isEmpty ? name : String(stripped)
        }
        if t.album.isEmpty {
            let folder = url.deletingLastPathComponent()
            t.album = folder.standardizedFileURL == Library.documents.standardizedFileURL
                ? "Unknown album" : folder.lastPathComponent
        }
        if t.artist.isEmpty { t.artist = t.albumArtist.isEmpty ? "Unknown artist" : t.albumArtist }
        if t.albumArtist.isEmpty { t.albumArtist = t.artist }
    }

    private static func leadingNumber(_ text: String?) -> Int? {
        guard let text else { return nil }
        return Int(text.trimmingCharacters(in: .whitespaces).prefix { $0.isASCII && $0.isNumber })
    }

    private static func number(_ text: String?) -> Double? {
        text.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }

    private static func decibels(_ text: String?) -> Double? {
        guard let text else { return nil }
        return Double(text.replacingOccurrences(of: "dB", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces))
    }

    /// iTunes packs track and disc numbers as big-endian 16-bit values after two padding bytes.
    private static func packedNumber(_ data: Data?) -> Int? {
        guard let data, data.count >= 4 else { return nil }
        let bytes = [UInt8](data)
        let value = Int(bytes[2]) << 8 | Int(bytes[3])
        return value > 0 ? value : nil
    }
}
