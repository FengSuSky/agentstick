import Darwin
import Dispatch
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

public enum AgentEventBridgeError: Error {
    case systemCallFailed(String, Int32)
    case invalidSocketPath
    case encodingFailed
}

public final class AgentEventBridgeServer: @unchecked Sendable {
    private struct ClientConnection {
        let fileDescriptor: Int32
        let readSource: DispatchSourceRead
        var buffer = Data()
    }

    private let socketURL: URL
    private let queue = DispatchQueue(label: "app.agentstick.agent-event-bridge")
    private var listenFileDescriptor: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [Int32: ClientConnection] = [:]

    public var onEnvelope: ((AgentHookEnvelope) -> Void)?

    public init(socketURL: URL = AgentEventBridgeLocation.defaultSocketURL) {
        self.socketURL = socketURL
    }

    deinit {
        stop()
    }

    public func start() throws {
        guard listenFileDescriptor == -1 else { return }

        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: socketURL)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd != -1 else {
            throw AgentEventBridgeError.systemCallFailed("socket", errno)
        }

        do {
            try bindSocket(fd, path: socketURL.path)
            guard listen(fd, 16) != -1 else {
                throw AgentEventBridgeError.systemCallFailed("listen", errno)
            }
            try makeNonBlocking(fd)
        } catch {
            close(fd)
            throw error
        }

        listenFileDescriptor = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptPendingClients()
        }
        source.setCancelHandler {
            close(fd)
        }
        acceptSource = source
        source.resume()
    }

    public func stop() {
        queue.sync {
            for client in clients.values {
                client.readSource.cancel()
            }
            clients.removeAll()
            acceptSource?.cancel()
            acceptSource = nil
            listenFileDescriptor = -1
            try? FileManager.default.removeItem(at: socketURL)
        }
    }

    private func acceptPendingClients() {
        while true {
            let clientFD = accept(listenFileDescriptor, nil, nil)
            if clientFD == -1 {
                return
            }
            do {
                try makeNonBlocking(clientFD)
            } catch {
                close(clientFD)
                continue
            }
            configureClient(fileDescriptor: clientFD)
        }
    }

    private func configureClient(fileDescriptor: Int32) {
        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        clients[fileDescriptor] = ClientConnection(fileDescriptor: fileDescriptor, readSource: source)
        source.setEventHandler { [weak self] in
            self?.readClient(fileDescriptor: fileDescriptor)
        }
        source.setCancelHandler {
            close(fileDescriptor)
        }
        source.resume()
    }

    private func readClient(fileDescriptor: Int32) {
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fileDescriptor, &chunk, chunk.count)
            if count > 0 {
                clients[fileDescriptor]?.buffer.append(chunk, count: count)
                processClientBuffer(fileDescriptor: fileDescriptor)
            } else {
                closeClient(fileDescriptor)
                return
            }
            if count < chunk.count {
                return
            }
        }
    }

    private func processClientBuffer(fileDescriptor: Int32) {
        guard var client = clients[fileDescriptor] else { return }
        while let newlineIndex = client.buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = client.buffer[..<newlineIndex]
            client.buffer.removeSubrange(...newlineIndex)
            if let envelope = try? JSONDecoder().decode(AgentHookEnvelope.self, from: Data(line)) {
                onEnvelope?(envelope)
            }
        }
        clients[fileDescriptor] = client
    }

    private func closeClient(_ fileDescriptor: Int32) {
        guard let client = clients.removeValue(forKey: fileDescriptor) else { return }
        client.readSource.cancel()
    }
}

public enum AgentEventBridgeClient {
    public static func send(_ envelope: AgentHookEnvelope, to socketURL: URL) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd != -1 else {
            throw AgentEventBridgeError.systemCallFailed("socket", errno)
        }
        defer { close(fd) }

        try connectSocket(fd, path: socketURL.path)
        var data = try JSONEncoder().encode(envelope)
        data.append(UInt8(ascii: "\n"))
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var written = 0
            while written < data.count {
                let count = write(fd, baseAddress.advanced(by: written), data.count - written)
                guard count > 0 else {
                    throw AgentEventBridgeError.systemCallFailed("write", errno)
                }
                written += count
            }
        }
    }
}

private func bindSocket(_ fd: Int32, path: String) throws {
    try withSockAddr(path: path) { pointer, length in
        guard bind(fd, pointer, length) != -1 else {
            throw AgentEventBridgeError.systemCallFailed("bind", errno)
        }
    }
}

private func connectSocket(_ fd: Int32, path: String) throws {
    try withSockAddr(path: path) { pointer, length in
        guard connect(fd, pointer, length) != -1 else {
            throw AgentEventBridgeError.systemCallFailed("connect", errno)
        }
    }
}

private func withSockAddr<T>(
    path: String,
    _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T
) throws -> T {
    let maxPathLength = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
    guard path.utf8.count < maxPathLength else {
        throw AgentEventBridgeError.invalidSocketPath
    }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        path.withCString { source in
            strcpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self), source)
        }
    }

    let length = socklen_t(MemoryLayout<sa_family_t>.size + path.utf8.count + 1)
    return try withUnsafePointer(to: &address) { pointer in
        try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            try body(sockaddrPointer, length)
        }
    }
}

private func makeNonBlocking(_ fd: Int32) throws {
    let flags = fcntl(fd, F_GETFL, 0)
    guard flags != -1 else {
        throw AgentEventBridgeError.systemCallFailed("fcntl(F_GETFL)", errno)
    }
    guard fcntl(fd, F_SETFL, flags | O_NONBLOCK) != -1 else {
        throw AgentEventBridgeError.systemCallFailed("fcntl(F_SETFL)", errno)
    }
}
