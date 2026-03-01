import Foundation

enum WorkTranscriptRole: String, Sendable {
    case user
    case assistant
    case thinking
    case system
}

struct WorkTranscriptMessageEntry: Identifiable, Sendable, Equatable {
    let id: String
    let role: WorkTranscriptRole
    let text: String
    let timestamp: Date
    let sourceEventIDs: [String]
}

enum WorkTranscriptEntry: Identifiable, Sendable {
    case message(WorkTranscriptMessageEntry)
    case event(CanvasEvent)

    var id: String {
        switch self {
        case .message(let message):
            return message.id
        case .event(let event):
            return "event/\(event.id)"
        }
    }

    var timestamp: Date {
        switch self {
        case .message(let message):
            return message.timestamp
        case .event(let event):
            return event.timestamp
        }
    }
}

enum WorkTranscriptDisplayPolicy: String, Sendable {
    case standard
    case debug
    case textOnly

    init(displayMode: ACTranscriptDisplayMode) {
        switch displayMode {
        case .standard:
            self = .standard
        case .debug:
            self = .debug
        case .textOnly:
            self = .textOnly
        }
    }
}

enum WorkTranscriptMapper {
    static func entries(from events: [CanvasEvent]) -> [WorkTranscriptEntry] {
        entries(from: events, policy: .standard)
    }

    static func entries(
        from events: [CanvasEvent],
        policy: WorkTranscriptDisplayPolicy,
        activityGenUIEnabled: Bool = false,
        filterPromotedSurfaces: Bool = false
    ) -> [WorkTranscriptEntry] {
        guard !events.isEmpty else { return [] }

        var mapped: [WorkTranscriptEntry] = []
        mapped.reserveCapacity(events.count)
        let genUITimestamps = events.compactMap { event -> Date? in
            guard case .genUI(let genUI) = event else { return nil }
            return genUI.timestamp
        }

        for event in events {
            if case .genUI(let genUI) = event {
                appendGenUI(event: genUI, policy: policy, to: &mapped)
                continue
            }

            guard let message = messagePayload(from: event) else {
                mapped.append(.event(event))
                continue
            }

            if shouldSuppressDuplicateGenUIScaffoldMessage(
                message,
                policy: policy,
                genUITimestamps: genUITimestamps
            ) {
                continue
            }

            appendMessage(message, to: &mapped)
        }

        return mapped
    }

    private static func appendGenUI(
        event: GenUIEvent,
        policy: WorkTranscriptDisplayPolicy,
        to mapped: inout [WorkTranscriptEntry]
    ) {
        switch policy {
        case .standard:
            mapped.append(.event(.genUI(event)))

        case .debug:
            mapped.append(.event(.genUI(event)))
            guard let sourceText = genUISourceText(from: event) else { return }
            appendMessage(
                WorkTranscriptMessageEntry(
                    id: "msg/\(event.id)/source",
                    role: .assistant,
                    text: sourceText,
                    timestamp: event.timestamp,
                    sourceEventIDs: [event.id]
                ),
                to: &mapped
            )

        case .textOnly:
            guard let fallback = genUITextFallback(from: event) else { return }
            appendMessage(
                WorkTranscriptMessageEntry(
                    id: "msg/\(event.id)/fallback",
                    role: .assistant,
                    text: fallback,
                    timestamp: event.timestamp,
                    sourceEventIDs: [event.id]
                ),
                to: &mapped
            )
        }
    }

    private static func shouldSuppressDuplicateGenUIScaffoldMessage(
        _ message: WorkTranscriptMessageEntry,
        policy: WorkTranscriptDisplayPolicy,
        genUITimestamps: [Date]
    ) -> Bool {
        guard policy != .debug else { return false }
        guard message.role == .assistant else { return false }
        guard looksLikeGenUIScaffoldText(message.text) else { return false }
        return genUITimestamps.contains { timestamp in
            abs(timestamp.timeIntervalSince(message.timestamp)) <= 10
        }
    }

