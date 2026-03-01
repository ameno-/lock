import SwiftUI

struct GenUIShowcaseSample: Identifiable {
    let id: String
    let title: String
    let event: GenUIEvent

    init(title: String, event: GenUIEvent) {
        self.id = event.id
        self.title = title
        self.event = event
    }
}

enum GenUIShowcaseData {
    static let samples: [GenUIShowcaseSample] = [
        GenUIShowcaseSample(
            title: "Timeline",
            event: GenUIEvent(
                id: "showcase/timeline",
                surfaceID: "session.plan",
                title: "Migration Plan",
                body: "3 of 5 steps completed",
                surfacePayload: [
                    "components": AnyCodable([
                        AnyCodable([
                            "id": AnyCodable("timeline"),
                            "type": AnyCodable("timeline"),
                            "title": AnyCodable("Steps"),
                            "steps": AnyCodable([
                                AnyCodable(["id": AnyCodable("s1"), "label": AnyCodable("Parse schema"), "state": AnyCodable("completed")]),
                                AnyCodable(["id": AnyCodable("s2"), "label": AnyCodable("Generate models"), "state": AnyCodable("completed")]),
                                AnyCodable(["id": AnyCodable("s3"), "label": AnyCodable("Write migrations"), "state": AnyCodable("completed")]),
                                AnyCodable(["id": AnyCodable("s4"), "label": AnyCodable("Run tests"), "state": AnyCodable("active"), "detail": AnyCodable("12 of 24 passing")]),
                                AnyCodable(["id": AnyCodable("s5"), "label": AnyCodable("Deploy to staging"), "state": AnyCodable("pending")]),
                            ]),
                        ]),
                    ]),
                ],
                contextPayload: ["pinned": AnyCodable(true)]
            )
        ),

        GenUIShowcaseSample(
            title: "Text",
            event: GenUIEvent(
                id: "showcase/text",
                title: "Plain Text",
                body: "Markdown and plain text rendering example",
                surfacePayload: [
                    "components": AnyCodable([
                        AnyCodable([
                            "id": AnyCodable("note"),
                            "type": AnyCodable("text"),
                            "text": AnyCodable("Here is a simple status note rendered through GenUI text component."),
                        ]),
                    ]),
                ]
            )
        ),

        GenUIShowcaseSample(
            title: "Metric",
            event: GenUIEvent(
                id: "showcase/metric",
                title: "KPI Cards",
                body: "Single metric rendering test",
                surfacePayload: [
                    "components": AnyCodable([
                        AnyCodable([
                            "id": AnyCodable("cpu"),
                            "type": AnyCodable("metric"),
                            "label": AnyCodable("CPU usage"),
                            "value": AnyCodable("68%"),
                            "trend": AnyCodable("↑ 3%"),
                        ]),
                    ]),
                ]
            )
        ),

        GenUIShowcaseSample(
            title: "Decision",
            event: GenUIEvent(
                id: "showcase/decision",
                surfaceID: "session.decision.1",
                title: "Architecture Choice",
                body: "Choose an approach",
                surfacePayload: [
                    "components": AnyCodable([
                        AnyCodable([
                            "id": AnyCodable("decision"),
                            "type": AnyCodable("decision"),
                            "prompt": AnyCodable("How should we handle auth token refresh?"),
                            "options": AnyCodable([
                                AnyCodable(["id": AnyCodable("interceptor"), "label": AnyCodable("HTTP Interceptor"), "description": AnyCodable("Automatic retry with refreshed token on 401")]),
                                AnyCodable(["id": AnyCodable("preemptive"), "label": AnyCodable("Preemptive Refresh"), "description": AnyCodable("Check expiry before each request, refresh proactively")]),
                                AnyCodable(["id": AnyCodable("manual"), "label": AnyCodable("Manual Handling"), "description": AnyCodable("Caller handles refresh when needed")]),
                            ]),
                        ]),
                    ]),
                ],
                contextPayload: ["pinned": AnyCodable(true)]
            )
        ),

        GenUIShowcaseSample(
            title: "Risk Gate",
            event: GenUIEvent(
                id: "showcase/riskgate",
                surfaceID: "session.approval.demo",
                title: "Approval Required",
                body: "rm -rf build/ in production",
                surfacePayload: [
                    "components": AnyCodable([
                        AnyCodable([
                            "id": AnyCodable("risk"),
                            "type": AnyCodable("risk_gate"),
                            "level": AnyCodable("high"),
                            "summary": AnyCodable("Destructive command in production directory"),
                            "detail": AnyCodable("rm -rf build/ will permanently delete build artifacts"),
                        ]),
                        AnyCodable([
                            "id": AnyCodable("cmd"),
                            "type": AnyCodable("code_block"),
                            "language": AnyCodable("bash"),
                            "code": AnyCodable("rm -rf build/"),
                        ]),
                        AnyCodable([
                            "id": AnyCodable("actions"),
                            "type": AnyCodable("actions"),
                            "actions": AnyCodable([
                                AnyCodable(["id": AnyCodable("accept"), "label": AnyCodable("Accept")]),
                                AnyCodable(["id": AnyCodable("decline"), "label": AnyCodable("Decline")]),
                            ]),
                        ]),
                    ]),
                ],
                contextPayload: ["pinned": AnyCodable(true)]
            )
        ),

        GenUIShowcaseSample(
            title: "Diff Preview",
            event: GenUIEvent(
                id: "showcase/diff",
                title: "File Change Preview",
                body: "auth.swift +12 -3",
                surfacePayload: [
                    "components": AnyCodable([
                        AnyCodable([
                            "id": AnyCodable("diff"),
                            "type": AnyCodable("diff_preview"),
                            "file": AnyCodable("Sources/Auth/TokenManager.swift"),
                            "additions": AnyCodable(12),
                            "deletions": AnyCodable(3),
                            "diff": AnyCodable("@@ -15,8 +15,20 @@\n func refreshToken() async throws {\n-    let response = try await fetch(\"/auth/refresh\")\n-    token = response.token\n-    expiry = response.expiry\n+    guard !isRefreshing else {\n+        return try await withCheckedThrowingContinuation { continuation in\n+            pendingContinuations.append(continuation)\n+        }\n+    }\n+    isRefreshing = true\n+    defer { isRefreshing = false }\n+    let response = try await fetch(\"/auth/refresh\")\n+    token = response.token\n+    expiry = response.expiry\n+    for continuation in pendingContinuations {\n+        continuation.resume()\n+    }\n+    pendingContinuations.removeAll()\n}"),
                        ]),
                    ]),
                ]
            )
        ),

        GenUIShowcaseSample(
            title: "Key-Value",
            event: GenUIEvent(
                id: "showcase/kv",
                title: "Session Info",
                body: "Session metadata",
                surfacePayload: [
                    "components": AnyCodable([
                        AnyCodable([
                            "id": AnyCodable("kv"),
                            "type": AnyCodable("key_value"),
                            "title": AnyCodable("Build Info"),
                            "pairs": AnyCodable([
                                AnyCodable(["id": AnyCodable("p1"), "key": AnyCodable("Branch"), "value": AnyCodable("feat/genui-overhaul")]),
                                AnyCodable(["id": AnyCodable("p2"), "key": AnyCodable("Commit"), "value": AnyCodable("8020c75")]),
                                AnyCodable(["id": AnyCodable("p3"), "key": AnyCodable("Tests"), "value": AnyCodable("82/82 passing")]),
                                AnyCodable(["id": AnyCodable("p4"), "key": AnyCodable("Duration"), "value": AnyCodable("14.65s")]),
                            ]),
                        ]),
                    ]),
                ]
            )
        ),

        GenUIShowcaseSample(
            title: "Code Block",
            event: GenUIEvent(
                id: "showcase/code",
                title: "Generated Code",
                body: "Swift token refresh",
                surfacePayload: [
                    "components": AnyCodable([
                        AnyCodable([
                            "id": AnyCodable("code"),
                            "type": AnyCodable("code_block"),
                            "language": AnyCodable("swift"),
                            "code": AnyCodable("func refreshIfNeeded() async throws {\n    guard expiry < .now else { return }\n    token = try await provider.refresh()\n}"),
                        ]),
                    ]),
                ]
            )
        ),

        GenUIShowcaseSample(
            title: "Combined (Progress + Checklist + Actions)",
            event: GenUIEvent(
                id: "showcase/combined",
                surfaceID: "session.progress",
                title: "CI Pipeline",
                body: "Build and test progress",
                surfacePayload: [
                    "components": AnyCodable([
                        AnyCodable([
                            "id": AnyCodable("progress"),
                            "type": AnyCodable("progress"),
                            "label": AnyCodable("Pipeline"),
                            "value": AnyCodable(0.72),
                        ]),
                        AnyCodable([
                            "id": AnyCodable("checklist"),
                            "type": AnyCodable("checklist"),
                            "title": AnyCodable("Stages"),
                            "items": AnyCodable([
                                AnyCodable(["id": AnyCodable("lint"), "label": AnyCodable("Lint"), "done": AnyCodable(true)]),
                                AnyCodable(["id": AnyCodable("build"), "label": AnyCodable("Build"), "done": AnyCodable(true)]),
                                AnyCodable(["id": AnyCodable("test"), "label": AnyCodable("Test (82/82)"), "done": AnyCodable(true)]),
                                AnyCodable(["id": AnyCodable("deploy"), "label": AnyCodable("Deploy"), "done": AnyCodable(false)]),
                            ]),
                        ]),
                        AnyCodable([
                            "id": AnyCodable("actions"),
                            "type": AnyCodable("actions"),
                            "actions": AnyCodable([
                                AnyCodable(["id": AnyCodable("deploy"), "label": AnyCodable("Deploy Now")]),
                                AnyCodable(["id": AnyCodable("rerun"), "label": AnyCodable("Rerun Tests")]),
                            ]),
                        ]),
                    ]),
                ],
                contextPayload: ["pinned": AnyCodable(true)]
            )
        ),
    ]

    static let surfaceDockSamples: [GenUIEvent] = [
        samples[0].event,
        samples[2].event,
        samples[3].event,
    ]
}

struct GenUIComponentShowcase: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("All GenUI component types rendered from mock payloads.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)

                ForEach(GenUIShowcaseData.samples) { sample in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(sample.title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 12)

                        GenUICard(event: sample.event)
                            .padding(.horizontal, 12)
                    }
                }

                surfaceDockPreview
                    .padding(.top, 8)
            }
            .padding(.vertical, 12)
        }
        .navigationTitle("Component Showcase")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var surfaceDockPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SURFACE DOCK PREVIEW")
                .font(.caption.weight(.bold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 12)
            Text("Promoted surfaces rendered as a horizontal dock.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            SurfaceDockView(
                surfaces: GenUIShowcaseData.surfaceDockSamples
            )
        }
    }
}
