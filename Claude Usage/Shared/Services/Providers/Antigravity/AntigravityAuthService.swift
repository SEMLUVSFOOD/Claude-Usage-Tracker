//
//  AntigravityAuthService.swift
//  Claude Usage
//
//  Google sign-in for the Antigravity provider. Google stopped serving quota
//  data to the Gemini CLI's OAuth client for personal accounts (June 2026);
//  Antigravity's own client still works, so — like CodexBar — the sign-in
//  client is discovered at runtime from the locally installed Antigravity.app.
//

import AppKit
import CryptoKit
import Foundation
import Network

/// Tokens stored (as JSON) in `Profile.antigravityCredentialsJSON`.
struct AntigravityCredentials: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    /// Epoch milliseconds, like `~/.gemini/oauth_creds.json`
    var expiryDate: Double
    var idToken: String?
    var email: String?
    /// The OAuth client that issued the grant; refresh tokens are bound to it.
    var clientId: String
    var clientSecret: String
    var projectId: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiryDate = "expiry_date"
        case idToken = "id_token"
        case email
        case clientId = "client_id"
        case clientSecret = "client_secret"
        case projectId = "project_id"
    }

    var isExpiringSoon: Bool {
        expiryDate / 1000 - Date().timeIntervalSince1970 < 60
    }

    func serialized() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func parse(_ json: String?) -> AntigravityCredentials? {
        guard let data = json?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AntigravityCredentials.self, from: data)
    }
}

/// An OAuth client found inside Antigravity.app.
struct AntigravityOAuthClient: Equatable {
    let clientId: String
    let secrets: [String]  // candidate secrets; the pairing is resolved at code exchange
}

final class AntigravityAuthService {
    static let shared = AntigravityAuthService()

    private static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private static let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let scopes = [
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "openid",
    ]
    /// Gemini CLI's public client — present in some builds but rejected for
    /// personal accounts' quota, so never pick it.
    private static let geminiCLIClientId = "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com"

    private var cachedClients: [AntigravityOAuthClient]?
    /// Diagnostic for the "not found" error, e.g. "scanned 2 file(s), found 1 ID(s) and 0 secret(s)"
    private var lastDiscoverySummary = ""
    private var listener: NWListener?

    private init() {}

    // MARK: - Client discovery

