import SwiftUI

struct GenUIDemoView: View {
    @Environment(AppModel.self) private var appModel

    @State private var selectedSample: GenUIDemoSample = .taskPlan
    @State private var actionLog: [String] = []
    @State private var patchRevision = 0
    @State private var surfaceID = UUID().uuidString
    @State private var sendActionsToServer = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var snapshotEvent: GenUIEvent {
        selectedSample.snapshot(surfaceID: surfaceID)
    }

    private var patchEvent: GenUIEvent {
        selectedSample.patch(surfaceID: surfaceID, revision: patchRevision)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Prototype rich response surfaces and inject them into the active session stream.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Session")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(appModel.promotedSessionKey ?? "None selected. Open a session first.")
                        .font(.caption.monospaced())
                        .foregroundStyle(appModel.promotedSessionKey == nil ? .orange : .secondary)
                        .textSelection(.enabled)
                }

                Picker("Sample", selection: $selectedSample) {
                    ForEach(GenUIDemoSample.allCases) { sample in
                        Text(sample.title).tag(sample)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedSample) { _, _ in
                    patchRevision = 0
                    surfaceID = UUID().uuidString
                    statusMessage = nil
                    errorMessage = nil
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    GenUICard(event: snapshotEvent) { tappedEvent in
                        logAction(from: tappedEvent)
                    }
                }

                HStack(spacing: 10) {
                    Button("Inject Snapshot") {
                        inject(snapshotEvent)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Inject Patch") {
                        patchRevision += 1
                        inject(patchEvent)
                    }
                    .buttonStyle(.bordered)
                }

                Toggle("Send preview action callbacks to active session", isOn: $sendActionsToServer)
                    .font(.caption)
                    .tint(.blue)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Action Log")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if actionLog.isEmpty {
                        Text("Tap a GenUI action button to capture callback payloads here.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(Array(actionLog.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(12)
        }
        .navigationTitle("GenUI Demo")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func inject(_ event: GenUIEvent) {
        guard let sessionKey = appModel.promotedSessionKey else {
            errorMessage = "Select a real session before injecting demo GenUI events."
            return
        }

        appModel.eventStore.ingest(event: .genUI(event), sessionKey: sessionKey)
        appModel.persistGenUIStateNow()
        statusMessage = "Injected \(event.mode == .patch ? "patch" : "snapshot") into \(sessionKey)"
        errorMessage = nil
    }

    private func logAction(from event: GenUIEvent) {
        let actionID = event.actionPayload["actionId"]?.stringValue ?? "unknown"
        let line = "\(timestamp()) action=\(actionID) payload=\(compactJSON(event.actionPayload))"
        actionLog.insert(line, at: 0)
        if actionLog.count > 20 {
            actionLog = Array(actionLog.prefix(20))
        }

        guard sendActionsToServer else { return }
        guard let sessionKey = appModel.promotedSessionKey else {
            errorMessage = "Cannot send action callback: no active session selected."
            return
        }

        Task {
            do {
                try await appModel.transport.submitGenUIAction(sessionKey: sessionKey, event: event)
                statusMessage = "Sent action callback '\(actionID)' to \(sessionKey)"
                errorMessage = nil
            } catch {
                errorMessage = "Action callback failed: \(error.localizedDescription)"
            }
        }
    }

    private func compactJSON(_ payload: [String: AnyCodable]) -> String {
        let object = payload.mapValues(rawValue(from:))
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]),
              let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }

    private func rawValue(from value: AnyCodable) -> Any {
        if let dict = value.dictValue {
            return dict.mapValues(rawValue(from:))
        }
        if let array = value.arrayValue {
            return array.map(rawValue(from:))
        }
        if let string = value.stringValue { return string }
        if let bool = value.boolValue { return bool }
        if let int = value.intValue { return int }
        if let double = value.doubleValue { return double }
        return value.description
    }

    private func timestamp() -> String {
        Self.timeFormatter.string(from: .now)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private enum GenUIDemoSample: String, CaseIterable, Identifiable {
    case taskPlan
    case testRun
    case release

    var id: String { rawValue }

    var title: String {
        switch self {
        case .taskPlan: return "Task Plan"
        case .testRun: return "Test Run"
        case .release: return "Release"
        }
    }

    func snapshot(surfaceID: String) -> GenUIEvent {
        switch self {
        case .taskPlan:
            return GenUIEvent(
                id: "demo/genui/\(surfaceID)",
                schemaVersion: "v0",
                mode: .snapshot,
                surfaceID: surfaceID,
                revision: 1,
                correlationID: "demo-\(surfaceID)",
                title: "Migration Sprint",
                body: "Structured checklist and rollout controls",
                surfacePayload: [
                    "components": AnyCodable([
                        AnyCodable([
                            "id": AnyCodable("summary"),
                            "type": AnyCodable("text"),
                            "text": AnyCodable("Applying Agmente UI base + ACP protocol fidelity upgrades.")
                        ]),
                        AnyCodable([
                            "id": AnyCodable("progress"),
                            "type": AnyCodable("progress"),
                            "label": AnyCodable("Completion"),
                            "value": AnyCodable(0.33)
                        ]),
                        AnyCodable([
                            "id": AnyCodable("checklist"),
                            "type": AnyCodable("checklist"),
                            "title": AnyCodable("Gate Status"),
                            "items": AnyCodable([
                                AnyCodable(["id": AnyCodable("ui"), "label": AnyCodable("UI parity"), "done": AnyCodable(true)]),
                                AnyCodable(["id": AnyCodable("acp"), "label": AnyCodable("ACP replay fidelity"), "done": AnyCodable(false)]),
                                AnyCodable(["id": AnyCodable("genui"), "label": AnyCodable("GenUI callback contract"), "done": AnyCodable(false)])
                            ])
                        ]),
                        AnyCodable([
                            "id": AnyCodable("actions"),
                            "type": AnyCodable("actions"),
                            "actions": AnyCodable([
                                AnyCodable(["id": AnyCodable("continue"), "label": AnyCodable("Continue")]),
                                AnyCodable(["id": AnyCodable("pause"), "label": AnyCodable("Pause")]),
                                AnyCodable(["id": AnyCodable("open_logs"), "label": AnyCodable("Open Logs")])
                            ])
                        ])
                    ])
                ],
                contextPayload: [
                    "source": AnyCodable("demo"),
                    "sample": AnyCodable("taskPlan")
                ],
                actionLabel: "Continue",
                actionPayload: ["actionId": AnyCodable("continue")]
            )

        case .testRun:
            return GenUIEvent(
                id: "demo/genui/\(surfaceID)",
                schemaVersion: "v0",
                mode: .snapshot,
                surfaceID: surfaceID,
                revision: 1,
                correlationID: "demo-\(surfaceID)",
                title: "CI Test Matrix",
                body: "Latest simulator run with flaky-suite diagnostics",
                surfacePayload: [
                    "components": AnyCodable([
                        AnyCodable([
                            "id": AnyCodable("passed"),
                            "type": AnyCodable("metric"),
                            "label": AnyCodable("Passed"),
                            "value": AnyCodable("124"),
                            "trend": AnyCodable("+3")
                        ]),
                        AnyCodable([
                            "id": AnyCodable("failed"),
                            "type": AnyCodable("metric"),
                            "label": AnyCodable("Failed"),
                            "value": AnyCodable("2"),
                            "trend": AnyCodable("-1")
                        ]),
                        AnyCodable([
                            "id": AnyCodable("progress"),
                            "type": AnyCodable("progress"),
                            "label": AnyCodable("Run Progress"),
                            "value": AnyCodable(0.82)
                        ]),
                        AnyCodable([
                            "id": AnyCodable("actions"),
                            "type": AnyCodable("actions"),
                            "actions": AnyCodable([
                                AnyCodable(["id": AnyCodable("rerun_failed"), "label": AnyCodable("Rerun Failed")]),
                                AnyCodable(["id": AnyCodable("open_report"), "label": AnyCodable("Open Report")])
                            ])
                        ])
                    ])
                ],
                contextPayload: [
                    "source": AnyCodable("demo"),
                    "sample": AnyCodable("testRun")
                ],
                actionLabel: "Rerun Failed",
                actionPayload: ["actionId": AnyCodable("rerun_failed")]
            )

        case .release:
            return GenUIEvent(
                id: "demo/genui/\(surfaceID)",
                schemaVersion: "v0",
                mode: .snapshot,
                surfaceID: surfaceID,
                revision: 1,
                correlationID: "demo-\(surfaceID)",
                title: "Release Cockpit",
                body: "Production rollout across 3 environments",
                surfacePayload: [
                    "components": AnyCodable([
                        AnyCodable([
                            "id": AnyCodable("summary"),
                            "type": AnyCodable("text"),
                            "text": AnyCodable("Canary at 25%. Monitoring error budget and p95 latency.")
                        ]),
                        AnyCodable([
                            "id": AnyCodable("progress"),
                            "type": AnyCodable("progress"),
                            "label": AnyCodable("Rollout"),
                            "value": AnyCodable(0.25)
                        ]),
                        AnyCodable([
                            "id": AnyCodable("actions"),
                            "type": AnyCodable("actions"),
                            "actions": AnyCodable([
                                AnyCodable(["id": AnyCodable("promote"), "label": AnyCodable("Promote to 50%")]),
                                AnyCodable(["id": AnyCodable("rollback"), "label": AnyCodable("Rollback")])
                            ])
                        ])
                    ])
                ],
                contextPayload: [
                    "source": AnyCodable("demo"),
                    "sample": AnyCodable("release")
                ],
                actionLabel: "Promote to 50%",
                actionPayload: ["actionId": AnyCodable("promote")]
            )
        }
    }

    func patch(surfaceID: String, revision: Int) -> GenUIEvent {
        switch self {
        case .taskPlan:
            let doneCount = min(3, revision + 1)
            let completion = min(1.0, Double(doneCount) / 3.0)
            return GenUIEvent(
                id: "demo/genui/\(surfaceID)",
                schemaVersion: "v0",
                mode: .patch,
                surfaceID: surfaceID,
                revision: revision + 2,
                correlationID: "demo-\(surfaceID)",
                title: "Migration Sprint",
                body: "Patch update #\(revision + 1)",
                surfacePayload: [
                    "components": AnyCodable([
                        AnyCodable([
                            "id": AnyCodable("progress"),
                            "type": AnyCodable("progress"),
                            "label": AnyCodable("Completion"),
                            "value": AnyCodable(completion)
                        ]),
                        AnyCodable([
                            "id": AnyCodable("checklist"),
                            "type": AnyCodable("checklist"),
                            "title": AnyCodable("Gate Status"),
                            "items": AnyCodable([
                                AnyCodable(["id": AnyCodable("ui"), "label": AnyCodable("UI parity"), "done": AnyCodable(doneCount >= 1)]),
                                AnyCodable(["id": AnyCodable("acp"), "label": AnyCodable("ACP replay fidelity"), "done": AnyCodable(doneCount >= 2)]),
                                AnyCodable(["id": AnyCodable("genui"), "label": AnyCodable("GenUI callback contract"), "done": AnyCodable(doneCount >= 3)])
                            ])
                        ])
                    ])
                ],
                contextPayload: [
                    "source": AnyCodable("demo"),
                    "sample": AnyCodable("taskPlan")
                ],
                actionPayload: ["actionId": AnyCodable("continue")]
            )

        case .testRun:
            let failures = max(0, 2 - revision)
            let progress = min(1.0, 0.82 + (Double(revision) * 0.09))
            return GenUIEvent(
                id: "demo/genui/\(surfaceID)",
                schemaVersion: "v0",
                mode: .patch,
                surfaceID: surfaceID,
                revision: revision + 2,
                correlationID: "demo-\(surfaceID)",
                title: "CI Test Matrix",
                body: "Patch update #\(revision + 1)",
                surfacePayload: [
                    "components": AnyCodable([
                        AnyCodable(["id": AnyCodable("failed"), "type": AnyCodable("metric"), "label": AnyCodable("Failed"), "value": AnyCodable("\(failures)"), "trend": AnyCodable("stabilizing")]),
                        AnyCodable(["id": AnyCodable("progress"), "type": AnyCodable("progress"), "label": AnyCodable("Run Progress"), "value": AnyCodable(progress)])
                    ])
                ],
                contextPayload: [
                    "source": AnyCodable("demo"),
                    "sample": AnyCodable("testRun")
                ],
                actionPayload: ["actionId": AnyCodable("rerun_failed")]
            )

        case .release:
            let progress = min(1.0, 0.25 + (Double(revision + 1) * 0.25))
            return GenUIEvent(
                id: "demo/genui/\(surfaceID)",
                schemaVersion: "v0",
                mode: .patch,
                surfaceID: surfaceID,
                revision: revision + 2,
                correlationID: "demo-\(surfaceID)",
                title: "Release Cockpit",
                body: "Patch update #\(revision + 1)",
                surfacePayload: [
                    "components": AnyCodable([
                        AnyCodable([
                            "id": AnyCodable("progress"),
                            "type": AnyCodable("progress"),
                            "label": AnyCodable("Rollout"),
                            "value": AnyCodable(progress)
                        ])
                    ])
                ],
                contextPayload: [
                    "source": AnyCodable("demo"),
                    "sample": AnyCodable("release")
                ],
                actionPayload: ["actionId": AnyCodable("promote")]
            )
        }
    }
}
