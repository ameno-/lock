// SettingsView.swift — Gateway host, token, Bonjour toggle
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var gatewayToken = ""
    @State private var didSave = false
    @State private var schemeInput = "ws"
    @State private var hostInput = ""
    @State private var portInput = ""
    @State private var pathInput = "/"
    @State private var workingDirectoryInput = ""

    var body: some View {
        @Bindable var settings = appModel.settings

        Form {
            Section("Gateway Connection") {
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
                    TextField("100.68.58.17", text: $hostInput)
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

                Toggle("Bonjour Discovery", isOn: $settings.bonjourEnabled)
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
                SecureField("Gateway Token", text: $gatewayToken)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button("Save Token") {
                    try? ACKeychainStore.saveToken(gatewayToken)
                    didSave = true
                }
                .disabled(gatewayToken.isEmpty)

                if didSave {
                    Label("Token saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
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

            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Endpoint Mode", value: settings.serverProtocol.displayName)
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            schemeInput = appModel.settings.scheme
            hostInput = appModel.settings.host
            portInput = String(appModel.settings.port)
            pathInput = appModel.settings.path
            workingDirectoryInput = appModel.settings.workingDirectory
            gatewayToken = ACKeychainStore.loadToken() ?? ""
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
}
