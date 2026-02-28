import Foundation
import SwiftUI

protocol GenUISurfaceParsing: Sendable {
    func parse(surfacePayload: [String: AnyCodable]) -> [GenUIRenderComponent]
}

protocol GenUIRenderingEngine: Sendable {
    func components(for event: GenUIEvent) -> [GenUIRenderComponent]
}

struct DefaultGenUIRenderingEngine: GenUIRenderingEngine {
    let parser: any GenUISurfaceParsing

    init(parser: any GenUISurfaceParsing = DefaultGenUISurfaceParser()) {
        self.parser = parser
    }

    func components(for event: GenUIEvent) -> [GenUIRenderComponent] {
        parser.parse(surfacePayload: event.surfacePayload)
    }
}

struct AnyGenUIRenderingEngine: Sendable {
    private let componentsResolver: @Sendable (GenUIEvent) -> [GenUIRenderComponent]

    init(_ engine: some GenUIRenderingEngine) {
        componentsResolver = { event in
            engine.components(for: event)
        }
    }

    func components(for event: GenUIEvent) -> [GenUIRenderComponent] {
        componentsResolver(event)
    }
}

private struct GenUIRenderingEngineKey: EnvironmentKey {
    static let defaultValue = AnyGenUIRenderingEngine(DefaultGenUIRenderingEngine())
}

extension EnvironmentValues {
    var genUIRenderingEngine: AnyGenUIRenderingEngine {
        get { self[GenUIRenderingEngineKey.self] }
        set { self[GenUIRenderingEngineKey.self] = newValue }
    }
}

struct DefaultGenUISurfaceParser: GenUISurfaceParsing {
    func parse(surfacePayload payload: [String: AnyCodable]) -> [GenUIRenderComponent] {
        let components = payload["components"]?.arrayValue
            ?? payload["ui"]?.dictValue?["components"]?.arrayValue
            ?? payload["surface"]?.dictValue?["components"]?.arrayValue
            ?? []

        guard !components.isEmpty else { return [] }

        var parsed: [GenUIRenderComponent] = []
        parsed.reserveCapacity(components.count)

        for (index, rawAny) in components.enumerated() {
            guard let raw = rawAny.dictValue else { continue }
            let id = normalizedString(raw["id"]) ?? "component-\(index)"
            let type = (normalizedString(raw["type"]) ?? "").lowercased()

            switch type {
            case "text", "markdown":
                let value = normalizedString(raw["text"])
                    ?? normalizedString(raw["value"])
                    ?? normalizedString(raw["markdown"])
                    ?? ""
                if !value.isEmpty {
                    parsed.append(.text(GenUITextComponent(id: id, value: value)))
                }

            case "metric":
                let label = normalizedString(raw["label"]) ?? "Metric"
                let value = normalizedString(raw["value"]) ?? "—"
                let trend = normalizedString(raw["trend"])
                parsed.append(
                    .metric(
                        GenUIMetricComponent(
                            id: id,
                            label: label,
                            value: value,
                            trend: trend
                        )
                    )
                )

            case "progress":
                let numeric = normalizedDouble(raw["value"]) ?? normalizedDouble(raw["progress"]) ?? 0
                let clamped = min(1, max(0, numeric))
                let label = normalizedString(raw["label"])
                parsed.append(.progress(GenUIProgressComponent(id: id, label: label, value: clamped)))

            case "checklist":
                let rawItems = raw["items"]?.arrayValue ?? []
                var items: [GenUIChecklistComponent.Item] = []
                items.reserveCapacity(rawItems.count)

                for (itemIndex, itemAny) in rawItems.enumerated() {
                    guard let item = itemAny.dictValue else { continue }
                    let itemID = normalizedString(item["id"]) ?? "item-\(itemIndex)"
                    let label = normalizedString(item["label"])
                        ?? normalizedString(item["text"])
                        ?? "Item \(itemIndex + 1)"
                    let done = item["done"]?.boolValue ?? item["checked"]?.boolValue ?? false
                    items.append(.init(id: itemID, label: label, done: done))
                }

                parsed.append(
                    .checklist(
                        GenUIChecklistComponent(
                            id: id,
                            title: normalizedString(raw["title"]),
                            items: items
                        )
                    )
                )

            case "actions":
                let rawActions = raw["actions"]?.arrayValue ?? raw["buttons"]?.arrayValue ?? []
                var actions: [GenUIActionDescriptor] = []
                actions.reserveCapacity(rawActions.count)

                for (actionIndex, actionAny) in rawActions.enumerated() {
                    guard let action = actionAny.dictValue else { continue }
                    let actionID = normalizedString(action["actionId"])
                        ?? normalizedString(action["id"])
                        ?? normalizedString(action["type"])
                        ?? "action-\(actionIndex)"
                    let label = normalizedString(action["label"]) ?? "Action \(actionIndex + 1)"
                    actions.append(
                        GenUIActionDescriptor(
                            id: actionID,
                            label: label,
                            payload: action
                        )
                    )
                }
                parsed.append(.actions(GenUIActionsComponent(id: id, items: actions)))

            default:
                continue
            }
        }

        return parsed
    }

    private func normalizedString(_ value: AnyCodable?) -> String? {
        guard let trimmed = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    private func normalizedDouble(_ value: AnyCodable?) -> Double? {
        if let d = value?.doubleValue { return d }
        if let i = value?.intValue { return Double(i) }
        if let text = normalizedString(value), let d = Double(text) { return d }
        return nil
    }
}
