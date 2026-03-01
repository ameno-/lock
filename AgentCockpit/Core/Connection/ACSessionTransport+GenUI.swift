// ACSessionTransport+GenUI.swift — GenUI action methods
import Foundation

@MainActor
extension ACSessionTransport {
    func submitGenUIActionInternal(sessionKey: String, event: GenUIEvent) async throws {
        var payload = try validatedGenUIActionPayload(from: event)
        payload["surfaceId"] = AnyCodable(event.surfaceID)
        payload["schemaVersion"] = AnyCodable(event.schemaVersion)
        payload["revision"] = AnyCodable(event.revision)
        payload["mode"] = AnyCodable(event.mode == .patch ? "patch" : "snapshot")
        if let correlationID = event.correlationID {
            payload["correlationId"] = AnyCodable(correlationID)
        }
        if payload["context"] == nil, !event.contextPayload.isEmpty {
            payload["context"] = AnyCodable(event.contextPayload)
        }

        switch settings.serverProtocol {
        case .acp:
            try await ensureACPSessionLoaded(sessionKey: sessionKey)
            payload["sessionId"] = AnyCodable(sessionKey)
            guard let method = resolvedGenUIActionMethod(for: .acp) else {
                throw ACTransportError.invalidRequest(
                    "Server does not advertise a GenUI action callback method for ACP."
                )
            }
            _ = try await requestJSON(method: method, params: payload)

        case .codex:
            try await ensureCodexThreadResumed(sessionKey: sessionKey)
            payload["threadId"] = AnyCodable(sessionKey)
            guard let method = resolvedGenUIActionMethod(for: .codex) else {
                throw ACTransportError.invalidRequest(
                    "Connected Codex server does not advertise GenUI action callbacks."
                )
            }
            _ = try await requestJSON(method: method, params: payload)
        }
    }

    func validatedGenUIActionPayload(from event: GenUIEvent) throws -> [String: AnyCodable] {
        var payload = event.actionPayload
        if payload.isEmpty, let actionLabel = event.actionLabel {
            let fallback = actionLabel
                .lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.isEmpty {
                payload["actionId"] = AnyCodable(fallback)
                payload["label"] = AnyCodable(actionLabel)
            }
        }

        let actionLabelFallback = event.actionLabel?
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        let directActionID = payload["actionId"]?.stringValue
        let underscoredActionID = payload["action_id"]?.stringValue
        let idField = payload["id"]?.stringValue
        let typeField = payload["type"]?.stringValue
        let kindField = payload["kind"]?.stringValue
        let actionID = firstNonEmptyString(
            directActionID,
            underscoredActionID,
            idField,
            typeField,
            kindField,
            actionLabelFallback
        )

        guard let actionID,
              !actionID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
        else {
            throw ACTransportError.invalidRequest("GenUI action missing actionId/type")
        }

        payload["actionId"] = AnyCodable(actionID)
        if payload["surfaceId"] == nil {
            payload["surfaceId"] = AnyCodable(event.surfaceID)
        }
        if payload["schemaVersion"] == nil {
            payload["schemaVersion"] = AnyCodable(event.schemaVersion)
        }
        if payload["revision"] == nil {
            payload["revision"] = AnyCodable(event.revision)
        }
        if payload["mode"] == nil {
            payload["mode"] = AnyCodable(event.mode == .patch ? "patch" : "snapshot")
        }
        if payload["context"] == nil, !event.contextPayload.isEmpty {
            payload["context"] = AnyCodable(event.contextPayload)
        }
        if payload["correlationId"] == nil, let correlationID = event.correlationID {
            payload["correlationId"] = AnyCodable(correlationID)
        }

        let rawPayload = ACPProtocolParser.compactJSONString(from: payload)
        if rawPayload.count > 32_000 {
            throw ACTransportError.invalidRequest("GenUI action payload too large")
        }
        return payload
    }

    func resolvedGenUIActionMethod(for protocolMode: ACServerProtocol) -> String? {
        if let cached = negotiatedGenUIActionMethodByProtocol[protocolMode] {
            return cached
        }
        if let resolved = Self.resolveGenUIActionMethod(
            for: protocolMode,
            advertisedMethods: serverAdvertisedMethods
        ) {
            negotiatedGenUIActionMethodByProtocol[protocolMode] = resolved
            return resolved
        }
        return nil
    }

    nonisolated static func genUIActionMethodCandidates(for protocolMode: ACServerProtocol) -> [String] {
        switch protocolMode {
        case .acp:
            return [
                "genui/action",
                "genui/submitAction",
                "gen_ui/action",
                "session/genui/action",
                "session/gen_ui/action",
            ]
        case .codex:
            return [
                "genui/action",
                "genui/submitAction",
                "gen_ui/action",
                "item/genui/action",
                "item/gen_ui/action",
            ]
        }
    }

    nonisolated static func negotiateGenUIActionMethod(
        for protocolMode: ACServerProtocol,
        advertisedMethods: Set<String>
    ) -> String? {
        let candidates = genUIActionMethodCandidates(for: protocolMode)
        guard !advertisedMethods.isEmpty else {
            return protocolMode == .acp ? candidates.first : nil
        }

        let normalizedLookup = Dictionary(
            uniqueKeysWithValues: advertisedMethods.map {
                ($0.lowercased(), $0)
            }
        )
        for candidate in candidates {
            if let matched = normalizedLookup[candidate.lowercased()] {
                return matched
            }
        }
        return nil
    }

    nonisolated static func resolveGenUIActionMethod(
        for protocolMode: ACServerProtocol,
        advertisedMethods: Set<String>
    ) -> String? {
        if let negotiated = negotiateGenUIActionMethod(
            for: protocolMode,
            advertisedMethods: advertisedMethods
        ) {
            return negotiated
        }
        if protocolMode == .acp, advertisedMethods.isEmpty {
            return genUIActionMethodCandidates(for: protocolMode).first ?? "genui/action"
        }
        return nil
    }

    nonisolated static func advertisedMethods(fromInitializeResult result: AnyCodable?) -> Set<String> {
        guard let root = result?.dictValue else { return [] }
        var methods: Set<String> = []
        collectAdvertisedMethods(from: root, into: &methods, depth: 0)
        return methods
    }

    private nonisolated static func collectAdvertisedMethods(
        from dictionary: [String: AnyCodable],
        into methods: inout Set<String>,
        depth: Int
    ) {
        guard depth < 8 else { return }
        for (key, value) in dictionary {
            if key.contains("/") {
                methods.insert(key)
            }

            if let text = value.stringValue,
               text.contains("/") {
                methods.insert(text)
            }

            if let array = value.arrayValue {
                for item in array {
                    if let method = item.stringValue,
                       method.contains("/") {
                        methods.insert(method)
                    } else if let dict = item.dictValue {
                        if let method = dict["name"]?.stringValue, method.contains("/") {
                            methods.insert(method)
                        }
                        collectAdvertisedMethods(from: dict, into: &methods, depth: depth + 1)
                    }
                }
            }

            if let nested = value.dictValue {
                if let method = nested["method"]?.stringValue, method.contains("/") {
                    methods.insert(method)
                }
                if let method = nested["name"]?.stringValue, method.contains("/") {
                    methods.insert(method)
                }
                collectAdvertisedMethods(from: nested, into: &methods, depth: depth + 1)
            }
        }
    }

    func firstNonEmptyString(_ values: String?...) -> String? {
        for value in values {
            if let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
               !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}
