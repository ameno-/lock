// KeyboardInputMode.swift — Modifier strip + TextEditor + action buttons
import SwiftUI
import UIKit

struct KeyboardInputMode: View {
    @Binding var text: String
    var onSend: (String) -> Void
    var onAbort: () -> Void
    var onSnippetToggle: () -> Void
    @FocusState private var isInputFocused: Bool
    @State private var isCommandPalettePresented = false
    @State private var lastProcessedText = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Message the agent…", text: $text, axis: .vertical)
                .font(.system(.body))
                .lineLimit(1 ... 4)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

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

                Button {
                    pasteFromClipboard()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
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
        .onAppear {
            isInputFocused = true
        }
        .sheet(isPresented: $isCommandPalettePresented) {
            SlashCommandPalette(
                commands: AvailableCommand.defaultCommands,
                isPresented: $isCommandPalettePresented,
                onSelect: { command in
                    insertCommand(command)
                }
            )
        }
        .onChange(of: text) { _, newText in
            detectSlashCommand(newText: newText)
        }
    }

    private func detectSlashCommand(newText: String) {
        // Detect when user types "/" at the beginning of input
        if newText == "/" && lastProcessedText.isEmpty {
            isCommandPalettePresented = true
            text = ""  // Clear the slash
        }
        lastProcessedText = newText
    }

    private func insertCommand(_ command: AvailableCommand) {
        if let hint = command.inputHint {
            text = "/\(command.name) <\(hint)>"
        } else {
            text = "/\(command.name)"
        }
        isInputFocused = true
    }

    private func pasteFromClipboard() {
        guard let clipboardText = UIPasteboard.general.string, !clipboardText.isEmpty else { return }
        text += clipboardText
        isInputFocused = true
    }
}
