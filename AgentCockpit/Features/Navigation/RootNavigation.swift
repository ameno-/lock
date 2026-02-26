// RootNavigation.swift — TabView (iPhone) + NavigationSplitView (iPad)
import SwiftUI

struct RootNavigation: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            iPadLayout
        } else {
            iPhoneLayout
        }
    }

    // MARK: - iPad: NavigationSplitView (AIs sidebar + Work detail)

    private var iPadLayout: some View {
        @Bindable var model = appModel
        return NavigationSplitView {
            AIsView(appModel: appModel)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
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

    // MARK: - iPhone: TabView (Home | Work | AIs)

    private var iPhoneLayout: some View {
        @Bindable var model = appModel
        return TabView(selection: $model.selectedTab) {
            HomeView()
                .environment(appModel)
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(AppTab.home)

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
            .tabItem {
                Label("Work", systemImage: "terminal")
            }
            .tag(AppTab.work)

            AIsView(appModel: appModel)
                .environment(appModel)
                .tabItem {
                    Label("AIs", systemImage: "brain")
                }
                .tag(AppTab.ais)
        }
    }
}
