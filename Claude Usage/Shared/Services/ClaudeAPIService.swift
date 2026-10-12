import Foundation

/// Service for fetching usage data directly from Claude's API
class ClaudeAPIService {
    // MARK: - Types

    /// Authentication method for API requests
    private enum AuthenticationType {
        case claudeAISession(String)      // Cookie: sessionKey=...
        case cliOAuth(String)              // Authorization: Bearer ... (with anthropic-beta header)
    }

    // MARK: - Properties

    private let sessionKeyPath: URL
    private let sessionKeyValidator: SessionKeyValidator
    let baseURL = Constants.APIEndpoints.claudeBase

    // MARK: - Initialization

    init(sessionKeyPath: URL? = nil, sessionKeyValidator: SessionKeyValidator = SessionKeyValidator()) {
        // Default path: ~/.claude-session-key
        self.sessionKeyPath = sessionKeyPath ?? Constants.ClaudePaths.homeDirectory
            .appendingPathComponent(".claude-session-key")
        self.sessionKeyValidator = sessionKeyValidator
    }

    // MARK: - Session Key Management

    /// Cookie header for claude.ai session requests: the session key plus any
    /// Cloudflare clearance / device cookies captured by the sign-in webview
    /// (shared cookie storage). Requests that send ONLY `sessionKey` get
    /// challenged or rejected with E3000 permission errors even when the
    /// session is valid (#204, #277) — every claude.ai call must go through
    /// this, not just `performRequest`.
    static func sessionCookieHeader(sessionKey: String, url: URL) -> String {
        var cookiePairs = ["sessionKey=\(sessionKey)"]
        if let stored = HTTPCookieStorage.shared.cookies(for: url) {
            for cookie in stored where ["cf_clearance", "__cf_bm", "anthropic-device-id"].contains(cookie.name) {
                cookiePairs.append("\(cookie.name)=\(cookie.value)")
            }
        }
        return cookiePairs.joined(separator: "; ")
    }

