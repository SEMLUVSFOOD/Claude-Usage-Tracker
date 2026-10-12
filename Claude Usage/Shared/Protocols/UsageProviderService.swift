//
//  UsageProviderService.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-07-15.
//

import Foundation

/// The fetch contract every usage provider implements. Resolved through
/// `ProviderRegistry.service(for:)` — call sites never reference a concrete
/// provider type, so new providers plug in without core-file changes.
protocol UsageProviderService {
    var provider: Provider { get }

    /// Whether the profile can fetch usage right now, including any
    /// provider-specific system-level credential fallbacks that only apply
    /// to the active profile.
    func hasCredentials(for profile: Profile) -> Bool

    /// Fetches usage for a specific (possibly non-active) profile using only
    /// that profile's own credentials.
    func fetchUsage(for profile: Profile) async throws -> ClaudeUsage
}

