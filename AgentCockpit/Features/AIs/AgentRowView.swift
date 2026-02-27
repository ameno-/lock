// AgentRowView.swift — Agmente-style session row card
import SwiftUI

struct AgentRowView: View {
    let summary: SessionRowSummary
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(summary.isRunning ? Color.green : Color(.systemGray4))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(summary.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if summary.isPromoted {
                        chip("Active", tint: .green)
                    }

                    chip(summary.protocolLabel, tint: .secondary, neutral: true)

                    Spacer(minLength: 0)
                }

                Text(summary.preview)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    Text(summary.statusLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(summary.isRunning ? .green : .secondary)
                        .lineLimit(1)

                    Text(summary.lastActivityLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    if let tokenUsage = summary.tokenUsageLabel {
                        Text(tokenUsage)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption2)
                    Text(summary.location)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(colorScheme == .dark ? Color(.secondarySystemBackground) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(.systemGray5).opacity(colorScheme == .dark ? 0.4 : 1), lineWidth: colorScheme == .dark ? 0.5 : 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 10, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Opens session")
    }

    @ViewBuilder
    private func chip(_ text: String, tint: Color, neutral: Bool = false) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(neutral ? .secondary : tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background((neutral ? Color(.systemGray5) : tint.opacity(0.14)), in: Capsule())
    }

    private var accessibilitySummary: String {
        "\(summary.title), \(summary.protocolLabel), \(summary.statusLabel), \(summary.lastActivityLabel), \(summary.location)"
    }
}
