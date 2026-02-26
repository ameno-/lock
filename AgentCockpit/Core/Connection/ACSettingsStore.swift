// ACSettingsStore.swift — UserDefaults-backed gateway host/port settings
import Foundation

@Observable
@MainActor
public final class ACSettingsStore {
    private enum Keys {
        static let host = "agentcockpit.gateway.host"
        static let port = "agentcockpit.gateway.port"
        static let scheme = "agentcockpit.gateway.scheme"
        static let path = "agentcockpit.gateway.path"
        static let protocolMode = "agentcockpit.gateway.protocol"
        static let workingDirectory = "agentcockpit.gateway.workingDirectory"
        static let bonjourEnabled = "agentcockpit.bonjour.enabled"
    }

    public var host: String {
        get { UserDefaults.standard.string(forKey: Keys.host) ?? "127.0.0.1" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.host) }
    }

    public var port: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: Keys.port)
            return v > 0 ? v : 8788
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.port) }
    }

    public var scheme: String {
        get { UserDefaults.standard.string(forKey: Keys.scheme) ?? "ws" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.scheme) }
    }

    public var path: String {
        get { UserDefaults.standard.string(forKey: Keys.path) ?? "/" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.path) }
    }

    public var serverProtocol: ACServerProtocol {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Keys.protocolMode),
                  let parsed = ACServerProtocol(rawValue: raw)
            else { return .codex }
            return parsed
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.protocolMode) }
    }

    public var workingDirectory: String {
        get { UserDefaults.standard.string(forKey: Keys.workingDirectory) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.workingDirectory) }
    }

    public var bonjourEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.bonjourEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.bonjourEnabled) }
    }

    public var wsURL: URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        components.path = normalizedPath.isEmpty ? "/" : normalizedPath
        return components.url ?? URL(string: "\(scheme)://\(host):\(port)\(normalizedPath)")!
    }

    public init() {}
}
