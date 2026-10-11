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
    /// HTTP status of the last session-probe request (for diagnostics only).
    private var lastProbeStatus: Int = 0
    /// How the last login attempt went about capturing the session cookie.
    private var lastCaptureNote: String = "无"
    /// What happened on the last session probe.
    private var lastProbeNote: String = "无"

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
        // Accept every cookie into storage so the storage-based fallback capture
        // (captureSessionCookie) can never be silently blocked by the accept
        // policy on some iOS versions.
        config.httpCookieAcceptPolicy = .always
        HTTPCookieStorage.shared.cookieAcceptPolicy = .always
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
        // Move any legacy single-account credentials into the multi-account
        // store (no-op when the account list already exists).
        AccountStore.migrateLegacy()
        // NOTE: no silent auto-login here on purpose. A background auto-login races
        // with a manual login: the late auto-login response overwrites the FRESH
        // sessionCookie captured by the manual one (NPS invalidates/rotates session
        // data), so dashboard requests get 302'd back to the login page seconds after
        // successfully entering the app. Login is always explicit now.
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

    private func markSessionExpired(path: String, httpStatus: Int) {
        sessionExpired = true
        isLoggedIn = false
        let fp = cookieFingerprint()
        if sessionCookie == nil {
            errorMessage = "会话Cookie未捕获，请求被重定向到登录页。路径 \(path)，HTTP \(httpStatus)。请重新登录。"
        } else {
            errorMessage = "服务器拒绝了会话并跳转登录页。路径 \(path)，HTTP \(httpStatus)，Cookie指纹 \(fp)。请重试一次登录；若反复出现请把此提示截图反馈。"
        }
    }

    /// Last 6 chars of the captured cookie — enough to tell whether the cookie
    /// being replayed is the same one the server issued at login.
    private func cookieFingerprint() -> String {
        guard let c = sessionCookie else { return "无" }
        return String(c.suffix(6))
    }

    // MARK: - Login / Logout
    @discardableResult
    func login(username: String, password: String, save: Bool = true) async -> Bool {
        sessionExpired = false
        for _ in 1...2 {
            guard await loginOnce(username: username, password: password, save: save) else {
                // Credentials wrong / network error / non-JSON response — the
                // specific message is already set; never auto-retry these.
                isLoggedIn = false
                return false
            }
            // The server accepted the credentials. Verify the session actually
            // works BEFORE entering the dashboard, so a cookie problem surfaces
            // here (with detail) instead of as a mysterious bounce afterwards.
            let (ok, status, note) = await probeWithSession()
            lastProbeStatus = status
            lastProbeNote = note
            if ok {
                sessionExpired = false
                errorMessage = nil
                isLoggedIn = true
                return true
            }
            // Session rejected — drop the captured cookie and try once more
            // with a completely fresh login round (fresh session from server).
            sessionCookie = nil
        }
        errorMessage = "登录接口成功，但服务器拒绝了会话（已自动重试1次）。捕获：\(lastCaptureNote)。探测：\(lastProbeNote)。这不是密码错误。请用手机 Safari 打开同一地址测试网页版能否正常登录使用，并把本条截图反馈。"
        isLoggedIn = false
        return false
    }

    /// One raw login POST. Returns true only when the server reports success;
    /// captures the session cookie from Set-Cookie on the way.
    private func loginOnce(username: String, password: String, save: Bool) async -> Bool {
        guard let url = endpoint("Login/Verify") else {
            errorMessage = "请先填写服务器地址"
            return false
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formBody(["username": username, "password": password])

        do {
            let (data, response) = try await session.data(for: req)
            // Capture the NPS session cookie (beegosessionID) from the response.
            // value(forHTTPHeaderField:) proved unreliable on-device; enumerate
            // allHeaderFields instead and fall back to the cookie storage.
            var captureNote = "响应无Set-Cookie头"
            if let httpResp = response as? HTTPURLResponse {
                let raws = extractSetCookieHeaders(httpResp)
                if raws.isEmpty {
                    captureNote = "响应无Set-Cookie头"
                } else {
                    var parsed: String?
                    for raw in raws {
                        if let c = parseBeegoSession(from: raw) { parsed = c; break }
                    }
                    if let c = parsed {
                        sessionCookie = c
                        captureNote = "已从Set-Cookie捕获，指纹 \(cookieFingerprint())"
                    } else {
                        captureNote = "有Set-Cookie头(\(raws.count)条)但未解析出beegosessionID：\(raws.joined(separator: " | ").prefix(140))"
                    }
                }
            }
            if sessionCookie == nil {
                captureSessionCookie(for: url)
                if sessionCookie != nil {
                    captureNote += "；存储兜底捕获成功，指纹 \(cookieFingerprint())"
                } else {
                    captureNote += "；存储兜底也没有"
                }
            }
            lastCaptureNote = captureNote

            let result = try? JSONDecoder().decode(ApiResult.self, from: data)
            if result?.status == 1 {
                if save {
                    saveCredentials(url: baseURL, username: username, password: password)
                }
                return true
            }
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
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Collect every Set-Cookie header value from the response, robust against
    /// iOS header-merging quirks (multiple headers may arrive comma-joined).
    private func extractSetCookieHeaders(_ resp: HTTPURLResponse) -> [String] {
        var out: [String] = []
        for (k, v) in resp.allHeaderFields {
            if let key = k as? String, key.lowercased() == "set-cookie",
               let val = v as? String {
                // A comma-joined value may contain several cookies; keep the raw
                // string — parseBeegoSession scans segments for beegosessionID.
                out.append(val)
            }
        }
        if out.isEmpty, let v = resp.value(forHTTPHeaderField: "Set-Cookie") {
            out.append(v)
        }
        return out
    }

    /// Raw session probe: a cookie-carrying POST to the client table must return
    /// a JSON table (ok). Without a valid session the server redirects to the
    /// login page (HTML). Does not touch error state.
    private func probeWithSession() async -> (Bool, Int, String) {
        guard let url = endpoint("client/list") else { return (false, 0, "地址为空") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formBody(["offset": "0", "limit": "1", "search": "", "sort": "", "order": ""])
        applyAuth(&req)
        let carried = sessionCookie != nil ? "有(指纹 \(cookieFingerprint()))" : "无(裸请求)"
        do {
            let (data, resp) = try await session.data(for: req)
            let st = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let ok = !isHTML(data)
            return (ok, st, "携带Cookie=\(carried)，HTTP \(st)，响应=\(ok ? "JSON表格" : "HTML登录页")")
        } catch {
            return (false, 0, "携带Cookie=\(carried)，网络错误：\(error.localizedDescription)")
        }
    }

    /// Parse `beegosessionID=...` out of a `Set-Cookie` header value.
    /// Example header: `beegosessionID=abc123; Path=/; HttpOnly`
    /// Case-insensitive, tolerates multiple cookies joined by ",".
    private func parseBeegoSession(from header: String) -> String? {
        let parts = header.split(whereSeparator: { $0 == ";" || $0 == "," })
        for p in parts {
            let s = p.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.lowercased().hasPrefix("beegosessionid=") {
                let v = String(s.dropFirst("beegosessionid=".count))
                if !v.isEmpty {
                    return "beegosessionID=" + v
                }
            }
        }
        return nil
    }

    /// Log out of the current session but KEEP all saved accounts. The login
    /// screen will be pre-filled with the last-used address / username /
    /// password, so switching back or re-logging in needs zero typing.
    /// Use `clearCredentials()` only when something must be truly wiped.
    func logout() {
        if let url = endpoint("Login/Out") {
            var req = URLRequest(url: url)
            applyAuth(&req)
            Task {
                try? await session.data(for: req)
            }
        }
        // Drop only the live session state.
        sessionCookie = nil
        if let cookies = cookieStorage.cookies {
            for c in cookies { cookieStorage.deleteCookie(c) }
        }
        errorMessage = nil
        sessionExpired = false
        isLoggedIn = false
    }

    // MARK: - POST form -> JSON table
    /// NPS serves list data ONLY via POST — the web panel's bootstrap-table posts
    /// to the very URL that, on GET, renders the HTML page instead. Requesting
    /// lists with GET returned that page HTML, which the app misread as "session
    /// expired" and caused the endless auto-logout loop.
    private func postTable<T: Codable>(_ path: String, params: [String: String]) async -> TableResponse<T>? {
        guard let url = endpoint(path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formBody(params)
        applyAuth(&req)
        do {
            let (data, resp) = try await session.data(for: req)
            let st = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if isHTML(data) { markSessionExpired(path: path, httpStatus: st); return nil }
            return try JSONDecoder().decode(TableResponse<T>.self, from: data)
        } catch {
            // After logout (or view dismissal) in-flight requests get cancelled
            // and land here. Surfacing that would show a stale "网络错误:
            // cancelled" on the login screen right after logging out.
            guard isLoggedIn, !Task.isCancelled else { return nil }
            errorMessage = "网络错误（\(path)）：\(error.localizedDescription)"
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
            let (data, resp) = try await session.data(for: req)
            let st = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if isHTML(data) { markSessionExpired(path: path, httpStatus: st); return nil }
            let r = try? JSONDecoder().decode(ApiResult.self, from: data)
            if let r = r, r.status != 1 {
                errorMessage = r.msg
            }
            return r
        } catch {
            // After logout (or view dismissal) in-flight requests get cancelled
            // and land here. Surfacing that would show a stale "网络错误:
            // cancelled" on the login screen right after logging out.
            guard isLoggedIn, !Task.isCancelled else { return nil }
            errorMessage = "网络错误（\(path)）：\(error.localizedDescription)"
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
            let (data, resp) = try await session.data(for: req)
            let st = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if isHTML(data) { markSessionExpired(path: path, httpStatus: st); return nil }
            return try JSONDecoder().decode(SingleResponse<T>.self, from: data)
        } catch {
            // After logout (or view dismissal) in-flight requests get cancelled
            // and land here. Surfacing that would show a stale "网络错误:
            // cancelled" on the login screen right after logging out.
            guard isLoggedIn, !Task.isCancelled else { return nil }
            errorMessage = "网络错误（\(path)）：\(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Clients
    func getClients(search: String = "", limit: Int = 10000) async -> [Client] {
        // NOTE: sort/order MUST stay empty — NPS panics (beego 500) on sort=Id.
        let resp: TableResponse<Client>? = await postTable("client/list", params: [
            "offset": "0", "limit": "\(limit)", "search": search, "sort": "", "order": ""
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
    /// NPS only matches tunnels with an explicit `type` (an empty type matches
    /// nothing — verified against the live server), so query every known mode
    /// and merge, mirroring the panel's per-type pages.
    func getTunnels(type: String = "", clientId: Int = 0, search: String = "", limit: Int = 10000) async -> [Tunnel] {
        let types = type.isEmpty
            ? ["tcp", "udp", "socks5", "httpProxy", "file", "secret", "p2p"]
            : [type]
        var all: [Tunnel] = []
        for t in types {
            var p: [String: String] = ["offset": "0", "limit": "\(limit)", "search": search, "type": t]
            if clientId != 0 { p["client_id"] = "\(clientId)" }
            let r: TableResponse<Tunnel>? = await postTable("index/gettunnel", params: p)
            if let r = r { all.append(contentsOf: r.rows) }
        }
        return all
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
        var p: [String: String] = ["offset": "0", "limit": "\(limit)", "search": search]
        if clientId != 0 { p["client_id"] = "\(clientId)" }
        let resp: TableResponse<Host>? = await postTable("index/hostlist", params: p)
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
