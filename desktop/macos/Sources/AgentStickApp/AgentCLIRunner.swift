import AppKit
import Foundation

enum AgentCLIType: String {
    case codexExec = "codex_exec"
    case claudePrint = "claude_print"
    case generic = "generic"
}

struct AgentCLIDefinition: Equatable {
    var type: AgentCLIType
    var command: String?
    var arguments: [String]

    init(type: AgentCLIType, command: String? = nil, arguments: [String] = []) {
        self.type = type
        self.command = command
        self.arguments = arguments
    }
}

struct AgentCLIConfig: Equatable {
    var defaultAgent: String
    var workingDirectory: URL
    var timeoutSeconds: Int
    var agents: [String: AgentCLIDefinition]

    static let `default` = AgentCLIConfig(
        defaultAgent: "claude",
        workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
        timeoutSeconds: 600,
        agents: [
            "claude": AgentCLIDefinition(type: .claudePrint),
            "codex": AgentCLIDefinition(type: .codexExec)
        ]
    )

    func definition(for name: String) -> AgentCLIDefinition? {
        agents[name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }
}

struct AgentCLITask {
    let prompt: String
    let agentName: String
    let workingDirectory: URL

    init(prompt: String, agentName: String, workingDirectory: URL) {
        self.prompt = prompt
        self.agentName = agentName
        self.workingDirectory = workingDirectory
    }

    init(prompt: String, agentName: String, workingDirectory: String) {
        self.init(
            prompt: prompt,
            agentName: agentName,
            workingDirectory: URL(fileURLWithPath: workingDirectory, isDirectory: true)
        )
    }
}

struct AgentCLICommand {
    let executable: String
    let arguments: [String]
    let workingDirectory: URL

    init(executable: String, arguments: [String], workingDirectory: URL) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }

    init(
        definition: AgentCLIDefinition,
        task: AgentCLITask,
        bypassApprovals: Bool,
        claudeApprovalSettings: String?,
        memoryContext: String?,
        resumeSessionID: String? = nil
    ) {
        workingDirectory = task.workingDirectory
        switch definition.type {
        case .codexExec:
            executable = definition.command ?? "codex"
            arguments = [
                "exec",
            ] + (bypassApprovals ? ["--dangerously-bypass-approvals-and-sandbox"] : []) + [
                "--cd",
                task.workingDirectory.path,
                task.prompt
            ]
        case .claudePrint:
            executable = definition.command ?? "claude"
            arguments = [
                "-p",
                "--output-format",
                "json",
            ] + (bypassApprovals ? ["--dangerously-skip-permissions"]
                + (memoryContext.map { ["--append-system-prompt", $0] } ?? []) : [
                "--permission-mode", "default",
                "--append-system-prompt",
                "AgentStick handles native Claude tool permission requests in its approval window. Attempt the tool directly instead of asking first solely because a tool may require permission. For a non-tool decision that truly needs explicit confirmation, explain it and end with [AGENTSTICK_APPROVAL_REQUIRED]. When you need information, a choice, or clarification from the user, ask one concise question and end with [AGENTSTICK_INPUT_REQUIRED]."
                    + (memoryContext.map { "\n\n\($0)" } ?? "")
            ]) + (claudeApprovalSettings.map { ["--settings", $0] } ?? []) +
            (resumeSessionID.map { ["--resume", $0] } ?? []) + [
                task.prompt
            ]
        case .generic:
            executable = definition.command ?? task.agentName
            arguments = definition.arguments.map {
                $0
                    .replacingOccurrences(of: "{text}", with: task.prompt)
                    .replacingOccurrences(of: "{prompt}", with: task.prompt)
                    .replacingOccurrences(of: "{cwd}", with: task.workingDirectory.path)
            }
        }
    }
}

struct AgentCLIResult {
    let task: AgentCLITask
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let resultURL: URL

    var succeeded: Bool { exitCode == 0 }

