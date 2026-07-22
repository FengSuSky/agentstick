import Foundation

public enum AgentKind: String, Codable, Sendable, Equatable {
    case claudeCode = "claude_code"
    case codexCLI = "codex_cli"
    case codexDesktop = "codex_desktop"
    case unknown
}

public enum AgentSurface: String, Codable, Sendable, Equatable {
    case cli
    case desktop
}

public enum AgentTaskEventKind: String, Codable, Sendable, Equatable {
    case sessionStarted = "session_started"
    case promptSubmitted = "prompt_submitted"
    case turnStarted = "turn_started"
    case waitingForApproval = "waiting_for_approval"
    case needsInput = "needs_input"
    case completed
    case failed
}

public struct AgentTaskEvent: Codable, Sendable, Equatable {
    public var kind: AgentTaskEventKind
    public var agent: AgentKind
    public var surface: AgentSurface
    public var sessionID: String
    public var taskID: String?
    public var cwd: String?
    public var title: String?
    public var summary: String?
    public var jumpTarget: String?
    public var occurredAt: Date

    public init(
        kind: AgentTaskEventKind,
        agent: AgentKind,
        surface: AgentSurface,
        sessionID: String,
        taskID: String? = nil,
        cwd: String? = nil,
        title: String? = nil,
        summary: String? = nil,
        jumpTarget: String? = nil,
        occurredAt: Date = Date()
    ) {
        self.kind = kind
        self.agent = agent
        self.surface = surface
        self.sessionID = sessionID
        self.taskID = taskID
        self.cwd = cwd
        self.title = title
        self.summary = summary
        self.jumpTarget = jumpTarget
        self.occurredAt = occurredAt
    }
}
