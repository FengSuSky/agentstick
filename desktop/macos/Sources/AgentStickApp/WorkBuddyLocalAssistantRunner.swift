import AppKit
import Foundation

/// Sends a spoken task to the WorkBuddy local assistant on this Mac and waits for the result.
///
/// The local assistant is the WorkBuddy client the user is already signed in to, so the
/// task runs on this machine with the user's own workspace and permissions. Delivery goes
/// through `POST /localassistant/message`; replies are read back by incrementally polling
/// `GET /localassistant/message?message_id=...`.
///
/// While polling, any downlink permission request (tool approval or AskQuestion) is routed to
/// the existing AgentStick approval UI. Whatever the user answers is sent back as a
/// `permission_response` message so the task continues without leaving the app.
final class WorkBuddyLocalAssistantRunner {
    static let defaultSettleSeconds = 15
    private static let pollIntervalSeconds: TimeInterval = 2
    /// Upper bound on how long we wait for the user to answer a single request.
    private static let maxInteractionWaitSeconds: TimeInterval = 900
    /// Exit code used when the task produced output but at least one approval or
    /// question went unanswered. The text is preserved so the caller can display
    /// it, but `succeeded` returns false so the UI does not play a success sound.
    static let exitCodePendingApproval: Int32 = 2

    private let baseURL = URL(string: "https://www.workbuddy.cn/openapi/v2")!
    private let auth = WorkBuddyAuthController()

    func run(
        task: AgentCLITask,
        clientID: String,
        timeoutSeconds: Int,
        settleSeconds: Int = defaultSettleSeconds,
        approvalHandler: CodexInteractiveRunner.ApprovalHandler? = nil,
        inputHandler: CodexInteractiveRunner.InputHandler? = nil
    ) -> Result<AgentCLIResult, Error> {
        do {
            guard let clientSecret = WorkBuddyAuthStore.shared.clientSecret(clientID: clientID), !clientSecret.isEmpty else {
                throw WorkBuddyAuthError.missingClientSecret
            }
            let token = try auth.validToken(clientID: clientID, clientSecret: clientSecret)

            guard try isOnline(token: token.accessToken) else {
                throw WorkBuddyLocalAssistantError.assistantOffline
            }

            let sentMessageID = try send(text: task.prompt, token: token.accessToken)

            var deadline = Date().addingTimeInterval(TimeInterval(max(30, timeoutSeconds)))
            let settle = TimeInterval(max(0, settleSeconds))
            var cursor = sentMessageID
            var latestReply: String?
            var unansweredRequest = false
            var lastActivity = Date()
            var handledRequestIDs: Set<String> = []

            while Date() < deadline {
                // The access token is kept fresh so a long-running task does not
                // get rejected by an expired grant mid-poll.
                let currentToken = try auth.validToken(clientID: clientID, clientSecret: clientSecret)
                let messages = try messages(after: cursor, token: currentToken.accessToken)
                if let newestID = messages.last?.id, !newestID.isEmpty {
                    cursor = newestID
                }

                for message in messages where message.role == "assistant" {
                    if let interaction = WorkBuddyInteractionParser.parse(message),
                       !handledRequestIDs.contains(interaction.requestId) {
                        handledRequestIDs.insert(interaction.requestId)
                        let waitStart = Date()
                        let answered = handle(
                            interaction,
                            task: task,
                            deadline: deadline,
                            clientID: clientID,
                            clientSecret: clientSecret,
                            approvalHandler: approvalHandler,
                            inputHandler: inputHandler
                        )
                        lastActivity = Date()
                        // Time spent waiting for the user should not eat the task budget.
                        if answered { deadline = deadline.addingTimeInterval(Date().timeIntervalSince(waitStart)) }
                        if !answered {
                            unansweredRequest = true
                        }
                        continue
                    }
                    // Downlink protocol traffic we could not parse. Never surface it as the
                    // answer, but record it so the result tells the user to check WorkBuddy.
                    if Self.looksLikeRequest(message) {
                        NSLog("WorkBuddy: unparsed request message type=\(message.type) id=\(message.id)")
                        unansweredRequest = true
                        continue
                    }
                    if let text = Self.replyText(message), !text.isEmpty {
                        latestReply = text
                        lastActivity = Date()
                    }
                }

                if let latestReply, Date().timeIntervalSince(lastActivity) >= settle {
                    return .success(makeResult(task: task, output: latestReply, permissionPending: unansweredRequest))
                }
                Thread.sleep(forTimeInterval: Self.pollIntervalSeconds)
            }

            if let latestReply {
                return .success(makeResult(task: task, output: latestReply, permissionPending: unansweredRequest))
            }
            if unansweredRequest {
                throw WorkBuddyLocalAssistantError.waitingForApproval
            }
            throw WorkBuddyLocalAssistantError.timedOut
        } catch {
            return .failure(error)
        }
    }

