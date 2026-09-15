import AppKit
import Foundation

/// Developer application credentials shipped with AgentStick. These are extractable
/// from the app bundle; user OAuth tokens are stored in a 0600 file on this Mac.
enum WorkBuddyAppCredentials {
    static let clientID = "cb_0LfEMdsUbkP5DB7e0148"
    static let clientSecret = "gFBTm9GQmnkMB7mQr3DhXGg0u7YmvZjv"

    static func effectiveClientID(_ configured: String?) -> String {
        let value = configured?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? clientID : value
    }
}

enum WorkBuddyAuthError: LocalizedError {
    case missingClientID
    case missingClientSecret
    case missingAuthorizationCode
    case notAuthorized
    case invalidResponse
    case stateMismatch
    case timedOut
    case codeExpired
    case serverError(String)
    case rejected(String)
    case storageFailure(String)
    case authorizationRevoked

    var errorDescription: String? {
        let chinese = currentLanguage == .chinese
        switch self {
        case .missingClientID:
            return chinese
                ? "未填写 WorkBuddy Client ID。请在设置中填写，或检查 [agents.workbuddy] 配置。"
                : "No WorkBuddy Client ID. Fill it in Settings or in [agents.workbuddy]."
        case .missingClientSecret:
            return chinese
                ? "未保存 WorkBuddy Client Secret。请在设置中粘贴一次，它会保存在本机。"
                : "No WorkBuddy Client Secret. Paste it once in Settings; it is stored on this Mac."
        case .missingAuthorizationCode:
            return chinese
                ? "没有读到授权码。请在浏览器中完成授权后，把地址栏里的完整链接粘贴进来。"
                : "No authorization code found. After approving in the browser, paste the full address-bar URL here."
        case .notAuthorized:
            return chinese
                ? "尚未授权 WorkBuddy。请在设置中点击“连接 WorkBuddy”。"
                : "WorkBuddy is not authorized yet. Click “Connect WorkBuddy” in Settings."
        case .invalidResponse:
            return chinese ? "WorkBuddy 返回了无法解析的响应" : "WorkBuddy returned an unreadable response"
        case .stateMismatch:
            return chinese ? "授权回调校验失败，请重新连接" : "The authorization callback failed validation. Connect again."
        case .timedOut:
            return chinese ? "等待 WorkBuddy 授权超时" : "Timed out waiting for WorkBuddy authorization"
        case .codeExpired:
            return chinese
                ? "授权码已失效（有效期约 2 分钟）。请重新点“连接 WorkBuddy”，授权后立刻粘贴。"
                : "The authorization code expired (about 2 minutes). Click “Connect WorkBuddy” again and paste right away."
        case .serverError(let detail):
            return detail
        case .rejected(let detail):
            return detail.isEmpty
                ? (chinese ? "WorkBuddy 拒绝了本次请求" : "WorkBuddy rejected the request")
                : detail
        case .storageFailure(let detail):
            return chinese
                ? "授权信息读写失败：\(detail)"
                : "Could not read or write the stored credentials: \(detail)"
        case .authorizationRevoked:
            return chinese
                ? "WorkBuddy 授权已失效，请重新点击“连接 WorkBuddy”。"
                : "The WorkBuddy authorization was revoked. Click “Connect WorkBuddy” again."
        }
    }
}

struct WorkBuddyOAuthToken: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var scope: String
    var openID: String
    /// The application the token was issued to; a stored token is only reused
    /// for this Client ID so switching apps never leaks credentials across.
    var clientID: String = ""

    /// Refresh slightly early so an in-flight request does not race the expiry.
    var isExpiringSoon: Bool {
        expiresAt.timeIntervalSinceNow < 120
    }
}

/// Stores WorkBuddy credentials in a 0600 file under the app's Application Support
/// directory instead of the Keychain.
///
/// The app ships with ad hoc signing, so the Keychain ACL breaks on every rebuild:
/// reads start prompting or failing while the UI still reports "authorized". A plain
/// file behaves identically across rebuilds. The built-in developer secret never
/// touches disk; only user-provided custom secrets and OAuth tokens are persisted.
final class WorkBuddyAuthStore {
    static let shared = WorkBuddyAuthStore()

    private struct Record: Codable {
        var clientID: String = ""
        var clientSecret: String?
        var token: WorkBuddyOAuthToken?
    }

    static var storageURL: URL {
        AppConfig.configDirectory.appendingPathComponent("workbuddy-auth.json")
    }

    /// Serial queue guarding the memory cache and file writes: the runner refreshes
    /// tokens on a background queue while Settings reads status on the main thread.
    private let queue = DispatchQueue(label: "app.agentstick.mac.workbuddy.authstore")
    private var record = Record()
    private var loaded = false
    private var storedLastError: String?

