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

    // MARK: - Internal
    private var wsTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var reconnectTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?

    private let settings: ACSettingsStore
    private var onMessage: ((ACServerMessage) -> Void)?

    // Exponential backoff state
    private var backoffDelay: Double = 0.5
    private let backoffBase: Double = 1.7
    private let backoffMax: Double = 8.0

    public init(settings: ACSettingsStore) {
        self.settings = settings
        super.init()
    }

    // MARK: - Public API

    public func connect(onMessage: @escaping (ACServerMessage) -> Void) {
        self.onMessage = onMessage
        startConnect()
    }

    public func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        wsTask?.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
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
                    guard let task = await self?.wsTask else { break }
                    let message = try await task.receive()
                    await self?.handleReceived(message)
                } catch {
                    await self?.handleDisconnect(reason: error.localizedDescription)
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
        case .authErr(let msg):
            state = .failed("Auth failed: \(msg)")
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
        wsTask = nil
        state = .disconnected
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        let delay = backoffDelay
        backoffDelay = min(backoffDelay * backoffBase, backoffMax)
        print("[connection] Reconnecting in \(String(format: "%.1f", delay))s...")
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.startConnect()
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
