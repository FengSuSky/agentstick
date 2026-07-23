import Foundation

final class AgentSessionStore {
    enum Route {
        case new(prompt: String)
        case resume(id: String, prompt: String)

        var prompt: String {
            switch self { case .new(let prompt), .resume(_, let prompt): return prompt }
        }
        var sessionID: String? {
            if case .resume(let id, _) = self { return id }
            return nil
        }
    }

    private struct Record: Codable {
        var id: String
        var agent: String
        var workingDirectory: String
        var lastPrompt: String
        var updatedAt: Date
    }

    private let lock = NSLock()
    private var records: [Record]
    private let url = AppConfig.configDirectory.appendingPathComponent("agent-sessions.json")

    init() {
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([Record].self, from: data) {
            records = decoded
        } else {
            records = []
        }
    }

    func route(prompt: String, agent: String, workingDirectory: URL) -> Route {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAgent = agent.lowercased()
        let cwd = workingDirectory.standardizedFileURL.path
        let forcedNewPrefixes = ["新会话", "新任务", "重新开始", "开启新会话", "new conversation", "new task", "start over"]
        let forcedResumePrefixes = ["继续会话", "继续任务", "继续", "接着", "基于刚才", "continue conversation", "continue task", "continue"]
        if let prompt = strippingPrefix(from: trimmed, prefixes: forcedNewPrefixes) {
            return .new(prompt: prompt)
        }

        lock.lock()
        let candidates = records
            .filter { $0.agent == normalizedAgent && $0.workingDirectory == cwd }
            .sorted { $0.updatedAt > $1.updatedAt }
        lock.unlock()

        if let prompt = strippingPrefix(from: trimmed, prefixes: forcedResumePrefixes), let latest = candidates.first {
            return .resume(id: latest.id, prompt: prompt)
        }
        guard let best = bestCandidate(for: trimmed, among: candidates) else { return .new(prompt: trimmed) }
        return .resume(id: best.id, prompt: trimmed)
    }

    func remember(id: String, agent: String, workingDirectory: URL, prompt: String) {
        guard !id.isEmpty else { return }
        lock.lock()
        let cwd = workingDirectory.standardizedFileURL.path
        let normalizedAgent = agent.lowercased()
        if let index = records.firstIndex(where: { $0.id == id && $0.agent == normalizedAgent }) {
            records[index].lastPrompt = prompt
            records[index].updatedAt = Date()
        } else {
            records.append(Record(id: id, agent: normalizedAgent, workingDirectory: cwd, lastPrompt: prompt, updatedAt: Date()))
        }
        records = records.sorted { $0.updatedAt > $1.updatedAt }.prefix(80).map { $0 }
        let snapshot = records
        lock.unlock()
        persist(snapshot)
    }

    func forget(id: String) {
        lock.lock()
        records.removeAll { $0.id == id }
        let snapshot = records
        lock.unlock()
        persist(snapshot)
    }

    func clear() {
        lock.lock()
        records.removeAll()
        lock.unlock()
        try? FileManager.default.removeItem(at: url)
    }

    private func bestCandidate(for prompt: String, among candidates: [Record]) -> Record? {
        let now = Date()
        let followUpCues = [
            "刚才", "上一个", "前面", "继续", "接着", "然后", "再", "这个", "那个", "它", "修改一下", "补充",
            "previous", "earlier", "continue", "then", "also", "that", "it", "follow up"
        ]
        let lower = prompt.lowercased()
        if followUpCues.contains(where: { lower.contains($0) }),
           let recent = candidates.first(where: { now.timeIntervalSince($0.updatedAt) < 7 * 24 * 60 * 60 }) {
            return recent
        }
        return candidates
            .filter { now.timeIntervalSince($0.updatedAt) < 6 * 60 * 60 }
            .map { ($0, similarity(prompt, $0.lastPrompt)) }
            .filter { $0.1 >= 0.28 }
            .max { lhs, rhs in lhs.1 < rhs.1 }?.0
    }

    private func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = tokens(lhs), right = tokens(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let intersection = left.intersection(right).count
        let union = left.union(right).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    private func tokens(_ text: String) -> Set<String> {
        let normalized = text.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }
        var result = Set(normalized.split(whereSeparator: \Character.isWhitespace).map(String.init).filter { $0.count > 1 })
        let compact = normalized.filter { !$0.isWhitespace }
        let characters = Array(compact)
        if characters.count >= 2 {
            for index in 0..<(characters.count - 1) {
                result.insert(String(characters[index...index + 1]))
            }
        }
        return result
    }

    private func strippingPrefix(from text: String, prefixes: [String]) -> String? {
        let lower = text.lowercased()
        guard let prefix = prefixes.first(where: { lower.hasPrefix($0.lowercased()) }) else { return nil }
        let index = text.index(text.startIndex, offsetBy: prefix.count)
        let remainder = text[index...].trimmingCharacters(in: CharacterSet(charactersIn: " ：:，,。\n\t"))
        return remainder.isEmpty ? text : remainder
    }

    private func persist(_ records: [Record]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? FileManager.default.createDirectory(at: AppConfig.configDirectory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
