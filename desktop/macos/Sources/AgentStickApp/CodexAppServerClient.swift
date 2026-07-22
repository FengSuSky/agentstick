import Foundation
import AgentStickCore

final class CodexAppServerClient {
    var onEvent: ((AgentTaskEvent) -> Void)?

    private var process: Process?
    private var stdin: FileHandle?
    private var nextRequestID = 1
    private var threadTitles: [String: String] = [:]

    var isRunning: Bool { process?.isRunning == true }

    func start() {
        guard !isRunning else { return }

        let codexPath = resolveCodexPath()
        guard FileManager.default.isExecutableFile(atPath: codexPath) else {
            NSLog("CodexAppServer: codex not found at \(codexPath), skipping Codex Desktop capture")
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: codexPath)
        proc.arguments = ["app-server", "--listen", "stdio://"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        self.stdin = stdinPipe.fileHandleForWriting
        self.process = proc

        // Read stdout line by line for JSON-RPC notifications.
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.handleIncomingData(data)
        }

        // Drain stderr to prevent pipe blocking.
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        proc.terminationHandler = { [weak self] _ in
            NSLog("CodexAppServer: process terminated")
            self?.stdin = nil
        }

        do {
            try proc.run()
            NSLog("CodexAppServer: started pid=\(proc.processIdentifier)")
            sendInitialize()
        } catch {
            NSLog("CodexAppServer: launch failed: \(error)")
            self.process = nil
            self.stdin = nil
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        stdin = nil
    }

    // MARK: - JSON-RPC

    private func sendInitialize() {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": nextID(),
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "AgentStick",
                    "version": "1.0.0"
                ]
            ]
        ]
        sendJSON(request)
    }

    private func nextID() -> Int {
        let id = nextRequestID
        nextRequestID += 1
        return id
    }

    private func sendJSON(_ object: [String: Any]) {
        guard let stdin else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        var line = data
        line.append(UInt8(ascii: "\n"))
        stdin.write(line)
    }

    // MARK: - Incoming data

    private var readBuffer = Data()

    private func handleIncomingData(_ data: Data) {
        readBuffer.append(data)

        // Split on newlines; each line is a complete JSON-RPC message.
        while let newlineIndex = readBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = readBuffer[readBuffer.startIndex..<newlineIndex]
            readBuffer = Data(readBuffer[readBuffer.index(after: newlineIndex)...])

            guard !lineData.isEmpty else { continue }
            processLine(Data(lineData))
        }
    }

    private func processLine(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // We only care about notifications (no "id" field) and the "method" key.
        guard let method = json["method"] as? String else { return }
        let params = json["params"] as? [String: Any] ?? [:]

        switch method {
        case "thread/started":
            handleThreadStarted(params: params)
        case "turn/started":
            handleTurnStarted(params: params)
        case "turn/completed":
            handleTurnCompleted(params: params)
        case "thread/closed":
            handleThreadClosed(params: params)
        default:
            break
        }
    }

    // MARK: - Event mapping

    private func handleThreadStarted(params: [String: Any]) {
        guard let threadID = extractThreadID(from: params) else { return }
        let title = params["name"] as? String ?? params["preview"] as? String
        if let title { threadTitles[threadID] = title }

        let event = AgentTaskEvent(
            kind: .sessionStarted,
            agent: .codexDesktop,
            surface: .desktop,
            sessionID: threadID,
            cwd: params["cwd"] as? String,
            title: title,
            jumpTarget: "codex://threads/\(threadID)"
        )
        emit(event)
    }

    private func handleTurnStarted(params: [String: Any]) {
        guard let threadID = extractThreadID(from: params) else { return }
        let turnID = extractTurnID(from: params)

        let event = AgentTaskEvent(
            kind: .turnStarted,
            agent: .codexDesktop,
            surface: .desktop,
            sessionID: threadID,
            taskID: turnID,
            title: threadTitles[threadID],
            jumpTarget: "codex://threads/\(threadID)"
        )
        emit(event)
    }

    private func handleTurnCompleted(params: [String: Any]) {
        guard let threadID = extractThreadID(from: params) else { return }
        let turnID = extractTurnID(from: params)

        // Determine if the turn succeeded or failed.
        let turnObj = params["turn"] as? [String: Any]
        let status = turnObj?["status"] as? String ?? params["status"] as? String ?? "completed"
        let failed = (status == "failed" || status == "interrupted")

        let event = AgentTaskEvent(
            kind: failed ? .failed : .completed,
            agent: .codexDesktop,
            surface: .desktop,
            sessionID: threadID,
            taskID: turnID,
            title: threadTitles[threadID],
            summary: failed ? "Turn \(status)" : nil,
            jumpTarget: "codex://threads/\(threadID)"
        )
        emit(event)
    }

    private func handleThreadClosed(params: [String: Any]) {
        guard let threadID = extractThreadID(from: params) else { return }
        threadTitles.removeValue(forKey: threadID)
    }

    // MARK: - Helpers

    private func extractThreadID(from params: [String: Any]) -> String? {
        if let threadID = params["threadId"] as? String { return threadID }
        if let threadObj = params["thread"] as? [String: Any] {
            return threadObj["id"] as? String
        }
        return nil
    }

    private func extractTurnID(from params: [String: Any]) -> String? {
        if let turnID = params["turnId"] as? String { return turnID }
        if let turnObj = params["turn"] as? [String: Any] {
            return turnObj["id"] as? String
        }
        return nil
    }

    private func emit(_ event: AgentTaskEvent) {
        NSLog("CodexAppServer: event=\(event.kind.rawValue) session=\(event.sessionID)")
        onEvent?(event)
    }

    private func resolveCodexPath() -> String {
        // Prefer Codex.app bundle if present, otherwise fall back to PATH.
        let appBundle = "/Applications/Codex.app/Contents/Resources/codex"
        if FileManager.default.isExecutableFile(atPath: appBundle) {
            return appBundle
        }
        // Check common nvm/homebrew paths, then default to "codex" via env.
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return "codex"
    }
}