    var displayText: String {
        let output = succeeded ? stdout : [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n\n")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class AgentCLIRunner {
    enum RunnerError: LocalizedError {
        case unknownAgent(String)
        case emptyPrompt
        case launchFailed(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .unknownAgent(let name):
                return currentLanguage == .chinese ? "未知 Agent：\(name)" : "Unknown agent: \(name)"
            case .emptyPrompt:
                return currentLanguage == .chinese ? "任务文本为空" : "Task prompt is empty"
            case .launchFailed(let message):
                return message
            case .timedOut:
                return currentLanguage == .chinese ? "Agent 执行超时" : "Agent run timed out"
            }
        }
    }

    private let fileManager: FileManager
    private let sessionStore = AgentSessionStore()
    private let memoryStore = AgentMemoryStore()
    private var codexRuns: [UUID: CodexInteractiveRunner] = [:]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func clearSessionHistory() {
        sessionStore.clear()
    }

    func run(
        prompt: String,
        config: AgentCLIConfig,
        bypassApprovals: Bool = false,
        memoryEnabled: Bool = true,
        approvalHandler: CodexInteractiveRunner.ApprovalHandler? = nil,
        inputHandler: CodexInteractiveRunner.InputHandler? = nil,
        completion: @escaping (Result<AgentCLIResult, Error>) -> Void
    ) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            completion(.failure(RunnerError.emptyPrompt))
            return
        }
        let agentName = config.defaultAgent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let definition = config.definition(for: agentName) else {
            completion(.failure(RunnerError.unknownAgent(agentName)))
            return
        }

