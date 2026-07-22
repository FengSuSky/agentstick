import Foundation
import AgentStickCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let event = AgentTaskEvent(
    kind: .completed,
    agent: .codexDesktop,
    surface: .desktop,
    sessionID: "thread-1",
    taskID: "turn-2",
    cwd: "/tmp/project",
    title: "Fix login test",
    summary: "Done",
    jumpTarget: "codex://threads/thread-1",
    occurredAt: Date(timeIntervalSince1970: 1_800_000_000)
)

let data = try JSONEncoder().encode(event)
let decoded = try JSONDecoder().decode(AgentTaskEvent.self, from: data)

expect(decoded == event, "AgentTaskEvent should round-trip through JSON")

let claudeStopJSON = """
{
  "hook_event_name": "Stop",
  "session_id": "claude-session",
  "cwd": "/tmp/app",
  "last_assistant_message": "All tests pass."
}
""".data(using: .utf8)!
let claudeStop = try AgentHookPayloadMapper.event(from: claudeStopJSON, source: "claude")

expect(claudeStop.kind == .completed, "Claude Stop should map to completed")
expect(claudeStop.agent == .claudeCode, "Claude source should map to Claude Code")
expect(claudeStop.surface == .cli, "Claude hooks should map to CLI surface")
expect(claudeStop.sessionID == "claude-session", "Claude session id should decode")
expect(claudeStop.summary == "All tests pass.", "Claude final summary should decode")

let codexStopJSON = """
{
  "hook_event_name": "Stop",
  "session_id": "codex-session",
  "turn_id": "turn-1",
  "cwd": "/tmp/app",
  "last_assistant_message": "Done."
}
""".data(using: .utf8)!
let codexStop = try AgentHookPayloadMapper.event(from: codexStopJSON, source: "codex")

expect(codexStop.kind == .completed, "Codex Stop should map to completed")
expect(codexStop.agent == .codexCLI, "Codex source should map to Codex CLI")
expect(codexStop.taskID == "turn-1", "Codex turn id should decode")
expect(codexStop.summary == "Done.", "Codex final summary should decode")

var monitor = AgentTaskMonitor()
monitor.apply(AgentTaskEvent(
    kind: .promptSubmitted,
    agent: .claudeCode,
    surface: .cli,
    sessionID: "s1",
    title: "Fix bug",
    occurredAt: Date(timeIntervalSince1970: 10)
))
let completedSnapshot = monitor.apply(AgentTaskEvent(
    kind: .completed,
    agent: .claudeCode,
    surface: .cli,
    sessionID: "s1",
    summary: "Done",
    occurredAt: Date(timeIntervalSince1970: 11)
))

expect(completedSnapshot.state == .completed, "Completed event should produce completed state")
expect(completedSnapshot.agent == .claudeCode, "Snapshot should keep agent")
expect(completedSnapshot.title == "Fix bug", "Snapshot should keep earlier title")
expect(completedSnapshot.summary == "Done", "Snapshot should use completion summary")

monitor.apply(AgentTaskEvent(
    kind: .turnStarted,
    agent: .codexCLI,
    surface: .cli,
    sessionID: "s2"
))
let failedSnapshot = monitor.apply(AgentTaskEvent(
    kind: .failed,
    agent: .codexCLI,
    surface: .cli,
    sessionID: "s2",
    summary: "Failed"
))

expect(failedSnapshot.state == .failed, "Failed event should override running state")
expect(failedSnapshot.summary == "Failed", "Failure summary should be retained")

let envelope = AgentHookEnvelope(source: "codex", payload: Data("{\"ok\":true}".utf8))
let encodedEnvelope = try JSONEncoder().encode(envelope)
let decodedEnvelope = try JSONDecoder().decode(AgentHookEnvelope.self, from: encodedEnvelope)
expect(decodedEnvelope.source == "codex", "Envelope source should round-trip")
expect(String(data: decodedEnvelope.payload, encoding: .utf8) == "{\"ok\":true}", "Envelope payload should round-trip")

let socketURL = URL(fileURLWithPath: "/tmp/as-\(getpid()).sock")
let bridgeServer = AgentEventBridgeServer(socketURL: socketURL)
let semaphore = DispatchSemaphore(value: 0)
var receivedEnvelope: AgentHookEnvelope?
bridgeServer.onEnvelope = { envelope in
    receivedEnvelope = envelope
    semaphore.signal()
}
try bridgeServer.start()
try AgentEventBridgeClient.send(AgentHookEnvelope(source: "claude", payload: Data("{\"hello\":true}".utf8)), to: socketURL)
let waitResult = semaphore.wait(timeout: .now() + 2)
bridgeServer.stop()
expect(waitResult == .success, "Bridge server should receive client envelope")
expect(receivedEnvelope?.source == "claude", "Bridge should preserve source")
expect(String(data: receivedEnvelope?.payload ?? Data(), encoding: .utf8) == "{\"hello\":true}", "Bridge should preserve payload")
print("AgentStickCoreTests passed")
