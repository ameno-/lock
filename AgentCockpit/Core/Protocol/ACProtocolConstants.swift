// ACProtocolConstants.swift — Protocol method names and error codes for ACP and Codex protocols

import Foundation

// MARK: - ACP Protocol Methods

/// JSON-RPC method names for the Agent Cockpit Protocol (ACP)
public enum ACPMethod: String, Sendable {
    /// Initialize the protocol connection
    case initialize

    /// Protocol initialization completed successfully
    case initialized

    /// Shutdown the protocol connection
    case shutdown

    /// Create a new session
    case sessionNew = "session/new"

    /// Load an existing session
    case sessionLoad = "session/load"

    /// Resume a suspended session
    case sessionResume = "session/resume"

    /// List all available sessions
    case sessionList = "session/list"

    /// Cancel an ongoing session operation
    case sessionCancel = "session/cancel"

    /// Send a prompt to a session
    case sessionPrompt = "session/prompt"

    /// Request approval for tool execution
    case toolApprovalRequest = "tool/approvalRequest"

    /// Request user input during tool execution
    case toolUserInputRequest = "tool/userInputRequest"

    /// GenUI action notification
    case genuiAction = "genui/action"
}

// MARK: - Codex Protocol Methods

/// JSON-RPC method names for the Codex App Server Protocol
public enum CodexMethod: String, Sendable {
    /// List all available threads
    case threadList = "thread/list"

    /// Start a new thread
    case threadStart = "thread/start"

    /// Resume an existing thread
    case threadResume = "thread/resume"

    /// Read thread contents
    case threadRead = "thread/read"

    /// Start a new turn in a thread
    case turnStart = "turn/start"

    /// Interrupt an ongoing turn
    case turnInterrupt = "turn/interrupt"

    /// Mark a turn as completed
    case turnComplete = "turn/complete"
}

// MARK: - JSON-RPC Error Codes

/// Standard JSON-RPC 2.0 error codes used across ACP and Codex protocols
public enum ACPErrorCode: Int, Sendable {
    /// Parse error (-32700): Invalid JSON was received by the server
    case parseError = -32700

    /// Invalid Request (-32600): The JSON sent is not a valid Request object
    case invalidRequest = -32600

    /// Method not found (-32601): The method does not exist / is not available
    case methodNotFound = -32601

    /// Invalid params (-32602): Invalid method parameter(s)
    case invalidParams = -32602

    /// Internal error (-32603): Internal JSON-RPC error
    case internalError = -32603

    /// Server error (-32000 to -32099): Reserved for implementation-defined server-errors
    case serverError = -32000

    /// Application error (-32001): Application-specific error
    case applicationError = -32001

    /// Session not found (-32002): The requested session does not exist
    case sessionNotFound = -32002

    /// Session already exists (-32003): Attempted to create a session that already exists
    case sessionAlreadyExists = -32003

    /// Tool execution failed (-32004): Tool execution encountered an error
    case toolExecutionFailed = -32004

    /// Unauthorized (-32005): The request is not authorized
    case unauthorized = -32005

    /// Rate limited (-32006): Too many requests
    case rateLimited = -32006

    /// Timeout (-32007): The operation timed out
    case timeout = -32007

    /// Cancelled (-32008): The operation was cancelled by the user
    case cancelled = -32008

    /// GenUI error (-32009): GenUI-specific error
    case genuiError = -32009

    /// Protocol version mismatch (-32010): Incompatible protocol versions
    case protocolVersionMismatch = -32010
}
