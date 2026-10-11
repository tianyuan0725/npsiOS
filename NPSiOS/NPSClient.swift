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
    @Published var errorMessage: String?
    @Published var sessionExpired: Bool = false

    private var session: URLSession
    private let cookieStorage = HTTPCookieStorage.shared

    private let kBase = "baseURL"
    private let kUser = "username"
    private let kPass = "password"

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = cookieStorage
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)

        // Restore previously saved credentials and silently re-login.
        if let url = KeychainHelper.read(account: kBase),
           let user = KeychainHelper.read(account: kUser),
           let pass = KeychainHelper.read(account: kPass) {
            self.baseURL = url
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
        if let cookies = cookieStorage.cookies {
            for c in cookies { cookieStorage.deleteCookie(c) }
        }
    }

    // MARK: - URL building
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
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formBody(["username": username, "password": password])

        do {
            let (data, _) = try await session.data(for: req)
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
                errorMessage = result?.msg ?? "登录失败"
                isLoggedIn = false
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoggedIn = false
            return false
        }
    }

    func logout() {
        if let url = endpoint("Login/Out") {
            Task {
                try? await session.data(for: URLRequest(url: url))
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
