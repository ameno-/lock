// ACError.swift — structured error types for AgentCockpit
import Foundation

// MARK: - Error Recovery Actions

public enum ACErrorRecoveryAction: String, CaseIterable, Sendable {
    case retry
    case reconnect
    case checkSettings
    case dismiss
}

// MARK: - ACError

public struct ACError: Error, Sendable, Identifiable {
    public let id = UUID()
    public let code: Int
    public let message: String
    public let underlyingError: (any Error)?
    public let isRecoverable: Bool
    public let recoveryActions: [ACErrorRecoveryAction]

    public init(
        code: Int,
        message: String,
        underlyingError: (any Error)? = nil,
        isRecoverable: Bool = false,
        recoveryActions: [ACErrorRecoveryAction] = []
    ) {
        self.code = code
        self.message = message
        self.underlyingError = underlyingError
        self.isRecoverable = isRecoverable
        self.recoveryActions = recoveryActions
    }
}

// MARK: - Error Codes

public extension ACError {
    enum Code: Int {
        case invalidParams = -32602
        case internalError = -32603
        case methodNotFound = -32601
        case authRequired = -32001
        case connectionFailed = -32002
        case timeout = -32003
    }
}

// MARK: - Factory Methods

public extension ACError {
    static func invalidParams(message: String) -> ACError {
        ACError(
            code: Code.invalidParams.rawValue,
            message: message,
            isRecoverable: false,
            recoveryActions: [.dismiss]
        )
    }

    static func internalError(message: String) -> ACError {
        ACError(
            code: Code.internalError.rawValue,
            message: message,
            isRecoverable: false,
            recoveryActions: [.dismiss]
        )
    }

    static func methodNotFound(method: String) -> ACError {
        ACError(
            code: Code.methodNotFound.rawValue,
            message: "Method not found: \(method)",
            isRecoverable: false,
            recoveryActions: [.dismiss]
        )
    }

    static func authRequired(authMethods: [String] = []) -> ACError {
        let methodsText = authMethods.isEmpty ? "" : " Available methods: \(authMethods.joined(separator: ", "))"
        return ACError(
            code: Code.authRequired.rawValue,
            message: "Authentication required.\(methodsText)",
            isRecoverable: true,
            recoveryActions: [.checkSettings, .dismiss]
        )
    }

    static func connectionFailed(reason: String) -> ACError {
        ACError(
            code: Code.connectionFailed.rawValue,
            message: "Connection failed: \(reason)",
            isRecoverable: true,
            recoveryActions: [.reconnect, .checkSettings, .dismiss]
        )
    }

    static func timeout(operation: String) -> ACError {
        ACError(
            code: Code.timeout.rawValue,
            message: "Operation timed out: \(operation)",
            isRecoverable: true,
            recoveryActions: [.retry, .dismiss]
        )
    }
}

// MARK: - User Presentation

public extension ACError {
    var localizedTitle: String {
        switch code {
        case Code.invalidParams.rawValue:
            return "Invalid Parameters"
        case Code.internalError.rawValue:
            return "Internal Error"
        case Code.methodNotFound.rawValue:
            return "Method Not Found"
        case Code.authRequired.rawValue:
            return "Authentication Required"
        case Code.connectionFailed.rawValue:
            return "Connection Failed"
        case Code.timeout.rawValue:
            return "Request Timed Out"
        default:
            return "Error"
        }
    }

    var localizedMessage: String {
        message
    }

    var iconName: String {
        switch code {
        case Code.invalidParams.rawValue:
            return "exclamationmark.triangle"
        case Code.internalError.rawValue:
            return "xmark.octagon"
        case Code.methodNotFound.rawValue:
            return "questionmark.diamond"
        case Code.authRequired.rawValue:
            return "lock.shield"
        case Code.connectionFailed.rawValue:
            return "wifi.exclamationmark"
        case Code.timeout.rawValue:
            return "clock.arrow.circlepath"
        default:
            return "exclamationmark.circle"
        }
    }
}

// MARK: - CustomStringConvertible

extension ACError: CustomStringConvertible {
    public var description: String {
        var components: [String] = [
            "ACError(code: \(code)",
            "message: \"\(message)\""
        ]
        if let underlying = underlyingError {
            components.append("underlying: \(underlying)")
        }
        components.append("recoverable: \(isRecoverable))")
        return components.joined(separator: ", ")
    }
}
