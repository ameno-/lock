// KeyboardInputMode.swift — Modifier strip + TextEditor + action buttons
import SwiftUI

struct KeyboardInputMode: View {
    @Binding var text: String
    var onSend: (String) -> Void
    var onAbort: () -> Void
    var snippetStackCount: Int
    var onExecuteStack: () -> Void
    var onClearStack: () -> Void
    var onSnippetToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TextField("Message the agent…", text: $text, axis: .vertical)
                .font(.system(.body))
                .lineLimit(1 ... 4)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider().opacity(0.3)

            // Action bar
            HStack(spacing: 12) {
                // Snippet toggle
                Button {
                    onSnippetToggle()
                } label: {
                    HStack(spacing: 6) {
                        Label("Snippets", systemImage: "bolt.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.yellow)
                        if snippetStackCount > 0 {
                            Text("\(snippetStackCount)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)

                if snippetStackCount > 0 {
                    Button {
                        onExecuteStack()
                    } label: {
                        Label("Execute Stack", systemImage: "play.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onClearStack()
                    } label: {
                        Label("Clear Stack", systemImage: "xmark.circle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

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
