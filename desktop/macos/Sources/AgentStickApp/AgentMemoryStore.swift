import AppKit
import Foundation

final class AgentMemoryStore {
    struct Entry: Codable, Equatable {
        let id: UUID
        var text: String
        var projectPath: String?
        var createdAt: Date
        var updatedAt: Date
    }

    private struct Document: Codable { var entries: [Entry] }
    private let lock = NSLock()
    private let fileManager: FileManager
    private let url: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.url = AppConfig.configDirectory.appendingPathComponent("agent-memory.json")
    }

    func observe(prompt: String, workingDirectory: URL) {
        let candidates = prompt
            .components(separatedBy: CharacterSet(charactersIn: "。！？!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { shouldRemember($0) }
        guard !candidates.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var entries = loadUnlocked()
        for candidate in candidates {
            let clean = String(candidate.prefix(500))
            guard !containsSecret(clean) else { continue }
            let isProject = clean.contains("这个项目") || clean.contains("本项目") || clean.lowercased().contains("this project")
            let projectPath = isProject ? workingDirectory.standardizedFileURL.path : nil
            if let index = entries.firstIndex(where: { $0.text.caseInsensitiveCompare(clean) == .orderedSame && $0.projectPath == projectPath }) {
                entries[index].updatedAt = Date()
            } else {
                entries.append(Entry(id: UUID(), text: clean, projectPath: projectPath, createdAt: Date(), updatedAt: Date()))
            }
        }
        saveUnlocked(Array(entries.sorted { $0.updatedAt > $1.updatedAt }.prefix(100)))
    }

    func context(workingDirectory: URL) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let path = workingDirectory.standardizedFileURL.path
        let relevant = loadUnlocked().filter { $0.projectPath == nil || $0.projectPath == path }.prefix(20)
        guard !relevant.isEmpty else { return nil }
        return "AgentStick memory (user-managed preferences and stable context):\n" + relevant.map { "- \($0.text)" }.joined(separator: "\n")
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? fileManager.removeItem(at: url)
    }

    static func openMemoryFile() {
        let store = AgentMemoryStore()
        store.lock.lock()
        if !store.fileManager.fileExists(atPath: store.url.path) { store.saveUnlocked([]) }
        store.lock.unlock()
        NSWorkspace.shared.open(store.url)
    }

    private func shouldRemember(_ text: String) -> Bool {
        guard text.count >= 4 else { return false }
        let lower = text.lowercased()
        return ["记住", "以后", "我习惯", "我喜欢", "我偏好", "默认", "不要再", "本项目", "这个项目",
                "remember", "from now on", "i prefer", "i like", "always", "never", "by default", "this project"]
            .contains { lower.contains($0) }
    }

    private func containsSecret(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["api key", "api_key", "app key", "token", "password", "密码", "密钥", "secret", "sk-"].contains { lower.contains($0) }
    }

    private func loadUnlocked() -> [Entry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let document = try? decoder.decode(Document.self, from: data) else { return [] }
        return document.entries
    }

    private func saveUnlocked(_ entries: [Entry]) {
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(Document(entries: entries)).write(to: url, options: .atomic)
        } catch {
            NSLog("AgentMemoryStore: save failed: \(error)")
        }
    }
}
