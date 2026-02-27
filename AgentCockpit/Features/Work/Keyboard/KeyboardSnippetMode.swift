// KeyboardSnippetMode.swift — Category tabs + template grid
import SwiftUI

struct KeyboardSnippetMode: View {
    @Binding var selectedCategory: String
    var onInsert: (String) -> Void
    var onDismiss: () -> Void

    @State private var pendingTemplate: SnippetTemplate? = nil
    @State private var variableValues: [String: String] = [:]

    let categories: [SnippetCategory]

    var body: some View {
        VStack(spacing: 0) {
            // Category tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button("← Back") { onDismiss() }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())

                    ForEach(categories) { cat in
                        Button(cat.name) {
                            withAnimation { selectedCategory = cat.id }
                        }
                        .font(.caption.weight(selectedCategory == cat.id ? .semibold : .regular))
                        .foregroundStyle(selectedCategory == cat.id ? .blue : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            selectedCategory == cat.id
                                ? Color.blue.opacity(0.15)
                                : Color.clear,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(selectedCategory == cat.id ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 0.5)
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Divider().opacity(0.3)

            // Template grid
            if let category = categories.first(where: { $0.id == selectedCategory }) {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(category.templates) { template in
                            TemplateCard(template: template) {
                                if template.variables.isEmpty {
                                    onInsert(template.text)
                                } else {
                                    pendingTemplate = template
                                    variableValues = Dictionary(uniqueKeysWithValues: template.variables.map { ($0, "") })
                                }
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 160)
            }

            // Variable form (inline)
            if let template = pendingTemplate {
                Divider().opacity(0.3)
                VariableForm(
                    template: template,
                    values: $variableValues,
                    onInsert: {
                        let resolved = resolveTemplate(template.text, variables: variableValues)
                        onInsert(resolved)
                        pendingTemplate = nil
                        variableValues = [:]
                    },
                    onCancel: { pendingTemplate = nil }
                )
            }
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - Template card

private struct TemplateCard: View {
    let template: SnippetTemplate
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(template.name)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Variable form

private struct VariableForm: View {
    let template: SnippetTemplate
    @Binding var values: [String: String]
    let onInsert: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Fill in: \(template.name)")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("Cancel", action: onCancel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(template.variables, id: \.self) { variable in
                HStack {
                    Text(variable)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                    TextField(variable, text: Binding(
                        get: { values[variable] ?? "" },
                        set: { values[variable] = $0 }
                    ))
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                }
            }
            Button("Insert", action: onInsert)
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
    }
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
