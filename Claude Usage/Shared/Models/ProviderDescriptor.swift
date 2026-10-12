//
//  ProviderDescriptor.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-07-15.
//

import Foundation

/// Declarative single source of truth for everything the app needs to know
/// about a provider: branding, status page, capabilities, and which sign-in
/// pages it offers in Settings.
struct ProviderDescriptor {
    let id: Provider

    /// Brand name shown in pickers and settings. Brand names are not localized.
    let displayName: String

    /// Asset catalog image for the provider mark; SF Symbol used as fallback.
    let logoAssetName: String
    let logoSystemSymbolFallback: String

    /// Statuspage-compatible status endpoint (same JSON schema across providers).
    let statusPageURL: URL?

    let capabilities: ProviderCapabilities

    /// Sign-in pages this provider offers in Settings.
    let credentialSections: [SettingsSection]
}

/// Capability flags that gate provider-specific behavior.
struct ProviderCapabilities {
    /// The provider's accounts are Claude Code logins: they can be linked to
    /// Claude Code config folders ("Follow Claude Code") and use Claude Code's
    /// keychain login as a credential fallback.
    let cliAccountSync: Bool
}
