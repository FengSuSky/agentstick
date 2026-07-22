# Agent Task Capture And Fixed Sound Alerts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture Claude Code, Codex CLI, and Codex Desktop task lifecycle events in the AgentStick macOS app, forward completion/failure/attention states to the ESP32 device, and play fixed firmware-resident alert sounds.

**Architecture:** Implement a local-first event bridge modeled after Open Island's hook/app-server architecture, but with AgentStick-owned code and protocol types. Agent hooks and Codex Desktop app-server events normalize into `AgentTaskEvent`, flow through an `AgentTaskMonitor`, and drive existing BLE `ui_state` plus a new `play_sound` control event. Fixed audio lives in firmware; macOS sends only symbolic sound names.

**Tech Stack:** Swift 5.9 / AppKit / Foundation / Unix domain sockets / JSON, Swift Package Manager tests, ESP-IDF C firmware, existing AgentStick BLE control protocol.

---

## Scope Decisions

- Do not implement macOS TTS.
- Do not stream audio from Mac to device.
- Do not copy code from Open Island; use it only as an implementation reference because its repository is GPLv3.
- First implementation supports status capture and fixed sound playback. Permission approve/deny can be modeled but should not block this milestone.
- Hooks must fail open: if AgentStick is not running, Claude Code and Codex continue normally.

## File Structure

- Modify `desktop/macos/Package.swift` to add:
  - `AgentStickCore` library target for testable models and bridge logic.
  - `AgentStickHooks` executable target for hook forwarding.
  - `AgentStickAppTests` test target.
- Create `desktop/macos/Sources/AgentStickCore/AgentTaskEvent.swift` for normalized lifecycle models.
- Create `desktop/macos/Sources/AgentStickCore/AgentHookPayloads.swift` for minimal Claude/Codex hook decoding.
- Create `desktop/macos/Sources/AgentStickCore/AgentTaskMonitor.swift` for task state reduction.
- Create `desktop/macos/Sources/AgentStickCore/AgentEventBridge.swift` for Unix socket server/client helpers.
- Create `desktop/macos/Sources/AgentStickHooks/main.swift` for the fail-open hook CLI.
- Create `desktop/macos/Sources/AgentStickApp/AgentTaskCaptureController.swift` to connect the bridge, monitor, Codex app-server, and BLE coordinator callbacks.
- Modify `desktop/macos/Sources/AgentStickApp/VoiceStickCoordinator.swift` to emit device task status and fixed sound commands.
- Modify `desktop/macos/Sources/AgentStickApp/BleProtocol.swift` and `BleCentral.swift` to support `play_sound`.
- Modify `desktop/macos/Sources/AgentStickApp/AppDelegate.swift` to start/stop task capture.
- Modify `desktop/macos/Sources/AgentStickApp/AppConfig.swift` and `desktop/macos/Config/config.example.toml` to add capture/sound settings.
- Create `desktop/macos/Sources/AgentStickApp/CodexAppServerClient.swift` for Codex Desktop JSON-RPC lifecycle events.
- Create `desktop/macos/Sources/AgentStickApp/AgentHookInstallers.swift` for managed hook install/status/uninstall.
- Modify `firmware/main/main.c` to parse `play_sound`.
- Create `firmware/components/audio_pipeline/include/audio_playback.h` and `firmware/components/audio_pipeline/audio_playback.c` for fixed sound playback.
- Modify `firmware/components/audio_pipeline/CMakeLists.txt` to compile playback support.
- Add fixed audio assets under `firmware/components/audio_pipeline/assets/`.
- Modify `docs/protocol.md` with the new control event.

---

### Task 1: Make Core Logic Testable

**Files:**
- Modify: `desktop/macos/Package.swift`
- Create: `desktop/macos/Sources/AgentStickCore/AgentTaskEvent.swift`
- Create: `desktop/macos/Tests/AgentStickAppTests/AgentTaskEventTests.swift`

- [ ] **Step 1: Add library, hook executable, and test target**

Update `desktop/macos/Package.swift` so the target list includes:

```swift
.target(
    name: "AgentStickCore",
    dependencies: []
),
.executableTarget(
    name: "AgentStickHooks",
    dependencies: ["AgentStickCore"],
    path: "Sources/AgentStickHooks"
),
.testTarget(
    name: "AgentStickAppTests",
    dependencies: ["AgentStickCore"],
    path: "Tests/AgentStickAppTests"
)
```

Then add `"AgentStickCore"` as a dependency of the existing `AgentStickApp` executable target.

- [ ] **Step 2: Create normalized task event models**

Create `desktop/macos/Sources/AgentStickCore/AgentTaskEvent.swift`:

