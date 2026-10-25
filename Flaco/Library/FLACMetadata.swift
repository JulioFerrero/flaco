import Foundation

/// What a FLAC file says about itself in its metadata blocks: the stream format, the Vorbis comments and the
/// front cover. Only the blocks are read, never the audio.
struct FLACMetadata {
    var sampleRate = 0
    var channels = 0
    var bitsPerSample = 0
    var totalSamples: Int64 = 0
    /// Keys upper-cased; the first value wins when a key repeats.
    var comments: [String: String] = [:]
    var picture: Data?

    init?(url: URL, wantsPicture: Bool = true) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var start: UInt64 = 0
        let head = [UInt8](handle.readData(ofLength: 10))
        if head.count == 10, head[0] == 0x49, head[1] == 0x44, head[2] == 0x33 {
            // An ID3v2 tag some taggers put in front. Its size is synchsafe.
            let size = UInt64(head[6] & 0x7F) << 21 | UInt64(head[7] & 0x7F) << 14
                | UInt64(head[8] & 0x7F) << 7 | UInt64(head[9] & 0x7F)
            start = 10 + size + (head[5] & 0x10 != 0 ? 10 : 0)
        }
        guard (try? handle.seek(toOffset: start)) != nil,
              handle.readData(ofLength: 4) == Data("fLaC".utf8) else { return nil }

        var pictureKind: Int?
        while true {
            let header = [UInt8](handle.readData(ofLength: 4))
            guard header.count == 4 else { break }
            let isLast = header[0] & 0x80 != 0
            let type = header[0] & 0x7F
            let length = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])

            switch type {
            case 0:
                readStreamInfo([UInt8](handle.readData(ofLength: length)))
            case 4:
                readComments([UInt8](handle.readData(ofLength: length)))
            case 6 where wantsPicture && pictureKind != 3:
                // Type 3 is the front cover; any other picture is kept until one turns up.
                if let found = Self.readPicture([UInt8](handle.readData(ofLength: length))),
                   picture == nil || found.kind == 3 {
                    picture = found.data
                    pictureKind = found.kind
                }
            default:
                guard let position = try? handle.offset(),
                      (try? handle.seek(toOffset: position + UInt64(length))) != nil else { return nil }
            }
            if isLast { break }
        }
        guard sampleRate > 0 else { return nil }
    }

    private mutating func readStreamInfo(_ b: [UInt8]) {
        guard b.count >= 18 else { return }
        sampleRate = Int(b[10]) << 12 | Int(b[11]) << 4 | Int(b[12]) >> 4
        channels = Int((b[12] >> 1) & 0x07) + 1
        bitsPerSample = (Int(b[12] & 0x01) << 4 | Int(b[13]) >> 4) + 1
        totalSamples = Int64(b[13] & 0x0F) << 32 | Int64(b[14]) << 24 | Int64(b[15]) << 16
            | Int64(b[16]) << 8 | Int64(b[17])
    }

    /// Vorbis comments are little-endian, unlike the rest of FLAC.
    private mutating func readComments(_ b: [UInt8]) {
        var i = 0
        func next() -> Int? {
            guard i + 4 <= b.count else { return nil }
            defer { i += 4 }
            return Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24
        }
        guard let vendor = next(), i + vendor <= b.count else { return }
        i += vendor
        guard let count = next() else { return }
        for _ in 0..<count {
            guard let length = next(), length >= 0, i + length <= b.count else { return }
            let entry = String(decoding: b[i..<i + length], as: UTF8.self)
            i += length
            guard let equals = entry.firstIndex(of: "=") else { continue }
            let key = entry[..<equals].uppercased()
            if comments[key] == nil {
                comments[key] = String(entry[entry.index(after: equals)...])
            }
        }
    }

    private static func readPicture(_ b: [UInt8]) -> (kind: Int, data: Data)? {
        var i = 0
        func next() -> Int? {
            guard i + 4 <= b.count else { return nil }
            defer { i += 4 }
            return Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
        }
        guard let kind = next(), let mimeLength = next() else { return nil }
        i += mimeLength
        guard let descriptionLength = next() else { return nil }
        i += descriptionLength + 16 // width, height, depth, colors
        guard let length = next(), length > 0, i + length <= b.count else { return nil }
        return (kind, Data(b[i..<i + length]))
    }
}