    /// Builds an authenticated request with the appropriate headers for the auth type
    private func buildAuthenticatedRequest(url: URL, auth: AuthenticationType) -> URLRequest {
        var request = URLRequest(url: url)

        switch auth {
        case .claudeAISession(let sessionKey):
            // Existing claude.ai authentication
            request.setValue(Self.sessionCookieHeader(sessionKey: sessionKey, url: url), forHTTPHeaderField: "Cookie")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
            request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")

        case .cliOAuth(let accessToken):
            // CLI OAuth authentication (requires specific headers)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("claude-code/2.1.5", forHTTPHeaderField: "User-Agent")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        }

        return request
    }

    // MARK: - API Requests

    /// Fetches all organizations for the authenticated user
    func fetchAllOrganizations(sessionKey: String) async throws -> [AccountInfo] {
        return try await ErrorRecovery.shared.executeWithRetry(maxAttempts: 3) {

            // Build URL safely
            let url: URL
            do {
                url = try URLBuilder(baseURL: self.baseURL)
                    .appendingPath("/organizations")
                    .build()
            } catch {
                throw AppError.wrap(error)
            }

            var request = URLRequest(url: url)
            request.setValue(Self.sessionCookieHeader(sessionKey: sessionKey, url: url), forHTTPHeaderField: "Cookie")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
            request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
            request.httpMethod = "GET"
            request.timeoutInterval = 30

            let startTime = Date()
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                // Network errors
                let duration = Date().timeIntervalSince(startTime)

                let appError = AppError(
                    code: .networkGenericError,
                    message: "Failed to connect to Claude API",
                    technicalDetails: error.localizedDescription,
                    underlyingError: error,
                    isRecoverable: true,
                    recoverySuggestion: "Please check your internet connection and try again"
                )
                ErrorLogger.shared.log(appError)
                throw appError
            }

            let duration = Date().timeIntervalSince(startTime)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AppError(
                    code: .apiInvalidResponse,
                    message: "Invalid response from server",
                    isRecoverable: true
                )
            }

            // Log to NetworkLoggerService

            switch httpResponse.statusCode {
            case 200:
                // Parse organizations array
                do {
                    let organizations = try JSONDecoder().decode([AccountInfo].self, from: data)
                    guard !organizations.isEmpty else {
                        throw AppError(
                            code: .apiParsingFailed,
                            message: "No organizations found",
                            technicalDetails: "Organizations array is empty",
                            isRecoverable: false,
                            recoverySuggestion: "Please ensure your Claude account has access to organizations"
                        )
                    }

                    // Log all available organizations for debugging
                    LoggingService.shared.logInfo("Found \(organizations.count) organization(s):")
                    for (index, org) in organizations.enumerated() {
                        LoggingService.shared.logInfo("  [\(index)] \(org.name) (ID: \(org.uuid))")
                    }

                    return organizations
                } catch {
                    let appError = AppError(
                        code: .apiParsingFailed,
                        message: "Failed to parse organizations",
                        technicalDetails: error.localizedDescription,
                        underlyingError: error,
                        isRecoverable: false
                    )
                    ErrorLogger.shared.log(appError)
                    throw appError
                }

            case 401, 403:
                // A Cloudflare bot challenge is not an auth verdict: reporting
                // it as E3000/expired credentials sends users chasing
                // re-logins that can never help (#277).
                let preview = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
                if preview.contains("Just a moment") || httpResponse.value(forHTTPHeaderField: "cf-mitigated") != nil {
                    throw AppError(
                        code: .apiServiceUnavailable,
                        message: "Request blocked by Cloudflare protection.",
                        technicalDetails: "claude.ai answered the organizations request with a bot-verification challenge, not an auth verdict.",
                        isRecoverable: true,
                        recoverySuggestion: "Your session key is likely still valid. Re-open the sign-in window so the webview can refresh Cloudflare cookies, then try again."
                    )
                }
                throw AppError.apiUnauthorized()

            case 429:
                throw AppError.apiRateLimited()

            case 500...599:
                throw AppError.apiServerError(statusCode: httpResponse.statusCode)

            default:
                throw AppError(
                    code: .apiGenericError,
                    message: "Unexpected API response",
                    technicalDetails: "HTTP \(httpResponse.statusCode)",
                    isRecoverable: true
                )
            }
        }
    }

    // MARK: - Read-Only Testing

    /// testSessionKey with retry for freshly issued keys: a new sessionKey can
    /// take a moment to propagate on Anthropic's side, so the first request may
    /// get a transient 401 (E3000) even though the key is valid. Retries only
    /// on .apiUnauthorized, with a growing delay (1.5s, 3s, 4.5s).
    func testSessionKeyWithRetry(_ key: String, maxAttempts: Int = 4) async throws -> [AccountInfo] {
        var attempt = 1
        while true {
            do {
                return try await testSessionKey(key)
            } catch {
                guard AppError.wrap(error).code == .apiUnauthorized, attempt < maxAttempts else {
                    throw error
                }
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_500_000_000)
                attempt += 1
            }
        }
    }

    /// Tests a session key without saving to Keychain
    /// Returns available organizations if successful
    func testSessionKey(_ key: String) async throws -> [AccountInfo] {
        // Validate using professional validator
        let validatedKey = try sessionKeyValidator.validate(key)

        // Fetch organizations using the test key (don't save it)
        let organizations = try await fetchAllOrganizations(sessionKey: validatedKey)

        LoggingService.shared.logInfo("Tested session key - found \(organizations.count) organization(s)")

        return organizations
    }

    /// Fetches usage data for a specific profile using provided credentials
    /// - Parameters:
    ///   - sessionKey: The Claude.ai session key
    ///   - organizationId: The organization ID
    /// - Returns: ClaudeUsage data for the profile
    func fetchUsageData(sessionKey: String, organizationId: String) async throws -> ClaudeUsage {
        async let usageDataTask = performRequest(endpoint: "/organizations/\(organizationId)/usage", sessionKey: sessionKey)
        async let overageDataTask: Data? = performRequest(endpoint: "/organizations/\(organizationId)/overage_spend_limit", sessionKey: sessionKey)
        async let creditGrantTask: Data? = performRequest(endpoint: "/organizations/\(organizationId)/overage_credit_grant", sessionKey: sessionKey)

        let usageData = try await usageDataTask
        var claudeUsage = try parseUsageResponse(usageData)

        if let data = try? await overageDataTask,
           let overage = try? JSONDecoder().decode(OverageSpendLimitResponse.self, from: data),
           overage.isEnabled == true {
            claudeUsage.costUsed = overage.usedCredits
            claudeUsage.costLimit = overage.monthlyCreditLimit
            claudeUsage.costCurrency = overage.currency
        }

        if let creditData = try? await creditGrantTask,
           let creditGrant = try? JSONDecoder().decode(OverageCreditGrantResponse.self, from: creditData) {
            claudeUsage.overageBalance = creditGrant.remainingBalance
            claudeUsage.overageBalanceCurrency = creditGrant.currency
        }

        return claudeUsage
    }

    /// Fetches usage data via OAuth access token (CLI credential flow)
    func fetchUsageData(oauthAccessToken: String) async throws -> ClaudeUsage {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            throw AppError(code: .urlMalformed, message: "Invalid OAuth usage endpoint", isRecoverable: false)
        }

        var request = buildAuthenticatedRequest(url: url, auth: .cliOAuth(oauthAccessToken))
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError(code: .apiInvalidResponse, message: "Invalid response from OAuth endpoint", isRecoverable: true)
        }

        guard httpResponse.statusCode == 200 else {
            throw AppError(
                code: httpResponse.statusCode == 401 || httpResponse.statusCode == 403
                    ? .apiUnauthorized : .apiGenericError,
                message: "OAuth fetch failed (status \(httpResponse.statusCode))",
                isRecoverable: true
            )
        }

        return try parseUsageResponse(data)
    }

    private func performRequest(endpoint: String, sessionKey: String) async throws -> Data {
        // Build URL safely
        let url = try URLBuilder(baseURL: baseURL)
            .appendingPath(endpoint)
            .build()

        var request = URLRequest(url: url)
        // Include Cloudflare clearance cookies captured by the sign-in webview
        // (shared cookie storage) — without them claude.ai intermittently
        // answers with a 403 "Just a moment..." challenge page.
        request.setValue(Self.sessionCookieHeader(sessionKey: sessionKey, url: url), forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        LoggingService.shared.logAPIRequest(endpoint)

        let startTime = Date()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // Network-level errors
            let duration = Date().timeIntervalSince(startTime)

            LoggingService.shared.logAPIError(endpoint, error: error)
            let appError = AppError(
                code: .networkGenericError,
                message: "Failed to connect to Claude API",
                technicalDetails: "Endpoint: \(endpoint)\nError: \(error.localizedDescription)",
                underlyingError: error,
                isRecoverable: true,
                recoverySuggestion: "Please check your internet connection and try again"
            )
            throw appError
        }

        let duration = Date().timeIntervalSince(startTime)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError(
                code: .apiInvalidResponse,
                message: "Invalid response from server",
                technicalDetails: "Endpoint: \(endpoint)",
                isRecoverable: true
            )
        }

        LoggingService.shared.logAPIResponse(endpoint, statusCode: httpResponse.statusCode)

        // Log to NetworkLoggerService

        switch httpResponse.statusCode {
        case 200:
            return data

        case 401, 403:
            // Include response body in error for debugging
            let responsePreview = String(data: data, encoding: .utf8)?.prefix(200) ?? "Unable to read response"

            // Cloudflare bot challenge, not an actual auth failure — the
            // session key is fine, the request just got challenged. Must NOT
            // be .apiUnauthorized: the credential-error banner keys off that
            // code and would falsely tell the user their credentials expired
            // (#277).
            if responsePreview.contains("Just a moment") || responsePreview.contains("cf-mitigated")
                || httpResponse.value(forHTTPHeaderField: "cf-mitigated") != nil {
                throw AppError(
                    code: .apiServiceUnavailable,
                    message: "Request blocked by Cloudflare protection.",
                    technicalDetails: "Endpoint: \(endpoint)\nStatus: \(httpResponse.statusCode)\nCloudflare challenge page returned",
                    isRecoverable: true,
                    recoverySuggestion: "Your session key is likely still valid — this usually resolves on the next refresh. If it persists, re-sign-in via Settings to refresh Cloudflare cookies."
                )
            }

            throw AppError(
                code: .apiUnauthorized,
                message: "Unauthorized. Your session key may have expired.",
                technicalDetails: "Endpoint: \(endpoint)\nStatus: \(httpResponse.statusCode)\nResponse: \(responsePreview)",
                isRecoverable: true,
                recoverySuggestion: "Please update your session key in Settings"
            )

        case 429:
            throw AppError(
                code: .apiRateLimited,
                message: "Rate limited by Claude API",
                technicalDetails: "Endpoint: \(endpoint)",
                isRecoverable: true,
                recoverySuggestion: "Please wait a few minutes before trying again"
            )

        case 500...599:
            let responsePreview = String(data: data, encoding: .utf8)?.prefix(200) ?? "Unable to read response"
            throw AppError(
                code: .apiServerError,
                message: "Claude API server error",
                technicalDetails: "Endpoint: \(endpoint)\nStatus: \(httpResponse.statusCode)\nResponse: \(responsePreview)",
                isRecoverable: true,
                recoverySuggestion: "Please try again later"
            )

        default:
            let responsePreview = String(data: data, encoding: .utf8)?.prefix(200) ?? "Unable to read response"
            throw AppError(
                code: .apiGenericError,
                message: "Unexpected API response",
                technicalDetails: "Endpoint: \(endpoint)\nStatus: \(httpResponse.statusCode)\nResponse: \(responsePreview)",
                isRecoverable: true
            )
        }
    }

    // MARK: - Response Parsing

    private func parseUsageResponse(_ data: Data) throws -> ClaudeUsage {
        // Parse Claude's actual API response structure

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // One shared formatter for every resets_at field in this response —
            // ISO8601DateFormatter construction is expensive.
            let resetTimeFormatter = ISO8601DateFormatter()
            resetTimeFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            // Extract session usage (five_hour)
            var sessionPercentage = 0.0
            var sessionResetTime = Date().addingTimeInterval(5 * 3600)
            if let fiveHour = json["five_hour"] as? [String: Any] {
                if let utilization = fiveHour["utilization"] {
                    sessionPercentage = parseUtilization(utilization)
                }
                if let resetsAt = fiveHour["resets_at"] as? String {
                    sessionResetTime = resetTimeFormatter.date(from: resetsAt) ?? sessionResetTime
                }
            }

            // Extract weekly usage (seven_day)
            var weeklyPercentage = 0.0
            var weeklyResetTime = Date().nextMonday1259pm()
            if let sevenDay = json["seven_day"] as? [String: Any] {
                if let utilization = sevenDay["utilization"] {
                    weeklyPercentage = parseUtilization(utilization)
                }
                if let resetsAt = sevenDay["resets_at"] as? String {
                    weeklyResetTime = resetTimeFormatter.date(from: resetsAt) ?? weeklyResetTime
                }
            }

            // Extract Opus weekly usage (seven_day_opus)
            var opusPercentage = 0.0
            if let sevenDayOpus = json["seven_day_opus"] as? [String: Any] {
                if let utilization = sevenDayOpus["utilization"] {
                    opusPercentage = parseUtilization(utilization)
                }
            }

            // Extract Sonnet weekly usage (seven_day_sonnet)
            var sonnetPercentage = 0.0
            var sonnetResetTime: Date? = nil
            if let sevenDaySonnet = json["seven_day_sonnet"] as? [String: Any] {
                if let utilization = sevenDaySonnet["utilization"] {
                    sonnetPercentage = parseUtilization(utilization)
                }
                if let resetsAt = sevenDaySonnet["resets_at"] as? String {
                    sonnetResetTime = resetTimeFormatter.date(from: resetsAt)
                }
            }

            // Extract Design weekly usage (seven_day_design)
            var designPercentage = 0.0
            var designResetTime: Date? = nil
            if let sevenDayDesign = json["seven_day_omelette"] as? [String: Any] {
                if let utilization = sevenDayDesign["utilization"] {
                    designPercentage = parseUtilization(utilization)
                }
                if let resetsAt = sevenDayDesign["resets_at"] as? String {
                    designResetTime = resetTimeFormatter.date(from: resetsAt)
                }
            }

            // Extract Fable weekly usage (seven_day_fable)
            var fablePercentage = 0.0
            var fableResetTime: Date? = nil
            if let sevenDayFable = json["seven_day_fable"] as? [String: Any] {
                if let utilization = sevenDayFable["utilization"] {
                    fablePercentage = parseUtilization(utilization)
                }
                if let resetsAt = sevenDayFable["resets_at"] as? String {
                    fableResetTime = resetTimeFormatter.date(from: resetsAt)
                }
            }

            // Newer API responses null out the legacy seven_day_* per-model
            // fields and report per-model usage in a "limits" array instead:
            // {"kind":"weekly_scoped","percent":73,"resets_at":...,
            //  "scope":{"model":{"id":null,"display_name":"Fable"}}}
            // limits[] is therefore the source of truth: when an entry is
            // present it overrides whatever the legacy fields said.
            if let limits = json["limits"] as? [[String: Any]] {
                for limit in limits {
                    guard limit["kind"] as? String == "weekly_scoped",
                          let scope = limit["scope"] as? [String: Any],
                          let model = scope["model"] as? [String: Any],
                          let percentValue = limit["percent"] else { continue }
                    let percent = parseUtilization(percentValue)
                    let resetTime = (limit["resets_at"] as? String).flatMap { resetTimeFormatter.date(from: $0) }

                    // Match on the stable model id when the API provides one;
                    // display_name is a rename-prone human label kept as fallback.
                    let modelId = (model["id"] as? String)?.lowercased() ?? ""
                    let name = (model["display_name"] as? String)?.lowercased() ?? ""
                    func matches(_ keys: String...) -> Bool {
                        keys.contains { name == $0 || modelId.contains($0) }
                    }

                    if matches("fable", "mythos") {
                        fablePercentage = percent
                        fableResetTime = resetTime ?? fableResetTime
                    } else if matches("opus") {
                        opusPercentage = percent
                    } else if matches("sonnet") {
                        sonnetPercentage = percent
                        sonnetResetTime = resetTime ?? sonnetResetTime
                    } else if matches("design", "omelette") {
                        designPercentage = percent
                        designResetTime = resetTime ?? designResetTime
                    }
                }
            }

            // We don't know user's plan, so we use 0 for limits we can't determine
            let weeklyLimit = Constants.weeklyLimit

            // Calculate token counts from percentages (using weekly limit as reference)
            let sessionTokens = 0  // Can't calculate without knowing plan
            let sessionLimit = 0   // Unknown without plan
            let weeklyTokens = Int(Double(weeklyLimit) * (weeklyPercentage / 100.0))
            let opusTokens = Int(Double(weeklyLimit) * (opusPercentage / 100.0))
            let sonnetTokens = Int(Double(weeklyLimit) * (sonnetPercentage / 100.0))
            let designTokens = Int(Double(weeklyLimit) * (designPercentage / 100.0))
            let fableTokens = Int(Double(weeklyLimit) * (fablePercentage / 100.0))

            let usage = ClaudeUsage(
                sessionTokensUsed: sessionTokens,
                sessionLimit: sessionLimit,
                sessionPercentage: sessionPercentage,
                sessionResetTime: sessionResetTime,
                weeklyTokensUsed: weeklyTokens,
                weeklyLimit: weeklyLimit,
                weeklyPercentage: weeklyPercentage,
                weeklyResetTime: weeklyResetTime,
                opusWeeklyTokensUsed: opusTokens,
                opusWeeklyPercentage: opusPercentage,
                sonnetWeeklyTokensUsed: sonnetTokens,
                sonnetWeeklyPercentage: sonnetPercentage,
                sonnetWeeklyResetTime: sonnetResetTime,
                designWeeklyTokensUsed: designTokens,
                designWeeklyPercentage: designPercentage,
                designWeeklyResetTime: designResetTime,
                fableWeeklyTokensUsed: fableTokens,
                fableWeeklyPercentage: fablePercentage,
                fableWeeklyResetTime: fableResetTime,
                costUsed: nil,
                costLimit: nil,
                costCurrency: nil,
                lastUpdated: Date(),
                userTimezone: .current
            )

            return usage
        }

        throw AppError(
            code: .apiParsingFailed,
            message: "Failed to parse usage data",
            technicalDetails: "Unable to parse JSON response structure",
            isRecoverable: false,
            recoverySuggestion: "Please check the error log and report this issue"
        )
    }

    // MARK: - Rate Limit Header Parsing

    // MARK: - Parsing Helpers

    /// Robust utilization parser that handles Int, Double, or String types
    /// - Parameter value: The utilization value from API (can be Int, Double, or String)
    /// - Returns: Parsed percentage as Double, or 0.0 if parsing fails
    private func parseUtilization(_ value: Any) -> Double {
        // Try Int first (most common)
        if let intValue = value as? Int {
            return Double(intValue)
        }

        // Try Double
        if let doubleValue = value as? Double {
            return doubleValue
        }

        // Try String
        if let stringValue = value as? String {
            // Remove any percentage symbols or whitespace
            let cleaned = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "%", with: "")

            if let parsed = Double(cleaned) {
                return parsed
            }
        }

        // Log warning if we couldn't parse
        LoggingService.shared.logWarning("Failed to parse utilization value: \(value) (type: \(type(of: value)))")
        return 0.0
    }

    // MARK: - Session Initialization

}
