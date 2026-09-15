import Darwin
import Foundation

/// Minimal loopback HTTP server that receives the WorkBuddy OAuth redirect.
///
/// The open platform only accepts the redirect URI registered with the app, so the
/// listener must serve exactly that path. It binds to 127.0.0.1 and stops itself as
/// soon as one callback has been handled.
final class WorkBuddyOAuthCallbackServer {
    static let defaultPort: UInt16 = 8799
    static let defaultCallbackPath = "/oauth/callback"

    /// Concurrent so the IPv4 and IPv6 listeners can block on `accept` at the same time.
    private let queue = DispatchQueue(label: "app.agentstick.workbuddy.oauth", attributes: .concurrent)
    private var listenSockets: [Int32] = []
    private var timeoutWorkItem: DispatchWorkItem?
    private let finishLock = NSLock()
    private var finished = false
    private var completion: ((Result<(code: String, state: String), Error>) -> Void)?

    /// The loopback address actually served by this instance.
    let redirectURI: String
    private let port: UInt16
    private let callbackPath: String

    static var defaultRedirectURI: String {
        "http://localhost:\(defaultPort)\(defaultCallbackPath)"
    }

    init(redirectURI override: String? = nil) {
        let resolved = Self.resolve(override)
        self.redirectURI = resolved.uri
        self.port = resolved.port
        self.callbackPath = resolved.path
    }

    /// Only loopback overrides are honoured; anything else keeps the default so the local
    /// server never claims an address it cannot serve.
    private static func resolve(_ override: String?) -> (uri: String, port: UInt16, path: String) {
        guard let raw = override?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let components = URLComponents(string: raw),
              let host = components.host, host == "localhost" || host == "127.0.0.1"
        else {
            return (defaultRedirectURI, defaultPort, defaultCallbackPath)
        }
        let path = components.path.isEmpty ? defaultCallbackPath : components.path
        let port = UInt16(components.port ?? Int(defaultPort))
        return (raw, port, path)
    }

    func start(
        timeoutSeconds: TimeInterval,
        completion: @escaping (Result<(code: String, state: String), Error>) -> Void
    ) throws {
        stop()

        // Bind both stacks. macOS resolves "localhost" to ::1 as well as 127.0.0.1, and a
        // browser is free to try IPv6 first, so an IPv4-only listener can miss the redirect.
        var sockets: [Int32] = []
        if let socket = makeIPv4Listener() { sockets.append(socket) }
        if let socket = makeIPv6Listener() { sockets.append(socket) }
        guard !sockets.isEmpty else {
            throw WorkBuddyAuthError.serverError(
                currentLanguage == .chinese
                    ? "端口 \(port) 被占用，无法启动本地回调服务"
                    : "Port \(port) is in use, so the local callback server could not start"
            )
        }
        listenSockets = sockets

        self.completion = completion
        finished = false

        let workItem = DispatchWorkItem { [weak self] in
            self?.finish(.failure(WorkBuddyAuthError.timedOut))
        }
        timeoutWorkItem = workItem
        queue.asyncAfter(deadline: .now() + max(10, timeoutSeconds), execute: workItem)

        for socket in sockets {
            queue.async { [weak self] in
                self?.acceptLoop(on: socket)
            }
        }
    }

    private func makeIPv4Listener() -> Int32? {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return nil }
        var reuse: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                Darwin.bind(socket, rebound, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(socket, 4) == 0 else {
            Darwin.close(socket)
            return nil
        }
        return socket
    }

    /// Loopback only, and `IPV6_V6ONLY` stays at its default so this never opens LAN access.
    private func makeIPv6Listener() -> Int32? {
        let socket = Darwin.socket(AF_INET6, SOCK_STREAM, 0)
        guard socket >= 0 else { return nil }
        var reuse: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_port = port.bigEndian
        address.sin6_addr = in6addr_loopback

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                Darwin.bind(socket, rebound, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
        guard bound == 0, Darwin.listen(socket, 4) == 0 else {
            Darwin.close(socket)
            return nil
        }
        return socket
    }

    func stop() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        for socket in listenSockets where socket >= 0 {
            Darwin.shutdown(socket, SHUT_RDWR)
            Darwin.close(socket)
        }
        listenSockets = []
    }

    private func acceptLoop(on listenSocket: Int32) {
        while true {
            let client = Darwin.accept(listenSocket, nil, nil)
            guard client >= 0 else { return }
            let request = readRequest(client)
            let target = parseCallback(request)
            respond(client, target == nil)
            Darwin.close(client)

            if let target {
                finish(.success(target))
                return
            }
            if finished { return }
        }
    }

    private func readRequest(_ client: Int32) -> String {
        var buffer = [UInt8](repeating: 0, count: 8192)
        let count = buffer.withUnsafeMutableBytes { raw in
            Darwin.read(client, raw.baseAddress, raw.count - 1)
        }
        guard count > 0 else { return "" }
        return String(bytes: buffer[0..<count], encoding: .utf8) ?? ""
    }

    private func parseCallback(_ request: String) -> (code: String, state: String)? {
        guard let firstLine = request.split(whereSeparator: \.isNewline).first else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        guard let components = URLComponents(string: String(parts[1])) else { return nil }
        guard components.path == callbackPath else { return nil }
        let items = components.queryItems ?? []
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { return nil }
        let state = items.first(where: { $0.name == "state" })?.value ?? ""
        return (code: code, state: state)
    }

    private func respond(_ client: Int32, _ isError: Bool) {
        let title = isError
            ? (currentLanguage == .chinese ? "授权未完成" : "Authorization incomplete")
            : (currentLanguage == .chinese ? "授权成功" : "Authorization complete")
        let body = isError
            ? (currentLanguage == .chinese ? "没有收到授权码，请回到 AgentStick 重试。" : "No authorization code was received. Return to AgentStick and try again.")
            : (currentLanguage == .chinese ? "可以回到 AgentStick 了。" : "You can return to AgentStick now.")
        let html = """
        <!doctype html><html lang="zh"><head><meta charset="utf-8">
        <title>\(title)</title></head>
        <body style="font-family:-apple-system,system-ui,sans-serif;padding:48px;text-align:center">
        <h2>\(title)</h2><p>\(body)</p></body></html>
        """
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n"
        let payload = Array((header + html).utf8)
        _ = payload.withUnsafeBytes { raw in
            Darwin.write(client, raw.baseAddress, raw.count)
        }
    }

    private func finish(_ result: Result<(code: String, state: String), Error>) {
        finishLock.lock()
        guard !finished else {
            finishLock.unlock()
            return
        }
        finished = true
        let delivery = completion
        completion = nil
        finishLock.unlock()
        stop()
        DispatchQueue.main.async { delivery?(result) }
    }
}
