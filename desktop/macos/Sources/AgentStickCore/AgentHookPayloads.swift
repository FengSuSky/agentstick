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
        var toolName: String?
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
            case toolName = "tool_name"
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
        let surface: AgentSurface
        switch normalizedSource {
        case "claude":
            agent = .claudeCode
            surface = .cli
        case "codex":
            agent = .codexCLI
            surface = .cli
        case "workbuddy":
            agent = .workBuddy
            surface = .desktop
        case "codebuddy":
            agent = .codeBuddy
            surface = .cli
        case "gemini":
            agent = .geminiCLI
            surface = .cli
        case "qwen":
            agent = .qwenCode
            surface = .cli
        case "qoder":
            agent = .qoder
            surface = .cli
        case "factory":
            agent = .factoryCLI
            surface = .cli
        case "cursor":
            agent = .cursorCLI
            surface = .desktop
        default:
            throw AgentHookPayloadError.unsupportedSource(source)
        }

        return AgentTaskEvent(
            kind: kind(for: payload.hookEventName),
            agent: agent,
            surface: surface,
            sessionID: sessionID,
            taskID: payload.turnID,
            cwd: payload.cwd,
            title: payload.title ?? payload.prompt ?? payload.toolName,
            summary: payload.lastAssistantMessage ?? payload.message ?? payload.error,
            occurredAt: occurredAt
        )
    }

    private static func kind(for hookEventName: String) -> AgentTaskEventKind {
        // Cursor names its events in lower case ("stop", "beforeSubmitPrompt").
        switch hookEventName.lowercased() {
        case "sessionstart":
            return .sessionStarted
        case "userpromptsubmit", "beforesubmitprompt":
            return .promptSubmitted
        case "permissionrequest", "pretooluse":
            return .waitingForApproval
        case "notification":
            return .needsInput
        case "stop":
            return .completed
        case "stopfailure", "posttoolusefailure":
            return .failed
        case "sessionend":
            // A closed session means the turn is over; reporting "running"
            // here would leave the device stuck on the working animation.
            return .completed
        default:
            return .turnStarted
        }
    }
}
