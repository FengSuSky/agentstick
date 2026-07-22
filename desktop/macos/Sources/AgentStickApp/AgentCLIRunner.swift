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

    init(definition: AgentCLIDefinition, task: AgentCLITask) {
        workingDirectory = task.workingDirectory
        switch definition.type {
        case .codexExec:
            executable = definition.command ?? "codex"
            arguments = [
                "exec",
                "--cd",
                task.workingDirectory.path,
                task.prompt
            ]
        case .claudePrint:
            executable = definition.command ?? "claude"
            arguments = [
                "-p",
                "--output-format",
                "text",
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

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func run(prompt: String, config: AgentCLIConfig, completion: @escaping (Result<AgentCLIResult, Error>) -> Void) {
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

        let task = AgentCLITask(
            prompt: trimmedPrompt,
            agentName: agentName,
            workingDirectory: config.workingDirectory
        )
        let command = AgentCLICommand(definition: definition, task: task)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.run(command: command, task: task, timeoutSeconds: config.timeoutSeconds)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private func run(command: AgentCLICommand, task: AgentCLITask, timeoutSeconds: Int) -> Result<AgentCLIResult, Error> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command.executable] + command.arguments
        process.currentDirectoryURL = command.workingDirectory
        process.environment = environment(for: command)

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

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        outputLock.lock()
        stdoutData.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        stderrData.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
        let capturedStdout = stdoutData
        let capturedStderr = stderrData
        outputLock.unlock()
        let stdout = String(data: capturedStdout, encoding: .utf8) ?? ""
        let stderr = String(data: capturedStderr, encoding: .utf8) ?? ""
        let resultURL: URL
        do {
            resultURL = try writeResult(task: task, exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
        } catch {
            return .failure(error)
        }
        return .success(AgentCLIResult(
            task: task,
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            resultURL: resultURL
        ))
    }

    private func writeResult(task: AgentCLITask, exitCode: Int32, stdout: String, stderr: String) throws -> URL {
        let directory = AppConfig.configDirectory.appendingPathComponent("Tasks", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
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
        pathEntries.append(contentsOf: [
            "/Users/fengsu/.nvm/versions/node/v24.11.0/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ])
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
}
