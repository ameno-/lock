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

            case "timeline":
                let rawSteps = raw["steps"]?.arrayValue ?? raw["items"]?.arrayValue ?? []
                var steps: [GenUITimelineComponent.Step] = []
                steps.reserveCapacity(rawSteps.count)
                for (stepIndex, stepAny) in rawSteps.enumerated() {
                    guard let step = stepAny.dictValue else { continue }
                    let stepID = normalizedString(step["id"]) ?? "step-\(stepIndex)"
                    let label = normalizedString(step["label"])
                        ?? normalizedString(step["text"])
                        ?? "Step \(stepIndex + 1)"
                    let stateRaw = normalizedString(step["state"])
                        ?? normalizedString(step["status"])
                        ?? "pending"
                    let state = GenUITimelineComponent.StepState(rawValue: stateRaw) ?? .pending
                    let detail = normalizedString(step["detail"]) ?? normalizedString(step["description"])
                    steps.append(.init(id: stepID, label: label, state: state, detail: detail))
                }
                parsed.append(.timeline(GenUITimelineComponent(
                    id: id,
                    title: normalizedString(raw["title"]),
                    steps: steps
                )))

            case "decision":
                let prompt = normalizedString(raw["prompt"])
                    ?? normalizedString(raw["question"])
                    ?? "Choose an option"
                let rawOptions = raw["options"]?.arrayValue ?? raw["choices"]?.arrayValue ?? []
                var options: [GenUIDecisionComponent.Option] = []
                options.reserveCapacity(rawOptions.count)
                for (optIndex, optAny) in rawOptions.enumerated() {
                    guard let opt = optAny.dictValue else { continue }
                    let optID = normalizedString(opt["id"]) ?? "option-\(optIndex)"
                    let label = normalizedString(opt["label"]) ?? "Option \(optIndex + 1)"
                    let desc = normalizedString(opt["description"]) ?? normalizedString(opt["detail"])
                    options.append(.init(id: optID, label: label, description: desc, payload: opt))
                }
                parsed.append(.decision(GenUIDecisionComponent(id: id, prompt: prompt, options: options)))

            case "diff", "diff_preview", "diffpreview":
                let diff = normalizedString(raw["diff"])
                    ?? normalizedString(raw["content"])
                    ?? normalizedString(raw["text"])
                    ?? ""
                let filePath = normalizedString(raw["filePath"]) ?? normalizedString(raw["file"])
                let additions = raw["additions"]?.intValue ?? 0
                let deletions = raw["deletions"]?.intValue ?? 0
                if !diff.isEmpty {
                    parsed.append(.diffPreview(GenUIDiffPreviewComponent(
                        id: id, filePath: filePath, diff: diff,
                        additions: additions, deletions: deletions
                    )))
                }

            case "risk_gate", "riskgate", "risk":
                let levelRaw = normalizedString(raw["level"])
                    ?? normalizedString(raw["risk"])
                    ?? "medium"
                let level = GenUIRiskGateComponent.RiskLevel(rawValue: levelRaw) ?? .medium
                let summary = normalizedString(raw["summary"])
                    ?? normalizedString(raw["label"])
                    ?? normalizedString(raw["text"])
                    ?? "Review required"
                let detail = normalizedString(raw["detail"]) ?? normalizedString(raw["description"])
                parsed.append(.riskGate(GenUIRiskGateComponent(
                    id: id, level: level, summary: summary, detail: detail
                )))

            case "key_value", "keyvalue", "kv":
                let rawPairs = raw["pairs"]?.arrayValue ?? raw["items"]?.arrayValue ?? []
                var pairs: [GenUIKeyValueComponent.Pair] = []
                pairs.reserveCapacity(rawPairs.count)
                for (pairIndex, pairAny) in rawPairs.enumerated() {
                    guard let pair = pairAny.dictValue else { continue }
                    let pairID = normalizedString(pair["id"]) ?? "kv-\(pairIndex)"
                    let key = normalizedString(pair["key"]) ?? normalizedString(pair["label"]) ?? "Key"
                    let value = normalizedString(pair["value"]) ?? "—"
                    pairs.append(.init(id: pairID, key: key, value: value))
                }
                if !pairs.isEmpty {
                    parsed.append(.keyValue(GenUIKeyValueComponent(
                        id: id, title: normalizedString(raw["title"]), pairs: pairs
                    )))
                }

            case "code", "code_block", "codeblock":
                let code = normalizedString(raw["code"])
                    ?? normalizedString(raw["content"])
                    ?? normalizedString(raw["text"])
                    ?? ""
                let language = normalizedString(raw["language"]) ?? normalizedString(raw["lang"])
                if !code.isEmpty {
                    parsed.append(.codeBlock(GenUICodeBlockComponent(
                        id: id, language: language, code: code
                    )))
                }

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