```swift
import Foundation

public enum AgentKind: String, Codable, Sendable, Equatable {
    case claudeCode = "claude_code"
    case codexCLI = "codex_cli"
    case codexDesktop = "codex_desktop"
    case unknown
}

public enum AgentSurface: String, Codable, Sendable, Equatable {
    case cli
    case desktop
}

public enum AgentTaskEventKind: String, Codable, Sendable, Equatable {
    case sessionStarted = "session_started"
    case promptSubmitted = "prompt_submitted"
    case turnStarted = "turn_started"
    case waitingForApproval = "waiting_for_approval"
    case needsInput = "needs_input"
    case completed
    case failed
}

public struct AgentTaskEvent: Codable, Sendable, Equatable {
    public var kind: AgentTaskEventKind
    public var agent: AgentKind
    public var surface: AgentSurface
    public var sessionID: String
    public var taskID: String?
    public var cwd: String?
    public var title: String?
    public var summary: String?
    public var jumpTarget: String?
    public var occurredAt: Date

    public init(
        kind: AgentTaskEventKind,
        agent: AgentKind,
        surface: AgentSurface,
        sessionID: String,
        taskID: String? = nil,
        cwd: String? = nil,
        title: String? = nil,
        summary: String? = nil,
        jumpTarget: String? = nil,
        occurredAt: Date = Date()
    ) {
        self.kind = kind
        self.agent = agent
        self.surface = surface
        self.sessionID = sessionID
        self.taskID = taskID
        self.cwd = cwd
        self.title = title
        self.summary = summary
        self.jumpTarget = jumpTarget
        self.occurredAt = occurredAt
    }
}
```

- [ ] **Step 3: Add model encoding test**

Create `desktop/macos/Tests/AgentStickAppTests/AgentTaskEventTests.swift`:

```swift
import XCTest
@testable import AgentStickCore

final class AgentTaskEventTests: XCTestCase {
    func testRoundTripsNormalizedEvent() throws {
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

        XCTAssertEqual(decoded, event)
    }
}
```

- [ ] **Step 4: Run the focused test**

Run:

```bash
cd desktop/macos
swift test --filter AgentTaskEventTests
```

Expected: test passes after the target wiring and model are in place.

- [ ] **Step 5: Commit**

```bash
git add desktop/macos/Package.swift desktop/macos/Sources/AgentStickCore/AgentTaskEvent.swift desktop/macos/Tests/AgentStickAppTests/AgentTaskEventTests.swift
git commit -m "test: add agent task event core model"
```

---

### Task 2: Decode Claude And Codex Hook Payloads

**Files:**
- Create: `desktop/macos/Sources/AgentStickCore/AgentHookPayloads.swift`
- Create: `desktop/macos/Tests/AgentStickAppTests/AgentHookPayloadTests.swift`

- [ ] **Step 1: Write failing hook mapping tests**

Create `desktop/macos/Tests/AgentStickAppTests/AgentHookPayloadTests.swift`:

```swift
import XCTest
@testable import AgentStickCore

final class AgentHookPayloadTests: XCTestCase {
    func testClaudeStopMapsToCompletedEvent() throws {
        let json = """
        {
          "hook_event_name": "Stop",
          "session_id": "claude-session",
          "cwd": "/tmp/app",
          "last_assistant_message": "All tests pass."
        }
        """.data(using: .utf8)!

        let event = try AgentHookPayloadMapper.event(from: json, source: "claude")

        XCTAssertEqual(event.kind, .completed)
        XCTAssertEqual(event.agent, .claudeCode)
        XCTAssertEqual(event.surface, .cli)
        XCTAssertEqual(event.sessionID, "claude-session")
        XCTAssertEqual(event.summary, "All tests pass.")
    }

    func testCodexStopMapsToCompletedEvent() throws {
        let json = """
        {
          "hook_event_name": "Stop",
          "session_id": "codex-session",
          "turn_id": "turn-1",
          "cwd": "/tmp/app",
          "last_assistant_message": "Done."
        }
        """.data(using: .utf8)!

        let event = try AgentHookPayloadMapper.event(from: json, source: "codex")

        XCTAssertEqual(event.kind, .completed)
        XCTAssertEqual(event.agent, .codexCLI)
        XCTAssertEqual(event.taskID, "turn-1")
        XCTAssertEqual(event.summary, "Done.")
    }
}
```

- [ ] **Step 2: Implement minimal decoder**

Create `desktop/macos/Sources/AgentStickCore/AgentHookPayloads.swift`:

