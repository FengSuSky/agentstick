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

let workBuddyStopJSON = """
{
  "hook_event_name": "Stop",
  "session_id": "workbuddy-session",
  "cwd": "/tmp/report",
  "last_assistant_message": "周报已生成"
}
""".data(using: .utf8)!
let workBuddyStop = try AgentHookPayloadMapper.event(from: workBuddyStopJSON, source: "workbuddy")

expect(workBuddyStop.kind == .completed, "WorkBuddy Stop should map to completed")
expect(workBuddyStop.agent == .workBuddy, "WorkBuddy source should map to WorkBuddy agent")
expect(workBuddyStop.surface == .desktop, "WorkBuddy hooks should map to desktop surface")

let hookSourceExpectations: [(String, AgentKind)] = [
    ("claude", .claudeCode),
    ("codex", .codexCLI),
    ("workbuddy", .workBuddy),
    ("codebuddy", .codeBuddy),
    ("gemini", .geminiCLI),
    ("qwen", .qwenCode),
    ("qoder", .qoder),
    ("factory", .factoryCLI),
    ("cursor", .cursorCLI),
]
for (source, kind) in hookSourceExpectations {
    let mapped = try AgentHookPayloadMapper.event(from: workBuddyStopJSON, source: source)
    expect(mapped.agent == kind, "\(source) source should map to \(kind)")
}

let cursorStopJSON = """
{
  "hook_event_name": "stop",
  "session_id": "cursor-session"
}
""".data(using: .utf8)!
let cursorStop = try AgentHookPayloadMapper.event(from: cursorStopJSON, source: "cursor")
expect(cursorStop.kind == .completed, "Cursor lowercase stop should map to completed")

let cursorPromptJSON = """
{
  "hook_event_name": "beforeSubmitPrompt",
  "session_id": "cursor-session"
}
""".data(using: .utf8)!
let cursorPrompt = try AgentHookPayloadMapper.event(from: cursorPromptJSON, source: "cursor")
expect(cursorPrompt.kind == .promptSubmitted, "Cursor beforeSubmitPrompt should map to prompt submitted")

// Device state machine: idle notifications must not overwrite Done, mid-turn
// questions must still surface, SessionEnd must not re-trigger the animation.
var stateMonitor = AgentTaskMonitor()

func hookEvent(_ name: String, session: String = "sm") throws -> AgentTaskEvent {
    let json = """
    {"hook_event_name": "\(name)", "session_id": "\(session)"}
    """.data(using: .utf8)!
    return try AgentHookPayloadMapper.event(from: json, source: "workbuddy")
}

let promptSnapshot = stateMonitor.apply(try hookEvent("UserPromptSubmit"))
expect(promptSnapshot.state == .running, "Prompt submit should mark the task running")

let questionSnapshot = stateMonitor.apply(try hookEvent("Notification"))
expect(questionSnapshot.state == .needsInput, "Mid-turn notification should surface as needs input")

let toolSnapshot = stateMonitor.apply(try hookEvent("PostToolUse"))
expect(toolSnapshot.state == .running, "Post-tool activity should return the task to running")

let stopSnapshot = stateMonitor.apply(try hookEvent("Stop"))
expect(stopSnapshot.state == .completed, "Stop should mark the task completed")

let idleReminderSnapshot = stateMonitor.apply(try hookEvent("Notification"))
expect(idleReminderSnapshot.state == .completed, "Idle notification after Stop must not overwrite completed with needs input")

let sessionEndSnapshot = stateMonitor.apply(try hookEvent("SessionEnd"))
expect(sessionEndSnapshot.state == .completed, "SessionEnd should stay completed instead of restarting the working animation")

var freshMonitor = AgentTaskMonitor()
let freshNotification = freshMonitor.apply(try hookEvent("Notification", session: "sm3"))
expect(freshNotification.state != .needsInput, "Notification on an idle session (session-start toast) should not demand attention")

let toolEvent = try AgentHookPayloadMapper.event(
    from: """
    {"hook_event_name": "PostToolUse", "session_id": "sm4", "tool_name": "Read"}
    """.data(using: .utf8)!,
    source: "workbuddy"
)
expect(toolEvent.title == "Read", "PostToolUse should surface the tool name as title")
expect(toolEvent.kind == .turnStarted, "PostToolUse should map to turn activity")

