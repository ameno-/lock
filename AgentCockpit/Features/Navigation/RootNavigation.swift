// RootNavigation.swift — Agmente-style session-first navigation
import SwiftUI

private enum PhoneRoute: Hashable {
    case session
}

struct RootNavigation: View {
    @Environment(AppModel.self) private var appModel
    @State private var phonePath: [PhoneRoute] = []

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            iPadLayout
        } else {
            iPhoneLayout
        }
    }

    private var iPadLayout: some View {
        NavigationSplitView {
            AIsView(appModel: appModel)
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 420)
        } detail: {
            NavigationStack {
                WorkView(appModel: appModel)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            NavigationLink {
                                SettingsView()
                                    .environment(appModel)
                            } label: {
                                Image(systemName: "gear")
                            }
                        }
                    }
            }
        }
    }

    private var iPhoneLayout: some View {
        NavigationStack(path: $phonePath) {
            AIsView(appModel: appModel)
                .navigationDestination(for: PhoneRoute.self) { route in
                    switch route {
                    case .session:
                        WorkView(appModel: appModel)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    NavigationLink {
                                        SettingsView()
                                            .environment(appModel)
                                    } label: {
                                        Image(systemName: "gear")
                                    }
                                }
                            }
                    }
                }
                .onChange(of: appModel.promotedSessionKey) { _, newValue in
                    guard newValue != nil else { return }
                    if phonePath.last != .session {
                        phonePath.append(.session)
                    }
                }
        }
    }
}