    private init() {}

    /// Last file read/write failure, shown by the Settings status line so storage
    /// problems stop failing silently.
    func storageError() -> String? {
        queue.sync { storedLastError }
    }

    func saveClientSecret(_ secret: String, forClientID clientID: String) throws {
        try queue.sync {
            var current = loadIfNeeded()
            let newID = WorkBuddyAppCredentials.effectiveClientID(clientID)
            // Switching applications invalidates any existing token: the old grant
            // belongs to a different app and cannot be refreshed with the new secret.
            if !current.clientID.isEmpty && current.clientID != newID {
                current.token = nil
            }
            current.clientID = newID
            current.clientSecret = secret
            try persist(current)
        }
    }

    func clientSecret(clientID: String = WorkBuddyAppCredentials.clientID) -> String? {
        let id = WorkBuddyAppCredentials.effectiveClientID(clientID)
        if id == WorkBuddyAppCredentials.clientID {
            return WorkBuddyAppCredentials.clientSecret
        }
        return queue.sync {
            let current = loadIfNeeded()
            guard current.clientID == id else { return nil }
            return current.clientSecret
        }
    }

    func saveToken(_ token: WorkBuddyOAuthToken, clientID: String) throws {
        try queue.sync {
            var current = loadIfNeeded()
            current.clientID = WorkBuddyAppCredentials.effectiveClientID(clientID)
            current.token = token
            try persist(current)
        }
    }

    func loadToken(clientID: String = WorkBuddyAppCredentials.clientID) -> WorkBuddyOAuthToken? {
        let id = WorkBuddyAppCredentials.effectiveClientID(clientID)
        return queue.sync {
            let current = loadIfNeeded()
            guard current.clientID.isEmpty || current.clientID == id else { return nil }
            guard let token = current.token else { return nil }
            // Double-check the token itself: a bug during migration or manual
            // file edit could leave a token whose embedded clientID disagrees
            // with the record-level one.
            guard token.clientID.isEmpty || token.clientID == id else { return nil }
            return token
        }
    }

    func clearToken() throws {
        try queue.sync {
            var current = loadIfNeeded()
            current.token = nil
            try persist(current)
        }
    }

    func clearAll() throws {
        try queue.sync {
            try persist(Record())
        }
    }

    /// Reads the file once; afterwards everything is served from memory. Must run
    /// on `queue`. A missing file is a fresh install; an unreadable one keeps the
    /// empty record and records the error instead of crashing the caller.
    private func loadIfNeeded() -> Record {
        guard !loaded else { return record }
        loaded = true
        do {
            let data = try Data(contentsOf: Self.storageURL)
            record = try JSONDecoder().decode(Record.self, from: data)
            storedLastError = nil
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            record = Record()
        } catch {
            storedLastError = error.localizedDescription
            record = Record()
        }
        return record
    }

    /// Writes atomically and keeps the memory cache in sync. On failure the cache is
    /// still updated so the current session keeps working; the error is recorded for
    /// the Settings status line and rethrown for callers that report it.
    private func persist(_ value: Record) throws {
        record = value
        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: AppConfig.configDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(value)
            try data.write(to: Self.storageURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: Self.storageURL.path
            )
            storedLastError = nil
        } catch {
            storedLastError = error.localizedDescription
            throw WorkBuddyAuthError.storageFailure(error.localizedDescription)
        }
    }
}

/// Runs the OAuth 2.1 authorization-code flow against the WorkBuddy open platform.
final class WorkBuddyAuthController {
    static let localAssistantScope = "user.localassistant.invokable user.localassistant.readable"
    static let cloudTaskScope = "user.task.invokable user.task.readable"

    private let baseURL = URL(string: "https://www.workbuddy.cn/openapi/v2")!
    private var callbackServer = WorkBuddyOAuthCallbackServer()
    private var pendingState: String?
    private var pendingExpiry: Date?
    /// Guards token refreshes: the platform rotates refresh tokens, so two
    /// concurrent refreshes with the same grant would invalidate the second one.
    private let refreshLock = NSLock()

    var redirectURI: String { callbackServer.redirectURI }

    /// Builds the consent URL and remembers the `state` for later validation.
    ///
    /// Kept separate from `authorize` so the Settings UI can hand the URL to the user
    /// manually. A redirect URI the desktop app cannot serve (for example an `https`
    /// loopback address) still needs to be sent verbatim, because the platform compares
    /// it byte for byte against the registered value.
    func makeAuthorizationURL(
        clientID: String,
        scope: String? = nil,
        redirectURLOverride: String? = nil
    ) -> URL? {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }

        let state = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        pendingState = state
        pendingExpiry = Date().addingTimeInterval(600)

        var components = URLComponents(url: baseURL.appendingPathComponent("authorize"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: id),
            URLQueryItem(name: "redirect_uri", value: redirectURLOverride ?? redirectURI),
            URLQueryItem(name: "scope", value: scope ?? Self.localAssistantScope),
            URLQueryItem(name: "state", value: state)
        ]
        return components?.url
    }

    /// Opens the browser, waits for the loopback callback, and exchanges the code.
    /// `redirectURLOverride` must match whatever the platform has registered for this app.
    func authorize(
        clientID: String,
        clientSecret: String,
        scope: String? = nil,
        redirectURLOverride: String? = nil,
        completion: @escaping (Result<WorkBuddyOAuthToken, Error>) -> Void
    ) {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            completion(.failure(WorkBuddyAuthError.missingClientID))
            return
        }
        let server = WorkBuddyOAuthCallbackServer(redirectURI: redirectURLOverride)
        callbackServer = server

        guard let authorizeURL = makeAuthorizationURL(
            clientID: id,
            scope: scope,
            redirectURLOverride: server.redirectURI
        ) else {
            completion(.failure(WorkBuddyAuthError.invalidResponse))
            return
        }

        do {
            try callbackServer.start(timeoutSeconds: 300) { [weak self] result in
                guard let self else { return }
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let callback):
                    self.exchange(
                        code: callback.code,
                        state: callback.state,
                        clientID: id,
                        clientSecret: clientSecret,
                        redirectURI: server.redirectURI,
                        completion: completion
                    )
                }
            }
        } catch {
            completion(.failure(error))
            return
        }

        NSWorkspace.shared.open(authorizeURL)
    }

    /// Completes the flow with a code the user copied out of the browser address bar.
    ///
    /// The platform only redirects to registered URIs, so when registration points at an
    /// address the desktop app cannot serve (an `https` loopback address, for instance),
    /// the browser lands on a dead page. The code is still in the URL, so the user pastes
    /// it here instead. Accepts either a bare code or the full callback URL.
    func completeWithPastedCode(
        _ pasted: String,
        clientID: String,
        clientSecret: String,
        redirectURI: String,
        completion: @escaping (Result<WorkBuddyOAuthToken, Error>) -> Void
    ) {
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(WorkBuddyAuthError.missingAuthorizationCode))
            return
        }

        var code = trimmed
        var state: String?
        if let components = URLComponents(string: trimmed),
           let items = components.queryItems,
           let found = items.first(where: { $0.name == "code" })?.value {
            code = found
            state = items.first(where: { $0.name == "state" })?.value
        } else if let range = trimmed.range(of: "code=") {
            // Handles a pasted fragment that is not a well-formed URL.
            var slice = String(trimmed[range.upperBound...])
            if let amp = slice.range(of: "&") { slice = String(slice[..<amp.lowerBound]) }
            code = slice
        }

        code = code.removingPercentEncoding ?? code
        guard !code.isEmpty else {
            completion(.failure(WorkBuddyAuthError.missingAuthorizationCode))
            return
        }

        // The pasted code travels out of band, so validation is best effort: when the
        // consent page was opened by this same app session (state still in memory) and
        // the pasted URL carries a state, it is checked like a live redirect. Only an
        // app relaunch since then, or a bare code without a state, falls back to the
        // server-side check — the server rejects unknown or expired codes anyway.
        if let pastedState = state, !pastedState.isEmpty, let expected = pendingState {
            guard pastedState == expected, let expiry = pendingExpiry, Date() < expiry else {
                completion(.failure(WorkBuddyAuthError.stateMismatch))
                return
            }
        }

        exchange(
            code: code,
            state: state ?? pendingState ?? "",
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI,
            skipStateCheck: true,
            completion: completion
        )
    }

    /// True when the desktop app can actually receive a browser redirect at this address.
    ///
    /// Plain `http` loopback works. `https` needs a TLS certificate we do not ship, so the
    /// caller should fall back to the paste-code path.
    static func canServeRedirect(_ redirectURI: String) -> Bool {
        guard let components = URLComponents(string: redirectURI),
              let scheme = components.scheme?.lowercased(),
              let host = components.host else { return false }
        return scheme == "http" && (host == "localhost" || host == "127.0.0.1")
    }

    /// Returns a usable access token, refreshing it first when it is about to expire.
    func validToken(clientID: String, clientSecret: String) throws -> WorkBuddyOAuthToken {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw WorkBuddyAuthError.missingClientID }
        guard !clientSecret.isEmpty else { throw WorkBuddyAuthError.missingClientSecret }
        guard let token = WorkBuddyAuthStore.shared.loadToken(clientID: id) else {
            throw WorkBuddyAuthError.notAuthorized
        }
        guard token.isExpiringSoon else { return token }

        refreshLock.lock()
        defer { refreshLock.unlock() }

        // Another thread may have refreshed while this one waited for the lock.
        if let refreshed = WorkBuddyAuthStore.shared.loadToken(clientID: id), !refreshed.isExpiringSoon {
            return refreshed
        }

        do {
            let refreshed = try refresh(
                refreshToken: token.refreshToken,
                clientID: id,
                clientSecret: clientSecret
            )
            // A failed disk write must not fail the running task; the in-memory cache
            // is already updated and Settings surfaces the storage error.
            try? WorkBuddyAuthStore.shared.saveToken(refreshed, clientID: id)
            return refreshed
        } catch {
            // A rejected refresh means the grant itself is gone. Drop it so the user
            // is sent back through authorization instead of looping on a dead token;
            // transient network errors are rethrown unchanged.
            if case WorkBuddyAuthError.codeExpired = error {
                try? WorkBuddyAuthStore.shared.clearToken()
                throw WorkBuddyAuthError.authorizationRevoked
            }
            throw error
        }
    }

    private func exchange(
        code: String,
        state: String,
        clientID: String,
        clientSecret: String,
        redirectURI: String,
        skipStateCheck: Bool = false,
        completion: @escaping (Result<WorkBuddyOAuthToken, Error>) -> Void
    ) {
        if !skipStateCheck {
            guard let expected = pendingState, state == expected, let expiry = pendingExpiry, Date() < expiry else {
                completion(.failure(WorkBuddyAuthError.stateMismatch))
                return
            }
        }
        pendingState = nil
        pendingExpiry = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<WorkBuddyOAuthToken, Error>
            do {
                let token = try self.tokenRequest(
                    parameters: [
                        "grant_type": "authorization_code",
                        "code": code,
                        "client_id": clientID,
                        "client_secret": clientSecret,
                        "redirect_uri": redirectURI
                    ]
                )
                do {
                    try WorkBuddyAuthStore.shared.saveToken(token, clientID: clientID)
                    result = .success(token)
                } catch {
                    // The token is valid but could not be persisted; surface that
                    // instead of reporting a successful authorization that would
                    // be gone after a relaunch.
                    result = .failure(error)
                }
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func refresh(refreshToken: String, clientID: String, clientSecret: String) throws -> WorkBuddyOAuthToken {
        try tokenRequest(
            parameters: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": clientID,
                "client_secret": clientSecret
            ]
        )
    }

    private func tokenRequest(parameters: [String: String]) throws -> WorkBuddyOAuthToken {
        var request = URLRequest(url: baseURL.appendingPathComponent("token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded(parameters)

        let (data, response) = try WorkBuddyHTTP.perform(request)
        guard let http = response as? HTTPURLResponse else { throw WorkBuddyAuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = WorkBuddyAuthError.description(from: data)
            let raw = String(data: data, encoding: .utf8) ?? ""
            let haystack = (detail + " " + raw).lowercased()
            if haystack.contains("invalid_grant")
                || haystack.contains("expired")
                || haystack.contains("already used")
                || haystack.contains("not found") {
                throw WorkBuddyAuthError.codeExpired
            }
            throw WorkBuddyAuthError.rejected(detail)
        }
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = payload["access_token"] as? String,
              let refreshToken = payload["refresh_token"] as? String else {
            throw WorkBuddyAuthError.invalidResponse
        }
        let expiresIn = (payload["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        return WorkBuddyOAuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn),
            scope: payload["scope"] as? String ?? "",
            openID: payload["open_id"] as? String ?? "",
            clientID: parameters["client_id"] ?? ""
        )
    }

    private func formEncoded(_ parameters: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery?.data(using: .utf8)
    }

}

/// Synchronous URLSession wrapper so the runner can block on a background queue.
enum WorkBuddyHTTP {
    static func perform(_ request: URLRequest) throws -> (Data, URLResponse) {
        var result: Result<(Data, URLResponse), Error>!
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else {
                result = .success((data ?? Data(), response ?? URLResponse()))
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return try result.get()
    }
}

extension WorkBuddyAuthError {
    /// Pulls `msg` / `message` out of an Open API error envelope.
    static func description(from data: Data) -> String {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return (payload["msg"] as? String)
            ?? (payload["message"] as? String)
            ?? (payload["error_description"] as? String)
            ?? ""
    }
}
