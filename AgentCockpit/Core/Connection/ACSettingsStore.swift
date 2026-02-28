// ACSettingsStore.swift — UserDefaults-backed gateway host/port settings
import Foundation

public enum ACTranscriptDisplayMode: String, CaseIterable, Sendable {
    case standard
    case debug
    case textOnly

    public var displayName: String {
        switch self {
        case .standard:
            return "Standard"
        case .debug:
            return "Debug"
        case .textOnly:
            return "Text Only"
        }
    }

    public var settingsDescription: String {
        switch self {
        case .standard:
            return "Balanced transcript view for regular conversation flow."
        case .debug:
            return "Show extra technical detail to help inspect session behavior."
        case .textOnly:
            return "Prioritize plain text output and minimize structured event cards."
        }
    }
}

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
        static let cfAccessClientId = "agentcockpit.auth.cfAccessClientId"
        static let cfAccessClientSecret = "agentcockpit.auth.cfAccessClientSecret"
        static let genuiEnabled = "agentcockpit.feature.genuiEnabled"
        static let implicitGenUIFromTextEnabled = "agentcockpit.feature.implicitGenUIFromTextEnabled"
        static let activityGenUIEnabled = "agentcockpit.feature.activityGenUIEnabled"
        static let transcriptDisplayMode = "agentcockpit.transcript.displayMode"
        static let snippetAgentSlug = "agentcockpit.snippets.agentSlug"
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

    public var authToken: String {
        get { ACKeychainStore.loadToken() ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                ACKeychainStore.deleteToken()
            } else {
                try? ACKeychainStore.saveToken(trimmed)
            }
        }
    }

    public var cfAccessClientId: String {
        get { UserDefaults.standard.string(forKey: Keys.cfAccessClientId) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.cfAccessClientId) }
    }

    public var cfAccessClientSecret: String {
        get { UserDefaults.standard.string(forKey: Keys.cfAccessClientSecret) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.cfAccessClientSecret) }
    }

    public var bonjourEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.bonjourEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.bonjourEnabled) }
    }

    public var genuiEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.genuiEnabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Keys.genuiEnabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.genuiEnabled) }
    }

    public var implicitGenUIFromTextEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.implicitGenUIFromTextEnabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Keys.implicitGenUIFromTextEnabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.implicitGenUIFromTextEnabled) }
    }

    public var activityGenUIEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.activityGenUIEnabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Keys.activityGenUIEnabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.activityGenUIEnabled) }
    }

    public var transcriptDisplayMode: ACTranscriptDisplayMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Keys.transcriptDisplayMode),
                  let parsed = ACTranscriptDisplayMode(rawValue: raw)
            else { return .standard }
            return parsed
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.transcriptDisplayMode) }
    }

    public var snippetAgentSlug: String {
        get { UserDefaults.standard.string(forKey: Keys.snippetAgentSlug) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.snippetAgentSlug) }
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