    /// Routes one downlink request to the AgentStick approval UI and posts the answer back.
    /// Returns false when the user could not answer, so the request stays pending in WorkBuddy.
    private func handle(
        _ interaction: WorkBuddyInteraction,
        task: AgentCLITask,
        deadline: Date,
        clientID: String,
        clientSecret: String,
        approvalHandler: CodexInteractiveRunner.ApprovalHandler?,
        inputHandler: CodexInteractiveRunner.InputHandler?
    ) -> Bool {
        let remaining = max(deadline.timeIntervalSinceNow, 0)
        let wait = min(max(remaining, 30), Self.maxInteractionWaitSeconds)
        let details = Self.details(for: interaction)

        if interaction.isQuestion {
            guard let inputHandler else { logUnhandled(interaction); return false }
            guard let answers = waitForInput(
                interaction,
                agent: task.agentName,
                details: details,
                wait: wait,
                handler: inputHandler
            ) else {
                NSLog("WorkBuddy: question \(interaction.requestId) went unanswered")
                return false
            }
            // Refresh the token: the user may have taken minutes to answer.
            guard let freshToken = try? auth.validToken(clientID: clientID, clientSecret: clientSecret) else {
                NSLog("WorkBuddy: token refresh failed before posting question response \(interaction.requestId)")
                return false
            }
            return postResponse(requestId: interaction.requestId, outcome: WorkBuddyInteractionPayload.selectedOutcome, answers: answers, token: freshToken.accessToken)
        }

        guard let approvalHandler else { logUnhandled(interaction); return false }
        guard let allowed = waitForApproval(
            interaction,
            agent: task.agentName,
            details: details,
            wait: wait,
            handler: approvalHandler
        ) else {
            NSLog("WorkBuddy: approval \(interaction.requestId) went unanswered")
            return false
        }
        // Refresh the token: the user may have taken minutes to approve.
        guard let freshToken = try? auth.validToken(clientID: clientID, clientSecret: clientSecret) else {
            NSLog("WorkBuddy: token refresh failed before posting approval response \(interaction.requestId)")
            return false
        }
        let outcome = allowed ? WorkBuddyInteractionPayload.allowOutcome : WorkBuddyInteractionPayload.denyOutcome
        return postResponse(requestId: interaction.requestId, outcome: outcome, answers: [:], token: freshToken.accessToken)
    }

    private func waitForApproval(
        _ interaction: WorkBuddyInteraction,
        agent: String,
        details: String,
        wait: TimeInterval,
        handler: @escaping CodexInteractiveRunner.ApprovalHandler
    ) -> Bool? {
        var allowed: Bool?
        let semaphore = DispatchSemaphore(value: 0)
        handler(agent, Self.approvalKind, interaction.summary, details) { value in
            allowed = value
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + wait) == .timedOut { return nil }
        return allowed
    }

    private func waitForInput(
        _ interaction: WorkBuddyInteraction,
        agent: String,
        details: String,
        wait: TimeInterval,
        handler: @escaping CodexInteractiveRunner.InputHandler
    ) -> [String: [String]]? {
        var result: [String: [String]]?
        var replied = false
        let semaphore = DispatchSemaphore(value: 0)
        handler(agent, interaction.summary, details, interaction.questions) { answers in
            result = answers
            replied = true
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + wait) == .timedOut { return nil }
        guard replied else { return nil }
        return result
    }

    private func postResponse(requestId: String, outcome: String, answers: [String: [String]], token: String) -> Bool {
        guard let content = WorkBuddyInteractionPayload.permissionResponse(
            requestId: requestId,
            outcome: outcome,
            answers: answers
        ) else {
            NSLog("WorkBuddy: failed to encode permission_response for \(requestId)")
            return false
        }
        do {
            _ = try post("localassistant/message", body: ["content": content, "msg_type": "permission_response"], token: token)
            return true
        } catch {
            NSLog("WorkBuddy: permission_response failed for \(requestId): \(error.localizedDescription)")
            return false
        }
    }

    /// True for downlink traffic that carries a permission request rather than an answer.
    private static func looksLikeRequest(_ message: AssistantMessage) -> Bool {
        let type = message.type.lowercased()
        return type.localizedCaseInsensitiveContains("permission")
            || type.localizedCaseInsensitiveContains("question")
            || type.localizedCaseInsensitiveContains("approval")
            || type.localizedCaseInsensitiveContains("request")
    }

    private func logUnhandled(_ interaction: WorkBuddyInteraction) {
        NSLog("WorkBuddy: no UI handler for \(interaction.isQuestion ? "question" : "approval") \(interaction.requestId)")
    }

    private static var approvalKind: String {
        currentLanguage == .chinese ? "WorkBuddy 授权" : "WorkBuddy approval"
    }

