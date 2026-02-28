import Foundation

enum GenUIRenderComponent: Identifiable, Sendable {
    case text(GenUITextComponent)
    case metric(GenUIMetricComponent)
    case progress(GenUIProgressComponent)
    case checklist(GenUIChecklistComponent)
    case actions(GenUIActionsComponent)

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