```swift
import Foundation

public enum AgentHookPayloadError: Error, Equatable {
    case unsupportedSource(String)
    case missingSessionID
}

public struct AgentHookPayloadMapper {
    private struct GenericHookPayload: Decodable {
        var hookEventName: String
        var sessionID: String?
        var cwd: String?
        var turnID: String?
        var prompt: String?
        var message: String?
        var title: String?
        var lastAssistantMessage: String?
        var error: String?

        private enum CodingKeys: String, CodingKey {
            case hookEventName = "hook_event_name"
            case sessionID = "session_id"
            case cwd
            case turnID = "turn_id"
            case prompt
            case message
            case title
            case lastAssistantMessage = "last_assistant_message"
            case error
        }
    }

    public static func event(from data: Data, source: String, occurredAt: Date = Date()) throws -> AgentTaskEvent {
        let payload = try JSONDecoder().decode(GenericHookPayload.self, from: data)
        guard let sessionID = payload.sessionID, !sessionID.isEmpty else {
            throw AgentHookPayloadError.missingSessionID
        }

        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let agent: AgentKind
        switch normalizedSource {
        case "claude":
            agent = .claudeCode
        case "codex":
            agent = .codexCLI
        default:
            throw AgentHookPayloadError.unsupportedSource(source)
        }

        return AgentTaskEvent(
            kind: kind(for: payload.hookEventName),
            agent: agent,
            surface: .cli,
            sessionID: sessionID,
            taskID: payload.turnID,
            cwd: payload.cwd,
            title: payload.title ?? payload.prompt,
            summary: payload.lastAssistantMessage ?? payload.message ?? payload.error,
            occurredAt: occurredAt
        )
    }

    private static func kind(for hookEventName: String) -> AgentTaskEventKind {
        switch hookEventName {
        case "SessionStart":
            return .sessionStarted
        case "UserPromptSubmit":
            return .promptSubmitted
        case "PermissionRequest", "PreToolUse":
            return .waitingForApproval
        case "Notification":
            return .needsInput
        case "Stop":
            return .completed
        case "StopFailure", "PostToolUseFailure":
            return .failed
        default:
            return .turnStarted
        }
    }
}
```

- [ ] **Step 3: Run tests**

```bash
cd desktop/macos
swift test --filter AgentHookPayloadTests
```

Expected: both tests pass.

- [ ] **Step 4: Commit**

```bash
git add desktop/macos/Sources/AgentStickCore/AgentHookPayloads.swift desktop/macos/Tests/AgentStickAppTests/AgentHookPayloadTests.swift
git commit -m "feat: decode agent hook lifecycle events"
```

---

### Task 3: Add Task Monitor State Reduction

**Files:**
- Create: `desktop/macos/Sources/AgentStickCore/AgentTaskMonitor.swift`
- Create: `desktop/macos/Tests/AgentStickAppTests/AgentTaskMonitorTests.swift`

- [ ] **Step 1: Write monitor tests**

Create `desktop/macos/Tests/AgentStickAppTests/AgentTaskMonitorTests.swift`:

```swift
import XCTest
@testable import AgentStickCore

final class AgentTaskMonitorTests: XCTestCase {
    func testPromptThenCompletedProducesDoneSnapshot() {
        var monitor = AgentTaskMonitor()
        monitor.apply(.init(kind: .promptSubmitted, agent: .claudeCode, surface: .cli, sessionID: "s1", title: "Fix bug"))
        let snapshot = monitor.apply(.init(kind: .completed, agent: .claudeCode, surface: .cli, sessionID: "s1", summary: "Done"))

        XCTAssertEqual(snapshot.state, .completed)
        XCTAssertEqual(snapshot.agent, .claudeCode)
        XCTAssertEqual(snapshot.title, "Fix bug")
        XCTAssertEqual(snapshot.summary, "Done")
    }

    func testFailureOverridesRunning() {
        var monitor = AgentTaskMonitor()
        monitor.apply(.init(kind: .turnStarted, agent: .codexCLI, surface: .cli, sessionID: "s2"))
        let snapshot = monitor.apply(.init(kind: .failed, agent: .codexCLI, surface: .cli, sessionID: "s2", summary: "Failed"))

        XCTAssertEqual(snapshot.state, .failed)
        XCTAssertEqual(snapshot.summary, "Failed")
    }
}
```

- [ ] **Step 2: Implement monitor**

Create `desktop/macos/Sources/AgentStickCore/AgentTaskMonitor.swift`:

```swift
import Foundation

public enum AgentTaskState: String, Codable, Sendable, Equatable {
    case idle
    case running
    case waitingForApproval = "waiting_for_approval"
    case needsInput = "needs_input"
    case completed
    case failed
}

public struct AgentTaskSnapshot: Codable, Sendable, Equatable {
    public var sessionID: String
    public var taskID: String?
    public var agent: AgentKind
    public var surface: AgentSurface
    public var state: AgentTaskState
    public var cwd: String?
    public var title: String?
    public var summary: String?
    public var jumpTarget: String?
    public var updatedAt: Date
}

public struct AgentTaskMonitor {
    private var snapshots: [String: AgentTaskSnapshot] = [:]

    public init() {}

    @discardableResult
    public mutating func apply(_ event: AgentTaskEvent) -> AgentTaskSnapshot {
        var snapshot = snapshots[event.sessionID] ?? AgentTaskSnapshot(
            sessionID: event.sessionID,
            taskID: event.taskID,
            agent: event.agent,
            surface: event.surface,
            state: .idle,
            cwd: event.cwd,
            title: event.title,
            summary: event.summary,
            jumpTarget: event.jumpTarget,
            updatedAt: event.occurredAt
        )

        snapshot.taskID = event.taskID ?? snapshot.taskID
        snapshot.cwd = event.cwd ?? snapshot.cwd
        snapshot.title = event.title ?? snapshot.title
        snapshot.summary = event.summary ?? snapshot.summary
        snapshot.jumpTarget = event.jumpTarget ?? snapshot.jumpTarget
        snapshot.updatedAt = event.occurredAt

        switch event.kind {
        case .sessionStarted:
            snapshot.state = .idle
        case .promptSubmitted, .turnStarted:
            snapshot.state = .running
        case .waitingForApproval:
            snapshot.state = .waitingForApproval
        case .needsInput:
            snapshot.state = .needsInput
        case .completed:
            snapshot.state = .completed
        case .failed:
            snapshot.state = .failed
        }

        snapshots[event.sessionID] = snapshot
        return snapshot
    }

    public func snapshot(sessionID: String) -> AgentTaskSnapshot? {
        snapshots[sessionID]
    }

    public var allSnapshots: [AgentTaskSnapshot] {
        snapshots.values.sorted { $0.updatedAt > $1.updatedAt }
    }
}
```

- [ ] **Step 3: Run tests**

```bash
cd desktop/macos
swift test --filter AgentTaskMonitorTests
```

Expected: tests pass.

- [ ] **Step 4: Commit**

```bash
git add desktop/macos/Sources/AgentStickCore/AgentTaskMonitor.swift desktop/macos/Tests/AgentStickAppTests/AgentTaskMonitorTests.swift
git commit -m "feat: reduce agent events into task state"
```

---

### Task 4: Implement Fail-Open Hook Bridge

**Files:**
- Create: `desktop/macos/Sources/AgentStickCore/AgentEventBridge.swift`
- Create: `desktop/macos/Sources/AgentStickHooks/main.swift`
- Create: `desktop/macos/Tests/AgentStickAppTests/AgentEventBridgeTests.swift`

- [ ] **Step 1: Write bridge envelope test**

Create `desktop/macos/Tests/AgentStickAppTests/AgentEventBridgeTests.swift`:

```swift
import XCTest
@testable import AgentStickCore

final class AgentEventBridgeTests: XCTestCase {
    func testEnvelopeRoundTrip() throws {
        let envelope = AgentHookEnvelope(source: "codex", payload: Data("{\"ok\":true}".utf8))
        let encoded = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(AgentHookEnvelope.self, from: encoded)

        XCTAssertEqual(decoded.source, "codex")
        XCTAssertEqual(String(data: decoded.payload, encoding: .utf8), "{\"ok\":true}")
    }
}
```

- [ ] **Step 2: Implement bridge envelope and socket location**

Create `desktop/macos/Sources/AgentStickCore/AgentEventBridge.swift` with:

```swift
import Foundation

public struct AgentHookEnvelope: Codable, Sendable, Equatable {
    public var source: String
    public var payload: Data

    public init(source: String, payload: Data) {
        self.source = source
        self.payload = payload
    }
}

public enum AgentEventBridgeLocation {
    public static var defaultSocketURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AgentStick/agent-events.sock")
    }
}
```

Then add the Unix socket server/client implementation in the same file with these public APIs:

```swift
import Darwin

public final class AgentEventBridgeServer: @unchecked Sendable {
    public var onEnvelope: ((AgentHookEnvelope) -> Void)?

    public init(socketURL: URL = AgentEventBridgeLocation.defaultSocketURL)
    public func start() throws
    public func stop()
}

public enum AgentEventBridgeClient {
    public static func send(_ envelope: AgentHookEnvelope, to socketURL: URL) throws
}
```

