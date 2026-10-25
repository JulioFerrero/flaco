import Foundation

/// Timings for tuning on the device, appended to Library/Caches/flaco.log (out of the Files tab).
enum Log {
    private static let queue = DispatchQueue(label: "flaco.log")
    private static let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("flaco.log")
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func write(_ line: String) {
        let stamp = clock.string(from: Date())
        queue.async {
            guard let data = "\(stamp)  \(line)\n".data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
