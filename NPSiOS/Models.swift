import Foundation
// (Models are pure Codable structs; Foundation/Codable are available here.)

// MARK: - Flow
struct Flow: Codable {
    var exportFlow: Int64?
    var inletFlow: Int64?
    var flowLimit: Int64?

    enum CodingKeys: String, CodingKey {
        case exportFlow = "ExportFlow"
        case inletFlow = "InletFlow"
        case flowLimit = "FlowLimit"
    }
}

// MARK: - Config (client connection config)
struct Config: Codable {
    var u: String?
    var p: String?
    var compress: Bool?
    var crypt: Bool?

    enum CodingKeys: String, CodingKey {
        case u = "U"
        case p = "P"
        case compress = "Compress"
        case crypt = "Crypt"
    }
}

// MARK: - Target (used by tunnel/host)
struct Target: Codable {
    var targetStr: String?
    var localProxy: Bool?
    var targetArr: [String]?

    enum CodingKeys: String, CodingKey {
        case targetStr = "TargetStr"
        case localProxy = "LocalProxy"
        case targetArr = "TargetArr"
    }
}

// MARK: - Client
struct Client: Codable, Identifiable {
    var id: Int
    var cnf: Config?
    var verifyKey: String?
    var addr: String?
    var remark: String?
    var status: Bool?
    var isConnect: Bool?
    var rateLimit: Int?
    var flow: Flow?
    var maxConn: Int?
    var nowConn: Int?
    var webUserName: String?
    var maxTunnelNum: Int?
    var version: String?
    var configConnAllow: Bool?
    var noDisplay: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case cnf = "Cnf"
        case verifyKey = "VerifyKey"
        case addr = "Addr"
        case remark = "Remark"
        case status = "Status"
        case isConnect = "IsConnect"
        case rateLimit = "RateLimit"
        case flow = "Flow"
        case maxConn = "MaxConn"
        case nowConn = "NowConn"
        case webUserName = "WebUserName"
        case maxTunnelNum = "MaxTunnelNum"
        case version = "Version"
        case configConnAllow = "ConfigConnAllow"
        case noDisplay = "NoDisplay"
    }

    var displayName: String {
        if let r = remark, !r.isEmpty { return r }
        return "客户端 #\(id)"
    }
}

// MARK: - Tunnel
struct Tunnel: Codable, Identifiable {
    var id: Int
    var port: Int?
    var serverIp: String?
    var mode: String?
    var status: Bool?
    var runStatus: Bool?
    var client: Client?
    var flow: Flow?
    var password: String?
    var remark: String?
    var targetAddr: String?
    var localPath: String?
    var stripPre: String?
    var target: Target?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case port = "Port"
        case serverIp = "ServerIp"
        case mode = "Mode"
        case status = "Status"
        case runStatus = "RunStatus"
        case client = "Client"
        case flow = "Flow"
        case password = "Password"
        case remark = "Remark"
        case targetAddr = "TargetAddr"
        case localPath = "LocalPath"
        case stripPre = "StripPre"
        case target = "Target"
    }

    var displayName: String {
        if let r = remark, !r.isEmpty { return r }
        return "隧道 #\(id)"
    }

    var targetString: String {
        target?.targetStr ?? targetAddr ?? "-"
    }

    static let modes = ["tcp", "udp", "socks5", "httpProxy", "secret", "p2p"]

    var modeLabel: String {
        switch mode {
        case "tcp": return "TCP"
        case "udp": return "UDP"
        case "socks5": return "Socks5"
        case "httpProxy": return "HTTP代理"
        case "secret": return "私密"
        case "p2p": return "P2P"
        default: return mode ?? "未知"
        }
    }
}

// MARK: - Host
struct Host: Codable, Identifiable {
    var id: Int
    var host: String?
    var headerChange: String?
    var hostChange: String?
    var location: String?
    var remark: String?
    var scheme: String?
    var certFilePath: String?
    var keyFilePath: String?
    var isClose: Bool?
    var flow: Flow?
    var client: Client?
    var target: Target?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case host = "Host"
        case headerChange = "HeaderChange"
        case hostChange = "HostChange"
        case location = "Location"
        case remark = "Remark"
        case scheme = "Scheme"
        case certFilePath = "CertFilePath"
        case keyFilePath = "KeyFilePath"
        case isClose = "IsClose"
        case flow = "Flow"
        case client = "Client"
        case target = "Target"
    }

    var displayName: String {
        if let r = remark, !r.isEmpty { return r }
        return host ?? "主机 #\(id)"
    }

    var targetString: String { target?.targetStr ?? "-" }
}

// MARK: - Generic responses
struct TableResponse<T: Codable>: Codable {
    var rows: [T]
    var total: Int?
}

struct SingleResponse<T: Codable>: Codable {
    var code: Int?
    var data: T?
    var msg: String?
}

struct ApiResult: Codable {
    var status: Int?
    var msg: String?
}
