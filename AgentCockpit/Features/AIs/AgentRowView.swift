// AgentRowView.swift — Session list row with protocol/status/preview metadata
import SwiftUI

struct AgentRowView: View {
    let summary: SessionRowSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            content
            Spacer(minLength: 8)
        }
        .padding(.vertical, 6)
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(summary.isPromoted ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.14))
                .frame(width: 40, height: 40)
            Text("🤖")
                .font(.title3)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(summary.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if summary.isPromoted {
                    badge("Active", tint: .blue)
                }
                badge(summary.protocolLabel, tint: .gray, isNeutral: true)
                Spacer(minLength: 0)
            }

            Text(summary.preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                statusChip
                Text(summary.lastActivityLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let tokenUsage = summary.tokenUsageLabel {
                    Text(tokenUsage)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text(summary.location)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private var statusChip: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(summary.isRunning ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
            Text(summary.statusLabel)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(summary.isRunning ? Color.green : Color.secondary)
    }

    @ViewBuilder
    private func badge(_ text: String, tint: Color, isNeutral: Bool = false) -> some View {
        let label = Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)

        if #available(iOS 26.0, *) {
            label
                .foregroundStyle(isNeutral ? .primary : tint)
                .glassEffect(.regular.tint(tint.opacity(0.22)), in: .rect(cornerRadius: 8))
        } else {
            label
                .foregroundStyle(isNeutral ? .secondary : tint)
                .background(tint.opacity(isNeutral ? 0.08 : 0.15), in: Capsule())
        }
    }
}
