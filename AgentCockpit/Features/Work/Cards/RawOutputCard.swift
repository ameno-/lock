// RawOutputCard.swift — Monospaced fallback for unrecognized events
import SwiftUI

struct RawOutputCard: View {
    let event: RawOutputEvent

    var body: some View {
        CardBase {
            VStack(alignment: .leading, spacing: 6) {
                if !event.hookEvent.isEmpty {
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
}
