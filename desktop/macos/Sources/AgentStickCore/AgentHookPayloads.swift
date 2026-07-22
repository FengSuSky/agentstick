import Foundation

public enum AgentHookPayloadError: Error, Equatable {
    case unsupportedSource(String)
    case missingSessionID
}

public struct AgentHookPayloadMapper {
    private struct GenericHookPayload: Decodable {
        var hookEventName: String
        var sessionID: String?
        var cwd: String?
        var turnID: String?
        var prompt: String?
        var message: String?
        var title: String?
        var lastAssistantMessage: String?
        var error: String?

        private enum CodingKeys: String, CodingKey {
            case hookEventName = "hook_event_name"
            case sessionID = "session_id"
            case cwd
            case turnID = "turn_id"
            case prompt
            case message
            case title
            case lastAssistantMessage = "last_assistant_message"
            case error
        }
    }

    public static func event(from data: Data, source: String, occurredAt: Date = Date()) throws -> AgentTaskEvent {
        let payload = try JSONDecoder().decode(GenericHookPayload.self, from: data)
        guard let sessionID = payload.sessionID, !sessionID.isEmpty else {
            throw AgentHookPayloadError.missingSessionID
        }

        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let agent: AgentKind
        switch normalizedSource {
        case "claude":
            agent = .claudeCode
        case "codex":
            agent = .codexCLI
        default:
            throw AgentHookPayloadError.unsupportedSource(source)
        }

        return AgentTaskEvent(
            kind: kind(for: payload.hookEventName),
            agent: agent,
            surface: .cli,
            sessionID: sessionID,
            taskID: payload.turnID,
            cwd: payload.cwd,
            title: payload.title ?? payload.prompt,
            summary: payload.lastAssistantMessage ?? payload.message ?? payload.error,
            occurredAt: occurredAt
        )
    }

    private static func kind(for hookEventName: String) -> AgentTaskEventKind {
        switch hookEventName {
        case "SessionStart":
            return .sessionStarted
        case "UserPromptSubmit":
            return .promptSubmitted
        case "PermissionRequest", "PreToolUse":
            return .waitingForApproval
        case "Notification":
            return .needsInput
        case "Stop":
            return .completed
        case "StopFailure", "PostToolUseFailure":
            return .failed
        default:
            return .turnStarted
        }
    }
}
