import Foundation

public enum AgentTaskState: String, Codable, Sendable, Equatable {
    case idle
    case running
    case waitingForApproval = "waiting_for_approval"
    case needsInput = "needs_input"
    case completed
    case failed

    /// Background `.running` occupies the stick only in Agent Run, so Text Paste
    /// can still start a recording while a task continues on the Mac.
    public func shouldDriveDeviceUI(outputTargetRawValue: String) -> Bool {
        switch self {
        case .idle:
            return false
        case .running:
            return outputTargetRawValue == "agent_cli"
        case .waitingForApproval, .needsInput, .completed, .failed:
            return true
        }
    }
}

public struct AgentTaskSnapshot: Codable, Sendable, Equatable {
    public var sessionID: String
    public var taskID: String?
    public var agent: AgentKind
    public var surface: AgentSurface
    public var state: AgentTaskState
    public var cwd: String?
    public var title: String?
    public var summary: String?
    public var jumpTarget: String?
    public var updatedAt: Date
}

public struct AgentTaskMonitor {
    private var snapshots: [String: AgentTaskSnapshot] = [:]

    public init() {}

    @discardableResult
    public mutating func apply(_ event: AgentTaskEvent) -> AgentTaskSnapshot {
        var snapshot = snapshots[event.sessionID] ?? AgentTaskSnapshot(
            sessionID: event.sessionID,
            taskID: event.taskID,
            agent: event.agent,
            surface: event.surface,
            state: .idle,
            cwd: event.cwd,
            title: event.title,
            summary: event.summary,
            jumpTarget: event.jumpTarget,
            updatedAt: event.occurredAt
        )

        snapshot.taskID = event.taskID ?? snapshot.taskID
        snapshot.cwd = event.cwd ?? snapshot.cwd
        snapshot.title = event.title ?? snapshot.title
        snapshot.summary = event.summary ?? snapshot.summary
        snapshot.jumpTarget = event.jumpTarget ?? snapshot.jumpTarget
        snapshot.updatedAt = event.occurredAt

        switch event.kind {
        case .sessionStarted:
            snapshot.state = .idle
        case .promptSubmitted, .turnStarted:
            snapshot.state = .running
        case .waitingForApproval:
            snapshot.state = .waitingForApproval
        case .needsInput:
            // Claude-style agents emit Notification hooks both for real
            // mid-turn questions and for session-start toasts / idle reminders
            // fired ~60s after Stop. Only a notification during an active turn
            // means the agent is blocked on the user; otherwise keep the
            // current state so "Done" is not overwritten with "Needs You".
            if snapshot.state == .running || snapshot.state == .waitingForApproval {
                snapshot.state = .needsInput
            }
        case .completed:
            snapshot.state = .completed
        case .failed:
            snapshot.state = .failed
        }

        snapshots[event.sessionID] = snapshot
        return snapshot
    }

    public func snapshot(sessionID: String) -> AgentTaskSnapshot? {
        snapshots[sessionID]
    }

    public var allSnapshots: [AgentTaskSnapshot] {
        snapshots.values.sorted { $0.updatedAt > $1.updatedAt }
    }
}
