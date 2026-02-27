// RawOutputCard.swift — Monospaced fallback for unrecognized events
import SwiftUI

struct RawOutputCard: View {
    let event: RawOutputEvent

    var body: some View {
        CardBase {
            VStack(alignment: .leading, spacing: 6) {
                if showsHookEvent {
                    Text(event.hookEvent)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(event.text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
                    .textSelection(.enabled)
            }
        }
    }

    private var showsHookEvent: Bool {
        let hook = event.hookEvent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hook.isEmpty else { return false }
        let hiddenPrefixes = ["item/", "thread/", "session/", "local/userMessage", "history/userMessage"]
        return !hiddenPrefixes.contains(where: { hook.hasPrefix($0) })
    }
}
