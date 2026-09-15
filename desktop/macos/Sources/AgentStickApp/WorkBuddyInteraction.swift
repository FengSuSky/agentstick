import AppKit
import Foundation

/// A tool approval or question WorkBuddy sent down while a task was running.
///
/// Downlink permission requests are not described structurally in the open platform
/// documentation, so the parser is deliberately defensive: it scans `metadata`, then any
/// JSON object embedded in `content`, looking for known key spellings. Anything it cannot
/// resolve is surfaced as free-text input rather than dropped, so the user can always answer
/// in AgentStick instead of having to switch to the WorkBuddy window.
struct WorkBuddyInteraction {
    enum Kind {
        case question
        case toolApproval
    }

    var requestId: String
    var kind: Kind
    var toolName: String?
    var toolInput: String?
    var summary: String
    var questions: [AgentInputQuestion]

    var isQuestion: Bool { kind == .question }
}

enum WorkBuddyInteractionParser {
    /// Keys searched in order. `id` is a last resort and only accepted together with other evidence.
    private static let requestIdKeys = ["requestId", "request_id", "requestID", "permissionId", "permission_id", "id"]
    private static let questionArrayKeys = ["questions", "question_list", "items"]
    private static let questionTextKeys = ["question", "text", "label", "header", "prompt", "title"]
    private static let optionKeys = ["options", "choices", "values"]
    private static let multiSelectKeys = ["multiSelect", "multi_select", "multiselect", "multiple"]
    private static let toolNameKeys = ["toolName", "tool_name", "tool", "name"]
    private static let descriptionKeys = ["description", "desc", "detail", "details", "message", "reason"]
    private static let previewKeys = ["inputPreview", "input_preview", "input", "params", "arguments"]

    static func parse(_ message: AssistantMessage) -> WorkBuddyInteraction? {
        let objects = jsonObjectCandidates(message)
        let requestId = requestId(in: message.metadata)
            ?? objects.lazy.compactMap { requestId(in: $0) }.first
        guard let requestId, !requestId.isEmpty else { return nil }

        let questions = questions(from: message.metadata) ?? objects.lazy.compactMap { questions(from: $0) }.first ?? []
        let toolName = stringValue(message.metadata, toolNameKeys)
            ?? objects.lazy.compactMap { stringValue($0, toolNameKeys) }.first
        let inputPreview = stringValue(message.metadata, previewKeys)
            ?? objects.lazy.compactMap { stringValue($0, previewKeys) }.first
        let description = stringValue(message.metadata, descriptionKeys)
            ?? objects.lazy.compactMap { stringValue($0, descriptionKeys) }.first

        let looksLikeRequest = message.type.localizedCaseInsensitiveContains("permission")
            || message.type.localizedCaseInsensitiveContains("question")
            || !questions.isEmpty
            || toolName != nil
        guard looksLikeRequest else { return nil }

        let summary = Self.summary(
            description: description,
            toolName: toolName,
            questions: questions,
            fallbackText: WorkBuddyLocalAssistantRunner.replyText(message)
        )

        return WorkBuddyInteraction(
            requestId: requestId,
            kind: questions.isEmpty ? .toolApproval : .question,
            toolName: toolName,
            toolInput: inputPreview,
            summary: summary,
            questions: questions
        )
    }

    // MARK: - Request id

    private static func requestId(in dictionary: [String: Any]) -> String? {
        for key in requestIdKeys {
            if let value = dictionary[key] as? String, !value.isEmpty {
                // `id` alone is too generic to trust on its own.
                if key == "id" { continue }
                return value
            }
        }
        return nil
    }

    // MARK: - Questions

    private static func questions(from dictionary: [String: Any]) -> [AgentInputQuestion]? {
        for key in questionArrayKeys {
            guard let raw = dictionary[key] as? [[String: Any]], !raw.isEmpty else { continue }
            let questions = raw.enumerated().compactMap { index, item -> AgentInputQuestion? in
                guard let text = stringValue(item, questionTextKeys), !text.isEmpty else { return nil }
                return AgentInputQuestion(
                    id: "q_\(index)",
                    header: header(for: text, item: item),
                    question: text,
                    options: options(in: item),
                    allowsFreeText: true,
                    isSecret: false
                )
            }
            if !questions.isEmpty { return questions }
        }
        return nil
    }

    private static func options(in item: [String: Any]) -> [String] {
        for key in optionKeys {
            guard let raw = item[key] as? [Any], !raw.isEmpty else { continue }
            let labels = raw.compactMap { element -> String? in
                switch element {
                case let string as String:
                    return string
                case let dictionary as [String: Any]:
                    return (dictionary["label"] ?? dictionary["text"] ?? dictionary["value"]) as? String
                default:
                    return nil
                }
            }
            if !labels.isEmpty { return labels }
        }
        return []
    }

    private static func header(for text: String, item: [String: Any]) -> String {
        if let header = item["header"] as? String, !header.isEmpty { return header }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 24 ? String(trimmed.prefix(24)) + "…" : trimmed
    }

    // MARK: - Details

    private static func summary(
        description: String?,
        toolName: String?,
        questions: [AgentInputQuestion],
        fallbackText: String?
    ) -> String {
        var parts: [String] = []
        if let toolName, !toolName.isEmpty {
            parts.append(currentLanguage == .chinese ? "工具：\(toolName)" : "Tool: \(toolName)")
        }
        if let description, !description.isEmpty {
            parts.append(description)
        }
        if parts.isEmpty, let first = questions.first {
            parts.append(first.question)
        }
        if parts.isEmpty, let fallbackText, !fallbackText.isEmpty {
            parts.append(fallbackText)
        }
        if parts.isEmpty {
            parts.append(currentLanguage == .chinese ? "WorkBuddy 请求确认" : "WorkBuddy requests confirmation")
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Traversal

    /// Every JSON object reachable from `metadata` values or from JSON embedded in `content`.
    private static func jsonObjectCandidates(_ message: AssistantMessage) -> [[String: Any]] {
        var objects: [[String: Any]] = []
        for element in message.content {
            if let string = element as? String, let object = Self.jsonObject(from: string) {
                objects.append(object)
            } else if let dictionary = element as? [String: Any] {
                objects.append(dictionary)
            }
        }
        for value in message.metadata.values {
            if let dictionary = value as? [String: Any] {
                objects.append(dictionary)
            } else if let string = value as? String, let object = Self.jsonObject(from: string) {
                objects.append(object)
            }
        }
        return objects
    }

    private static func jsonObject(from string: String) -> [String: Any]? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func stringValue(_ dictionary: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }
}

/// Builds the `content` string for a `permission_response` message.
///
/// The platform expects `content` to be a *serialized JSON string*, not a JSON object:
/// `{"outcome":"selected","requestId":"...","answers":{"q_0":"..."}}`.
enum WorkBuddyInteractionPayload {
    /// Outcome for answering a questionnaire. This is the only value the platform documents.
    static let selectedOutcome = "selected"
    /// Outcomes used for tool approvals. The documentation does not enumerate these; they follow
    /// the same allow/deny wording the CLI uses for permission responses. Override them from
    /// `[agents.workbuddy]` if the platform publishes different names.
    static let allowOutcome = "allow"
    static let denyOutcome = "deny"

    static func permissionResponse(requestId: String, outcome: String, answers: [String: [String]]) -> String? {
        var encoded: [String: Any] = [:]
        for (key, values) in answers.sorted(by: { $0.key < $1.key }) {
            encoded[key] = values.count == 1 ? values[0] : values
        }
        let payload: [String: Any] = [
            "outcome": outcome,
            "requestId": requestId,
            "answers": encoded
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
