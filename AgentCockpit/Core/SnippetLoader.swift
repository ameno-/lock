// SnippetLoader.swift — Resolves layered snippets from filesystem + bundle fallback
import Foundation

struct SnippetContext: Hashable {
    let agentSlug: String?
    let harnessSlug: String?

    static let empty = SnippetContext(agentSlug: nil, harnessSlug: nil)

    init(agentSlug: String?, harnessSlug: String?) {
        self.agentSlug = SnippetContext.normalizeSlug(agentSlug)
        self.harnessSlug = SnippetContext.normalizeSlug(harnessSlug)
    }

    private static func normalizeSlug(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}

@MainActor
final class SnippetLoader {
    static let shared = SnippetLoader()

    private let fileManager: FileManager
    private let snippetsRootURL: URL
    private let bundledCategories: [SnippetCategory]?
    private var cache: [SnippetContext: [SnippetCategory]] = [:]

    // Kept for existing callers that use the non-context API.
    private(set) var categories: [SnippetCategory] = []

    init(
        fileManager: FileManager = .default,
        bundle: Bundle = .main,
        snippetsRootURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.snippetsRootURL = snippetsRootURL ?? SnippetLoader.defaultSnippetsRoot(fileManager: fileManager)
        self.bundledCategories = SnippetLoader.loadBundledCategories(bundle: bundle)

        let initial = resolveCategories(for: .empty)
        self.categories = initial
    }

    func categories(for context: SnippetContext) -> [SnippetCategory] {
        resolveCategories(for: context)
    }

    private func resolveCategories(for context: SnippetContext) -> [SnippetCategory] {
        if let cached = cache[context] {
            return cached
        }

        var layers: [[SnippetCategory]] = [defaultCategories]
        if let bundledCategories {
            layers.append(bundledCategories)
        }

        for url in filesystemLayerURLs(for: context) {
            if let decoded = decodeCategories(from: url) {
                layers.append(decoded)
            }
        }

        let resolved = SnippetLoader.mergeLayers(layers)
        cache[context] = resolved
        return resolved
    }

    private func filesystemLayerURLs(for context: SnippetContext) -> [URL] {
        var urls: [URL] = [
            snippetsRootURL.appendingPathComponent("defaults.json")
        ]

        if let harnessSlug = context.harnessSlug {
            urls.append(
                snippetsRootURL
                    .appendingPathComponent("harness", isDirectory: true)
                    .appendingPathComponent("\(harnessSlug).json")
            )
        }

        if let agentSlug = context.agentSlug {
            urls.append(
                snippetsRootURL
                    .appendingPathComponent("agent", isDirectory: true)
                    .appendingPathComponent("\(agentSlug).json")
            )
        }

        return urls
    }

    private func decodeCategories(from url: URL) -> [SnippetCategory]? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([SnippetCategory].self, from: data)
        } catch {
            print("[SnippetLoader] Failed to decode \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    private static func loadBundledCategories(bundle: Bundle) -> [SnippetCategory]? {
        guard let url = bundle.url(forResource: "snippet-templates", withExtension: "json") else {
            print("[SnippetLoader] snippet-templates.json not found in bundle")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([SnippetCategory].self, from: data)
        } catch {
            print("[SnippetLoader] Failed to decode bundled snippet-templates.json: \(error)")
            return nil
        }
    }

    private static func defaultSnippetsRoot(fileManager: FileManager) -> URL {
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            return documentsURL.appendingPathComponent("snippets", isDirectory: true)
        }
        return fileManager.temporaryDirectory.appendingPathComponent("snippets", isDirectory: true)
    }

    static func mergeLayers(_ layers: [[SnippetCategory]]) -> [SnippetCategory] {
        var categoryOrder: [String] = []
        var categoriesByID: [String: CategoryAccumulator] = [:]

        for layer in layers {
            for category in layer {
                if var existing = categoriesByID[category.id] {
                    existing.merge(category)
                    categoriesByID[category.id] = existing
                } else {
                    categoryOrder.append(category.id)
                    categoriesByID[category.id] = CategoryAccumulator(category: category)
                }
            }
        }

        return categoryOrder.compactMap { categoriesByID[$0]?.materialized }
    }

    // Hard fallback if no bundle/filesystem content can be decoded.
    private var defaultCategories: [SnippetCategory] {
        [
            SnippetCategory(id: "git", name: "Git", templates: [
                SnippetTemplate(id: "gs", name: "Git status", text: "git status", variables: []),
                SnippetTemplate(id: "gd", name: "Git diff", text: "git diff HEAD", variables: []),
            ])
        ]
    }
}

private struct CategoryAccumulator {
    private(set) var id: String
    private(set) var name: String
    private var templateOrder: [String] = []
    private var templatesByID: [String: SnippetTemplate] = [:]

    init(category: SnippetCategory) {
        id = category.id
        name = category.name
        merge(category)
    }

    mutating func merge(_ category: SnippetCategory) {
        name = category.name
        for template in category.templates {
            if templatesByID[template.id] == nil {
                templateOrder.append(template.id)
            }
            templatesByID[template.id] = template
        }
    }

    var materialized: SnippetCategory {
        let templates = templateOrder.compactMap { templatesByID[$0] }
        return SnippetCategory(id: id, name: name, templates: templates)
    }
}
