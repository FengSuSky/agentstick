import Foundation

/// Hook config file shapes seen across agent CLIs. Claude Code and its
/// derivatives (Codex, WorkBuddy, CodeBuddy, Gemini, Qwen, Qoder, Factory)
/// nest commands under `hooks.<Event>[].hooks[].command`; Cursor uses a flat
/// `hooks.<Event>[].command` list with its own event names.
public enum AgentHookConfigFormat: Equatable, Sendable {
    case nested
    case flatCommandList
}

public struct AgentHookIntegrationTarget: Equatable, Sendable {
    public let source: String
    public let relativePath: String
    public let format: AgentHookConfigFormat
    public let events: [String]

    public init(source: String, relativePath: String, format: AgentHookConfigFormat, events: [String]) {
        self.source = source
        self.relativePath = relativePath
        self.format = format
        self.events = events
    }
}

/// Idempotent merge of AgentStick hook entries into hook config files.
/// The command marker keeps our entries identifiable and keeps third-party
/// entries (e.g. vibe-island) untouched.
public enum AgentHookRegistration {
    public static let marker = "agentstick-bridge"

    /// Events that matter for device notifications. Hosts ignore events they
    /// do not support, so registering the same set everywhere is safe.
    /// PostToolUse feeds live activity (tool names) into the running screen.
    public static let standardEvents = ["UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SessionEnd"]

    /// Agent CLIs AgentStick integrates with. Installation is gated on the
    /// config file existing, so absent tools are simply skipped.
    public static let targets: [AgentHookIntegrationTarget] = [
        .init(source: "claude", relativePath: ".claude/settings.json", format: .nested, events: standardEvents),
        .init(source: "codex", relativePath: ".codex/hooks.json", format: .nested, events: standardEvents),
        .init(source: "workbuddy", relativePath: ".workbuddy/settings.json", format: .nested, events: standardEvents),
        .init(source: "codebuddy", relativePath: ".codebuddy/settings.json", format: .nested, events: standardEvents),
        .init(source: "gemini", relativePath: ".gemini/settings.json", format: .nested, events: standardEvents),
        .init(source: "qwen", relativePath: ".qwen/settings.json", format: .nested, events: standardEvents),
        .init(source: "qoder", relativePath: ".qoder/settings.json", format: .nested, events: standardEvents),
        .init(source: "factory", relativePath: ".factory/settings.json", format: .nested, events: standardEvents),
        .init(source: "cursor", relativePath: ".cursor/hooks.json", format: .flatCommandList, events: ["beforeSubmitPrompt", "stop"]),
    ]

    public enum RegistrationError: Error, Equatable {
        case unreadableConfig(String)
    }

    /// Adds the hook command for all `events` into the JSON config at `url`.
    /// Existing AgentStick entries are refreshed, everything else is preserved.
    /// Returns true when the file was modified. A timestamped backup is written
    /// before modifying an existing file.
    @discardableResult
    public static func install(
        command: String,
        into url: URL,
        format: AgentHookConfigFormat,
        events: [String]
    ) throws -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return false }

        let root = try loadConfig(url)
        guard var root else { throw RegistrationError.unreadableConfig(url.path) }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var modified = false
        for event in events {
            let groups = hooks[event] as? [[String: Any]] ?? []
            let cleaned = groups.filter { !groupContainsMarker($0, format: format) }
            let updated = cleaned + [entryGroup(command: command, format: format)]
            if normalizedJSON(groups) != normalizedJSON(updated) {
                modified = true
            }
            hooks[event] = updated
        }
        guard modified else { return false }

        root["hooks"] = hooks
        try backup(url)
        try writeConfig(root, to: url)
        return true
    }

    /// Removes every hook entry containing our marker, in both formats.
    /// Returns true when the file was modified.
    @discardableResult
    public static func uninstall(from url: URL) throws -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return false }

        let root = try loadConfig(url)
        guard var root else { throw RegistrationError.unreadableConfig(url.path) }

        guard var hooks = root["hooks"] as? [String: Any], !hooks.isEmpty else { return false }
        var modified = false
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let cleaned = groups.filter { !groupContainsMarker($0, format: .nested) && !groupContainsMarker($0, format: .flatCommandList) }
            if cleaned.count != groups.count {
                modified = true
                if cleaned.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = cleaned
                }
            }
        }
        guard modified else { return false }

        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        try writeConfig(root, to: url)
        return true
    }

    public static func isInstalled(command: String, in url: URL, format: AgentHookConfigFormat, events: [String]) -> Bool {
        guard let root = try? loadConfig(url),
              let hooks = root["hooks"] as? [String: Any] else { return false }
        let expected = Set(events)
        let installed = Set(hooks.keys.filter { event in
            guard let groups = hooks[event] as? [[String: Any]] else { return false }
            return groups.contains { group in
                commands(in: group, format: format).contains(command)
            }
        })
        return expected.isSubset(of: installed)
    }

    private static func entryGroup(command: String, format: AgentHookConfigFormat) -> [String: Any] {
        switch format {
        case .nested:
            return [
                "hooks": [
                    [
                        "type": "command",
                        "command": command,
                    ]
                ]
            ]
        case .flatCommandList:
            return ["command": command]
        }
    }

    private static func commands(in group: [String: Any], format: AgentHookConfigFormat) -> [String] {
        switch format {
        case .nested:
            return (group["hooks"] as? [[String: Any]])?.compactMap { $0["command"] as? String } ?? []
        case .flatCommandList:
            return [group["command"] as? String].compactMap { $0 }
        }
    }

    private static func groupContainsMarker(_ group: [String: Any], format: AgentHookConfigFormat) -> Bool {
        commands(in: group, format: format).contains { $0.contains(marker) }
    }

    private static func loadConfig(_ url: URL) throws -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func writeConfig(_ root: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private static func normalizedJSON(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func backup(_ url: URL) throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".backup.agentstick-" + formatter.string(from: Date()))
        if let data = try? Data(contentsOf: url) {
            try data.write(to: backupURL)
        }
    }
}
