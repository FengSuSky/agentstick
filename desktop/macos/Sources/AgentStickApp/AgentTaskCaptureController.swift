import Foundation
import AgentStickCore

final class AgentTaskCaptureController {
    private let bridge = AgentEventBridgeServer()
    private let codexAppServer = CodexAppServerClient()
    private var monitor = AgentTaskMonitor()

    var onSnapshot: ((AgentTaskSnapshot) -> Void)?

    func start() {
        // Hook bridge: receives events from AgentStickHooks CLI (Claude Code, Codex CLI).
        bridge.onEnvelope = { [weak self] envelope in
            guard let self else { return }
            do {
                let event = try AgentHookPayloadMapper.event(from: envelope.payload, source: envelope.source)
                self.applyEvent(event)
            } catch {
                NSLog("Agent hook decode failed: \(error)")
            }
        }

        do {
            try bridge.start()
            NSLog("Agent event bridge started")
        } catch {
            NSLog("Agent event bridge start failed: \(error)")
        }

        // Codex Desktop: receives turn lifecycle from codex app-server JSON-RPC.
        codexAppServer.onEvent = { [weak self] event in
            self?.applyEvent(event)
        }
        codexAppServer.start()
    }

    func stop() {
        bridge.stop()
        codexAppServer.stop()
    }

    private func applyEvent(_ event: AgentTaskEvent) {
        let snapshot = monitor.apply(event)
        DispatchQueue.main.async {
            self.onSnapshot?(snapshot)
        }
    }
}
