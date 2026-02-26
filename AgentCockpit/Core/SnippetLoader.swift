// SnippetLoader.swift — Loads snippet-templates.json from the app bundle
import Foundation

@MainActor
final class SnippetLoader {
    static let shared = SnippetLoader()

    private(set) var categories: [SnippetCategory] = []

    private init() {
        load()
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "snippet-templates", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            print("[SnippetLoader] snippet-templates.json not found in bundle")
            categories = defaultCategories
            return
        }
        do {
            categories = try JSONDecoder().decode([SnippetCategory].self, from: data)
        } catch {
            print("[SnippetLoader] Decode error: \(error)")
            categories = defaultCategories
        }
    }

    // Fallback if JSON not loaded
    private var defaultCategories: [SnippetCategory] {
        [
            SnippetCategory(id: "git", name: "Git", templates: [
                SnippetTemplate(id: "gs", name: "Git status", text: "git status", variables: []),
                SnippetTemplate(id: "gd", name: "Git diff", text: "git diff HEAD", variables: []),
            ])
        ]
    }
}