        if memoryEnabled { memoryStore.observe(prompt: trimmedPrompt, workingDirectory: config.workingDirectory) }
        let memoryContext = memoryEnabled ? memoryStore.context(workingDirectory: config.workingDirectory) : nil
        let route = sessionStore.route(
            prompt: trimmedPrompt,
            agent: agentName,
            workingDirectory: config.workingDirectory
        )
        NSLog("AgentCLIRunner: session route agent=\(agentName) mode=\(route.sessionID == nil ? "new" : "resume") cwd=\(config.workingDirectory.path)")
        let task = AgentCLITask(
            prompt: route.prompt,
            agentName: agentName,
            workingDirectory: config.workingDirectory
        )
        if definition.type == .codexExec, let approvalHandler, let inputHandler {
            let identifier = UUID()
            let runner = CodexInteractiveRunner()
            codexRuns[identifier] = runner
            runner.run(
                task: task,
                timeoutSeconds: config.timeoutSeconds,
                approvalHandler: approvalHandler,
                inputHandler: inputHandler,
                bypassApprovals: bypassApprovals,
                memoryContext: memoryContext,
                resumeThreadID: route.sessionID,
                onSessionUpdated: { [weak self] threadID in
                    self?.sessionStore.remember(
                        id: threadID,
                        agent: agentName,
                        workingDirectory: config.workingDirectory,
                        prompt: route.prompt
                    )
                },
                onResumeFailed: { [weak self] threadID in self?.sessionStore.forget(id: threadID) }
            ) { [weak self] result in
                self?.codexRuns.removeValue(forKey: identifier)
                completion(result)
            }
            return
        }
        let command = AgentCLICommand(
            definition: definition,
            task: task,
            bypassApprovals: bypassApprovals,
            claudeApprovalSettings: bypassApprovals ? nil : claudeApprovalSettings(),
            memoryContext: memoryContext,
            resumeSessionID: definition.type == .claudePrint ? route.sessionID : nil
        )
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.run(
                command: command,
                task: task,
                timeoutSeconds: config.timeoutSeconds,
                bypassApprovals: bypassApprovals,
                approvalHandler: approvalHandler,
                inputHandler: inputHandler
            )
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private func claudeApprovalSettings() -> String? {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/AgentStickHooks").path
        guard fileManager.isExecutableFile(atPath: helper) else {
            NSLog("AgentCLIRunner: approval helper missing at \(helper)")
            return nil
        }
        let escaped = helper.replacingOccurrences(of: "'", with: "'\\''")
        let settings: [String: Any] = [
            "hooks": [
                "PermissionRequest": [[
                    "hooks": [[
                        "type": "command",
                        "command": "'\(escaped)' --source claude --approval"
                    ]]
                ]]
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: settings) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func run(
        command: AgentCLICommand,
        task: AgentCLITask,
        timeoutSeconds: Int,
        bypassApprovals: Bool,
        approvalHandler: CodexInteractiveRunner.ApprovalHandler?,
        inputHandler: CodexInteractiveRunner.InputHandler?,
        approvalDepth: Int = 0
    ) -> Result<AgentCLIResult, Error> {
        let environment = environment(for: command)
        guard let executableURL = resolveExecutable(command.executable, environment: environment) else {
            let message = currentLanguage == .chinese
                ? "未找到 \(command.executable) CLI。请先安装，或在 AgentStick 配置中设置 command。"
                : "Could not find the \(command.executable) CLI. Install it or set command in the AgentStick config."
            return .failure(RunnerError.launchFailed(message))
        }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = command.arguments
        process.currentDirectoryURL = command.workingDirectory
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        var stdoutData = Data()
        var stderrData = Data()
        let outputLock = NSLock()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputLock.lock()
            stdoutData.append(data)
            outputLock.unlock()
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputLock.lock()
            stderrData.append(data)
            outputLock.unlock()
        }

        do {
            NSLog("AgentCLIRunner: launch \(task.agentName) approvalDepth=\(approvalDepth) resume=\(command.arguments.contains("--resume"))")
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            return .failure(RunnerError.launchFailed(error.localizedDescription))
        }

        let timeout = max(10, timeoutSeconds)
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            return .failure(RunnerError.timedOut)
        }

        NSLog("AgentCLIRunner: \(task.agentName) exited status=\(process.terminationStatus) approvalDepth=\(approvalDepth)")
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        outputLock.lock()
        stdoutData.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        stderrData.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
        let capturedStdout = stdoutData
        let capturedStderr = stderrData
        outputLock.unlock()
        var stdout = String(data: capturedStdout, encoding: .utf8) ?? ""
        let stderr = String(data: capturedStderr, encoding: .utf8) ?? ""
        var effectiveExitCode = process.terminationStatus
        if effectiveExitCode != 0,
           task.agentName == "claude",
           let resumeIndex = command.arguments.firstIndex(of: "--resume"),
           command.arguments.indices.contains(resumeIndex + 1) {
            let combined = (stdout + "\n" + stderr).lowercased()
            if combined.contains("session") && (combined.contains("not found") || combined.contains("no conversation") || combined.contains("invalid")) {
                let staleSessionID = command.arguments[resumeIndex + 1]
                sessionStore.forget(id: staleSessionID)
                var freshArguments = command.arguments
                freshArguments.removeSubrange(resumeIndex...resumeIndex + 1)
                return run(
                    command: AgentCLICommand(
                        executable: command.executable,
                        arguments: freshArguments,
                        workingDirectory: command.workingDirectory
                    ),
                    task: task,
                    timeoutSeconds: timeoutSeconds,
                    bypassApprovals: bypassApprovals,
                    approvalHandler: approvalHandler,
                    inputHandler: inputHandler,
                    approvalDepth: approvalDepth
                )
            }
        }
        if task.agentName == "claude", bypassApprovals,
           let payload = claudeJSONPayload(stdout), let resultText = payload.result {
            stdout = resultText
            if let sessionID = payload.sessionID {
                sessionStore.remember(
                    id: sessionID,
                    agent: task.agentName,
                    workingDirectory: task.workingDirectory,
                    prompt: task.prompt
                )
            }
        }
        if task.agentName == "claude", !bypassApprovals,
           let payload = claudeJSONPayload(stdout),
           let resultText = payload.result {
            if let sessionID = payload.sessionID {
                sessionStore.remember(
                    id: sessionID,
                    agent: task.agentName,
                    workingDirectory: task.workingDirectory,
                    prompt: task.prompt
                )
            }
            stdout = resultText
                .replacingOccurrences(of: "[AGENTSTICK_APPROVAL_REQUIRED]", with: "")
                .replacingOccurrences(of: "[AGENTSTICK_INPUT_REQUIRED]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if needsSemanticInput(resultText),
               let sessionID = payload.sessionID,
               approvalDepth < 8,
               let inputHandler {
                switch waitForInput(handler: inputHandler, question: stdout, timeoutSeconds: timeoutSeconds) {
                case .answered(let answer):
                    return run(
                        command: claudeResumeCommand(
                            from: command,
                            sessionID: sessionID,
                            message: currentLanguage == .chinese
                                ? "用户在 AgentStick 中的回答是：\(answer)\n请根据回答继续当前任务。"
                                : "The user's answer in AgentStick is: \(answer)\nContinue the current task using this answer."
                        ),
                        task: task,
                        timeoutSeconds: timeoutSeconds,
                        bypassApprovals: false,
                        approvalHandler: approvalHandler,
                        inputHandler: inputHandler,
                        approvalDepth: approvalDepth + 1
                    )
                case .cancelled:
                    stdout += currentLanguage == .chinese ? "\n\n用户取消了回答。" : "\n\nThe user cancelled this input request."
                    effectiveExitCode = 1
                case .timedOut:
                    return .failure(RunnerError.timedOut)
                }
            } else if needsSemanticApproval(resultText),
               let sessionID = payload.sessionID,
               approvalDepth < 8,
               let approvalHandler {
                let decision = waitForApproval(
                    handler: approvalHandler,
                    summary: stdout,
                    timeoutSeconds: timeoutSeconds
                )
                switch decision {
                case .allowed:
                    NSLog("AgentCLIRunner: semantic approval allowed; continuing Claude task depth=\(approvalDepth + 1)")
                    return run(
                        command: claudeResumeCommand(
                            from: command,
                            sessionID: sessionID,
                            message: currentLanguage == .chinese
                                ? "用户已在 AgentStick 中允许刚才请求的操作。请立即继续执行，不要再次询问同一操作。"
                                : "The user approved the requested operation in AgentStick. Continue now without asking again for the same operation."
                        ),
                        task: task,
                        timeoutSeconds: timeoutSeconds,
                        bypassApprovals: false,
                        approvalHandler: approvalHandler,
                        inputHandler: inputHandler,
                        approvalDepth: approvalDepth + 1
                    )
                case .denied:
                    NSLog("AgentCLIRunner: semantic approval denied")
                    stdout += currentLanguage == .chinese ? "\n\n用户已拒绝该操作。" : "\n\nThe user denied this operation."
                    effectiveExitCode = 1
                case .timedOut:
                    return .failure(RunnerError.timedOut)
                }
            }
        }
        let resultURL: URL
        do {
            resultURL = try Self.writeResultFile(task: task, exitCode: effectiveExitCode, stdout: stdout, stderr: stderr)
        } catch {
            return .failure(error)
        }
        return .success(AgentCLIResult(
            task: task,
            exitCode: effectiveExitCode,
            stdout: stdout,
            stderr: stderr,
            resultURL: resultURL
        ))
    }

    private enum ApprovalWaitResult { case allowed, denied, timedOut }
    private enum InputWaitResult { case answered(String), cancelled, timedOut }

    private func claudeResumeCommand(from command: AgentCLICommand, sessionID: String, message: String) -> AgentCLICommand {
        var arguments = ["-p", "--output-format", "json", "--permission-mode", "default", "--resume", sessionID]
        if let settingsIndex = command.arguments.firstIndex(of: "--settings"),
           command.arguments.indices.contains(settingsIndex + 1) {
            arguments += ["--settings", command.arguments[settingsIndex + 1]]
        }
        arguments.append(message)
        NSLog("AgentCLIRunner: resuming Claude session=\(sessionID) after AgentStick interaction")
        return AgentCLICommand(executable: command.executable, arguments: arguments, workingDirectory: command.workingDirectory)
    }

    private func waitForApproval(
        handler: @escaping CodexInteractiveRunner.ApprovalHandler,
        summary: String,
        timeoutSeconds: Int
    ) -> ApprovalWaitResult {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var allowed = false
        DispatchQueue.main.async {
            handler(
                "Claude Code",
                currentLanguage == .chinese ? "继续执行" : "Continue Task",
                summary.isEmpty ? (currentLanguage == .chinese ? "Claude 请求确认" : "Claude requests confirmation") : String(summary.prefix(240)),
                "## \(currentLanguage == .chinese ? "Claude 请求确认" : "Claude requests confirmation")\n\n\(summary)"
            ) { value in
                lock.lock()
                allowed = value
                lock.unlock()
                semaphore.signal()
            }
        }
        guard semaphore.wait(timeout: .now() + .seconds(max(10, timeoutSeconds))) == .success else {
            return .timedOut
        }
        lock.lock()
        let result = allowed
        lock.unlock()
        return result ? .allowed : .denied
    }

    private func waitForInput(
        handler: @escaping CodexInteractiveRunner.InputHandler,
        question: String,
        timeoutSeconds: Int
    ) -> InputWaitResult {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var answer: String?
        var cancelled = false
        let questionID = "answer"
        DispatchQueue.main.async {
            handler(
                "Claude Code",
                question.isEmpty ? (currentLanguage == .chinese ? "Claude 需要输入" : "Claude needs input") : String(question.prefix(240)),
                "## \(currentLanguage == .chinese ? "Claude 需要你的回答" : "Claude needs your answer")\n\n\(question)",
                [AgentInputQuestion(
                    id: questionID,
                    header: currentLanguage == .chinese ? "回答" : "Answer",
                    question: question,
                    options: [],
                    allowsFreeText: true,
                    isSecret: false
                )]
            ) { answers in
                lock.lock()
                if let value = answers?[questionID]?.first { answer = value } else { cancelled = true }
                lock.unlock()
                semaphore.signal()
            }
        }
        guard semaphore.wait(timeout: .now() + .seconds(max(10, timeoutSeconds))) == .success else { return .timedOut }
        lock.lock()
        let value = answer
        let wasCancelled = cancelled
        lock.unlock()
        if let value { return .answered(value) }
        return wasCancelled ? .cancelled : .timedOut
    }

    private func claudeJSONPayload(_ text: String) -> (result: String?, sessionID: String?)? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (object["result"] as? String, object["session_id"] as? String)
    }