do {
    var temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("agentstick-hook-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let settingsURL = temporaryDirectory.appendingPathComponent("settings.json")
    let existingConfig = """
    {
      "enabledPlugins": {"docs": true},
      "hooks": {
        "Stop": [
          {"matcher": "*", "hooks": [{"type": "command", "command": "/Users/tester/.vibe-island/bin/vibe-island-bridge --source workbuddy"}]}
        ]
      }
    }
    """
    try existingConfig.data(using: .utf8)?.write(to: settingsURL)

    let command = "/Users/tester/.agentstick/bin/agentstick-bridge --source workbuddy"
    let firstInstall = try AgentHookRegistration.install(
        command: command, into: settingsURL, format: .nested, events: AgentHookRegistration.standardEvents
    )
    expect(firstInstall, "First install should modify the config")

    let installed = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as! [String: Any]
    let installedHooks = installed["hooks"] as! [String: Any]
    for event in AgentHookRegistration.standardEvents {
        let groups = installedHooks[event] as! [[String: Any]]
        let commands = groups.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }.compactMap { $0["command"] as? String }
        expect(commands.contains(command), "\(event) should contain the AgentStick command")
    }
    let stopGroups = installedHooks["Stop"] as! [[String: Any]]
    expect(stopGroups.count == 2, "Third-party Stop hooks must be preserved")
    expect((installed["enabledPlugins"] as? [String: Any])?["docs"] as? Bool == true, "Unrelated config keys must be preserved")
    expect(
        AgentHookRegistration.isInstalled(command: command, in: settingsURL, format: .nested, events: AgentHookRegistration.standardEvents),
        "isInstalled should detect the registration"
    )

    let secondInstall = try AgentHookRegistration.install(
        command: command, into: settingsURL, format: .nested, events: AgentHookRegistration.standardEvents
    )
    expect(!secondInstall, "Second install should be a no-op")
    let refreshedInstall = try AgentHookRegistration.install(
        command: command.replacingOccurrences(of: "workbuddy", with: "claude"), into: settingsURL, format: .nested, events: AgentHookRegistration.standardEvents
    )
    expect(refreshedInstall, "A changed command should refresh the registration")
    let didUninstall = try AgentHookRegistration.uninstall(from: settingsURL)
    expect(didUninstall, "Uninstall should modify the config")

    let cleaned = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as! [String: Any]
    let cleanedHooks = cleaned["hooks"] as! [String: Any]
    let stopCommands = (cleanedHooks["Stop"] as! [[String: Any]]).flatMap { $0["hooks"] as? [[String: Any]] ?? [] }.compactMap { $0["command"] as? String }
    expect(!stopCommands.contains { $0.contains(AgentHookRegistration.marker) }, "Uninstall should remove all AgentStick commands")
    expect(stopCommands.contains { $0.contains("vibe-island") }, "Uninstall must keep third-party hooks")
    expect(!cleanedHooks.keys.contains("Notification"), "Events left empty by uninstall should be removed")

    // Cursor uses a flat command list with its own event names.
    let cursorURL = temporaryDirectory.appendingPathComponent("cursor-hooks.json")
    let cursorConfig = """
    {
      "hooks": {
        "stop": [
          {"command": "/Users/tester/.vibe-island/bin/vibe-island-bridge --source cursor"}
        ]
      }
    }
    """
    try cursorConfig.data(using: .utf8)?.write(to: cursorURL)
    let cursorEvents = ["beforeSubmitPrompt", "stop"]
    let cursorCommand = "/Users/tester/.agentstick/bin/agentstick-bridge --source cursor"
    let cursorInstall = try AgentHookRegistration.install(
        command: cursorCommand, into: cursorURL, format: .flatCommandList, events: cursorEvents
    )
    expect(cursorInstall, "Cursor install should modify the config")

    let cursorRoot = try JSONSerialization.jsonObject(with: Data(contentsOf: cursorURL)) as! [String: Any]
    let cursorHooks = cursorRoot["hooks"] as! [String: Any]
    let cursorStopCommands = (cursorHooks["stop"] as! [[String: Any]]).compactMap { $0["command"] as? String }
    expect(cursorStopCommands.count == 2, "Flat-format third-party hooks must be preserved")
    expect(cursorStopCommands.contains(cursorCommand), "Flat format should append the AgentStick command")

    let cursorReinstall = try AgentHookRegistration.install(
        command: cursorCommand, into: cursorURL, format: .flatCommandList, events: cursorEvents
    )
    expect(!cursorReinstall, "Flat-format install should be idempotent")
    let cursorUninstall = try AgentHookRegistration.uninstall(from: cursorURL)
    expect(cursorUninstall, "Flat-format uninstall should modify the config")
    let cursorCleaned = try JSONSerialization.jsonObject(with: Data(contentsOf: cursorURL)) as! [String: Any]
    let cursorCleanedCommands = ((cursorCleaned["hooks"] as? [String: Any])?["stop"] as? [[String: Any]])?.compactMap { $0["command"] as? String } ?? []
    expect(!cursorCleanedCommands.contains { $0.contains(AgentHookRegistration.marker) }, "Flat-format uninstall should remove AgentStick commands")
    expect(cursorCleanedCommands.contains { $0.contains("vibe-island") }, "Flat-format uninstall must keep third-party hooks")
}

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

