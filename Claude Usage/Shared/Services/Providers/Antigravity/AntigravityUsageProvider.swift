//
//  AntigravityUsageProvider.swift
//  Claude Usage
//
//  Google Antigravity usage (Gemini + Claude/GPT model quotas) for a Google
//  account signed in from the app's settings.
//

import Foundation

final class AntigravityUsageProvider: UsageProviderService {
    static let shared = AntigravityUsageProvider()

    let provider: Provider = .antigravity

    private let authService = AntigravityAuthService.shared
    private let apiService = AntigravityAPIService.shared

    private init() {}

    func hasCredentials(for profile: Profile) -> Bool {
        profile.antigravityCredentialsJSON != nil
    }

    /// refresh token if stale → resolve project → fetch quota → map.
    /// On a 401 before expiry, force one refresh and retry once.
    func fetchUsage(for profile: Profile) async throws -> ClaudeUsage {
        guard let stored = AntigravityCredentials.parse(profile.antigravityCredentialsJSON) else {
            throw AppError(
                code: .providerCredentialsNotFound,
                message: "Sign in with Google in Settings to show Antigravity usage.",
                isRecoverable: true
            )
        }

        var credentials = try await authService.refreshIfNeeded(stored)
        let usage: ClaudeUsage
        do {
            usage = try await fetch(with: &credentials, previous: profile.claudeUsage)
        } catch let error as AppError where error.code == .providerAuthExpired && credentials == stored {
            credentials = try await authService.refreshIfNeeded(credentials, force: true)
            usage = try await fetch(with: &credentials, previous: profile.claudeUsage)
        }
        persist(credentials, ifChangedFrom: stored, profileId: profile.id)
        return usage
    }

    private func fetch(with credentials: inout AntigravityCredentials, previous: ClaudeUsage?) async throws -> ClaudeUsage {
        let account = try await apiService.loadAccount(accessToken: credentials.accessToken,
                                                       storedProjectId: credentials.projectId)
        credentials.projectId = account.projectId ?? credentials.projectId
        let windows = try await apiService.fetchQuotaWindows(accessToken: credentials.accessToken,
                                                             projectId: credentials.projectId)
        guard !windows.isEmpty else {
            throw AppError(code: .apiParsingFailed,
                           message: "Google didn't report any Antigravity limits for this account.",
                           isRecoverable: true)
        }
        return AntigravityAPIService.mapToUsage(windows, previous: previous)
    }

    /// Writes refreshed tokens / the discovered project back to the CURRENT
    /// profile (looked up by id on the main actor, so concurrent edits to the
    /// profile aren't clobbered by this pre-fetch snapshot).
    private func persist(_ credentials: AntigravityCredentials, ifChangedFrom old: AntigravityCredentials, profileId: UUID) {
        guard credentials != old, let serialized = credentials.serialized() else { return }
        Task { @MainActor in
            guard var current = ProfileManager.shared.profiles.first(where: { $0.id == profileId }) else { return }
            current.antigravityCredentialsJSON = serialized
            ProfileManager.shared.updateProfile(current)
        }
    }
}
