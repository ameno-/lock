// ACProtocol.swift — transport + protocol message types for legacy gateway, ACP, and Codex app-server

import Foundation

// MARK: - Endpoint protocol mode

public enum ACServerProtocol: String, Codable, CaseIterable, Sendable {
    case gatewayLegacy = "gateway_legacy"
    case acp = "acp"
    case codex = "codex"

    public var displayName: String {
        switch self {
        case .gatewayLegacy: return "AgentCockpit Gateway"
        case .acp: return "ACP"
        case .codex: return "Codex App Server"
        }
    }
}

// MARK: - Stream types (legacy gateway)

public enum ACStreamType: String, Codable, Sendable {
    case tool
    case assistant
    case git
    case subagent
    case skill
    case system
}

// MARK: - Client → Server (legacy gateway)

public struct ACAuthMessage: Encodable, Sendable {
    public let type = "auth"
    public let token: String
    public init(token: String) { self.token = token }
}

public struct ACPongMessage: Encodable, Sendable {
    public let type = "pong"
    public init() {}
}

public struct ACRequestMessage: Encodable, Sendable {
    public let type = "req"
    public let id: String
    public let method: String
    public let params: ACParams?

    public init(id: String, method: String, params: ACParams? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public enum ACParams: Encodable, Sendable {
    case sessionKey(String)
    case sessionSend(sessionKey: String, text: String)

    private enum CodingKeys: String, CodingKey {
        case sessionKey, text
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sessionKey(let key):
            try container.encode(key, forKey: .sessionKey)
        case .sessionSend(let key, let text):
            try container.encode(key, forKey: .sessionKey)
            try container.encode(text, forKey: .text)
        }
    }
}

// MARK: - Client → Server (JSON-RPC transport for ACP/Codex)

public struct ACJSONRPCRequestMessage: Encodable, Sendable {
    public let jsonrpc = "2.0"
    public let id: String
    public let method: String
    public let params: [String: AnyCodable]?

    public init(id: String, method: String, params: [String: AnyCodable]? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct ACJSONRPCNotificationMessage: Encodable, Sendable {
    public let jsonrpc = "2.0"
    public let method: String
    public let params: [String: AnyCodable]?

    public init(method: String, params: [String: AnyCodable]? = nil) {
        self.method = method
        self.params = params
    }
}

public struct ACJSONRPCResponseMessage: Encodable, Sendable {
    public let jsonrpc = "2.0"
    public let id: String
    public let result: AnyCodable?
    public let error: ACJSONRPCErrorPayload?

    public init(id: String, result: AnyCodable? = nil, error: ACJSONRPCErrorPayload? = nil) {
        self.id = id
        self.result = result
        self.error = error
    }
}

public struct ACJSONRPCErrorPayload: Codable, Sendable {
    public let code: Int
    public let message: String
    public let data: [String: AnyCodable]?

    public init(code: Int, message: String, data: [String: AnyCodable]? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

// MARK: - Server → Client

public enum ACServerMessage: Sendable {
    case authOk
    case authErr(message: String)
    case ping
    case response(id: String, result: ACResult)
    case event(ACEventFrame)
    case jsonrpcResponse(id: String, result: AnyCodable?, error: ACJSONRPCErrorPayload?)
    case jsonrpcNotification(method: String, params: [String: AnyCodable]?)
    case jsonrpcRequest(id: String, method: String, params: [String: AnyCodable]?)
    case unknown(String)
}

public enum ACResult: Sendable {
    case sessions([ACSessionEntry])
    case ok(Bool)
    case error(code: Int, message: String)
    case raw([String: AnyCodable])
}

public struct ACEventFrame: Sendable {
    public let sessionKey: String
    public let seq: Int
    public let stream: ACStreamType
    public let data: [String: AnyCodable]
    public let ts: Date
}

public struct ACSessionEntry: Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let window: String
    public let pane: String
    public let running: Bool
    public let promoted: Bool
    public let createdAt: Date
    public let preview: String?
    public let statusText: String?
    public let updatedAt: Date?

    public init(
        key: String,
        name: String,
        window: String,
        pane: String,
        running: Bool,
        promoted: Bool,
        createdAt: Date,
        preview: String? = nil,
        statusText: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.key = key
        self.name = name
        self.window = window
        self.pane = pane
        self.running = running
        self.promoted = promoted
        self.createdAt = createdAt
        self.preview = preview
        self.statusText = statusText
        self.updatedAt = updatedAt
    }
}

// MARK: - AnyCodable helper

public struct AnyCodable: Codable, Sendable, CustomStringConvertible {
    public let value: any Sendable

    public var description: String { "\(value)" }

    public init(_ value: some Sendable) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { value = v }
        else if let v = try? container.decode(Int.self) { value = v }
        else if let v = try? container.decode(Double.self) { value = v }
        else if let v = try? container.decode(String.self) { value = v }
        else if let v = try? container.decode([String: AnyCodable].self) { value = v }
        else if let v = try? container.decode([AnyCodable].self) { value = v }
        else if container.decodeNil() { value = NSNull() }
        else { value = "<undecodable>" }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Bool: try container.encode(v)
        case let v as Int: try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as String: try container.encode(v)
        case let v as [String: AnyCodable]: try container.encode(v)
        case let v as [AnyCodable]: try container.encode(v)
        default: try container.encodeNil()
        }
    }

    public var stringValue: String? { value as? String }
    public var boolValue: Bool? { value as? Bool }
    public var intValue: Int? { value as? Int }
    public var doubleValue: Double? {
        if let v = value as? Double { return v }
        if let v = value as? Int { return Double(v) }
        return nil
    }
    public var dictValue: [String: AnyCodable]? { value as? [String: AnyCodable] }
    public var arrayValue: [AnyCodable]? { value as? [AnyCodable] }
}

// MARK: - Parser

public enum ACMessageParser {
    public static func parse(_ data: Data) -> ACServerMessage {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown(String(data: data, encoding: .utf8) ?? "<binary>")
        }