    private func needsSemanticApproval(_ text: String) -> Bool {
        if text.contains("[AGENTSTICK_APPROVAL_REQUIRED]") { return true }
        let normalized = text.lowercased()
        return [
            "需要你确认", "请批准后", "请确认后", "等待你的确认", "是否允许",
            "need your approval", "please approve", "please confirm", "waiting for your approval",
            "would you like me to"
        ].contains { normalized.contains($0) }
    }

    private func needsSemanticInput(_ text: String) -> Bool {
        text.contains("[AGENTSTICK_INPUT_REQUIRED]")
    }

    static func writeResultFile(task: AgentCLITask, exitCode: Int32, stdout: String, stderr: String) throws -> URL {
        let directory = AppConfig.configDirectory.appendingPathComponent("Tasks", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "\(formatter.string(from: Date()))-\(task.agentName).md"
        let url = directory.appendingPathComponent(filename)
        let text = """
        # AgentStick Task

        Agent: \(task.agentName)
        Working directory: \(task.workingDirectory.path)
        Exit code: \(exitCode)

        ## Prompt

        \(task.prompt)

        ## Output

        \(stdout.trimmingCharacters(in: .whitespacesAndNewlines))

        ## Error

        \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        """
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func environment(for command: AgentCLICommand) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        var pathEntries: [String] = []
        let executableURL = URL(fileURLWithPath: command.executable)
        if command.executable.hasPrefix("/") {
            pathEntries.append(executableURL.deletingLastPathComponent().path)
        }
        let home = fileManager.homeDirectoryForCurrentUser
        pathEntries.append(contentsOf: [
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".volta/bin").path,
            home.appendingPathComponent(".bun/bin").path,
            home.appendingPathComponent(".npm-global/bin").path,
            home.appendingPathComponent("Library/pnpm").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ])
        let nvmVersions = home.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        if let versions = try? fileManager.contentsOfDirectory(
            at: nvmVersions,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            pathEntries.append(contentsOf: versions.sorted { $0.lastPathComponent > $1.lastPathComponent }.map {
                $0.appendingPathComponent("bin", isDirectory: true).path
            })
        }
        if let existingPath = environment["PATH"], !existingPath.isEmpty {
            pathEntries.append(contentsOf: existingPath.split(separator: ":").map(String.init))
        }
        environment["PATH"] = pathEntries.reduce(into: []) { entries, entry in
            if !entry.isEmpty && !entries.contains(entry) {
                entries.append(entry)
            }
        }.joined(separator: ":")
        return environment
    }

    private func resolveExecutable(_ executable: String, environment: [String: String]) -> URL? {
        if executable.hasPrefix("/") {
            return fileManager.isExecutableFile(atPath: executable) ? URL(fileURLWithPath: executable) : nil
        }

        // GUI apps do not inherit the user's interactive shell PATH. Prefer the CLI bundled
        // with Codex/ChatGPT before looking through common package-manager locations.
        if executable == "codex" {
            for path in [
                "/Applications/Codex.app/Contents/Resources/codex",
                "/Applications/ChatGPT.app/Contents/Resources/codex"
            ] where fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory), isDirectory: true)
                .appendingPathComponent(executable)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
