// ACGatewayConnection.swift — URLSessionWebSocketTask client with auth headers + exponential backoff
import Foundation

public enum ACConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case authenticating
    case connected
    case failed(String)
}

@Observable
@MainActor
public final class ACGatewayConnection: NSObject {
    // MARK: - Published state
    public private(set) var state: ACConnectionState = .disconnected
    public let healthMonitor: ACConnectionHealthMonitor

    // MARK: - Internal
    private var wsTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var reconnectTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?

    private let settings: ACSettingsStore
    private var onMessage: ((ACServerMessage) -> Void)?

    // Exponential backoff state
    private var backoffDelay: Double = 0.5
    private let backoffBase: Double = 1.7
    private let backoffMax: Double = 8.0
    private let adaptiveBackoffMultiplier: Double = 0.7  // Reduce delay when quality is poor

    public init(settings: ACSettingsStore) {
        self.settings = settings
        self.healthMonitor = ACConnectionHealthMonitor()
        super.init()
    }

    // MARK: - Public API

    public func connect(onMessage: @escaping (ACServerMessage) -> Void) {
        self.onMessage = onMessage
        healthMonitor.monitor(connection: self)
        startConnect()
    }

    public func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        pingTask?.cancel()
        pingTask = nil
        wsTask?.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
        healthMonitor.stopMonitoring()
        state = .disconnected
    }

    public func send(_ encodable: some Encodable) {
        guard let wsTask else { return }
        guard state == .connected else { return }
        do {
            let data = try JSONEncoder().encode(encodable)
            let string = String(data: data, encoding: .utf8) ?? ""
            wsTask.send(.string(string)) { [weak self] error in
                if let error {
                    Task { @MainActor [weak self] in
                        self?.handleDisconnect(reason: error.localizedDescription)
                    }
                }
            }
        } catch {
            print("[connection] Encode error: \(error)")
        }
    }

    public func sendPong() {
        send(ACPongMessage())
    }

    // MARK: - Connection lifecycle

    private func startConnect() {
        state = .connecting
        let url = settings.wsURL
        var request = URLRequest(url: url)

        let token = settings.authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let cfAccessClientId = settings.cfAccessClientId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cfAccessClientId.isEmpty {
            request.setValue(cfAccessClientId, forHTTPHeaderField: "CF-Access-Client-Id")
        }

        let cfAccessClientSecret = settings.cfAccessClientSecret
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !cfAccessClientSecret.isEmpty {
            request.setValue(cfAccessClientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        }

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        urlSession = session
        let task = session.webSocketTask(with: request)
        wsTask = task
        task.resume()
        startReceiving(task: task)
    }

    private func startReceiving(task: URLSessionWebSocketTask) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    guard let task = self?.wsTask else { break }
                    let message = try await task.receive()
                    self?.handleReceived(message)
                } catch {
                    self?.handleDisconnect(reason: error.localizedDescription)
                    break
                }
            }
        }
    }

    private func handleReceived(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return
        }

        let parsed = ACMessageParser.parse(data)

        switch parsed {
        case .authOk:
            state = .connected
            backoffDelay = 0.5 // reset on successful auth
            healthMonitor.reset()
            startPingLoop()
        case .authErr(let msg):
            state = .failed("Auth failed: \(msg)")
            healthMonitor.recordFailure()
            wsTask?.cancel()
        case .ping:
            sendPong()
        default:
            break
        }

        onMessage?(parsed)
    }

    private func handleDisconnect(reason: String) {
        guard state != .disconnected else { return }
        print("[connection] Disconnected: \(reason)")
        pingTask?.cancel()
        pingTask = nil
        wsTask = nil
        state = .disconnected
        healthMonitor.recordFailure()
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()

        // Adaptive backoff: reduce delay if connection quality is poor
        var delay = backoffDelay
        let health = healthMonitor.currentHealth

        if health.quality == .poor || health.quality == .critical {
            // Reduce delay to retry faster when connection is unstable
            delay = max(delay * adaptiveBackoffMultiplier, 0.1)
            print("[connection] Adaptive backoff: reduced delay to \(String(format: "%.2f", delay))s due to poor quality")
        }

        backoffDelay = min(backoffDelay * backoffBase, backoffMax)
        healthMonitor.recordReconnect()

        print("[connection] Reconnecting in \(String(format: "%.1f", delay))s...")
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.startConnect()
        }
    }

    // MARK: - Ping Loop

    private func startPingLoop() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            // Wait initial delay before first ping
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds

            while !Task.isCancelled {
                guard let self = self else { break }
                await self.performHealthPing()
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            }
        }
    }

    private func performHealthPing() async {
        guard state == .connected, let wsTask = wsTask else {
            healthMonitor.recordFailure()
            return
        }

        let startTime = Date()

        // Send ping through WebSocket
        do {
            let pingMessage = ACPingMessage()
            let data = try JSONEncoder().encode(pingMessage)
            let string = String(data: data, encoding: .utf8) ?? ""

            // Use a continuation to wait for pong response
            await withCheckedContinuation { continuation in
                wsTask.sendPing { [weak self] error in
                    Task { @MainActor [weak self] in
                        if let error = error {
                            print("[connection] Ping failed: \(error.localizedDescription)")
                            self?.healthMonitor.recordFailure()
                        } else {
                            let latency = Date().timeIntervalSince(startTime)
                            self?.healthMonitor.recordSuccess(latency: latency)
                        }
                        continuation.resume()
                    }
                }
            }
        } catch {
            print("[connection] Ping encode error: \(error)")
            healthMonitor.recordFailure()
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension ACGatewayConnection: URLSessionWebSocketDelegate {
    public nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.state = .connected
            self.backoffDelay = 0.5
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "no reason"
        Task { @MainActor [weak self] in
            self?.handleDisconnect(reason: "WS closed (\(closeCode.rawValue)): \(reasonStr)")
        }
    }
}
