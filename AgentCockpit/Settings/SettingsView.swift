// SettingsView.swift — Endpoint and auth configuration for ACP/Codex backends
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var authToken = ""
    @State private var cfAccessClientId = ""
    @State private var cfAccessClientSecret = ""
    @State private var didSave = false
    @State private var schemeInput = "ws"
    @State private var hostInput = ""
    @State private var portInput = ""
    @State private var pathInput = "/"
    @State private var workingDirectoryInput = ""
    @State private var didApplyProfile = false

    var body: some View {
        @Bindable var settings = appModel.settings

        Form {
            Section("Endpoint") {
                Picker("Protocol", selection: $settings.serverProtocol) {
                    ForEach(ACServerProtocol.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker("Scheme", selection: $schemeInput) {
                    Text("ws").tag("ws")
                    Text("wss").tag("wss")
                }

                LabeledContent("Host") {
                    TextField("127.0.0.1", text: $hostInput)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                LabeledContent("Port") {
                    TextField("19000", text: $portInput)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }

                LabeledContent("Path") {
                    TextField("/", text: $pathInput)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }

            Section("Quick Profiles") {
                Button("Pi ACP Local (ws://127.0.0.1:8765)") {
                    applyPiACPProfile()
                }
                Button("Codex Local (ws://127.0.0.1:8788)") {
                    applyCodexProfile()
                }
                .foregroundStyle(.primary)
                if didApplyProfile {
                    Text("Profile applied. For ACP, set an absolute Working Dir before create/load.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Session Defaults") {
                LabeledContent("Working Dir") {
                    TextField("/remote/path", text: $workingDirectoryInput)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }

            Section("Authentication") {
                SecureField("Bearer Token", text: $authToken)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                LabeledContent("CF Access Client ID") {
                    TextField("Optional", text: $cfAccessClientId)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                LabeledContent("CF Access Secret") {
                    SecureField("Optional", text: $cfAccessClientSecret)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Button("Save Authentication") {
                    settings.authToken = authToken
                    settings.cfAccessClientId = cfAccessClientId
                    settings.cfAccessClientSecret = cfAccessClientSecret
                    didSave = true
                }

                if didSave {
                    Label("Credentials saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            Section("Discovery") {
                Toggle("Bonjour Discovery", isOn: $settings.bonjourEnabled)
            }

            Section("Features") {
                Picker("Transcript Display", selection: $settings.transcriptDisplayMode) {
                    ForEach(ACTranscriptDisplayMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text(settings.transcriptDisplayMode.settingsDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Enable GenUI", isOn: $settings.genuiEnabled)
                Text("When disabled, GenUI payloads stay visible as raw text events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Auto-synthesize GenUI from assistant text", isOn: $settings.implicitGenUIFromTextEnabled)
                Text("When enabled, checklist/progress assistant text can render as GenUI cards when no embedded GenUI block is present.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Diagnostics")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                LabeledContent("GenUI callback") {
                    Text(appModel.activeGenUIActionCallbackDiagnostic.value)
                        .font(.footnote.monospaced())
                        .foregroundStyle(
                            appModel.activeGenUIActionCallbackDiagnostic == .notAdvertised
                                ? .secondary
                                : .primary
                        )
                }
                LabeledContent("GenUI parsed") {
                    Text("\(appModel.genUIParseTelemetry.parsed)")
                        .monospacedDigit()
                }
                LabeledContent("GenUI ignored") {
                    Text("\(appModel.genUIParseTelemetry.parseIgnored)")
                        .monospacedDigit()
                }
                LabeledContent("GenUI embedded") {
                    Text("\(appModel.genUIParseTelemetry.embeddedParsed)")
                        .monospacedDigit()
                }
            }

            Section("Connection Status") {
                HStack {
                    Text("Status")
                    Spacer()
                    StatusPill(state: appModel.connection.state)
                }
                Button("Reconnect") {
                    appModel.stop()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        appModel.start()
                    }
                }
            }

            Section("Labs") {
                NavigationLink {
                    GenUIComponentShowcase()
                } label: {
                    Label("Component Showcase", systemImage: "rectangle.3.group")
                }
                Text("Visual showcase of all GenUI component types: text, metric, progress, checklist, actions, timeline, decision, diff, risk gate, key-value, code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                NavigationLink {
                    RetroChatView()
                } label: {
                    Label("Retro Chat UI", systemImage: "bubble.left.and.bubble.right")
                }
                Text("Playful retro-styled chat interface with animated avatar and GenUI integration ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Endpoint Mode", value: settings.serverProtocol.displayName)
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            syncInputsFromSettings()
        }
        .onChange(of: schemeInput) { _, v in
            if v == "ws" || v == "wss" { appModel.settings.scheme = v }
        }
        .onChange(of: hostInput) { _, v in
            if !v.isEmpty { appModel.settings.host = v }
        }
        .onChange(of: portInput) { _, v in
            if let port = Int(v), port > 0 { appModel.settings.port = port }
        }
        .onChange(of: pathInput) { _, v in
            if !v.isEmpty { appModel.settings.path = v }
        }
        .onChange(of: workingDirectoryInput) { _, v in
            appModel.settings.workingDirectory = v
        }
    }

    private func applyPiACPProfile() {
        appModel.settings.serverProtocol = .acp
        appModel.settings.scheme = "ws"
        appModel.settings.host = "127.0.0.1"
        appModel.settings.port = 8765
        appModel.settings.path = "/"
        didApplyProfile = true
        syncInputsFromSettings()
    }

    private func applyCodexProfile() {
        appModel.settings.serverProtocol = .codex
        appModel.settings.scheme = "ws"
        appModel.settings.host = "127.0.0.1"
        appModel.settings.port = 8788
        appModel.settings.path = "/"
        didApplyProfile = true
        syncInputsFromSettings()
    }

    private func syncInputsFromSettings() {
        schemeInput = appModel.settings.scheme
        hostInput = appModel.settings.host
        portInput = String(appModel.settings.port)
        pathInput = appModel.settings.path
        workingDirectoryInput = appModel.settings.workingDirectory
        authToken = appModel.settings.authToken
        cfAccessClientId = appModel.settings.cfAccessClientId
        cfAccessClientSecret = appModel.settings.cfAccessClientSecret
    }
}
