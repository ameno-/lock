import Foundation

enum SessionReorientationSynthesizer {
    static func synthesize(
        sessionKey: String,
        digest: SessionDigest?,
        recentEvents: [CanvasEvent]
    ) -> GenUIEvent? {
        guard !recentEvents.isEmpty else { return nil }

        var components: [AnyCodable] = []

        if let digest {
            var kvPairs: [AnyCodable] = []

            if let status = digest.status {
                kvPairs.append(AnyCodable([
                    "id": AnyCodable("status"),
                    "key": AnyCodable("Status"),
                    "value": AnyCodable(status),
                ]))
            }

            if let lastEvent = digest.lastEventAt {
                let elapsed = Int(Date.now.timeIntervalSince(lastEvent))
                let formatted = formatDuration(elapsed)
                kvPairs.append(AnyCodable([
                    "id": AnyCodable("last-activity"),
                    "key": AnyCodable("Last Activity"),
                    "value": AnyCodable("\(formatted) ago"),
                ]))
            }

            if let usage = digest.tokenUsage {
                if let total = usage.totalTokens {
                    kvPairs.append(AnyCodable([
                        "id": AnyCodable("tokens"),
                        "key": AnyCodable("Tokens"),
                        "value": AnyCodable(formatNumber(total)),
                    ]))
                }
            }

            if !kvPairs.isEmpty {
                components.append(AnyCodable([
                    "id": AnyCodable("session-info"),
                    "type": AnyCodable("key_value"),
                    "title": AnyCodable("Session"),
                    "pairs": AnyCodable(kvPairs),
                ]))
            }
        }

        let recentSteps = buildTimelineSteps(from: recentEvents)
        if !recentSteps.isEmpty {
            components.append(AnyCodable([
                "id": AnyCodable("recent-activity"),
                "type": AnyCodable("timeline"),
                "title": AnyCodable("Recent Activity"),
                "steps": AnyCodable(recentSteps),
            ]))
        }

        if let preview = digest?.previewText, !preview.isEmpty {
            components.append(AnyCodable([
                "id": AnyCodable("current-context"),
                "type": AnyCodable("text"),
                "text": AnyCodable(preview),
            ]))
        }

        guard !components.isEmpty else { return nil }

        components.append(AnyCodable([
            "id": AnyCodable("actions"),
            "type": AnyCodable("actions"),
            "actions": AnyCodable([
                AnyCodable(["id": AnyCodable("dismiss"), "label": AnyCodable("Dismiss")]),
            ]),
        ]))

        return GenUIEvent(
            id: "reorientation/\(sessionKey)",
            schemaVersion: "v0",
            mode: .snapshot,
            surfaceID: "session.reorientation",
            revision: Int(Date.now.timeIntervalSince1970),
            correlationID: "reorientation-\(sessionKey)",
            title: "Session Overview",
            body: digest?.previewText ?? "Resuming session",
            surfacePayload: ["components": AnyCodable(components)],
            contextPayload: [
                "pinned": AnyCodable(true),
                "__synthetic": AnyCodable(true),
                "__reorientation": AnyCodable(true),
            ],
            actionLabel: nil,
            actionPayload: [:]
        )
    }

    private static func buildTimelineSteps(from events: [CanvasEvent]) -> [AnyCodable] {
        var steps: [AnyCodable] = []

        let recent = events.suffix(8)
        for event in recent {
            let (label, state) = stepInfo(from: event)
            guard !label.isEmpty else { continue }
            steps.append(AnyCodable([
                "id": AnyCodable(event.id),
                "label": AnyCodable(label),
                "state": AnyCodable(state),
            ]))
        }

        return steps
    }

    private static func stepInfo(from event: CanvasEvent) -> (String, String) {
        switch event {
        case .toolUse(let e):
            let state = switch e.status {
            case .running: "active"
            case .done: "completed"
            case .error: "failed"
            }
            return ("\(e.toolName)", state)
        case .reasoning(let e):
            let preview = String(e.text.prefix(60))
            return (e.isThinking ? "Thinking: \(preview)" : preview, "completed")
        case .fileEdit(let e):
            let name = e.filePath.split(separator: "/").last.map(String.init) ?? e.filePath
            return ("\(e.operation.displayLabel) \(name)", "completed")
        case .gitDiff(let e):
            let name = e.filePath.flatMap { $0.split(separator: "/").last.map(String.init) } ?? "files"
            return ("Diff: \(name) (+\(e.additions)/-\(e.deletions))", "completed")
        case .subAgent(let e):
            let state = switch e.phase {
            case .spawned, .running: "active"
            case .done: "completed"
            case .failed: "failed"
            }
            return ("Sub-agent: \(e.subSessionKey.prefix(16))", state)
        case .skillRun(let e):
            let state = switch e.status {
            case .running: "active"
            case .done: "completed"
            case .failed: "failed"
            }
            return ("Skill: \(e.skillName)", state)
        case .genUI(let e):
            return (e.title, "completed")
        case .rawOutput:
            return ("", "")
        }
    }

    private static func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }

    private static func formatNumber(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
        return "\(value)"
    }
}

private extension FileOperation {
    var displayLabel: String {
        switch self {
        case .read: "Read"
        case .write: "Wrote"
        case .edit: "Edited"
        case .delete: "Deleted"
        }
    }
}
