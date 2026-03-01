import Foundation

enum GenUIRenderComponent: Identifiable, Sendable {
    case text(GenUITextComponent)
    case metric(GenUIMetricComponent)
    case progress(GenUIProgressComponent)
    case checklist(GenUIChecklistComponent)
    case actions(GenUIActionsComponent)
    case timeline(GenUITimelineComponent)
    case decision(GenUIDecisionComponent)
    case diffPreview(GenUIDiffPreviewComponent)
    case riskGate(GenUIRiskGateComponent)
    case keyValue(GenUIKeyValueComponent)
    case codeBlock(GenUICodeBlockComponent)

    var id: String {
        switch self {
        case .text(let component):
            return "text/\(component.id)"
        case .metric(let component):
            return "metric/\(component.id)"
        case .progress(let component):
            return "progress/\(component.id)"
        case .checklist(let component):
            return "checklist/\(component.id)"
        case .actions(let component):
            return "actions/\(component.id)"
        case .timeline(let component):
            return "timeline/\(component.id)"
        case .decision(let component):
            return "decision/\(component.id)"
        case .diffPreview(let component):
            return "diffPreview/\(component.id)"
        case .riskGate(let component):
            return "riskGate/\(component.id)"
        case .keyValue(let component):
            return "keyValue/\(component.id)"
        case .codeBlock(let component):
            return "codeBlock/\(component.id)"
        }
    }
}

struct GenUITextComponent: Identifiable, Sendable {
    let id: String
    let value: String
}

struct GenUIMetricComponent: Identifiable, Sendable {
    let id: String
    let label: String
    let value: String
    let trend: String?
}

struct GenUIProgressComponent: Identifiable, Sendable {
    let id: String
    let label: String?
    let value: Double
}

struct GenUIChecklistComponent: Identifiable, Sendable {
    struct Item: Identifiable, Sendable {
        let id: String
        let label: String
        let done: Bool
    }

    let id: String
    let title: String?
    let items: [Item]
}

struct GenUIActionDescriptor: Identifiable, Sendable {
    let id: String
    let label: String
    let payload: [String: AnyCodable]
}

struct GenUIActionsComponent: Identifiable, Sendable {
    let id: String
    let items: [GenUIActionDescriptor]
}

// MARK: - Phase 2 Components

struct GenUITimelineComponent: Identifiable, Sendable {
    enum StepState: String, Sendable {
        case completed, active, pending, failed
    }

    struct Step: Identifiable, Sendable {
        let id: String
        let label: String
        let state: StepState
        let detail: String?
    }

    let id: String
    let title: String?
    let steps: [Step]
}

struct GenUIDecisionComponent: Identifiable, Sendable {
    struct Option: Identifiable, Sendable {
        let id: String
        let label: String
        let description: String?
        let payload: [String: AnyCodable]
    }

    let id: String
    let prompt: String
    let options: [Option]
}

struct GenUIDiffPreviewComponent: Identifiable, Sendable {
    let id: String
    let filePath: String?
    let diff: String
    let additions: Int
    let deletions: Int
}

struct GenUIRiskGateComponent: Identifiable, Sendable {
    enum RiskLevel: String, Sendable {
        case low, medium, high
    }

    let id: String
    let level: RiskLevel
    let summary: String
    let detail: String?
}

struct GenUIKeyValueComponent: Identifiable, Sendable {
    struct Pair: Identifiable, Sendable {
        let id: String
        let key: String
        let value: String
    }

    let id: String
    let title: String?
    let pairs: [Pair]
}

struct GenUICodeBlockComponent: Identifiable, Sendable {
    let id: String
    let language: String?
    let code: String
}
