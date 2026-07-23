import Foundation
import AgentStickCore

let args = CommandLine.arguments
let sourceIndex = args.firstIndex(of: "--source")
let source = sourceIndex.flatMap { index in
    args.indices.contains(index + 1) ? args[index + 1] : nil
} ?? "unknown"
let requestsApproval = args.contains("--approval")

let payload = FileHandle.standardInput.readDataToEndOfFile()
guard !payload.isEmpty else {
    exit(0)
}

let envelope = AgentHookEnvelope(source: source, payload: payload, expectsReply: requestsApproval)
do {
    if requestsApproval {
        let reply = try AgentEventBridgeClient.requestApproval(envelope, to: AgentEventBridgeLocation.defaultSocketURL)
        let behavior = reply.allowed ? "allow" : "deny"
        let decision: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": [
                    "behavior": behavior,
                    "message": reply.allowed ? "Approved in AgentStick" : "Denied in AgentStick"
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: decision)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([UInt8(ascii: "\n")]))
    } else {
        try AgentEventBridgeClient.send(envelope, to: AgentEventBridgeLocation.defaultSocketURL)
    }
} catch {
    // Fail open: hooks must never break Claude Code or Codex when AgentStick is not running.
}