    private static func looksLikeGenUIScaffoldText(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("```genui") || lower.contains("```gen_ui") {
            return true
        }
        return lower.contains("<genui>") && lower.contains("</genui>")
    }

    private static func genUISourceText(from event: GenUIEvent) -> String? {
        guard let sourceText = event.contextPayload["__sourceText"]?.stringValue else {
            return nil
        }
        return normalizedMessageText(sourceText)
    }

    private static func genUITextFallback(from event: GenUIEvent) -> String? {
        if let sourceText = genUISourceText(from: event) {
            return sourceText
        }

        let title = normalizedMessageText(event.title)
        let body = normalizedMessageText(event.body)

        switch (title, body) {
        case let (title?, body?) where title.caseInsensitiveCompare(body) == .orderedSame:
            return body
        case let (title?, body?):
            return "\(title)\n\n\(body)"
        case (nil, let body?):
            return body
        case (let title?, nil):
            return title
        case (nil, nil):
            return nil
        }
    }

    private static func messagePayload(from event: CanvasEvent) -> WorkTranscriptMessageEntry? {
        switch event {
        case .reasoning(let reasoning):
            let role: WorkTranscriptRole = reasoning.isThinking ? .thinking : .assistant
            guard let text = normalizedMessageText(reasoning.text) else { return nil }
            return WorkTranscriptMessageEntry(
                id: "msg/\(reasoning.id)",
                role: role,
                text: text,
                timestamp: reasoning.timestamp,
                sourceEventIDs: [reasoning.id]
            )

        case .rawOutput(let raw):
            guard let text = normalizedMessageText(raw.text) else { return nil }
            let role: WorkTranscriptRole
            let normalized: String

            if let userText = extractUserMessage(from: text) {
                role = .user
                normalized = userText
            } else {
                role = .system
                normalized = text
            }

            guard let finalText = normalizedMessageText(normalized) else { return nil }
            return WorkTranscriptMessageEntry(
                id: "msg/\(raw.id)",
                role: role,
                text: finalText,
                timestamp: raw.timestamp,
                sourceEventIDs: [raw.id]
            )

        default:
            return nil
        }
    }

    private static func appendMessage(
        _ message: WorkTranscriptMessageEntry,
        to mapped: inout [WorkTranscriptEntry]
    ) {
        guard let last = mapped.last,
              case .message(let existing) = last,
              shouldMerge(existing: existing, incoming: message)
        else {
            mapped.append(.message(message))
            return
        }

        var sourceIDs = existing.sourceEventIDs
        sourceIDs.append(contentsOf: message.sourceEventIDs)
        let merged = WorkTranscriptMessageEntry(
            id: existing.id,
            role: existing.role,
            text: "\(existing.text)\n\n\(message.text)",
            timestamp: message.timestamp,
            sourceEventIDs: sourceIDs
        )
        mapped[mapped.count - 1] = .message(merged)
    }

    private static func shouldMerge(
        existing: WorkTranscriptMessageEntry,
        incoming: WorkTranscriptMessageEntry
    ) -> Bool {
        guard existing.role == incoming.role else { return false }
        guard existing.role != .user else { return false }

        // Preserve event boundaries for larger updates and avoid enormous merged bubbles.
        let combinedCount = existing.text.count + incoming.text.count
        guard combinedCount < 8_000 else { return false }

        let timeGap = incoming.timestamp.timeIntervalSince(existing.timestamp)
        return timeGap <= 5.0
    }

    private static func extractUserMessage(from text: String) -> String? {
        let prefixes = ["you:", "user:"]
        for prefix in prefixes {
            if text.lowercased().hasPrefix(prefix) {
                let dropCount = prefix.count
                let index = text.index(text.startIndex, offsetBy: dropCount)
                let suffix = String(text[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return suffix.isEmpty ? nil : suffix
            }
        }
        return nil
    }

    private static func normalizedMessageText(_ raw: String) -> String? {
        let compact = raw
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return nil }
        return compact
    }
}