Use `socket(AF_UNIX, SOCK_STREAM, 0)`, `bind`, `listen`, and `DispatchSourceRead` for the server. Each client connection sends one newline-terminated JSON envelope and closes. The client connects to `socketURL`, writes `JSONEncoder().encode(envelope) + "\n"`, then closes the file descriptor. Use Open Island only as a reference for the Unix socket pattern. Keep the AgentStick implementation minimal: one envelope per connection, no directives in this milestone.

- [ ] **Step 3: Implement fail-open hook executable**

Create `desktop/macos/Sources/AgentStickHooks/main.swift`:

```swift
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
    // Fail open: never block or fail the agent because AgentStick is unavailable.
}
```

- [ ] **Step 4: Run tests and build hook CLI**

```bash
cd desktop/macos
swift test --filter AgentEventBridgeTests
swift build --product AgentStickHooks
```

Expected: test passes and `AgentStickHooks` builds.

- [ ] **Step 5: Commit**

```bash
git add desktop/macos/Sources/AgentStickCore/AgentEventBridge.swift desktop/macos/Sources/AgentStickHooks/main.swift desktop/macos/Tests/AgentStickAppTests/AgentEventBridgeTests.swift
git commit -m "feat: add fail-open agent hook bridge"
```

---

### Task 5: Wire Bridge Events Into The macOS App

**Files:**
- Create: `desktop/macos/Sources/AgentStickApp/AgentTaskCaptureController.swift`
- Modify: `desktop/macos/Sources/AgentStickApp/AppDelegate.swift`
- Modify: `desktop/macos/Sources/AgentStickApp/VoiceStickCoordinator.swift`

- [ ] **Step 1: Create capture controller**

Create `desktop/macos/Sources/AgentStickApp/AgentTaskCaptureController.swift`:

```swift
import Foundation
import AgentStickCore

final class AgentTaskCaptureController {
    private let bridge = AgentEventBridgeServer()
    private var monitor = AgentTaskMonitor()
    var onSnapshot: ((AgentTaskSnapshot) -> Void)?

    func start() {
        bridge.onEnvelope = { [weak self] envelope in
            guard let self else { return }
            do {
                let event = try AgentHookPayloadMapper.event(from: envelope.payload, source: envelope.source)
                let snapshot = self.monitor.apply(event)
                DispatchQueue.main.async {
                    self.onSnapshot?(snapshot)
                }
            } catch {
                NSLog("Agent hook decode failed: \(error)")
            }
        }
        do {
            try bridge.start()
        } catch {
            NSLog("Agent event bridge start failed: \(error)")
        }
    }

    func stop() {
        bridge.stop()
    }
}
```

Keep this responsibility boundary fixed: bridge receives envelopes, mapper normalizes events, monitor reduces state, app receives snapshots.

- [ ] **Step 2: Add coordinator entry point**

In `VoiceStickCoordinator.swift`, add:

```swift
func handleAgentTaskSnapshot(_ snapshot: AgentTaskSnapshot) {
    switch snapshot.state {
    case .running:
        ble.sendUIState("thinking", text: "\(snapshot.agent.displayName) running")
    case .completed:
        ble.sendUIState("ready", text: "\(snapshot.agent.displayName) done")
        ble.playSound("task_done")
    case .failed:
        ble.sendUIState("error", text: "\(snapshot.agent.displayName) failed")
        ble.playSound("task_failed")
    case .waitingForApproval, .needsInput:
        ble.sendUIState("pending_confirmation", text: "\(snapshot.agent.displayName) needs you")
        ble.playSound("needs_input")
    case .idle:
        break
    }
}
```

Add a private `displayName` extension either in the same file or `AgentTaskCaptureController.swift`:

```swift
private extension AgentKind {
    var displayName: String {
        switch self {
        case .claudeCode: return "Claude"
        case .codexCLI: return "Codex"
        case .codexDesktop: return "Codex"
        case .unknown: return "Agent"
        }
    }
}
```

- [ ] **Step 3: Start capture from AppDelegate**

In `AppDelegate.swift`, add:

```swift
private var taskCaptureController: AgentTaskCaptureController?
```

After `coordinator` is initialized:

```swift
let capture = AgentTaskCaptureController()
capture.onSnapshot = { [weak coordinator] snapshot in
    coordinator?.handleAgentTaskSnapshot(snapshot)
}
capture.start()
taskCaptureController = capture
```

- [ ] **Step 4: Build**

```bash
cd desktop/macos
swift build
```

Expected: app builds.

- [ ] **Step 5: Commit**

```bash
git add desktop/macos/Sources/AgentStickApp/AgentTaskCaptureController.swift desktop/macos/Sources/AgentStickApp/AppDelegate.swift desktop/macos/Sources/AgentStickApp/VoiceStickCoordinator.swift
git commit -m "feat: drive device state from captured agent tasks"
```

---

