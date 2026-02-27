// KeyboardSnippetMode.swift — Flattened snippet strip + detail pane
import SwiftUI

struct KeyboardSnippetMode: View {
    @Binding var selectedCategory: String
    var onInsert: (String) -> Void
    var onDismiss: () -> Void

    @State private var selectedSnippetID: String? = nil
    @State private var variableValues: [String: String] = [:]

    let categories: [SnippetCategory]

    private var snippets: [FlattenedSnippet] {
        categories.flatMap { category in
            category.templates.map { template in
                FlattenedSnippet(
                    id: "\(category.id)::\(template.id)",
                    categoryID: category.id,
                    categoryName: category.name,
                    template: template
                )
            }
        }
    }

    private var selectedSnippet: FlattenedSnippet? {
        guard let selectedSnippetID else { return nil }
        return snippets.first(where: { $0.id == selectedSnippetID })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button("← Back") { onDismiss() }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())

                    ForEach(snippets) { snippet in
                        Button {
                            selectSnippet(snippet)
                        } label: {
                            Text(snippet.template.name)
                                .font(.caption.weight(selectedSnippetID == snippet.id ? .semibold : .regular))
                                .foregroundStyle(selectedSnippetID == snippet.id ? .blue : .secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    selectedSnippetID == snippet.id
                                        ? Color.blue.opacity(0.15)
                                        : Color.clear,
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            selectedSnippetID == snippet.id ? Color.blue.opacity(0.4) : Color.white.opacity(0.12),
                                            lineWidth: 0.5
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Divider().opacity(0.3)

            if snippets.isEmpty {
                VStack(spacing: 6) {
                    Text("No snippets available")
                        .font(.caption.weight(.semibold))
                    Text("Add snippets to your library to use quick inserts here.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
            } else if let selectedSnippet {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(selectedSnippet.template.name)
                                .font(.caption.weight(.semibold))

                            Text(selectedSnippet.categoryName)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())

                            Spacer(minLength: 0)
                        }

                        Text(selectedSnippet.template.text)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                            )

                        if !selectedSnippet.template.variables.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Variables")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                ForEach(selectedSnippet.template.variables, id: \.self) { variable in
                                    HStack {
                                        Text(variable)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 96, alignment: .leading)
                                        TextField(variable, text: Binding(
                                            get: { variableValues[variable] ?? "" },
                                            set: { variableValues[variable] = $0 }
                                        ))
                                        .font(.caption)
                                        .textFieldStyle(.roundedBorder)
                                    }
                                }
                            }
                        }

                        Button {
                            let resolved = resolveTemplate(selectedSnippet.template.text, variables: variableValues)
                            onInsert(resolved)
                        } label: {
                            Text("Insert")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(.ultraThinMaterial)
        .onAppear(perform: ensureSelection)
        .onChange(of: snippets.map(\.id)) { _ in
            ensureSelection()
        }
    }

    private func ensureSelection() {
        guard !snippets.isEmpty else {
            selectedSnippetID = nil
            variableValues = [:]
            return
        }

        if let selectedSnippetID, snippets.contains(where: { $0.id == selectedSnippetID }) {
            return
        }

        if
            let preferred = snippets.first(where: { $0.categoryID == selectedCategory })
        {
            selectSnippet(preferred)
            return
        }

        if let first = snippets.first {
            selectSnippet(first)
        }
    }

    private func selectSnippet(_ snippet: FlattenedSnippet) {
        selectedSnippetID = snippet.id
        selectedCategory = snippet.categoryID
        variableValues = Dictionary(uniqueKeysWithValues: snippet.template.variables.map { ($0, "") })
    }
}

private struct FlattenedSnippet: Identifiable {
    let id: String
    let categoryID: String
    let categoryName: String
    let template: SnippetTemplate
}

// MARK: - Template resolution

func resolveTemplate(_ text: String, variables: [String: String]) -> String {
    var result = text
    for (key, value) in variables {
        result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
    }
    return result
}

// MARK: - Data models

struct SnippetCategory: Identifiable, Codable {
    let id: String
    let name: String
    let templates: [SnippetTemplate]
}

struct SnippetTemplate: Identifiable, Codable {
    let id: String
    let name: String
    let text: String
    let variables: [String]
}
