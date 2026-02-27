// CanvasEvent.swift — All renderable event types for the Work canvas
import Foundation

public enum CanvasEvent: Identifiable, Sendable {
    case toolUse(ToolUseEvent)
    case reasoning(ReasoningEvent)
    case gitDiff(GitDiffEvent)
    case subAgent(SubAgentEvent)
    case skillRun(SkillRunEvent)
    case fileEdit(FileEditEvent)
    case genUI(GenUIEvent)
    case rawOutput(RawOutputEvent)

    public var id: String {
        switch self {
        case .toolUse(let e): return e.id
        case .reasoning(let e): return e.id
        case .gitDiff(let e): return e.id
        case .subAgent(let e): return e.id
        case .skillRun(let e): return e.id
        case .fileEdit(let e): return e.id
        case .genUI(let e): return e.id
        case .rawOutput(let e): return e.id
        }
    }

    public var timestamp: Date {
        switch self {
        case .toolUse(let e): return e.timestamp
        case .reasoning(let e): return e.timestamp
        case .gitDiff(let e): return e.timestamp
        case .subAgent(let e): return e.timestamp
        case .skillRun(let e): return e.timestamp
        case .fileEdit(let e): return e.timestamp
        case .genUI(let e): return e.timestamp
        case .rawOutput(let e): return e.timestamp
        }
    }
}

// MARK: - Tool Use

public struct ToolUseEvent: Sendable {
    public let id: String
    public let toolName: String
    public let phase: ToolPhase
    public let input: String
    public let result: String?
    public let status: ToolStatus
    public let timestamp: Date

    public init(
        id: String = UUID().uuidString,
        toolName: String,
        phase: ToolPhase,
        input: String,
        result: String? = nil,
        status: ToolStatus,
        timestamp: Date = .now
    ) {
        self.id = id
        self.toolName = toolName
        self.phase = phase
        self.input = input
        self.result = result
        self.status = status
        self.timestamp = timestamp
    }
}

public enum ToolPhase: Sendable {
    case start
    case result
}

public enum ToolStatus: Sendable {
    case running
    case done
    case error
}

// MARK: - Reasoning / Assistant Text

public struct ReasoningEvent: Sendable {
    public let id: String
    public let text: String
    public let isThinking: Bool
    public let timestamp: Date

    public init(
        id: String = UUID().uuidString,
        text: String,
        isThinking: Bool,
        timestamp: Date = .now
    ) {
        self.id = id
        self.text = text
        self.isThinking = isThinking
        self.timestamp = timestamp
    }
}

// MARK: - Git Diff

public struct GitDiffEvent: Sendable {
    public let id: String
    public let rawDiff: String
    public let filePath: String?
    public let additions: Int
    public let deletions: Int
    public let timestamp: Date

    public init(
        id: String = UUID().uuidString,
        rawDiff: String,
        filePath: String? = nil,
        additions: Int = 0,
        deletions: Int = 0,
        timestamp: Date = .now
    ) {
        self.id = id
        self.rawDiff = rawDiff
        self.filePath = filePath
        self.additions = additions
        self.deletions = deletions
        self.timestamp = timestamp
    }
}

// MARK: - Sub-Agent

public struct SubAgentEvent: Sendable {
    public let id: String
    public let subSessionKey: String
    public let modelName: String?
    public let phase: SubAgentPhase
    public let startedAt: Date
    public let timestamp: Date

    public init(
        id: String = UUID().uuidString,
        subSessionKey: String,
        modelName: String? = nil,
        phase: SubAgentPhase,
        startedAt: Date = .now,
        timestamp: Date = .now
    ) {
        self.id = id
        self.subSessionKey = subSessionKey
        self.modelName = modelName
        self.phase = phase
        self.startedAt = startedAt
        self.timestamp = timestamp
    }
}

public enum SubAgentPhase: Sendable {
    case spawned
    case running
    case done
    case failed
}

// MARK: - Skill Run

public struct SkillRunEvent: Sendable {
    public let id: String
    public let skillName: String
    public let status: SkillStatus
    public let durationMs: Int?
    public let timestamp: Date

    public init(
        id: String = UUID().uuidString,
        skillName: String,
        status: SkillStatus,
        durationMs: Int? = nil,
        timestamp: Date = .now
    ) {
        self.id = id
        self.skillName = skillName
        self.status = status
        self.durationMs = durationMs
        self.timestamp = timestamp
    }
}

public enum SkillStatus: Sendable {
    case running
    case done
    case failed
}

// MARK: - File Edit

public struct FileEditEvent: Sendable {
    public let id: String
    public let filePath: String
    public let operation: FileOperation
    public let timestamp: Date

    public init(
        id: String = UUID().uuidString,
        filePath: String,
        operation: FileOperation,
        timestamp: Date = .now
    ) {
        self.id = id
        self.filePath = filePath
        self.operation = operation
        self.timestamp = timestamp
    }
}

public enum FileOperation: Sendable {
    case read
    case write
    case edit
    case delete
}

// MARK: - GenUI

public struct GenUIEvent: Sendable {
    public enum UpdateMode: Sendable {
        case snapshot
        case patch
    }

    public let id: String
    public let schemaVersion: String
    public let mode: UpdateMode
    public let title: String
    public let body: String
    public let actionLabel: String?
    public let actionPayload: [String: AnyCodable]
    public let timestamp: Date

    public init(
        id: String = UUID().uuidString,
        schemaVersion: String = "v0",
        mode: UpdateMode = .snapshot,
        title: String,
        body: String,
        actionLabel: String? = nil,
        actionPayload: [String: AnyCodable] = [:],
        timestamp: Date = .now
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.mode = mode
        self.title = title
        self.body = body
        self.actionLabel = actionLabel
        self.actionPayload = actionPayload
        self.timestamp = timestamp
    }
}

// MARK: - Raw Output (fallback)

public struct RawOutputEvent: Sendable {
    public let id: String
    public let text: String
    public let hookEvent: String
    public let timestamp: Date

    public init(
        id: String = UUID().uuidString,
        text: String,
        hookEvent: String = "",
        timestamp: Date = .now
    ) {
        self.id = id
        self.text = text
        self.hookEvent = hookEvent
        self.timestamp = timestamp
    }
}
