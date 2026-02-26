// AgentCockpitApp.swift — App entry point, scene setup
import SwiftUI

@main
struct AgentCockpitApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootNavigation()
                .environment(appModel)
                .onAppear {
                    appModel.start()
                }
                .onDisappear {
                    appModel.stop()
                }
        }
    }
}
