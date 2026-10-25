import CryptoKit
import Foundation
import Security

/// The music server Flaco downloads from: Navidrome, or anything else that speaks the Subsonic API. The address
/// and user are kept in UserDefaults, the password in the Keychain.
final class Server {
    static let shared = Server()

    struct Song {
        let id: String
        /// Where it goes under Documents.
        let path: String
        let size: Int64
        let album: String
    }

    struct Listing {
        let songs: [Song]
        /// While the server is still reading its folders its list may be short, so nothing should be removed.
        let scanning: Bool
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let defaults = UserDefaults.standard
    private var cachedPassword: String?

    var address: String { defaults.string(forKey: "serverAddress") ?? "" }
    var user: String { defaults.string(forKey: "serverUser") ?? "" }
    var host: String { URL(string: address)?.host ?? address }
    var isConfigured: Bool { !address.isEmpty && !user.isEmpty && password != nil }

    /// Saves a connection. A nil password keeps the saved one.
    func connect(address: String, user: String, password: String?) {
        var address = address.trimmingCharacters(in: .whitespaces)
        if !address.isEmpty, !address.contains("://") { address = "https://" + address }
        while address.hasSuffix("/") { address.removeLast() }
        let moved = address != self.address
        defaults.set(address, forKey: "serverAddress")
        defaults.set(user.trimmingCharacters(in: .whitespaces), forKey: "serverUser")
        if let password { self.password = password }
        if moved { Sync.shared.forgetServer() }
    }

    /// A connection dropped into Application Support as connect.json, read once into the Keychain.
    func adoptSeed() {
        let url = Library.support.appendingPathComponent("connect.json")
        guard let data = try? Data(contentsOf: url),
              let seed = try? JSONDecoder().decode([String: String].self, from: data),
              let address = seed["address"], let user = seed["user"], let password = seed["password"] else { return }
        connect(address: address, user: user, password: password)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Requests

    /// The server's name and version, to show it answers and the password is right.
    func ping() async throws -> String {
        let response = try await call("ping")
        let name = (response["type"] as? String).map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Subsonic"
        return [name, response["serverVersion"] as? String].compactMap { $0 }.joined(separator: " ")
    }

    /// Every song on the server, 500 at a time.
    func listing() async throws -> Listing {
        let status = try? await call("getScanStatus")
        let scanning = (status?["scanStatus"] as? [String: Any])?["scanning"] as? Bool ?? false
        var raw: [[String: Any]] = []
        while true {
            let response = try await call("search3", [
                "query": "", "artistCount": "0", "albumCount": "0",
                "songCount": "500", "songOffset": String(raw.count),
            ])
            let page = (response["searchResult3"] as? [String: Any])?["song"] as? [[String: Any]] ?? []
            raw += page
            if page.count < 500 { break }
        }

        var songs: [Song] = []
        var taken: Set<String> = []
        for item in raw {
            guard let id = item["id"] as? String, let reported = item["path"] as? String else { continue }
            let size = (item["size"] as? NSNumber)?.int64Value ?? 0
            var path = Self.localPath(reported, keepingSource: false)
            // The same album sent in two ways keeps both copies apart.
            if taken.contains(path.lowercased()) { path = Self.localPath(reported, keepingSource: true) }
            taken.insert(path.lowercased())
            songs.append(Song(id: id, path: path, size: size, album: item["albumId"] as? String ?? ""))
        }
        return Listing(songs: songs, scanning: scanning)
    }

    func downloadURL(_ id: String) -> URL? {
        url("download", ["id": id])
    }

    /// Navidrome reports where it keeps a file: its library folder, then the way the music came in (the Finder
    /// share's Uploads, Syncthing's Mac), then the music's own folders. Only that last part is kept.
    private static func localPath(_ reported: String, keepingSource: Bool) -> String {
        var parts = reported.split(separator: "/").map(String.init).filter { $0 != "." && $0 != ".." }
        if reported.hasPrefix("/"), parts.count > 2 {
            parts.removeFirst(keepingSource ? 1 : 2)
        }
        return parts.joined(separator: "/")
    }

    private func call(_ endpoint: String, _ items: [String: String] = [:]) async throws -> [String: Any] {
        guard let url = url(endpoint, items) else { throw Failure(message: "No server set up.") }
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: url)
        } catch {
            throw Failure(message: "Can't reach \(host).")
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = root["subsonic-response"] as? [String: Any] else {
            throw Failure(message: "\(host) isn't a Subsonic server.")
        }
        if response["status"] as? String != "ok" {
            let error = response["error"] as? [String: Any]
            let code = error?["code"] as? Int
            throw Failure(message: code == 40 ? "Wrong user or password." : error?["message"] as? String ?? "The server refused.")
        }
        return response
    }

    /// Token sign-in: the password never travels, only a hash of it with a fresh salt.
    private func url(_ endpoint: String, _ items: [String: String]) -> URL? {
        guard let password, var components = URLComponents(string: address) else { return nil }
        let salt = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
        let token = Insecure.MD5.hash(data: Data((password + salt).utf8)).map { String(format: "%02x", $0) }.joined()
        components.path += "/rest/\(endpoint)"
        components.queryItems = [
            URLQueryItem(name: "u", value: user), URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: String(salt)), URLQueryItem(name: "v", value: "1.16.1"),
            URLQueryItem(name: "c", value: "Flaco"), URLQueryItem(name: "f", value: "json"),
        ] + items.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url
    }

    // MARK: Keychain

    private var keychainQuery: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: "flaco.server", kSecAttrAccount: "password"]
    }

    private var password: String? {
        get {
            if let cachedPassword { return cachedPassword }
            var query = keychainQuery
            query[kSecReturnData] = true
            query[kSecMatchLimit] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            cachedPassword = String(data: data, encoding: .utf8)
            return cachedPassword
        }
        set {
            SecItemDelete(keychainQuery as CFDictionary)
            cachedPassword = newValue
            guard let newValue else { return }
            var item = keychainQuery
            item[kSecValueData] = Data(newValue.utf8)
            // Background downloads may need it while the phone is locked.
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