        if let jsonrpcMessage = parseJSONRPC(json) {
            return jsonrpcMessage
        }

        guard let type = json["type"] as? String else {
            return .unknown(String(data: data, encoding: .utf8) ?? "<binary>")
        }

        switch type {
        case "auth_ok":
            return .authOk

        case "auth_err":
            let msg = json["message"] as? String ?? "Unknown error"
            return .authErr(message: msg)

        case "ping":
            return .ping

        case "res":
            guard let id = json["id"] as? String else { return .unknown(type) }
            if let error = json["error"] as? [String: Any] {
                let code = error["code"] as? Int ?? 0
                let msg = error["message"] as? String ?? "Unknown"
                return .response(id: id, result: .error(code: code, message: msg))
            }
            let result = parseResult(json["result"])
            return .response(id: id, result: result)

        case "event":
            guard let sessionKey = json["sessionKey"] as? String,
                  let seq = json["seq"] as? Int,
                  let streamRaw = json["stream"] as? String,
                  let tsMs = json["ts"] as? Double
            else { return .unknown(type) }

            let stream = ACStreamType(rawValue: streamRaw) ?? .system
            let dataRaw = json["data"] as? [String: Any] ?? [:]
            let frame = ACEventFrame(
                sessionKey: sessionKey,
                seq: seq,
                stream: stream,
                data: encodeDictionary(dataRaw),
                ts: Date(timeIntervalSince1970: tsMs / 1000)
            )
            return .event(frame)

        default:
            return .unknown(type)
        }
    }

    private static func parseJSONRPC(_ json: [String: Any]) -> ACServerMessage? {
        if let method = json["method"] as? String {
            let params = (json["params"] as? [String: Any]).map(encodeDictionary)
            if let idRaw = json["id"] {
                return .jsonrpcRequest(
                    id: stringifyID(idRaw),
                    method: method,
                    params: params
                )
            }
            return .jsonrpcNotification(method: method, params: params)
        }

        guard let idRaw = json["id"], json["result"] != nil || json["error"] != nil else {
            return nil
        }

        let parsedError: ACJSONRPCErrorPayload?
        if let errorRaw = json["error"] as? [String: Any] {
            parsedError = ACJSONRPCErrorPayload(
                code: errorRaw["code"] as? Int ?? 0,
                message: errorRaw["message"] as? String ?? "Unknown JSON-RPC error",
                data: (errorRaw["data"] as? [String: Any]).map(encodeDictionary)
            )
        } else {
            parsedError = nil
        }

        return .jsonrpcResponse(
            id: stringifyID(idRaw),
            result: json["result"].map(encodeAny),
            error: parsedError
        )
    }

    private static func parseResult(_ raw: Any?) -> ACResult {
        guard let raw else { return .ok(false) }

        if let arr = raw as? [[String: Any]] {
            let sessions = arr.compactMap(parseSession)
            return .sessions(sessions)
        }
        if let dict = raw as? [String: Any] {
            if let ok = dict["ok"] as? Bool { return .ok(ok) }
            return .raw(encodeDictionary(dict))
        }
        return .ok(false)
    }

    private static func parseSession(_ dict: [String: Any]) -> ACSessionEntry? {
        guard let key = dict["key"] as? String,
              let name = dict["name"] as? String
        else { return nil }
        let createdMs = dict["createdAt"] as? Double ?? 0
        let updatedMs = dict["updatedAt"] as? Double
        return ACSessionEntry(
            key: key,
            name: name,
            window: dict["window"] as? String ?? "0",
            pane: dict["pane"] as? String ?? "0",
            running: dict["running"] as? Bool ?? true,
            promoted: dict["promoted"] as? Bool ?? false,
            createdAt: Date(timeIntervalSince1970: createdMs / 1000),
            preview: dict["preview"] as? String,
            statusText: dict["status"] as? String,
            updatedAt: updatedMs.map { Date(timeIntervalSince1970: $0 / 1000) }
        )
    }

    private static func stringifyID(_ idRaw: Any) -> String {
        switch idRaw {
        case let v as String: return v
        case let v as Int: return String(v)
        case let v as Double:
            let i = Int(v)
            return abs(Double(i) - v) < 0.000_001 ? String(i) : String(v)
        default: return String(describing: idRaw)
        }
    }

    private static func encodeDictionary(_ dict: [String: Any]) -> [String: AnyCodable] {
        var mapped: [String: AnyCodable] = [:]
        for (k, v) in dict {
            mapped[k] = encodeAny(v)
        }
        return mapped
    }

    private static func encodeAny(_ value: Any) -> AnyCodable {
        switch value {
        case let v as Bool: return AnyCodable(v)
        case let v as Int: return AnyCodable(v)
        case let v as Double: return AnyCodable(v)
        case let v as String: return AnyCodable(v)
        case let v as [String: Any]:
            return AnyCodable(encodeDictionary(v))
        case let v as [Any]:
            return AnyCodable(v.map { encodeAny($0) })
        default:
            return AnyCodable("<undecodable>")
        }
    }
}
