import Foundation

enum ApprovalSurfaceSynthesizer {
    static func synthesize(from request: ACPendingApprovalRequest) -> GenUIEvent {
        let riskLevel: String
        let command = request.command ?? ""
        let lowered = command.lowercased()
        if lowered.contains("rm ") || lowered.contains("delete") || lowered.contains("drop") || lowered.contains("--force") {
            riskLevel = "high"
        } else if lowered.contains("git push") || lowered.contains("deploy") || lowered.contains("migrate") {
            riskLevel = "medium"
        } else {
            riskLevel = "low"
        }

        let summary = request.reason
            ?? request.command.map { "Command: \($0)" }
            ?? "Agent requests approval"

        var components: [AnyCodable] = [
            AnyCodable([
                "id": AnyCodable("risk"),
                "type": AnyCodable("risk_gate"),
                "level": AnyCodable(riskLevel),
                "summary": AnyCodable(summary),
                "detail": AnyCodable(request.cwd.map { "Working directory: \($0)" } ?? ""),
            ]),
        ]

        if let cmd = request.command, !cmd.isEmpty {
            components.append(AnyCodable([
                "id": AnyCodable("command"),
                "type": AnyCodable("code_block"),
                "language": AnyCodable("bash"),
                "code": AnyCodable(cmd),
            ]))
        }

        components.append(AnyCodable([
            "id": AnyCodable("actions"),
            "type": AnyCodable("actions"),
            "actions": AnyCodable([
                AnyCodable(["id": AnyCodable("accept"), "label": AnyCodable("Accept")]),
                AnyCodable(["id": AnyCodable("decline"), "label": AnyCodable("Decline")]),
                AnyCodable(["id": AnyCodable("cancel"), "label": AnyCodable("Cancel")]),
            ]),
        ]))

        return GenUIEvent(
            id: "approval/\(request.id)",
            schemaVersion: "v0",
            mode: .snapshot,
            surfaceID: "session.approval.\(request.id)",
            revision: 0,
            correlationID: request.id,
            title: "Approval Required",
            body: summary,
            surfacePayload: ["components": AnyCodable(components)],
            contextPayload: [
                "pinned": AnyCodable(true),
                "__synthetic": AnyCodable(true),
                "__approvalRequestId": AnyCodable(request.id),
            ],
            actionLabel: nil,
            actionPayload: [:]
        )
    }
}
