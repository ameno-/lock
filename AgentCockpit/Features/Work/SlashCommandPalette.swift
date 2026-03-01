// SlashCommandPalette.swift — Command palette for slash commands
import SwiftUI

struct AvailableCommand: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let description: String?
    let inputHint: String?
}

// MARK: - Default Commands

extension AvailableCommand {
    static let defaultCommands: [AvailableCommand] = [
        AvailableCommand(
            name: "help",
            description: "Show available commands and usage information",
            inputHint: nil
        ),
        AvailableCommand(
            name: "clear",
            description: "Clear the current conversation context",
            inputHint: nil
        ),
        AvailableCommand(
            name: "context",
            description: "Add file context to the conversation",
            inputHint: "file path"
        ),
        AvailableCommand(
            name: "search",
            description: "Search the codebase for symbols or text",
            inputHint: "query"
        ),
        AvailableCommand(
            name: "explain",
            description: "Explain the selected code or concept",
            inputHint: "code or topic"
        ),
        AvailableCommand(
            name: "fix",
            description: "Fix issues in the provided code",
            inputHint: "code to fix"
        ),
        AvailableCommand(
            name: "test",
            description: "Generate tests for the provided code",
            inputHint: "code or file"
        ),
        AvailableCommand(
            name: "refactor",
            description: "Refactor the provided code",
            inputHint: "code to refactor"
        ),
        AvailableCommand(
            name: "review",
            description: "Review code for issues and improvements",
            inputHint: "code or PR"
        ),
        AvailableCommand(
            name: "commit",
            description: "Generate a commit message for changes",
            inputHint: nil
        ),
        AvailableCommand(
            name: "undo",
            description: "Undo the last action or change",
            inputHint: nil
        )
    ]
}

// MARK: - Command Palette View

struct SlashCommandPalette: View {
    let commands: [AvailableCommand]
    @State private var searchText = ""
    @Binding var isPresented: Bool
    var onSelect: (AvailableCommand) -> Void

    private var filteredCommands: [AvailableCommand] {
        if searchText.isEmpty {
            return commands
        }
        return commands.filter { command in
            command.name.localizedCaseInsensitiveContains(searchText) ||
            (command.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search commands…", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Command list
                List {
                    ForEach(filteredCommands) { command in
                        CommandRow(command: command)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect(command)
                                isPresented = false
                            }
                    }
                }
                .listStyle(.plain)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Slash Commands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Command Row

private struct CommandRow: View {
    let command: AvailableCommand

    var body: some View {
        HStack(spacing: 12) {
            // Command name with slash
            Text("/\(command.name)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)

            // Input hint if available
            if let hint = command.inputHint {
                Text("<\(hint)>")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Description
            if let description = command.description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var isPresented = true

    SlashCommandPalette(
        commands: AvailableCommand.defaultCommands,
        isPresented: $isPresented,
        onSelect: { command in
            print("Selected: /\(command.name)")
        }
    )
}
