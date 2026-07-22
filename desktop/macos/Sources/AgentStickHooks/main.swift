import Foundation
import AgentStickCore

let args = CommandLine.arguments
let sourceIndex = args.firstIndex(of: "--source")
let source = sourceIndex.flatMap { index in
    args.indices.contains(index + 1) ? args[index + 1] : nil
} ?? "unknown"

let payload = FileHandle.standardInput.readDataToEndOfFile()
guard !payload.isEmpty else {
    exit(0)
}

let envelope = AgentHookEnvelope(source: source, payload: payload)
do {
    try AgentEventBridgeClient.send(envelope, to: AgentEventBridgeLocation.defaultSocketURL)
} catch {
    // Fail open: hooks must never break Claude Code or Codex when AgentStick is not running.
}
