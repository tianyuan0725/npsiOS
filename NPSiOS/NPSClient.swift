import Foundation
import SwiftUI

/// Network client for the NPS web admin API.
///
/// Authentication uses the same session-cookie flow as the official web UI:
///  - POST `Login/Verify` with `username`/`password` -> server sets a session cookie.
///  - All subsequent requests reuse that cookie automatically.
///
/// For servers where the admin configured a `web_base_url` prefix, the user must
/// include that prefix in the Base URL (e.g. `https://nps.example.com/web`).
@MainActor
class NPSClient: ObservableObject {
    static let shared = NPSClient()

    @Published var isLoggedIn: Bool = false
    @Published var baseURL: String = ""
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var errorMessage: String?
    @Published var sessionExpired: Bool = false

    private var session: URLSession
    private let cookieStorage = HTTPCookieStorage.shared
    /// Captured session cookie (e.g. "beegosessionID=xxxx") replayed on every
    /// request. NPS authenticates purely via this cookie; replaying it manually
    /// is more robust than relying on URLSession's automatic cookie handling
    /// (which can silently drop the session between requests on some setups).
    private var sessionCookie: String?

    private let kBase = "baseURL"
    private let kUser = "username"
    private let kPass = "password"

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = cookieStorage
        // Deterministic cookie handling: the session cookie is replayed manually
        // via applyAuth(). With httpShouldSetCookies enabled, URLSession merges a
        // possibly STALE beegosessionID from the shared storage into every request
        // (a session cookie is issued even for FAILED login attempts and gets
        // auto-stored), which overrides/conflicts with the fresh one — the server
        // then treats every API call as logged-out and returns the login page as
        // HTML, kicking the user straight back out ("auto logout" loop).
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)

        // Restore saved credentials into the published fields so the login form
        // is pre-filled (password INCLUDED) on every launch. Previously only the
        // base URL was restored here, so the password field always looked "wiped"
        // after relaunching the app even though it was saved in the Keychain.
        if let url = KeychainHelper.read(account: kBase) { self.baseURL = url }
        if let user = KeychainHelper.read(account: kUser) { self.username = user }
        if let pass = KeychainHelper.read(account: kPass) { self.password = pass }
        // Silent auto-login when a complete set of credentials exists.
        if let url = KeychainHelper.read(account: kBase),
           let user = KeychainHelper.read(account: kUser),
           let pass = KeychainHelper.read(account: kPass),
           !url.isEmpty, !user.isEmpty, !pass.isEmpty {
            Task { await login(username: user, password: pass, save: false) }
        }
    }

    // MARK: - Credentials
    func saveCredentials(url: String, username: String, password: String) {
        KeychainHelper.save(url, account: kBase)
        KeychainHelper.save(username, account: kUser)
        KeychainHelper.save(password, account: kPass)
    }

    func clearCredentials() {
        KeychainHelper.delete(account: kBase)
        KeychainHelper.delete(account: kUser)
        KeychainHelper.delete(account: kPass)
        sessionCookie = nil
        username = ""
        password = ""
        if let cookies = cookieStorage.cookies {
            for c in cookies { cookieStorage.deleteCookie(c) }
        }
    }

    // MARK: - URL building
    /// Attach the captured session cookie to an outgoing request.
    private func applyAuth(_ req: inout URLRequest) {
        if let c = sessionCookie {
            req.setValue(c, forHTTPHeaderField: "Cookie")
        }
    }

    /// Grab the NPS session cookie (beegosessionID) from the shared storage and
    /// stash it for manual replay on later requests.
    private func captureSessionCookie(for url: URL) {
        guard let cookies = cookieStorage.cookies(for: url) else { return }
        if let sess = cookies.first(where: { $0.name.lowercased() == "beegosessionid" }) {
            sessionCookie = "\(sess.name)=\(sess.value)"
        }
    }

    private func endpoint(_ path: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + "/" + path)
    }

    private let formAllowed = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._*~")

    private func formEncode(_ s: String) -> String {
        let encoded = s.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? s
        return encoded.replacingOccurrences(of: " ", with: "+")
    }

    private func formBody(_ params: [String: String]) -> Data {
        let pairs = params.map { "\($0.key)=\(formEncode($0.value))" }
        return Data(pairs.joined(separator: "&").utf8)
    }

    private func isHTML(_ data: Data) -> Bool {
        guard let first = data.first else { return false }
        return first == 0x3C // '<'
    }

    private func markSessionExpired() {
        sessionExpired = true
        isLoggedIn = false
        errorMessage = "登录已过期，请重新登录"
    }

    // MARK: - Login / Logout
    @discardableResult
    func login(username: String, password: String, save: Bool = true) async -> Bool {
        guard let url = endpoint("Login/Verify") else {
            errorMessage = "请先填写服务器地址"
            return false
        }
        var req = URLRequest(url: url)
        // A previous session-expiry (e.g. the silent auto-login getting kicked)
        // must not suppress the error message of THIS attempt.
        sessionExpired = false
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formBody(["username": username, "password": password])

        do {
            let (data, response) = try await session.data(for: req)
            // Capture the NPS session cookie directly from the Set-Cookie header.
            // Relying on HTTPCookieStorage's cookies(for:) proved unreliable on iOS
            // (the session cookie was never replayed, causing an immediate logout /
            // "password disappears" when the dashboard request got redirected to the
            // login page as HTML).
            if let httpResp = response as? HTTPURLResponse,
               let setCookie = httpResp.value(forHTTPHeaderField: "Set-Cookie") {
                if let c = parseBeegoSession(from: setCookie) {
                    sessionCookie = c
                }
            }
            if sessionCookie == nil {
                captureSessionCookie(for: url) // fallback to storage
            }
            let result = try? JSONDecoder().decode(ApiResult.self, from: data)
            if result?.status == 1 {
                if save {
                    saveCredentials(url: baseURL, username: username, password: password)
                }
                sessionExpired = false
                errorMessage = nil
                isLoggedIn = true
                return true
            } else {
                if let r = result, let msg = r.msg, !msg.isEmpty {
                    errorMessage = msg
                } else if let r = result {
                    errorMessage = "登录失败（status=\(r.status ?? -1)）"
                } else {
                    // Response was not the expected JSON — surface what actually
                    // came back so misconfigured base URLs / proxies are visible.
                    let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let snippet = String(data: data.prefix(120), encoding: .utf8) ?? "(非文本响应)"
                    errorMessage = "登录失败（HTTP \(httpStatus)）：响应不是有效的登录结果，请确认地址指向 NPS 后台。服务器返回：\(snippet)"
                }
                isLoggedIn = false
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoggedIn = false
            return false
        }
    }

    /// Parse `beegosessionID=...` out of a `Set-Cookie` header value.
    /// Example header: `beegosessionID=abc123; Path=/; HttpOnly`
    private func parseBeegoSession(from header: String) -> String? {
        guard let range = header.range(of: "beegosessionID=") else { return nil }
        let after = header[range.upperBound...]
        let value = after.prefix(while: { $0 != ";" && $0 != "," })
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return nil }
        return "beegosessionID=" + v
    }

    func logout() {
        if let url = endpoint("Login/Out") {
            var req = URLRequest(url: url)
            applyAuth(&req)
            Task {
                try? await session.data(for: req)
            }
        }
        clearCredentials()
        isLoggedIn = false
    }

    // MARK: - GET (JSON table / object)
    private func get<T: Codable>(_ path: String, query: [String: String] = [:]) async -> T? {
        guard var url = endpoint(path) else { return nil }
        if !query.isEmpty {
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comps?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            if let u = comps?.url { url = u }
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyAuth(&req)
        do {
            let (data, _) = try await session.data(for: req)
            if isHTML(data) { markSessionExpired(); return nil }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - POST form -> ApiResult
    @discardableResult
    private func post(_ path: String, params: [String: String]) async -> ApiResult? {
        guard let url = endpoint(path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formBody(params)
        applyAuth(&req)
        do {
            let (data, _) = try await session.data(for: req)
            if isHTML(data) { markSessionExpired(); return nil }
            let r = try? JSONDecoder().decode(ApiResult.self, from: data)
            if let r = r, r.status != 1 {
                errorMessage = r.msg
            }
            return r
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - POST form -> SingleResponse<T>
    private func postSingle<T: Codable>(_ path: String, params: [String: String]) async -> SingleResponse<T>? {
        guard let url = endpoint(path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formBody(params)
        applyAuth(&req)
        do {
            let (data, _) = try await session.data(for: req)
            if isHTML(data) { markSessionExpired(); return nil }
            return try JSONDecoder().decode(SingleResponse<T>.self, from: data)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Clients
    func getClients(search: String = "", limit: Int = 10000) async -> [Client] {
        let resp: TableResponse<Client>? = await get("Client/List", query: [
            "offset": "0", "limit": "\(limit)", "search": search, "sort": "Id", "order": "ASC"
        ])
        return resp?.rows ?? []
    }

    func getClient(id: Int) async -> Client? {
        await postSingle("Client/GetClient", params: ["id": "\(id)"])?.data
    }

    func addClient(params: [String: String]) async -> Bool {
        await post("Client/Add", params: params)?.status == 1
    }

    func editClient(id: Int, params: [String: String]) async -> Bool {
        var p = params; p["id"] = "\(id)"
        return await post("Client/Edit", params: p)?.status == 1
    }

    func changeClientStatus(id: Int, status: Bool) async -> Bool {
        await post("Client/ChangeStatus", params: ["id": "\(id)", "status": status ? "true" : "false"])?.status == 1
    }

    func deleteClient(id: Int) async -> Bool {
        await post("Client/Del", params: ["id": "\(id)"])?.status == 1
    }

    // MARK: - Tunnels
    func getTunnels(type: String = "", clientId: Int = 0, search: String = "", limit: Int = 10000) async -> [Tunnel] {
        var q: [String: String] = ["offset": "0", "limit": "\(limit)"]
        if !type.isEmpty { q["type"] = type }
        if clientId != 0 { q["client_id"] = "\(clientId)" }
        if !search.isEmpty { q["search"] = search }
        let resp: TableResponse<Tunnel>? = await get("Index/GetTunnel", query: q)
        return resp?.rows ?? []
    }

    func getTunnel(id: Int) async -> Tunnel? {
        await postSingle("Index/GetOneTunnel", params: ["id": "\(id)"])?.data
    }

    func addTunnel(params: [String: String]) async -> Bool {
        await post("Index/Add", params: params)?.status == 1
    }

    func editTunnel(id: Int, params: [String: String]) async -> Bool {
        var p = params; p["id"] = "\(id)"
        return await post("Index/Edit", params: p)?.status == 1
    }

    func startTunnel(id: Int) async -> Bool {
        await post("Index/Start", params: ["id": "\(id)"])?.status == 1
    }

    func stopTunnel(id: Int) async -> Bool {
        await post("Index/Stop", params: ["id": "\(id)"])?.status == 1
    }

    func deleteTunnel(id: Int) async -> Bool {
        await post("Index/Del", params: ["id": "\(id)"])?.status == 1
    }

    // MARK: - Hosts
    func getHosts(clientId: Int = 0, search: String = "", limit: Int = 10000) async -> [Host] {
        var q: [String: String] = ["offset": "0", "limit": "\(limit)"]
        if clientId != 0 { q["client_id"] = "\(clientId)" }
        if !search.isEmpty { q["search"] = search }
        let resp: TableResponse<Host>? = await get("Index/HostList", query: q)
        return resp?.rows ?? []
    }

    func getHost(id: Int) async -> Host? {
        await postSingle("Index/GetHost", params: ["id": "\(id)"])?.data
    }

    func addHost(params: [String: String]) async -> Bool {
        await post("Index/AddHost", params: params)?.status == 1
    }

    func editHost(id: Int, params: [String: String]) async -> Bool {
        var p = params; p["id"] = "\(id)"
        return await post("Index/EditHost", params: p)?.status == 1
    }

    func deleteHost(id: Int) async -> Bool {
        await post("Index/DelHost", params: ["id": "\(id)"])?.status == 1
    }
}
