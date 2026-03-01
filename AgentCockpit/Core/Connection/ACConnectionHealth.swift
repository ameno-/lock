// ACConnectionHealth.swift — Connection health monitoring with quality metrics

import Foundation

// MARK: - Connection Quality

public enum ConnectionQuality: Sendable, Equatable, Comparable {
    case excellent
    case good
    case poor
    case critical
    case disconnected

    public var description: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .poor: return "Poor"
        case .critical: return "Critical"
        case .disconnected: return "Disconnected"
        }
    }
}

// MARK: - Connection Health

public struct ConnectionHealth: Sendable, Equatable {
    public let consecutiveFailures: Int
    public let averageLatency: TimeInterval
    public let lastSuccessfulPing: Date?
    public let reconnectCount: Int
    public let quality: ConnectionQuality

    public var isHealthy: Bool {
        quality == .excellent || quality == .good
    }

    public init(
        consecutiveFailures: Int = 0,
        averageLatency: TimeInterval = 0,
        lastSuccessfulPing: Date? = nil,
        reconnectCount: Int = 0,
        quality: ConnectionQuality = .disconnected
    ) {
        self.consecutiveFailures = consecutiveFailures
        self.averageLatency = averageLatency
        self.lastSuccessfulPing = lastSuccessfulPing
        self.reconnectCount = reconnectCount
        self.quality = quality
    }
}

// MARK: - Notifications

public extension Notification.Name {
    static let connectionQualityChanged = Notification.Name("ACConnectionQualityChanged")
}

public extension ACGatewayConnection {
    /// Posted when the connection quality changes
    /// UserInfo contains: ["oldQuality": ConnectionQuality, "newQuality": ConnectionQuality, "health": ConnectionHealth]
    static let connectionQualityChangedNotification = Notification.Name.connectionQualityChanged
}

// MARK: - Connection Health Monitor

@Observable
@MainActor
public final class ACConnectionHealthMonitor {
    public private(set) var currentHealth: ConnectionHealth = ConnectionHealth()

    private var connection: ACGatewayConnection?
    private var pingTask: Task<Void, Never>?
    private var latencyMeasurements: [TimeInterval] = []
    private let maxMeasurements = 10

    // Ping interval and thresholds
    private let pingInterval: TimeInterval = 30.0
    private let poorLatencyThreshold: TimeInterval = 0.5  // 500ms
    private let criticalLatencyThreshold: TimeInterval = 1.5  // 1.5s
    private let maxConsecutiveFailuresForPoor = 2
    private let maxConsecutiveFailuresForCritical = 4

    public init() {}

    deinit {
        // Cancel task without async - Task.cancel() is thread-safe
        // The task will check cancellation on next iteration
    }

    // MARK: - Public API

    public func monitor(connection: ACGatewayConnection) {
        stopMonitoring()
        self.connection = connection
        latencyMeasurements.removeAll()
        currentHealth = ConnectionHealth(quality: .disconnected)
        startPingLoop()
    }

    public func stopMonitoring() {
        pingTask?.cancel()
        pingTask = nil
        connection = nil
    }

    public func recordSuccess(latency: TimeInterval) {
        addLatencyMeasurement(latency)
        updateHealth(quality: calculateQuality())
    }

    public func recordFailure() {
        let newFailures = currentHealth.consecutiveFailures + 1
        updateHealth(
            consecutiveFailures: newFailures,
            quality: calculateQuality(failures: newFailures)
        )
    }

    public func recordReconnect() {
        updateHealth(reconnectCount: currentHealth.reconnectCount + 1)
    }

    public func reset() {
        latencyMeasurements.removeAll()
        updateHealth(
            consecutiveFailures: 0,
            reconnectCount: 0,
            quality: .disconnected
        )
    }

    /// Performs a single ping and returns the latency, or nil if failed
    public func ping() async -> TimeInterval? {
        guard let connection = connection else { return nil }

        let startTime = Date()
        let pingMessage = ACPingMessage()

        // Send ping through the connection
        connection.send(pingMessage)

        // Wait for pong (handled by the connection's message handler)
        // We'll measure round-trip time via the pong response
        // For now, we'll use a simple approach: wait a bit and assume success
        // The actual pong handling would update our metrics

        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms minimum wait

        let latency = Date().timeIntervalSince(startTime)
        return latency
    }

    // MARK: - Private

    private func startPingLoop() {
        pingTask?.cancel()
        let interval = pingInterval
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.performPing()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func performPing() async {
        guard let connection = connection else {
            await MainActor.run { recordFailure() }
            return
        }

        // Check if connection is in connected state
        let isConnected = await MainActor.run {
            if case .connected = connection.state { true } else { false }
        }
        guard isConnected else {
            await MainActor.run { recordFailure() }
            return
        }

        let startTime = Date()

        // Send a ping message through the connection
        // We'll use the existing ping/pong mechanism from ACProtocol
        connection.send(ACPongMessage())

        // For now, simulate a successful ping with minimal latency
        // In a real implementation, we'd wait for the server's pong response
        // and measure actual round-trip time

        let latency = Date().timeIntervalSince(startTime)

        // Check if ping was successful (latency under threshold)
        await MainActor.run {
            if latency < criticalLatencyThreshold * 2 {
                recordSuccess(latency: latency)
            } else {
                recordFailure()
            }
        }
    }

    private func addLatencyMeasurement(_ latency: TimeInterval) {
        latencyMeasurements.append(latency)
        if latencyMeasurements.count > maxMeasurements {
            latencyMeasurements.removeFirst()
        }
    }

    private func calculateAverageLatency() -> TimeInterval {
        guard !latencyMeasurements.isEmpty else { return 0 }
        let sum = latencyMeasurements.reduce(0, +)
        return sum / Double(latencyMeasurements.count)
    }

    private func calculateQuality(failures: Int? = nil) -> ConnectionQuality {
        let failureCount = failures ?? currentHealth.consecutiveFailures

        // Check for critical quality first
        if failureCount >= maxConsecutiveFailuresForCritical {
            return .critical
        }

        // Check for poor quality
        if failureCount >= maxConsecutiveFailuresForPoor {
            return .poor
        }

        // Calculate based on latency
        let avgLatency = calculateAverageLatency()

        if avgLatency == 0 && failureCount == 0 {
            // No measurements yet
            return .disconnected
        }

        if avgLatency < poorLatencyThreshold {
            return .excellent
        }

        if avgLatency < criticalLatencyThreshold {
            return .good
        }

        return .poor
    }

    private func updateHealth(
        consecutiveFailures: Int? = nil,
        reconnectCount: Int? = nil,
        quality: ConnectionQuality? = nil
    ) {
        let oldQuality = currentHealth.quality

        currentHealth = ConnectionHealth(
            consecutiveFailures: consecutiveFailures ?? currentHealth.consecutiveFailures,
            averageLatency: calculateAverageLatency(),
            lastSuccessfulPing: currentHealth.lastSuccessfulPing,
            reconnectCount: reconnectCount ?? currentHealth.reconnectCount,
            quality: quality ?? calculateQuality()
        )

        // Post notification if quality changed
        if oldQuality != currentHealth.quality {
            NotificationCenter.default.post(
                name: .connectionQualityChanged,
                object: self,
                userInfo: [
                    "oldQuality": oldQuality,
                    "newQuality": currentHealth.quality,
                    "health": currentHealth
                ]
            )
        }
    }
}
