// KeyboardInputMode.swift — Modifier strip + TextEditor + action buttons
import SwiftUI

struct KeyboardInputMode: View {
    @Binding var text: String
    var onSend: (String) -> Void
    var onAbort: () -> Void
    var onSnippetToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Modifier strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(modifierKeys, id: \.label) { key in
                        Button(key.label) { key.action(&text) }
                            .font(.system(.caption, design: .monospaced).weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Divider().opacity(0.3)

            // Text editor
            TextEditor(text: $text)
                .font(.system(.body))
                .frame(minHeight: 44, maxHeight: 120)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .scrollContentBackground(.hidden)

            Divider().opacity(0.3)

            // Action bar
            HStack(spacing: 12) {
                // Snippet toggle
                Button {
                    onSnippetToggle()
                } label: {
                    Label("Snippets", systemImage: "bolt.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.yellow)
                }
                .buttonStyle(.plain)

                Spacer()

                // Abort
                Button {
                    onAbort()
                } label: {
                    Label("Abort", systemImage: "stop.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)

                // Send
                Button {
                    let textToSend = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !textToSend.isEmpty else { return }
                    onSend(textToSend)
                    text = ""
                } label: {
                    HStack(spacing: 4) {
                        Text("Send")
                            .font(.caption.weight(.semibold))
                        Image(systemName: "arrow.up.circle.fill")
                    }
                    .foregroundStyle(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.blue)
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - Modifier keys definition

private struct ModifierKey: Sendable {
    let label: String
    let action: @Sendable (inout String) -> Void
}

@MainActor
private let modifierKeys: [ModifierKey] = [
    .init(label: "Ctrl-C") { _ in },  // handled by abort
    .init(label: "Esc") { text in text += "\u{1B}" },
    .init(label: "Tab") { text in text += "\t" },
    .init(label: "↑") { _ in },
    .init(label: "↓") { _ in },
    .init(label: "←") { _ in },
    .init(label: "→") { _ in },
    .init(label: "Enter") { text in text += "\n" },
    .init(label: "y/n") { text in text += "y" },
]
