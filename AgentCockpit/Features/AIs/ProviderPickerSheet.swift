// ProviderPickerSheet.swift — Pick which AI provider to create a session with
import SwiftUI

struct ProviderPickerSheet: View {
    let providers: [ProviderInfo]
    let onSelect: (ProviderInfo) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(providers) { provider in
                    Button {
                        onSelect(provider)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: provider.icon)
                                .font(.title2)
                                .foregroundStyle(colorForProvider(provider.name))
                                .frame(width: 36, height: 36)
                                .background(
                                    colorForProvider(provider.name).opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(descriptionForProvider(provider.name))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // Dismiss handled by parent
                    }
                }
            }
        }
    }

    private func colorForProvider(_ name: String) -> Color {
        switch name.lowercased() {
        case "pi": return .purple
        case "codex": return .green
        default: return .blue
        }
    }

    private func descriptionForProvider(_ name: String) -> String {
        switch name.lowercased() {
        case "pi": return "Claude-powered coding agent"
        case "codex": return "OpenAI Codex agent"
        default: return "AI agent"
        }
    }
}
