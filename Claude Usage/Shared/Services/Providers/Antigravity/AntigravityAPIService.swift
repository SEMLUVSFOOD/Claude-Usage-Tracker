//
//  AntigravityAPIService.swift
//  Claude Usage
//
//  Antigravity quota via Google's Cloud Code API (the endpoints the Antigravity
//  app itself uses). Request/response handling follows CodexBar's provider.
//  Parsing is deliberately tolerant (JSONSerialization, every field optional):
//  this is a private Google API and its shape can change.
//

import Foundation

final class AntigravityAPIService {
    static let shared = AntigravityAPIService()

    private static let baseURL = "https://cloudcode-pa.googleapis.com/v1internal"
    private static let metadata = ["ideType": "ANTIGRAVITY", "platform": "PLATFORM_UNSPECIFIED", "pluginType": "GEMINI"]
    /// Cloud Code only grants quota access to the Antigravity "hub" client family.
    private static let userAgent: String = {
        #if arch(arm64)
        return "antigravity/hub/2.9.1 darwin/arm64"
        #else
        return "antigravity/hub/2.9.1 darwin/amd64"
        #endif
    }()

    private init() {}

    struct Account {
        let projectId: String?
        let plan: String?
    }

    /// One quota window from the summary (e.g. "Gemini Models" five-hour limit).
    struct QuotaWindow {
        enum Cadence { case session, weekly, unknown }
        let group: String
        let cadence: Cadence
        let usedPercent: Double
        let resetTime: Date?
    }

    // MARK: - Requests

    func loadAccount(accessToken: String, storedProjectId: String?) async throws -> Account {
        let json = try await post("loadCodeAssist", body: ["metadata": Self.metadata], accessToken: accessToken)
        let project = storedProjectId ?? Self.projectId(from: json["cloudaicompanionProject"])
        let currentTier = json["currentTier"] as? [String: Any]
        let paidTier = json["paidTier"] as? [String: Any]
        let ineligible = (json["ineligibleTiers"] as? [[String: Any]]) ?? []

        if currentTier == nil, project == nil,
           ineligible.contains(where: { ($0["reasonCode"] as? String) == "GOOGLE_TOS_NOT_SUPPORTED_BY_CLIENT" }) {
            // Signed in with an Antigravity client Google doesn't accept for this
            // account type; quota would come back as placeholder 100% values.
            throw AppError(
                code: .providerAuthExpired,
                message: "Google rejected this sign-in for quota. Sign in again in Settings and choose \"Try another sign-in\".",
                isRecoverable: true
            )
        }
        let plan = (paidTier?["name"] as? String) ?? (currentTier?["name"] as? String)
        return Account(projectId: project, plan: plan)
    }

    func fetchQuotaWindows(accessToken: String, projectId: String?) async throws -> [QuotaWindow] {
        let body: [String: Any] = projectId.map { ["project": $0] } ?? [:]
        if let summary = try? await post("retrieveUserQuotaSummary", body: body, accessToken: accessToken) {
            let windows = Self.parseSummary(summary)
            if !windows.isEmpty { return windows }
        }
        // Fallback: per-model quotas (session-style windows only)
        let models = try await post("fetchAvailableModels", body: body, accessToken: accessToken)
        return Self.parseModels(models)
    }

