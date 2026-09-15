import Foundation

/// Opt-in diagnostics for the agent run pipeline.
///
/// The app has no logging by default. Creating `agent-debug.log` next to `config.toml`
/// turns this on, which is enough to answer "did the completion sound actually go out?"
/// without a debugger attached. Entries are appended, and the file is left alone once it
/// grows past `maxBytes` so a forgotten log cannot fill a disk.
enum AgentDebugLog {
    private static let fileName = "agent-debug.log"
    private static let maxBytes: UInt64 = 512 * 1024

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// Nil until the log file exists, so the feature costs nothing when it is off.
    private static var fileURL: URL? {
        let url = AppConfig.configDirectory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    static func write(_ message: String) {
        guard let url = fileURL else { return }
        guard let data = "\(formatter.string(from: Date())) \(message)\n".data(using: .utf8) else { return }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? UInt64,
              size < maxBytes
        else { return }

        guard let handle = FileHandle(forWritingAtPath: url.path) else {
            try? data.write(to: url)
            return
        }
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    }
}