### Task 6: Add BLE Fixed Sound Command

**Files:**
- Modify: `desktop/macos/Sources/AgentStickApp/BleProtocol.swift`
- Modify: `desktop/macos/Sources/AgentStickApp/BleCentral.swift`
- Modify: `docs/protocol.md`

- [ ] **Step 1: Add play sound payload**

In `BleProtocol.swift`, add:

```swift
static func playSoundPayload(_ sound: String) -> Data {
    let payload = [
        "event": "play_sound",
        "sound": sound
    ]
    return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
}
```

- [ ] **Step 2: Add BLE send method**

In `BleCentral.swift`, add:

```swift
func playSound(_ sound: String, to peripheralID: UUID? = nil) {
    let data = BleProtocol.playSoundPayload(sound)
    if let peripheralID {
        guard let characteristic = controlCharacteristics[peripheralID],
              let peripheral = peripherals[peripheralID] else { return }
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        return
    }

    for (id, characteristic) in controlCharacteristics {
        peripherals[id]?.writeValue(data, for: characteristic, type: .withoutResponse)
    }
}
```

- [ ] **Step 3: Document protocol**

In `docs/protocol.md`, add under Control Event:

```json
{"event":"play_sound","sound":"task_done"}
{"event":"play_sound","sound":"task_failed"}
{"event":"play_sound","sound":"needs_input"}
```

Document that `sound` is symbolic and maps to firmware-resident fixed audio. Unsupported sound names are ignored by firmware.

- [ ] **Step 4: Build**

```bash
cd desktop/macos
swift build
```

Expected: build passes.

- [ ] **Step 5: Commit**

```bash
git add desktop/macos/Sources/AgentStickApp/BleProtocol.swift desktop/macos/Sources/AgentStickApp/BleCentral.swift docs/protocol.md
git commit -m "feat: add BLE fixed sound control event"
```

---

### Task 7: Add Hook Installer Settings

**Files:**
- Create: `desktop/macos/Sources/AgentStickApp/AgentHookInstallers.swift`
- Modify: `desktop/macos/Sources/AgentStickApp/AppConfig.swift`
- Modify: `desktop/macos/Config/config.example.toml`
- Modify later when adding settings UI: `desktop/macos/Sources/AgentStickApp/SettingsWindowController.swift`

- [ ] **Step 1: Add config flags**

Add fields to `AppConfig`:

```swift
var agentCaptureEnabled: Bool
var agentSoundAlertsEnabled: Bool
```

Defaults:

```swift
agentCaptureEnabled: true,
agentSoundAlertsEnabled: true,
```

Decode and save TOML keys:

```toml
agent_capture_enabled = true
agent_sound_alerts_enabled = true
```

- [ ] **Step 2: Create hook installer shell**

Create `AgentHookInstallers.swift` with:

```swift
import Foundation

enum AgentHookInstallerStatus: Equatable {
    case installed
    case missing
    case invalid(String)
}

enum AgentHookInstallers {
    static func hookBinaryURL() -> URL {
        AppConfig.configDirectory
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("AgentStickHooks")
    }

    static func installClaudeHooks() throws {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        try installJSONHooks(
            settingsURL: settingsURL,
            source: "claude",
            events: ["SessionStart", "UserPromptSubmit", "Stop", "StopFailure", "Notification"]
        )
    }

    static func installCodexHooks() throws {
        let hooksURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/hooks.json")
        try installJSONHooks(
            settingsURL: hooksURL,
            source: "codex",
            events: ["SessionStart", "UserPromptSubmit", "Stop", "PermissionRequest"]
        )
    }

    private static func installJSONHooks(settingsURL: URL, source: String, events: [String]) throws {
        // Read JSON as [String: Any], preserve non-AgentStick hooks,
        // and add managed hook command: "\(hookBinaryURL().path) --source \(source)".
    }
}
```

Implement as JSON/TOML-safe mutation functions with tests before exposing UI. Do not overwrite non-AgentStick user hooks.

- [ ] **Step 3: Gate capture startup**

In `AppDelegate.swift`, start `AgentTaskCaptureController` only when `config.agentCaptureEnabled` is true.

- [ ] **Step 4: Build**

```bash
cd desktop/macos
swift build
```

Expected: build passes.

- [ ] **Step 5: Commit**

```bash
git add desktop/macos/Sources/AgentStickApp/AgentHookInstallers.swift desktop/macos/Sources/AgentStickApp/AppConfig.swift desktop/macos/Config/config.example.toml desktop/macos/Sources/AgentStickApp/AppDelegate.swift
git commit -m "feat: configure agent task capture"
```

---

### Task 8: Add Codex Desktop App-Server Client