    private func post(_ method: String, body: [String: Any], accessToken: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "\(Self.baseURL):\(method)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AppError(code: .apiParsingFailed, message: "Unexpected response from Google.",
                               technicalDetails: "\(method): not a JSON object", isRecoverable: true)
            }
            return json
        case 401:
            throw AppError(code: .providerAuthExpired, message: "Your Google sign-in expired. Sign in again in Settings.",
                           technicalDetails: "\(method) returned 401", isRecoverable: true)
        default:
            let snippet = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
            throw AppError(code: .apiServerError, message: "Google returned an error (\(status)).",
                           technicalDetails: "\(method) returned \(status): \(snippet)", isRecoverable: true)
        }
    }

    // MARK: - Parsing

    private static func projectId(from value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        if let object = value as? [String: Any] {
            return (object["id"] as? String) ?? (object["projectId"] as? String)
        }
        return nil
    }

    /// `{response?: {groups: [{displayName, buckets: [{bucketId, displayName,
    /// remaining: {remainingFraction}, description, window, resetTime?}]}]}}`
    static func parseSummary(_ json: [String: Any]) -> [QuotaWindow] {
        let root = (json["response"] as? [String: Any]) ?? json
        guard let groups = root["groups"] as? [[String: Any]] else { return [] }
        var windows: [QuotaWindow] = []
        for group in groups {
            let groupName = (group["displayName"] as? String) ?? "Models"
            for bucket in (group["buckets"] as? [[String: Any]]) ?? [] {
                let remaining = bucket["remaining"] as? [String: Any]
                guard let fraction = number(remaining?["remainingFraction"]) ?? number(bucket["remainingFraction"]) else {
                    continue
                }
                let reset = date(remaining?["resetTime"]) ?? date(bucket["resetTime"])
                    ?? date((bucket["window"] as? [String: Any])?["resetTime"])
                windows.append(QuotaWindow(
                    group: groupName,
                    cadence: cadence(of: bucket),
                    usedPercent: max(0, min(100, (1 - fraction) * 100)),
                    resetTime: reset
                ))
            }
        }
        return windows
    }

    /// `{models: {<id>: {displayName?, quotaInfo?: {remainingFraction?, resetTime?}}}}`
    static func parseModels(_ json: [String: Any]) -> [QuotaWindow] {
        guard let models = json["models"] as? [String: Any] else { return [] }
        return models.compactMap { id, value in
            guard let model = value as? [String: Any],
                  let quota = model["quotaInfo"] as? [String: Any],
                  let fraction = number(quota["remainingFraction"]) else { return nil }
            let lowered = id.lowercased()
            // Lite, autocomplete and image variants don't represent the main pools
            if ["lite", "autocomplete", "image", "embedding"].contains(where: lowered.contains) { return nil }
            let group = lowered.contains("gemini") ? "Gemini Models" : "Claude and GPT models"
            return QuotaWindow(group: group, cadence: .session,
                               usedPercent: max(0, min(100, (1 - fraction) * 100)),
                               resetTime: date(quota["resetTime"]))
        }
    }

    /// Weekly vs five-hour, from the explicit `window` field when present,
    /// else the bucket id / name / description.
    private static func cadence(of bucket: [String: Any]) -> QuotaWindow.Cadence {
        var text = [bucket["bucketId"], bucket["displayName"], bucket["description"]]
            .compactMap { $0 as? String }
        if let window = bucket["window"] {
            text.insert(contentsOf: flattenStrings(window), at: 0)
            if let seconds = durationSeconds(window) {
                return seconds >= 86_400 * 2 ? .weekly : .session
            }
        }
        let joined = text.joined(separator: " ").lowercased()
        if joined.contains("week") || joined.contains("7d") || joined.contains("7-day") { return .weekly }
        if joined.contains("hour") || joined.contains("5h") || joined.contains("session") || joined.contains("daily") {
            return .session
        }
        return .unknown
    }

    private static func durationSeconds(_ window: Any) -> Double? {
        if let object = window as? [String: Any] {
            for key in ["duration", "length", "windowDuration"] {
                if let seconds = durationSeconds(object[key] as Any) { return seconds }
            }
            return number(object["seconds"]) ?? number(object["durationSeconds"])
        }
        if let string = window as? String, string.hasSuffix("s"), let value = Double(string.dropLast()) {
            return value  // protobuf Duration JSON, e.g. "604800s"
        }
        return nil
    }

    private static func flattenStrings(_ value: Any) -> [String] {
        if let string = value as? String { return [string] }
        if let object = value as? [String: Any] { return object.values.flatMap(flattenStrings) }
        if let array = value as? [Any] { return array.flatMap(flattenStrings) }
        return []
    }

    private static func number(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let string = value as? String { return Double(string) }
        return (value as? NSNumber)?.doubleValue
    }

    private static func date(_ value: Any?) -> Date? {
        if let string = value as? String {
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: string) ?? ISO8601DateFormatter().date(from: string) {
                return date
            }
            if let seconds = Double(string) { return Date(timeIntervalSince1970: seconds) }
        }
        if let seconds = number(value) { return Date(timeIntervalSince1970: seconds) }
        return nil
    }

    // MARK: - Mapping

    /// Session = most constrained five-hour window, weekly = most constrained
    /// weekly window, across the Gemini and Claude/GPT groups.
    /// The plan (e.g. "Google AI Pro") is deliberately not mapped: the dropdown's
    /// plan badge adds little for Google accounts.
    static func mapToUsage(_ windows: [QuotaWindow], previous: ClaudeUsage?) -> ClaudeUsage {
        let session = windows.filter { $0.cadence != .weekly }.max { $0.usedPercent < $1.usedPercent }
        let weekly = windows.filter { $0.cadence == .weekly }.max { $0.usedPercent < $1.usedPercent }

        var usage = ClaudeUsage.empty
        usage.weeklyLimit = 0  // no token counts
        usage.sessionPercentage = session?.usedPercent ?? 0
        usage.sessionResetTime = session?.resetTime
            ?? (previous?.sessionResetTime).flatMap { $0 > Date() ? $0 : nil }
            ?? Date().addingTimeInterval(5 * 60 * 60)
        usage.weeklyPercentage = weekly?.usedPercent ?? 0
        usage.weeklyResetTime = weekly?.resetTime
            ?? (previous?.weeklyResetTime).flatMap { $0 > Date() ? $0 : nil }
            ?? Date().addingTimeInterval(7 * 24 * 60 * 60)
        usage.lastUpdated = Date()
        usage.userTimezone = .current
        return usage
    }
}
