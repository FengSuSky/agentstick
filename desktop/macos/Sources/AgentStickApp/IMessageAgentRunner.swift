import AppKit
import Foundation

/// Sends a task to an iMessage-based remote agent and waits for its next reply.
///
/// Messages.app has no public API for receiving messages. macOS stores the local
/// message history in `~/Library/Messages/chat.db`, which this runner reads in
/// read-only mode. The user must grant AgentStick Full Disk Access for replies
/// to be detected; Automation permission is needed to send through Messages.
final class IMessageAgentRunner {
    private let messagesDatabaseURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Messages/chat.db")
    private let sqliteURL = URL(fileURLWithPath: "/usr/bin/sqlite3")

    func run(
        task: AgentCLITask,
        recipient: String,
        timeoutSeconds: Int
    ) -> Result<AgentCLIResult, Error> {
        let address = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            return .failure(IMessageError.missingRecipient)
        }
        guard FileManager.default.fileExists(atPath: messagesDatabaseURL.path) else {
            return .failure(IMessageError.messagesDatabaseUnavailable)
        }

        do {
            let lastRowID = try newestMessageRowID(for: address)
            let requestID = String(UUID().uuidString.prefix(8)).uppercased()
            let envelope = """
            [AgentStick:\(requestID)]
            \(task.prompt)

            请完成任务后直接回复结果，并保留 [AgentStick:\(requestID)] 标记。
            """
            try send(envelope, to: address)

            let deadline = Date().addingTimeInterval(TimeInterval(max(10, timeoutSeconds)))
            while Date() < deadline {
                if let reply = try nextReply(for: address, after: lastRowID, requestID: requestID) {
                    let resultURL = try AgentCLIRunner.writeResultFile(
                        task: task,
                        exitCode: 0,
                        stdout: reply,
                        stderr: ""
                    )
                    return .success(AgentCLIResult(
                        task: task,
                        exitCode: 0,
                        stdout: reply,
                        stderr: "",
                        resultURL: resultURL
                    ))
                }
                Thread.sleep(forTimeInterval: 1)
            }
            return .failure(IMessageError.timedOut)
        } catch {
            return .failure(error)
        }
    }

    private func send(_ text: String, to recipient: String) throws {
        let escapedText = appleScriptLiteral(text)
        let escapedRecipient = appleScriptLiteral(recipient)
        let source = """
        tell application "Messages"
            set targetService to 1st service whose service type = iMessage
            set targetBuddy to buddy "\(escapedRecipient)" of targetService
            send "\(escapedText)" to targetBuddy
        end tell
        """
        var scriptError: NSDictionary?
        let execute = {
            NSAppleScript(source: source)?.executeAndReturnError(&scriptError)
        }
        if Thread.isMainThread {
            execute()
        } else {
            DispatchQueue.main.sync(execute: execute)
        }
        if let scriptError {
            throw IMessageError.sendFailed(scriptError[NSAppleScript.errorMessage] as? String ?? "Unknown Messages error")
        }
    }

    private func newestMessageRowID(for recipient: String) throws -> Int64 {
        let query = """
        SELECT COALESCE(MAX(message.ROWID), 0)
        FROM message JOIN handle ON message.handle_id = handle.ROWID
        WHERE handle.id = \(sqlLiteral(recipient));
        """
        return Int64(try sqlite(query).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private func nextReply(for recipient: String, after rowID: Int64, requestID: String) throws -> String? {
        let query = """
        SELECT COALESCE(text, '')
        FROM message JOIN handle ON message.handle_id = handle.ROWID
        WHERE message.is_from_me = 0
          AND handle.id = \(sqlLiteral(recipient))
          AND message.ROWID > \(rowID)
          AND message.text LIKE \(sqlLiteral("%[AgentStick:\(requestID)]%"))
        ORDER BY message.ROWID ASC LIMIT 1;
        """
        let output = try sqlite(query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return nil }
        return output.replacingOccurrences(of: "[AgentStick:\(requestID)]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sqlite(_ query: String) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: sqliteURL.path) else {
            throw IMessageError.messagesDatabaseUnavailable
        }
        let process = Process()
        process.executableURL = sqliteURL
        process.arguments = ["-readonly", messagesDatabaseURL.path, query]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let errorText = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw IMessageError.databaseReadFailed(errorText)
        }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func appleScriptLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }

    private func sqlLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }
}

private enum IMessageError: LocalizedError {
    case missingRecipient
    case messagesDatabaseUnavailable
    case databaseReadFailed(String)
    case sendFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .missingRecipient:
            return currentLanguage == .chinese
                ? "iMessage Agent 未配置联系人。请在 [agents.imessage] 中设置 recipient。"
                : "No iMessage recipient is configured. Set recipient in [agents.imessage]."
        case .messagesDatabaseUnavailable:
            return currentLanguage == .chinese
                ? "无法访问 Messages 数据库。请确认已登录信息，并向 AgentStick 授予“完全磁盘访问”权限。"
                : "Cannot access the Messages database. Sign in to Messages and grant AgentStick Full Disk Access."
        case .databaseReadFailed(let detail):
            return currentLanguage == .chinese
                ? "读取 iMessage 回复失败。请向 AgentStick 授予“完全磁盘访问”权限。\n\(detail)"
                : "Could not read iMessage replies. Grant AgentStick Full Disk Access.\n\(detail)"
        case .sendFailed(let detail):
            return currentLanguage == .chinese
                ? "无法通过信息发送任务。请允许 AgentStick 自动化控制“信息”。\n\(detail)"
                : "Could not send the task through Messages. Allow AgentStick to automate Messages.\n\(detail)"
        case .timedOut:
            return currentLanguage == .chinese ? "等待 iMessage Agent 回复超时" : "Timed out waiting for the iMessage agent reply"
        }
    }
}
