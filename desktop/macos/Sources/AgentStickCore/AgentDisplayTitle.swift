import Foundation

public enum AgentDisplayTitle {
    public static func from(_ text: String, fallback: String, limit: Int = 30) -> String {
        let content = text
            .split(whereSeparator: \.isNewline)
            .map { stripMarkdown(String($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let value = content.isEmpty ? stripMarkdown(fallback) : content
        guard !value.isEmpty else { return fallback }
        guard value.count > limit else { return value }

        let concise = removingRequestPrefix(from: value)
        if let sentenceEnd = concise.firstIndex(where: { "。！？!?；;".contains($0) }) {
            let sentence = String(concise[..<sentenceEnd]).trimmingCharacters(in: .whitespaces)
            if !sentence.isEmpty, sentence.count <= limit {
                return sentence
            }
        }

        return String(concise.prefix(max(1, limit - 1))).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func removingRequestPrefix(from text: String) -> String {
        let prefixes = [
            "请帮我", "麻烦帮我", "帮我", "我想让你", "我希望你", "请你", "请",
            "please help me", "could you please", "can you please", "please"
        ]
        let lowercased = text.lowercased()
        for prefix in prefixes where lowercased.hasPrefix(prefix) {
            let index = text.index(text.startIndex, offsetBy: prefix.count)
            let value = String(text[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return text
    }

    private static func stripMarkdown(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)

        while let first = value.first, "#>*+-".contains(first) {
            value.removeFirst()
            value = value.trimmingCharacters(in: .whitespaces)
        }

        value = value.replacingOccurrences(
            of: #"!\[([^\]]*)\]\([^)]+\)"#,
            with: "$1",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^)]+\)"#,
            with: "$1",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(`{1,3}|\*{1,2}|_{1,2}|~~)"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