    private static func details(for interaction: WorkBuddyInteraction) -> String {
        var blocks: [String] = []
        if !interaction.summary.isEmpty { blocks.append(interaction.summary) }
        if let toolName = interaction.toolName, !toolName.isEmpty {
            blocks.append("**Tool**\n\n\(toolName)")
        }
        if let toolInput = interaction.toolInput, !toolInput.isEmpty {
            blocks.append("**Input**\n\n```json\n\(toolInput)\n```")
        }
        if blocks.isEmpty {
            blocks.append(currentLanguage == .chinese
                ? "WorkBuddy 正在等待确认。"
                : "WorkBuddy is waiting for confirmation.")
        }
        return blocks.joined(separator: "\n\n")
    }

    private func makeResult(task: AgentCLITask, output: String, permissionPending: Bool) -> AgentCLIResult {
        let text = permissionPending ? output + Self.permissionNotice : output
        let code = permissionPending ? Self.exitCodePendingApproval : 0
        let resultURL = (try? AgentCLIRunner.writeResultFile(
            task: task,
            exitCode: code,
            stdout: text,
            stderr: ""
        )) ?? AppConfig.configDirectory
        return AgentCLIResult(
            task: task,
            exitCode: code,
            stdout: text,
            stderr: "",
            resultURL: resultURL
        )
    }

    private static var permissionNotice: String {
        currentLanguage == .chinese
            ? "\n\n（WorkBuddy 曾请求授权或提问，但未能在本机应答，请在 WorkBuddy 窗口中确认。）"
            : "\n\n(WorkBuddy asked for approval or input that AgentStick could not answer. Confirm it in the WorkBuddy window.)"
    }

    /// `content` is an array in responses; entries may be plain strings or nested objects.
    static func replyText(_ message: AssistantMessage) -> String? {
        let parts = message.content.compactMap { element -> String? in
            switch element {
            case let string as String:
                return string
            case let dictionary as [String: Any]:
                return dictionary["text"] as? String
            default:
                return nil
            }
        }
        let text = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: - Open API

    private func isOnline(token: String) throws -> Bool {
        let payload = try get("localassistant", query: nil, token: token)
        return (payload["online"] as? NSNumber)?.boolValue ?? (payload["online"] as? Bool) ?? false
    }

    private func send(text: String, token: String) throws -> String {
        let body = ["content": text, "msg_type": "text"]
        let payload = try post("localassistant/message", body: body, token: token)
        guard let messageID = payload["message_id"] as? String, !messageID.isEmpty else {
            throw WorkBuddyAuthError.invalidResponse
        }
        return messageID
    }

    private func messages(after messageID: String, token: String) throws -> [AssistantMessage] {
        let payload = try get(
            "localassistant/message",
            query: [URLQueryItem(name: "message_id", value: messageID)],
            token: token
        )
        guard let raw = payload["messages"] as? [[String: Any]] else { return [] }
        return raw.map { item in
            AssistantMessage(
                id: item["message_id"] as? String ?? "",
                role: item["role"] as? String ?? "",
                type: item["msg_type"] as? String ?? "",
                content: item["content"] as? [Any] ?? [],
                metadata: item["metadata"] as? [String: Any] ?? [:]
            )
        }
    }

    private func get(_ path: String, query: [URLQueryItem]?, token: String) throws -> [String: Any] {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query
        guard let url = components?.url else { throw WorkBuddyAuthError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try WorkBuddyHTTP.perform(request)
        return try unwrap(data, response)
    }

    private func post(_ path: String, body: [String: Any], token: String) throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try WorkBuddyHTTP.perform(request)
        return try unwrap(data, response)
    }

    private func unwrap(_ data: Data, _ response: URLResponse) throws -> [String: Any] {
        guard let http = response as? HTTPURLResponse else { throw WorkBuddyAuthError.invalidResponse }
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WorkBuddyAuthError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode), (payload["code"] as? NSNumber)?.intValue == 0 else {
            throw WorkBuddyAuthError.rejected(WorkBuddyAuthError.description(from: data))
        }
        return payload["data"] as? [String: Any] ?? [:]
    }
}

struct AssistantMessage {
    var id: String
    var role: String
    var type: String
    var content: [Any]
    var metadata: [String: Any]
}

private enum WorkBuddyLocalAssistantError: LocalizedError {
    case assistantOffline
    case timedOut
    case waitingForApproval

    var errorDescription: String? {
        let chinese = currentLanguage == .chinese
        switch self {
        case .assistantOffline:
            return chinese
                ? "本机的 WorkBuddy 不在线。请确认 WorkBuddy 已启动并登录。"
                : "WorkBuddy on this Mac is offline. Start WorkBuddy and sign in."
        case .timedOut:
            return chinese
                ? "等待 WorkBuddy 回复超时。可在 [agents.workbuddy] 中调大 timeout_seconds。"
                : "Timed out waiting for WorkBuddy. Raise timeout_seconds in [agents.workbuddy]."
        case .waitingForApproval:
            return chinese
                ? "WorkBuddy 正在等待授权或回答。请在审批窗口或 WorkBuddy 窗口中处理后再试。"
                : "WorkBuddy is waiting for approval or an answer. Handle it in the approval window or the WorkBuddy window."
        }
    }
}