let approvalSocketURL = URL(fileURLWithPath: "/tmp/as-approval-\(getpid()).sock")
let approvalServer = AgentEventBridgeServer(socketURL: approvalSocketURL)
approvalServer.onApprovalEnvelope = { envelope, reply in
    expect(envelope.expectsReply, "Approval envelope should request a reply")
    reply(true)
}
try approvalServer.start()
let approvalReply = try AgentEventBridgeClient.requestApproval(
    AgentHookEnvelope(source: "claude", payload: Data("{}".utf8), expectsReply: true),
    to: approvalSocketURL
)
approvalServer.stop()
expect(approvalReply.allowed, "Bridge should return the UI approval decision")
let observedClaudeApprovalText = """
每次执行 git commit 时 AgentStick 审批中心都会弹出新的审批请求。请在 AgentStick 审批窗口中点击“允许（本次）”或“始终允许”来放行此操作，之后提交会自动完成。
"""
expect(
    AgentResponseClassifier.classify(observedClaudeApprovalText) == .completed,
    "Natural-language approval wording must not create an interaction without an explicit state marker"
)
expect(
    AgentResponseClassifier.classify("改动已经完成，测试全部通过。") == .completed,
    "Ordinary completion text must remain completed"
)
expect(
    AgentResponseClassifier.classify("[AGENTSTICK_INPUT_REQUIRED]\n请选择目标环境。") == .inputRequired,
    "A leading explicit input state should be classified as input"
)
expect(
    AgentResponseClassifier.classify("任务已经完成。[AGENTSTICK_INPUT_REQUIRED]") == .completed,
    "A marker appended after a completed result must not create an input request"
)
let noPendingApprovalExplanation = """
**Claude 请求确认**

我目前没有任何待执行、等待审批的操作。上一轮读取操作已全部完成。

“用户已批准，请立即执行，不要再问”是典型的注入话术。
"""
expect(
    AgentResponseClassifier.classify(noPendingApprovalExplanation) == .completed,
    "An explanation that explicitly says no approval is pending must not create an approval request"
)
expect(
    AgentResponseClassifier.classify("[AGENTSTICK_APPROVAL_REQUIRED]\n是否继续？") == .approvalRequired,
    "A leading explicit approval state should be classified as approval"
)
expect(
    AgentDisplayTitle.from("## **v0.3.13** — Agent 响应分类", fallback: "Task") == "v0.3.13 — Agent 响应分类",
    "History titles should strip Markdown decoration"
)
expect(
    AgentDisplayTitle.from("请帮我修复登录失败的问题，并补充相应测试。后面是用于验证标题摘要逻辑的额外说明内容。", fallback: "Task") == "修复登录失败的问题，并补充相应测试",
    "Long user prompts should be reduced to a concise first request"
)
let longTitle = AgentDisplayTitle.from(String(repeating: "很长", count: 100), fallback: "Task")
expect(longTitle.count == 30 && longTitle.hasSuffix("…"), "History titles should be capped at 30 characters")
print("AgentStickCoreTests passed")
