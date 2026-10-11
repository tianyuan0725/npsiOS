import Foundation

/// One saved NPS server account (server + credentials).
struct NPSAccount: Codable, Identifiable, Equatable {
    var scheme: String   // "http" or "https"
    var host: String     // "1.2.3.4:8080" or "nps.example.com/web" (no scheme)
    var username: String
    var password: String

    var id: String { "\(scheme)|\(host)|\(username)" }
    var baseURL: String { "\(scheme)://\(host)" }
}

/// Multi-account store. Every account (including its password) is persisted
/// as one JSON blob in the Keychain, so credentials never leave the device.
enum AccountStore {
    private static let kList = "accounts_json"
    private static let kLast = "last_account_id"

    static func load() -> [NPSAccount] {
        guard let json = KeychainHelper.read(account: kList),
              let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([NPSAccount].self, from: data)) ?? []
    }

    static func persist(_ accounts: [NPSAccount]) {
        guard let data = try? JSONEncoder().encode(accounts),
              let json = String(data: data, encoding: .utf8) else { return }
        KeychainHelper.save(json, account: kList)
    }

    /// Insert or update by id. The touched account moves to the front of the
    /// list so the most recently used one is always on top, and becomes the
    /// "last used" account pre-filled on the next launch.
    @discardableResult
    static func upsert(_ account: NPSAccount) -> [NPSAccount] {
        var list = load().filter { $0.id != account.id }
        list.insert(account, at: 0)
        persist(list)
        setLast(account.id)
        return list
    }

    @discardableResult
    static func remove(id: String) -> [NPSAccount] {
        let list = load().filter { $0.id != id }
        persist(list)
        if lastID == id { KeychainHelper.delete(account: kLast) }
        return list
    }

    static var lastID: String? { KeychainHelper.read(account: kLast) }

    static func setLast(_ id: String) {
        KeychainHelper.save(id, account: kLast)
    }

    /// One-time migration from the previous single-account Keychain keys
    /// (baseURL / username / password) into the multi-account list.
    static func migrateLegacy() {
        guard load().isEmpty,
              let url = KeychainHelper.read(account: "baseURL"),
              let user = KeychainHelper.read(account: "username"),
              let pass = KeychainHelper.read(account: "password") else { return }
        var rest = url
        var scheme = "http"
        if let r = rest.range(of: "://") {
            scheme = String(rest[..<r.lowerBound]).lowercased()
            rest = String(rest[r.upperBound...])
        }
        let host = rest.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !host.isEmpty else { return }
        _ = upsert(NPSAccount(scheme: scheme, host: host, username: user, password: pass))
    }
}