**Files:**
- Create: `desktop/macos/Sources/AgentStickApp/CodexAppServerClient.swift`
- Modify: `desktop/macos/Sources/AgentStickApp/AgentTaskCaptureController.swift`

- [ ] **Step 1: Implement JSON-RPC client**

Create `CodexAppServerClient.swift` with these responsibilities:

```swift
import Foundation
import AgentStickCore

enum CodexAppServerNotification {
    case threadStarted(threadID: String, cwd: String?, title: String?)
    case turnStarted(threadID: String, turnID: String)
    case turnCompleted(threadID: String, turnID: String, failed: Bool)
    case threadClosed(threadID: String)
}

final class CodexAppServerClient {
    var onEvent: ((AgentTaskEvent) -> Void)?

    func start() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "app-server", "--listen", "stdio://"]
        // Attach stdin/stdout/stderr pipes, run the process, send initialize,
        // then map newline-delimited JSON-RPC notifications to AgentTaskEvent.
    }

    func stop() {
        // Terminate process and clear file-handle readability handlers.
    }
}
```

Use `/usr/bin/env codex` by default so PATH resolution matches `AgentCLIRunner`.

- [ ] **Step 2: Map Codex Desktop events**

Map:

```text
thread/started -> sessionStarted, agent codexDesktop, surface desktop
turn/started -> turnStarted
turn/completed completed status -> completed
turn/completed failed/interrupted status -> failed
```

Set jump target:

```swift
"codex://threads/\(threadID)"
```

- [ ] **Step 3: Wire into capture controller**

In `AgentTaskCaptureController`, keep one `CodexAppServerClient`:

```swift
private let codexAppServer = CodexAppServerClient()
```

On event:

```swift
let snapshot = monitor.apply(event)
DispatchQueue.main.async { self.onSnapshot?(snapshot) }
```

- [ ] **Step 4: Build**

```bash
cd desktop/macos
swift build
```

Expected: build passes. If `codex` is not installed, runtime should log and continue; app startup must not fail.

- [ ] **Step 5: Commit**

```bash
git add desktop/macos/Sources/AgentStickApp/CodexAppServerClient.swift desktop/macos/Sources/AgentStickApp/AgentTaskCaptureController.swift
git commit -m "feat: capture Codex Desktop turn lifecycle"
```

---

### Task 9: Add Firmware Fixed Sound Playback Command

**Files:**
- Modify: `firmware/main/main.c`
- Create: `firmware/components/audio_pipeline/include/audio_playback.h`
- Create: `firmware/components/audio_pipeline/audio_playback.c`
- Modify: `firmware/components/audio_pipeline/CMakeLists.txt`
- Add: `firmware/components/audio_pipeline/assets/task_done.pcm`
- Add: `firmware/components/audio_pipeline/assets/task_failed.pcm`
- Add: `firmware/components/audio_pipeline/assets/needs_input.pcm`

- [ ] **Step 1: Add playback API**

Create `audio_playback.h`:

```c
#pragma once

#include "esp_err.h"

typedef enum {
    AUDIO_PLAYBACK_SOUND_TASK_DONE,
    AUDIO_PLAYBACK_SOUND_TASK_FAILED,
    AUDIO_PLAYBACK_SOUND_NEEDS_INPUT,
} audio_playback_sound_t;

esp_err_t audio_playback_init(void);
esp_err_t audio_playback_play(audio_playback_sound_t sound);
bool audio_playback_is_busy(void);
```

- [ ] **Step 2: Implement simple fixed PCM player**

Create `audio_playback.c`:

```c
#include "audio_playback.h"

#include <stdbool.h>

#include "driver/i2s_std.h"
#include "esp_check.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "audio_playback";
static bool s_initialized;
static volatile bool s_busy;

esp_err_t audio_playback_init(void)
{
    s_initialized = true;
    return ESP_OK;
}

bool audio_playback_is_busy(void)
{
    return s_busy;
}

esp_err_t audio_playback_play(audio_playback_sound_t sound)
{
    if (!s_initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    if (s_busy) {
        return ESP_ERR_INVALID_STATE;
    }

    s_busy = true;
    ESP_LOGI(TAG, "play sound=%d", (int)sound);

    // First hardware pass may generate short tones through the codec DAC.
    // Keep sound enum names stable when replacing tones with embedded PCM arrays.

    s_busy = false;
    return ESP_OK;
}
```

The first working firmware pass may implement tones instead of PCM arrays if that is faster to validate on hardware. Keep the public sound names stable.

- [ ] **Step 3: Parse play_sound in control callback**

In `firmware/main/main.c`, include:

```c
#include "audio_playback.h"
```

In `ble_control_cb`, read:

```c
const cJSON *sound = cJSON_GetObjectItemCaseSensitive(root, "sound");
```

Add branch:

```c
} else if (cJSON_IsString(event) && strcmp(event->valuestring, "play_sound") == 0 &&
           cJSON_IsString(sound)) {
    if (strcmp(sound->valuestring, "task_done") == 0) {
        (void)audio_playback_play(AUDIO_PLAYBACK_SOUND_TASK_DONE);
    } else if (strcmp(sound->valuestring, "task_failed") == 0) {
        (void)audio_playback_play(AUDIO_PLAYBACK_SOUND_TASK_FAILED);
    } else if (strcmp(sound->valuestring, "needs_input") == 0) {
        (void)audio_playback_play(AUDIO_PLAYBACK_SOUND_NEEDS_INPUT);
    } else {
        ESP_LOGW(TAG, "unknown sound %s", sound->valuestring);
    }
```

Call `audio_playback_init()` from `app_main()` after board/audio init.

- [ ] **Step 4: Update component build**

Modify `firmware/components/audio_pipeline/CMakeLists.txt` so `audio_playback.c` is compiled.

- [ ] **Step 5: Build firmware**

```bash
cd firmware
. /Users/fengsu/esp/esp-idf/export.sh
idf.py build
```

Expected: firmware builds.

- [ ] **Step 6: Commit**

```bash
git add firmware/main/main.c firmware/components/audio_pipeline/include/audio_playback.h firmware/components/audio_pipeline/audio_playback.c firmware/components/audio_pipeline/CMakeLists.txt firmware/components/audio_pipeline/assets docs/protocol.md
git commit -m "feat: play fixed device sounds for agent events"
```

---

### Task 10: End-To-End Manual Verification

**Files:**
- Create: `scripts/test_agent_task_capture.sh`

- [ ] **Step 1: Create manual bridge smoke script**

Create `scripts/test_agent_task_capture.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../desktop/macos"
swift build --product AgentStickHooks

HOOK=".build/debug/AgentStickHooks"

printf '%s\n' '{"hook_event_name":"Stop","session_id":"manual-codex","turn_id":"turn-1","cwd":"/tmp","last_assistant_message":"Done"}' \
  | "$HOOK" --source codex

printf '%s\n' '{"hook_event_name":"StopFailure","session_id":"manual-claude","cwd":"/tmp","error":"Failed"}' \
  | "$HOOK" --source claude
```

Make executable:

```bash
chmod +x scripts/test_agent_task_capture.sh
```

- [ ] **Step 2: Verify app bridge manually**

Run app:

```bash
cd desktop/macos
swift run AgentStickApp
```

In another terminal:

```bash
scripts/test_agent_task_capture.sh
```

Expected:

- App logs decoded agent events.
- Connected device receives `task_done` for completed event.
- Connected device receives `task_failed` for failure event.
- If no device is connected, app does not crash.

- [ ] **Step 3: Verify real Claude Code hook**

Install managed Claude hook, run a small Claude Code task, and confirm:

- `UserPromptSubmit` maps to running.
- `Stop` maps to completed.
- Device plays `task_done`.

- [ ] **Step 4: Verify real Codex CLI hook**

Install managed Codex hook, run a small Codex CLI task, and confirm:

- `UserPromptSubmit` maps to running.
- `Stop` maps to completed.
- Device plays `task_done`.

- [ ] **Step 5: Verify Codex Desktop**

Enable Codex app-server capture, run a Codex Desktop turn, and confirm:

- `turn/started` maps to running.
- `turn/completed` maps to completed.
- Device plays `task_done`.

- [ ] **Step 6: Commit**

```bash
git add scripts/test_agent_task_capture.sh
git commit -m "test: add agent task capture smoke script"
```

---

## Verification Checklist

- `cd desktop/macos && swift test`
- `cd desktop/macos && swift build`
- `cd desktop/macos && swift build --product AgentStickHooks`
- `cd firmware && . /Users/fengsu/esp/esp-idf/export.sh && idf.py build`
- Manual hook smoke with no running AgentStick app: hook exits with code 0 and no stdout noise.
- Manual hook smoke with AgentStick app running: task snapshots update and BLE commands are emitted.
- Connected device handles unknown `play_sound` names by ignoring them.

## Rollout Notes

- Keep hook installation opt-in until the installer has status/uninstall coverage.
- Keep per-tool Codex `PreToolUse`/`PostToolUse` disabled by default to avoid terminal log noise.
- Treat Codex Desktop app-server as best-effort. If `codex` is missing or the app-server protocol changes, log and continue.
- Fixed sounds should be short. Start with generated tones or tiny PCM clips, then replace with branded sounds after playback timing is stable.