    /// Client IDs and secrets embedded in the installed Antigravity app's
    /// language server binary. Cached after the first (slow-ish) scan.
    func discoverClients() -> [AntigravityOAuthClient] {
        if let cachedClients { return cachedClients }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let apps = [
            "/Applications/Antigravity.app",
            "\(home)/Applications/Antigravity.app",
            "/Applications/Antigravity IDE.app",
            "\(home)/Applications/Antigravity IDE.app",
        ]
        var ids: [String] = []
        var secrets: [String] = []
        var scannedBinaries = 0
        for app in apps where FileManager.default.fileExists(atPath: app) {
            for binary in languageServerBinaries(in: app) {
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: binary), options: .alwaysMapped) else { continue }
                scannedBinaries += 1
                for id in Self.scanClientIds(in: data) where !ids.contains(id) && id != Self.geminiCLIClientId {
                    ids.append(id)
                }
                for secret in Self.scanSecrets(in: data) where !secrets.contains(secret) {
                    secrets.append(secret)
                }
            }
            if !ids.isEmpty && !secrets.isEmpty { break }
        }
        let clients = secrets.isEmpty ? [] : ids.map { AntigravityOAuthClient(clientId: $0, secrets: secrets) }
        LoggingService.shared.log("Antigravity: discovered \(ids.count) client ID(s), \(secrets.count) secret candidate(s) in \(scannedBinaries) binaries")
        lastDiscoverySummary = "scanned \(scannedBinaries) file(s), found \(ids.count) ID(s) and \(secrets.count) secret(s)"
        if !clients.isEmpty { cachedClients = clients }
        return clients
    }

    private func languageServerBinaries(in app: String) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: app + "/Contents") else { return [] }
        var result: [String] = []
        for case let path as String in enumerator {
            let name = (path as NSString).lastPathComponent.lowercased()
            if name.hasPrefix("language_server") || name.hasPrefix("language-server") {
                result.append(app + "/Contents/" + path)
            }
        }
        return result
    }

    private static func scanClientIds(in data: Data) -> [String] {
        let suffix = Array(".apps.googleusercontent.com".utf8)
        var found: [String] = []
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            var i = 0
            while let range = find(suffix, in: bytes, from: i) {
                var start = range
                while start > 0, isClientIdByte(bytes[start - 1]) { start -= 1 }
                // Binaries pool strings back-to-back with no separators, so the
                // span can start with the tail of a neighbouring string and the
                // project number's true length is ambiguous. Emit each plausible
                // length; verifiedClients() asks Google which one exists.
                let span = String(decoding: bytes[start..<(range + suffix.count)], as: UTF8.self)
                if let match = span.range(of: #"[0-9]+-[a-z0-9]{32}\.apps\.googleusercontent\.com$"#,
                                          options: .regularExpression) {
                    let full = span[match]
                    let dash = full.firstIndex(of: "-")!
                    let digits = full[full.startIndex..<dash]
                    let rest = full[dash...]
                    for length in [12, 11, 13, 10, 14] where digits.count >= length {
                        let id = String(digits.suffix(length)) + rest
                        if !found.contains(id) { found.append(id) }
                    }
                }
                i = range + suffix.count
            }
        }
        return found
    }

    private static func scanSecrets(in data: Data) -> [String] {
        let prefix = Array("GOCSPX-".utf8)
        var found: [String] = []
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            var i = 0
            while let range = find(prefix, in: bytes, from: i) {
                // "GOCSPX-" + 28 characters; anything after is a neighbouring pooled string
                let length = prefix.count + 28
                var end = range + prefix.count
                while end < bytes.count, end < range + length, isSecretByte(bytes[end]) { end += 1 }
                if end == range + length {
                    let secret = String(decoding: bytes[range..<end], as: UTF8.self)
                    if !found.contains(secret) { found.append(secret) }
                }
                i = range + prefix.count
            }
        }
        return found
    }

    private static func find(_ needle: [UInt8], in haystack: UnsafeBufferPointer<UInt8>, from start: Int) -> Int? {
        guard let first = needle.first, haystack.count >= needle.count else { return nil }
        var i = start
        let last = haystack.count - needle.count
        while i <= last {
            if haystack[i] == first {
                var j = 1
                while j < needle.count, haystack[i + j] == needle[j] { j += 1 }
                if j == needle.count { return i }
            }
            i += 1
        }
        return nil
    }

    private static func isClientIdByte(_ b: UInt8) -> Bool {
        (b >= 48 && b <= 57) || (b >= 97 && b <= 122) || b == 45  // 0-9 a-z -
    }

    private static func isSecretByte(_ b: UInt8) -> Bool {
        (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 45 || b == 95
    }

    // MARK: - Client verification

    private var verifiedClientsCache: [AntigravityOAuthClient]?

    /// (client ID, secret) pairs Google actually recognises. Probes the token
    /// endpoint with a dummy refresh token: an unknown client or wrong secret
    /// answers `invalid_client`, a real pair answers `invalid_grant`. This way
    /// the browser only ever opens with a client that exists.
    func verifiedClients() async throws -> [AntigravityOAuthClient] {
        if let verifiedClientsCache { return verifiedClientsCache }
        let candidates = discoverClients()
        guard !candidates.isEmpty else {
            throw Self.error(.providerCredentialsNotFound,
                             "Couldn't find Antigravity's Google sign-in (\(lastDiscoverySummary)).")
        }
        let pairs = candidates.flatMap { client in client.secrets.map { (client.clientId, $0) } }
        let valid = await withTaskGroup(of: (String, String)?.self) { group -> [(String, String)] in
            for (id, secret) in pairs {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    return await self.isValidPair(clientId: id, secret: secret) ? (id, secret) : nil
                }
            }
            var result: [(String, String)] = []
            for await pair in group { if let pair { result.append(pair) } }
            return result
        }
        // Keep discovery order (it reflects the binary's own ordering)
        let ordered = pairs.filter { pair in valid.contains { $0 == pair } }
        LoggingService.shared.log("Antigravity: \(ordered.count) of \(pairs.count) sign-in pair(s) accepted by Google")
        guard !ordered.isEmpty else {
            throw Self.error(.providerCredentialsNotFound,
                             "Google didn't accept any of the sign-ins found in Antigravity (\(lastDiscoverySummary), \(pairs.count) tried).")
        }
        let clients = ordered.map { AntigravityOAuthClient(clientId: $0.0, secrets: [$0.1]) }
        verifiedClientsCache = clients
        return clients
    }

    private func isValidPair(clientId: String, secret: String) async -> Bool {
        do {
            _ = try await tokenRequest([
                "client_id": clientId,
                "client_secret": secret,
                "refresh_token": "invalid",
                "grant_type": "refresh_token",
            ])
            return true
        } catch let error as TokenError {
            return error.code == "invalid_grant"
        } catch {
            return false
        }
    }

    // MARK: - Sign in

    /// Opens Google sign-in in the browser and waits for the redirect to a
    /// local loopback port. `clientIndex` picks among discovered clients so the
    /// UI can retry with another one if Google rejects the first.
    func signIn(clientIndex: Int = 0) async throws -> AntigravityCredentials {
        let clients = try await verifiedClients()
        let client = clients[clientIndex % clients.count]

        let verifier = Self.randomURLSafeString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
        let state = Self.randomURLSafeString(24)

        let (port, codeTask) = try await startCallbackListener(expectedState: state)
        let redirectURI = "http://127.0.0.1:\(port)"

        var components = URLComponents(string: Self.authURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: client.clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        await MainActor.run { _ = NSWorkspace.shared.open(components.url!) }

        let code = try await codeTask.value
        return try await exchange(code: code, verifier: verifier, redirectURI: redirectURI, client: client)
    }

    /// Number of discovered clients (for the "try another" retry in the UI).
    var clientCount: Int { verifiedClientsCache?.count ?? 0 }

    func cancelSignIn() {
        listener?.cancel()
        listener = nil
    }

    private func exchange(code: String, verifier: String, redirectURI: String,
                          client: AntigravityOAuthClient) async throws -> AntigravityCredentials {
        var lastError: Error?
        for secret in client.secrets {
            do {
                let json = try await tokenRequest([
                    "client_id": client.clientId,
                    "client_secret": secret,
                    "code": code,
                    "code_verifier": verifier,
                    "redirect_uri": redirectURI,
                    "grant_type": "authorization_code",
                ])
                guard let access = json["access_token"] as? String,
                      let refresh = json["refresh_token"] as? String else {
                    throw Self.error(.providerAuthRefreshFailed, "Google didn't return a refresh token.")
                }
                let idToken = json["id_token"] as? String
                let expiresIn = (json["expires_in"] as? Double) ?? 3600
                return AntigravityCredentials(
                    accessToken: access,
                    refreshToken: refresh,
                    expiryDate: (Date().timeIntervalSince1970 + expiresIn) * 1000,
                    idToken: idToken,
                    email: Self.email(fromIDToken: idToken),
                    clientId: client.clientId,
                    clientSecret: secret,
                    projectId: nil
                )
            } catch let error as TokenError where error.code == "invalid_client" {
                lastError = error  // wrong secret for this client — try the next
            }
        }
        throw lastError ?? Self.error(.providerAuthRefreshFailed, "Google sign-in failed.")
    }

    // MARK: - Refresh

    func refreshIfNeeded(_ credentials: AntigravityCredentials, force: Bool = false) async throws -> AntigravityCredentials {
        guard force || credentials.isExpiringSoon else { return credentials }
        let json: [String: Any]
        do {
            json = try await tokenRequest([
                "client_id": credentials.clientId,
                "client_secret": credentials.clientSecret,
                "refresh_token": credentials.refreshToken,
                "grant_type": "refresh_token",
            ])
        } catch let error as TokenError where error.code == "invalid_grant" {
            throw Self.error(.providerAuthExpired, "Your Google sign-in expired. Sign in again in Settings.")
        }
        guard let access = json["access_token"] as? String else {
            throw Self.error(.providerAuthRefreshFailed, "Google didn't return a new access token.")
        }
        var refreshed = credentials
        refreshed.accessToken = access
        refreshed.expiryDate = (Date().timeIntervalSince1970 + ((json["expires_in"] as? Double) ?? 3600)) * 1000
        if let idToken = json["id_token"] as? String {
            refreshed.idToken = idToken
            refreshed.email = Self.email(fromIDToken: idToken) ?? refreshed.email
        }
        if let rotated = json["refresh_token"] as? String { refreshed.refreshToken = rotated }
        return refreshed
    }

    private struct TokenError: Error {
        let code: String
        let status: Int
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = fields
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard status == 200 else {
            throw TokenError(code: json["error"] as? String ?? "http_\(status)", status: status)
        }
        return json
    }

    // MARK: - Loopback callback

    /// Listens on 127.0.0.1:<random port> for Google's redirect and resolves
    /// with the authorization code.
    private func startCallbackListener(expectedState: String) async throws -> (UInt16, Task<String, Error>) {
        cancelSignIn()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener

        let codeStream = AsyncThrowingStream<String, Error> { continuation in
            listener.newConnectionHandler = { connection in
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                    let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                    let result = Self.parseCallback(request, expectedState: expectedState)
                    let body: String
                    switch result {
                    case .success:
                        body = "<h2>Signed in to Claude Usage</h2><p>You can close this tab.</p>"
                    case .failure(let error):
                        body = "<h2>Sign-in failed</h2><p>\(error.localizedDescription)</p>"
                    case nil:
                        body = ""
                    }
                    let html = "<html><body style=\"font-family:-apple-system;text-align:center;padding-top:80px\">\(body)</body></html>"
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                    switch result {
                    case .success(let code): continuation.yield(code); continuation.finish()
                    case .failure(let error): continuation.finish(throwing: error)
                    case nil: break  // e.g. favicon request
                    }
                }
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state { continuation.finish(throwing: error) }
                if case .cancelled = state { continuation.finish(throwing: CancellationError()) }
            }
        }

        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            let previous = listener.stateUpdateHandler
            listener.stateUpdateHandler = { state in
                previous?(state)
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: .main)
        }

        let task = Task<String, Error> { [weak self] in
            defer { Task { @MainActor in self?.cancelSignIn() } }
            // Give up after 5 minutes so a forgotten browser tab doesn't hold the port
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    for try await code in codeStream { return code }
                    throw CancellationError()
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 300 * 1_000_000_000)
                    throw Self.error(.providerAuthExpired, "Google sign-in timed out.")
                }
                let code = try await group.next()!
                group.cancelAll()
                return code
            }
        }
        return (port, task)
    }

    private static func parseCallback(_ request: String, expectedState: String) -> Result<String, Error>? {
        guard let line = request.split(separator: "\r\n").first,
              let path = line.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: "http://127.0.0.1\(path)") else { return nil }
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        if let error = items["error"] {
            return .failure(Self.error(.providerAuthExpired, "Google sign-in was cancelled (\(error))."))
        }
        guard let code = items["code"] else { return nil }
        guard items["state"] == expectedState else {
            return .failure(Self.error(.providerAuthExpired, "Google sign-in state mismatch; try again."))
        }
        return .success(code)
    }

    // MARK: - Helpers

    static func email(fromIDToken idToken: String?) -> String? {
        guard let payload = idToken?.split(separator: ".").dropFirst().first else { return nil }
        var base64 = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return claims["email"] as? String
    }

    private static func randomURLSafeString(_ length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    static func error(_ code: ErrorCode, _ message: String) -> AppError {
        AppError(code: code, message: message, isRecoverable: true)
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
