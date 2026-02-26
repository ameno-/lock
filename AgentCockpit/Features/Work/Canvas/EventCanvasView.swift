// EventCanvasView.swift — LazyVStack + ScrollViewReader auto-scroll
import SwiftUI

struct EventCanvasView: View {
    let events: [CanvasEvent]
    var onViewSubAgentInAIs: ((SubAgentEvent) -> Void)? = nil

    @State private var isAtBottom = true
    @State private var lastRenderedMarker = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(events) { event in
                        EventCardRouter(event: event) {
                            if case .subAgent(let e) = event {
                                onViewSubAgentInAIs?(e)
                            }
                        }
                        .padding(.horizontal, 12)
                        .id(event.id)
                    }

                    // Bottom anchor
                    Color.clear
                        .frame(height: 1)
                        .id("__bottom__")
                }
                .padding(.top, 12)
            }
            .onChange(of: latestEventMarker) { _, marker in
                guard !marker.isEmpty else { return }
                guard marker != lastRenderedMarker else { return }
                guard isAtBottom else {
                    lastRenderedMarker = marker
                    return
                }
                lastRenderedMarker = marker
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("__bottom__", anchor: .bottom)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isAtBottom && events.count > 0 {
                    Button {
                        withAnimation { proxy.scrollTo("__bottom__", anchor: .bottom) }
                        isAtBottom = true
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    private var latestEventMarker: String {
        guard let last = events.last else { return "" }
        let seconds = Int(last.timestamp.timeIntervalSince1970 * 1000)
        return "\(last.id)-\(seconds)"
    }
}
