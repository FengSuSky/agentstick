import Foundation
import AgentStickCore

final class AgentTaskCaptureController {
    private let bridge = AgentEventBridgeServer()
    private let codexAppServer = CodexAppServerClient()
    private var monitor = AgentTaskMonitor()

    var onSnapshot: ((AgentTaskSnapshot) -> Void)?
    var onApprovalRequest: ((String, String, String, @escaping (Bool) -> Void) -> Void)?

    func start(captureEnabled: Bool = true) {
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
        bridge.onApprovalEnvelope = { [weak self] envelope, reply in
            guard let self else { reply(false); return }
            guard let object = try? JSONSerialization.jsonObject(with: envelope.payload) as? [String: Any] else {
                reply(false)
                return
            }
            let tool = object["tool_name"] as? String ?? "Permission Request"
            NSLog("AgentTaskCaptureController: Claude permission request tool=\(tool)")
            let input = object["tool_input"] ?? [:]
            let details: String
            if let data = try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: data, encoding: .utf8) {
                details = "## \(tool)\n\n```json\n\(text)\n```"
            } else {
                details = "## \(tool)\n\n\(String(describing: input))"
            }
            DispatchQueue.main.async {
                if let callback = self.onApprovalRequest {
                    callback("Claude Code", tool, details) { allowed in
                        NSLog("AgentTaskCaptureController: Claude permission decision tool=\(tool) allowed=\(allowed)")
                        reply(allowed)
                    }
                } else {
                    reply(false)
                }
            }
        }

        do {
            try bridge.start()
            NSLog("Agent event bridge started")
        } catch {
            NSLog("Agent event bridge start failed: \(error)")
        }

        // The bridge must always run because Claude approval hooks wait for its reply.
        // Lifecycle capture remains optional.
        if captureEnabled {
            codexAppServer.onEvent = { [weak self] event in
                self?.applyEvent(event)
            }
            codexAppServer.start()
        }
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
