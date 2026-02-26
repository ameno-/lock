// AgentDetailView.swift — Mini EventCanvasView (last 50 events) + Promote button
import SwiftUI

struct AgentDetailView: View {
    let session: ACSessionEntry
    @Environment(AppModel.self) private var appModel
    @State private var events: [CanvasEvent] = []

    var body: some View {
        VStack(spacing: 0) {
            // Mini canvas (last 50 events, read-only)
            if events.isEmpty {
                ContentUnavailableView {
                    Label("No Events", systemImage: "tray")
                } description: {
                    Text("No events received for this session yet.")
                }
            } else {
                EventCanvasView(events: events)
            }

            // Promote bar
            VStack(spacing: 0) {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.name)
                            .font(.subheadline.weight(.semibold))
                        Text(sessionLocationText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        appModel.promoteSession(session.key)
                    } label: {
                        Label(
                            appModel.promotedSessionKey == session.key ? "Open Work" : "Promote to Work",
                            systemImage: "arrow.up.circle.fill"
                        )
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(16)
                .background(.ultraThinMaterial)
            }
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            events = appModel.eventStore.recentEvents(for: session.key, limit: 50)
        }
        .onChange(of: appModel.eventStore.allEvents.count) {
            events = appModel.eventStore.recentEvents(for: session.key, limit: 50)
        }
    }

    private var sessionLocationText: String {
        if session.window != "0" || session.pane != "0" {
            return "window \(session.window) • pane \(session.pane)"
        }
        let shortKey = session.key.count > 20 ? "\(session.key.prefix(20))…" : session.key
        return "id \(shortKey)"
    }
}
