import AppKit
import Foundation

final class CodexInteractiveRunner {
    typealias ApprovalHandler = (_ agent: String, _ kind: String, _ summary: String, _ details: String, _ reply: @escaping (Bool) -> Void) -> Void
    typealias InputHandler = (_ agent: String, _ summary: String, _ details: String, _ questions: [AgentInputQuestion], _ reply: @escaping ([String: [String]]?) -> Void) -> Void

    private let queue = DispatchQueue(label: "app.agentstick.codex-interactive")
    private var process: Process?
    private var stdin: FileHandle?
    private var readBuffer = Data()
    private var output = ""
    private var stderr = Data()
    private var task: AgentCLITask?
    private var completion: ((Result<AgentCLIResult, Error>) -> Void)?
    private var approvalHandler: ApprovalHandler?
    private var inputHandler: InputHandler?
    private var completed = false
    private var itemGeneration = 0
    private var activeThreadID: String?
    private var nextClientRequestID = 4
    private var waitingForSemanticInteraction = false
    private var resumeThreadID: String?
    private var onSessionUpdated: ((String) -> Void)?
    private var onResumeFailed: ((String) -> Void)?
    private var bypassApprovals = false
    private var memoryContext: String?

    func run(
        task: AgentCLITask,
        timeoutSeconds: Int,
        approvalHandler: @escaping ApprovalHandler,
        inputHandler: @escaping InputHandler,
        bypassApprovals: Bool,
        memoryContext: String?,
        resumeThreadID: String?,
        onSessionUpdated: @escaping (String) -> Void,
        onResumeFailed: @escaping (String) -> Void,
        completion: @escaping (Result<AgentCLIResult, Error>) -> Void
    ) {
        self.task = task
        self.approvalHandler = approvalHandler
        self.inputHandler = inputHandler
        self.bypassApprovals = bypassApprovals
        self.memoryContext = memoryContext
        self.resumeThreadID = resumeThreadID
        self.onSessionUpdated = onSessionUpdated
        self.onResumeFailed = onResumeFailed
        self.completion = completion
        guard let executable = resolveCodexPath() else {
            finish(.failure(AgentCLIRunner.RunnerError.launchFailed(currentLanguage == .chinese ? "未找到 Codex CLI" : "Codex CLI not found")))
            return
        }
        let proc = Process()
        let inputPipe = Pipe(), outputPipe = Pipe(), errorPipe = Pipe()
        proc.executableURL = executable
        proc.arguments = ["app-server", "--listen", "stdio://"]
        proc.currentDirectoryURL = task.workingDirectory
        proc.standardInput = inputPipe
        proc.standardOutput = outputPipe
        proc.standardError = errorPipe
        stdin = inputPipe.fileHandleForWriting
        process = proc
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty { self?.queue.async { self?.consume(data) } }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty { self?.queue.async { self?.stderr.append(data) } }
        }
        proc.terminationHandler = { [weak self] process in
            self?.queue.async {
                guard let self, !self.completed else { return }
                let message = String(data: self.stderr, encoding: .utf8) ?? "Codex app-server exited (\(process.terminationStatus))"
                self.finish(.failure(AgentCLIRunner.RunnerError.launchFailed(message)))
            }
        }
        do {
            try proc.run()
            send(id: 1, method: "initialize", params: ["clientInfo": ["name": "AgentStick", "version": "0.3.4"]])
        } catch {
            finish(.failure(error))
            return
        }
        queue.asyncAfter(deadline: .now() + .seconds(max(10, timeoutSeconds))) { [weak self] in
            guard let self, !self.completed else { return }
            self.process?.terminate()
            self.finish(.failure(AgentCLIRunner.RunnerError.timedOut))
        }
    }

    private func consume(_ data: Data) {
        readBuffer.append(data)
        while let newline = readBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = Data(readBuffer[..<newline])
            readBuffer.removeSubrange(...newline)
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            handle(json)
        }
    }

    private func handle(_ json: [String: Any]) {
        if let id = json["id"] as? Int, json["method"] == nil {
            if let error = json["error"] as? [String: Any] {
                if id == 2, let failedThreadID = resumeThreadID {
                    onResumeFailed?(failedThreadID)
                    resumeThreadID = nil
                    sendNewThreadRequest()
                    return
                }
                finish(.failure(AgentCLIRunner.RunnerError.launchFailed(error["message"] as? String ?? "Codex request failed")))
                return
            }
            if id == 1, task != nil {
                sendJSON(["jsonrpc": "2.0", "method": "initialized", "params": [:]])
                if let resumeThreadID {
                    send(id: 2, method: "thread/resume", params: threadParameters(threadID: resumeThreadID))
                } else {
                    sendNewThreadRequest()
                }
            } else if id == 2,
                      let result = json["result"] as? [String: Any],
                      let thread = result["thread"] as? [String: Any],
                      let threadID = thread["id"] as? String,
                      let task {
                activeThreadID = threadID
                onSessionUpdated?(threadID)
                send(id: 3, method: "turn/start", params: [
                    "threadId": threadID,
                    "input": [["type": "text", "text": task.prompt]]
                ])
            }
            return
        }
        guard let method = json["method"] as? String else { return }
        let params = json["params"] as? [String: Any] ?? [:]
        switch method {
        case "item/started":
            itemGeneration += 1
        case "item/completed":
            let item = params["item"] as? [String: Any]
            if item?["type"] as? String == "agentMessage", !output.isEmpty {
                if handleSemanticInteractionIfNeeded() { break }
                itemGeneration += 1
                let generation = itemGeneration
                queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                    guard let self, !self.completed, self.itemGeneration == generation else { return }
                    // Some user-installed stop hooks never return. The final agent message is
                    // already complete, so do not hold the voice task open indefinitely.
                    self.finishResult(succeeded: true, error: "")
                }
            }
        case "item/agentMessage/delta":
            output += params["delta"] as? String ?? ""
        case "turn/completed":
            let turn = params["turn"] as? [String: Any]
            let status = turn?["status"] as? String ?? "completed"
            if !handleSemanticInteractionIfNeeded() {
                finishResult(succeeded: status == "completed", error: status == "completed" ? "" : "Codex turn \(status)")
            }
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval", "item/permissions/requestApproval":
            handleApproval(method: method, id: json["id"], params: params)
        case "item/tool/requestUserInput":
            handleUserInput(id: json["id"], params: params)
        case "mcpServer/elicitation/request":
            handleMCPElicitation(id: json["id"], params: params)
        case "error":
            handleErrorNotification(params)
        default:
            break
        }
    }

    private func sendNewThreadRequest() {
        guard task != nil else { return }
        send(id: 2, method: "thread/start", params: threadParameters(threadID: nil))
    }

    private func threadParameters(threadID: String?) -> [String: Any] {
        guard let task else { return [:] }
        var params: [String: Any] = [
            "cwd": task.workingDirectory.path,
            "approvalPolicy": bypassApprovals ? "never" : "on-request",
            "approvalsReviewer": "user",
            "developerInstructions": (bypassApprovals
                ? "The user granted unattended execution for operations. Do not ask for operation approval. When you need information, a choice, or clarification, ask one concise question and end with [AGENTSTICK_INPUT_REQUIRED]."
                : "AgentStick handles native tool approval requests. Attempt tools directly instead of asking first solely because they may require approval. For a non-tool decision requiring confirmation, explain it and end with [AGENTSTICK_APPROVAL_REQUIRED]. When you need information, a choice, or clarification, ask one concise question and end with [AGENTSTICK_INPUT_REQUIRED]. Do not report the task completed while waiting for either response.")
                + (memoryContext.map { "\n\n\($0)" } ?? "")
        ]
        if let threadID {
            params["threadId"] = threadID
        } else {
            params["ephemeral"] = false
        }
        if bypassApprovals {
            params["sandbox"] = "danger-full-access"
        }
        return params
    }

    @discardableResult
    private func handleSemanticInteractionIfNeeded() -> Bool {
        guard !waitingForSemanticInteraction, let threadID = activeThreadID else { return waitingForSemanticInteraction }
        if output.contains("[AGENTSTICK_INPUT_REQUIRED]"), let inputHandler {
            waitingForSemanticInteraction = true
            let question = output.replacingOccurrences(of: "[AGENTSTICK_INPUT_REQUIRED]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            output = question + "\n\n"
            let questionID = "answer"
            inputHandler(
                "Codex",
                String(question.prefix(240)),
                "## \(currentLanguage == .chinese ? "Codex 需要你的回答" : "Codex needs your answer")\n\n\(question)",
                [AgentInputQuestion(
                    id: questionID,
                    header: currentLanguage == .chinese ? "回答" : "Answer",
                    question: question,
                    options: [],
                    allowsFreeText: true,
                    isSecret: false
                )]
            ) { [weak self] answers in
                guard let self else { return }
                self.queue.async {
                    guard let answer = answers?[questionID]?.first else {
                        self.finishResult(succeeded: false, error: "User cancelled input")
                        return
                    }
                    self.waitingForSemanticInteraction = false
                    self.startContinuation(threadID: threadID, text: "The user's answer in AgentStick is: \(answer). Continue the current task using this answer.")
                }
            }
            return true
        }
        if output.contains("[AGENTSTICK_APPROVAL_REQUIRED]"), let approvalHandler {
            waitingForSemanticInteraction = true
            let question = output.replacingOccurrences(of: "[AGENTSTICK_APPROVAL_REQUIRED]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            output = question + "\n\n"
            approvalHandler(
                "Codex",
                currentLanguage == .chinese ? "继续执行" : "Continue Task",
                String(question.prefix(240)),
                "## \(currentLanguage == .chinese ? "Codex 请求确认" : "Codex requests confirmation")\n\n\(question)"
            ) { [weak self] allowed in
                guard let self else { return }
                self.queue.async {
                    guard allowed else {
                        self.finishResult(succeeded: false, error: "User denied operation")
                        return
                    }
                    self.waitingForSemanticInteraction = false
                    self.startContinuation(threadID: threadID, text: "The user approved the requested operation in AgentStick. Continue now without asking again for the same operation.")
                }
            }
            return true
        }
        return false
    }

    private func startContinuation(threadID: String, text: String) {
        let id = nextClientRequestID
        nextClientRequestID += 1
        itemGeneration += 1
        send(id: id, method: "turn/start", params: [
            "threadId": threadID,
            "input": [["type": "text", "text": text]]
        ])
    }

    private func handleMCPElicitation(id: Any?, params: [String: Any]) {
        guard let id else { return }
        let serverName = params["serverName"] as? String ?? "MCP"
        let message = params["message"] as? String ?? (currentLanguage == .chinese ? "MCP 服务需要输入" : "MCP server needs input")
        if params["mode"] as? String == "url", let urlText = params["url"] as? String, let url = URL(string: urlText) {
            guard let approvalHandler else { sendError(id: id, message: "No approval UI available"); return }
            approvalHandler(
                "Codex · \(serverName)",
                currentLanguage == .chinese ? "打开登录网页" : "Open Login Page",
                message,
                "## \(message)\n\n\(url.absoluteString)"
            ) { [weak self] allowed in
                guard let self else { return }
                if allowed {
                    DispatchQueue.main.async { NSWorkspace.shared.open(url) }
                    self.queue.async { self.sendResponse(id: id, result: ["action": "accept"]) }
                } else {
                    self.queue.async { self.sendResponse(id: id, result: ["action": "decline"]) }
                }
            }
            return
        }

        guard let inputHandler else { sendResponse(id: id, result: ["action": "decline"]); return }
        let schema = params["requestedSchema"] as? [String: Any] ?? [:]
        let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
        let questions = properties.sorted { $0.key < $1.key }.map { key, value -> AgentInputQuestion in
            let options = value["enum"] as? [String] ?? []
            return AgentInputQuestion(
                id: key,
                header: value["title"] as? String ?? key,
                question: value["description"] as? String ?? (value["title"] as? String ?? key),
                options: options,
                allowsFreeText: options.isEmpty,
                isSecret: value["format"] as? String == "password" || value["writeOnly"] as? Bool == true
            )
        }
        inputHandler("Codex · \(serverName)", message, "## MCP\n\n\(message)", questions) { [weak self] answers in
            guard let self else { return }
            self.queue.async {
                guard let answers else {
                    self.sendResponse(id: id, result: ["action": "cancel"])
                    return
                }
                var content: [String: Any] = [:]
                for (key, values) in answers {
                    let raw = values.first ?? ""
                    let type = properties[key]?["type"] as? String
                    if type == "boolean" { content[key] = ["true", "yes", "1", "on"].contains(raw.lowercased()) }
                    else if type == "integer" { content[key] = Int(raw) ?? 0 }
                    else if type == "number" { content[key] = Double(raw) ?? 0 }
                    else { content[key] = raw }
                }
                self.sendResponse(id: id, result: ["action": "accept", "content": content])
            }
        }
    }

    private func handleErrorNotification(_ params: [String: Any]) {
        let error = params["error"] as? [String: Any]
        let message = error?["message"] as? String ?? params["message"] as? String ?? "Codex error"
        if !stderr.isEmpty { stderr.append(Data("\n".utf8)) }
        stderr.append(Data(message.utf8))
        if params["willRetry"] as? Bool == false {
            finish(.failure(AgentCLIRunner.RunnerError.launchFailed(message)))
        }
    }

    private func handleUserInput(id: Any?, params: [String: Any]) {
        guard let id, let inputHandler else { return }
        let rawQuestions = params["questions"] as? [[String: Any]] ?? []
        let questions = rawQuestions.map { raw -> AgentInputQuestion in
            let options = (raw["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String }
            return AgentInputQuestion(
                id: raw["id"] as? String ?? UUID().uuidString,
                header: raw["header"] as? String ?? "",
                question: raw["question"] as? String ?? (currentLanguage == .chinese ? "请输入回答" : "Enter your answer"),
                options: options,
                allowsFreeText: raw["isOther"] as? Bool ?? true,
                isSecret: raw["isSecret"] as? Bool ?? false
            )
        }
        let summary = questions.first?.question ?? (currentLanguage == .chinese ? "Codex 需要输入" : "Codex needs input")
        let details = questions.map { question in
            let choices = question.options.isEmpty ? "" : "\n\n" + question.options.map { "- \($0)" }.joined(separator: "\n")
            return "## \(question.header.isEmpty ? summary : question.header)\n\n\(question.question)\(choices)"
        }.joined(separator: "\n\n")
        inputHandler("Codex", summary, details, questions) { [weak self] answers in
            guard let self else { return }
            self.queue.async {
                guard let answers else {
                    self.sendError(id: id, message: "User cancelled in AgentStick")
                    return
                }
                self.sendResponse(id: id, result: [
                    "answers": answers.mapValues { ["answers": $0] }
                ])
            }
        }
    }

    private func handleApproval(method: String, id: Any?, params: [String: Any]) {
        guard let id, let approvalHandler else { return }
        let kind: String
        let summary: String
        if method.contains("commandExecution") {
            kind = currentLanguage == .chinese ? "执行命令" : "Run Command"
            summary = params["command"] as? String ?? params["reason"] as? String ?? kind
        } else if method.contains("fileChange") {
            kind = currentLanguage == .chinese ? "修改文件" : "Change Files"
            summary = params["reason"] as? String ?? kind
        } else {
            kind = currentLanguage == .chinese ? "扩展权限" : "Additional Permissions"
            summary = params["reason"] as? String ?? kind
        }
        let pretty = (try? JSONSerialization.data(withJSONObject: params, options: [.prettyPrinted, .sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: params)
        approvalHandler("Codex", kind, summary, "## \(kind)\n\n```json\n\(pretty)\n```") { [weak self] allowed in
            guard let self else { return }
            self.queue.async {
                if method.contains("permissions") {
                    if allowed, let permissions = params["permissions"] {
                        self.sendResponse(id: id, result: ["permissions": permissions, "scope": "turn"])
                    } else {
                        self.sendError(id: id, message: "Denied in AgentStick")
                    }
                } else {
                    self.sendResponse(id: id, result: ["decision": allowed ? "accept" : "decline"])
                }
            }
        }
    }

    private func finishResult(succeeded: Bool, error: String) {
        guard let task else { return }
        do {
            let url = try AgentCLIRunner.writeResultFile(task: task, exitCode: succeeded ? 0 : 1, stdout: output, stderr: error)
            finish(.success(AgentCLIResult(task: task, exitCode: succeeded ? 0 : 1, stdout: output, stderr: error, resultURL: url)))
        } catch { finish(.failure(error)) }
    }

    private func send(id: Int, method: String, params: [String: Any]) {
        sendJSON(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
    }
    private func sendResponse(id: Any, result: [String: Any]) { sendJSON(["jsonrpc": "2.0", "id": id, "result": result]) }
    private func sendError(id: Any, message: String) { sendJSON(["jsonrpc": "2.0", "id": id, "error": ["code": -32000, "message": message]]) }
    private func sendJSON(_ object: [String: Any]) {
        guard let stdin, var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(UInt8(ascii: "\n"))
        try? stdin.write(contentsOf: data)
    }

    private func finish(_ result: Result<AgentCLIResult, Error>) {
        guard !completed else { return }
        completed = true
        let callback = completion
        completion = nil
        process?.terminate()
        DispatchQueue.main.async { callback?(result) }
    }

    private func resolveCodexPath() -> URL? {
        for path in ["/Applications/Codex.app/Contents/Resources/codex", "/Applications/ChatGPT.app/Contents/Resources/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"] {
            if FileManager.default.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }
}
