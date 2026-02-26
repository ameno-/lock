// HomeView.swift — Landing screen with connection status + quick stats
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Connection card
                    CardBase {
                        VStack(alignment: .leading, spacing: 12) {
                            CardHeader(icon: "📡", title: "Gateway")
                            StatusPill(state: appModel.connection.state)
                            Text(appModel.settings.serverProtocol.displayName)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(appModel.settings.wsURL.absoluteString)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)

                    // Quick stats
                    HStack(spacing: 12) {
                        StatCard(
                            icon: "🤖",
                            label: "Sub-Agents",
                            value: "\(appModel.eventStore.runningSubAgents.count) running"
                        )
                        StatCard(
                            icon: "📋",
                            label: "Events",
                            value: "\(appModel.eventStore.allEvents.count)"
                        )
                    }
                    .padding(.horizontal)

                    // Active session
                    if let key = appModel.promotedSessionKey {
                        CardBase {
                            VStack(alignment: .leading, spacing: 8) {
                                CardHeader(icon: "⚡", title: "Active Work Session")
                                Text(key)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal)
                    }

                    Spacer()
                }
                .padding(.top, 20)
            }
            .navigationTitle("AgentCockpit")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

private struct StatCard: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        CardBase {
            VStack(alignment: .leading, spacing: 6) {
                Text(icon).font(.title2)
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
