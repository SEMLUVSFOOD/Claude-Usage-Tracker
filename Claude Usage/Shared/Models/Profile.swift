//
//  Profile.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-07.
//

import Foundation

/// One tracked account: which provider it is, its credentials and its last usage.
struct Profile: Codable, Identifiable, Equatable {
    // MARK: - Identity
    let id: UUID
    var name: String

    /// Which usage provider this profile tracks. Existing (pre-provider)
    /// profiles decode as `.anthropic`. Immutable after creation in the UI.
    var provider: Provider

    // MARK: - Credentials (secrets live in the Keychain, see ProfileStore)
    var claudeSessionKey: String?
    var organizationId: String?
    var cliCredentialsJSON: String?

    /// Manually pasted Codex credentials (same JSON shape as `~/.codex/auth.json`).
    /// When nil, Codex profiles read the auth.json file live.
    var codexCredentialsJSON: String?

    /// Google sign-in tokens for the Antigravity provider.
    var antigravityCredentialsJSON: String?

    // MARK: - CLI Account Sync Metadata
    var hasCliAccount: Bool
    var cliAccountSyncedAt: Date?

    /// Optional override that pins this profile to a specific Claude Code keychain
    /// service entry (e.g. `Claude Code-credentials-11e1b79e`) as the source of truth
    /// for OAuth credentials. Lets users with multiple CLAUDE_CONFIG_DIR installs
    /// map each profile to its own keychain entry.
    var customKeychainServiceName: String?

    /// Serialized `oauthAccount` object from Claude Code's `.claude.json`,
    /// captured at sync time. Raw JSON to preserve unknown fields.
    var oauthAccountJSON: String?

    // MARK: - Usage / Behavior
    var claudeUsage: ClaudeUsage?
    var checkOverageLimitEnabled: Bool
    var isSelectedForDisplay: Bool

    // MARK: - Metadata
    var createdAt: Date
    var lastUsedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        provider: Provider = .anthropic,
        claudeSessionKey: String? = nil,
        organizationId: String? = nil,
        cliCredentialsJSON: String? = nil,
        codexCredentialsJSON: String? = nil,
        antigravityCredentialsJSON: String? = nil,
        hasCliAccount: Bool = false,
        cliAccountSyncedAt: Date? = nil,
        customKeychainServiceName: String? = nil,
        oauthAccountJSON: String? = nil,
        claudeUsage: ClaudeUsage? = nil,
        checkOverageLimitEnabled: Bool = true,
        isSelectedForDisplay: Bool = true,
        createdAt: Date = Date(),
        lastUsedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.claudeSessionKey = claudeSessionKey
        self.organizationId = organizationId
        self.cliCredentialsJSON = cliCredentialsJSON
        self.codexCredentialsJSON = codexCredentialsJSON
        self.antigravityCredentialsJSON = antigravityCredentialsJSON
        self.hasCliAccount = hasCliAccount
        self.cliAccountSyncedAt = cliAccountSyncedAt
        self.customKeychainServiceName = customKeychainServiceName
        self.oauthAccountJSON = oauthAccountJSON
        self.claudeUsage = claudeUsage
        self.checkOverageLimitEnabled = checkOverageLimitEnabled
        self.isSelectedForDisplay = isSelectedForDisplay
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    // MARK: - Codable (secrets excluded from the plist — #267)

    /// When true in the encoder's userInfo, secrets are encoded too (used only
    /// for the legacy-plist migration path in ProfileStore).
    static let includeSecretsKey = CodingUserInfoKey(rawValue: "profileIncludeSecrets")!

    private enum CodingKeys: String, CodingKey {
        case id, name, provider
        case claudeSessionKey, organizationId, cliCredentialsJSON
        case codexCredentialsJSON, antigravityCredentialsJSON
        case hasCliAccount, cliAccountSyncedAt
        case customKeychainServiceName, oauthAccountJSON
        case claudeUsage, checkOverageLimitEnabled, isSelectedForDisplay
        case createdAt, lastUsedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        // An unknown raw value (from a future version) must degrade, never throw:
        // a throw here wipes the whole profile list.
        provider = (try? c.decodeIfPresent(Provider.self, forKey: .provider)) ?? .anthropic
        claudeSessionKey = try c.decodeIfPresent(String.self, forKey: .claudeSessionKey)
        organizationId = try c.decodeIfPresent(String.self, forKey: .organizationId)
        cliCredentialsJSON = try c.decodeIfPresent(String.self, forKey: .cliCredentialsJSON)
        codexCredentialsJSON = try c.decodeIfPresent(String.self, forKey: .codexCredentialsJSON)
        antigravityCredentialsJSON = try c.decodeIfPresent(String.self, forKey: .antigravityCredentialsJSON)
        hasCliAccount = try c.decodeIfPresent(Bool.self, forKey: .hasCliAccount) ?? false
        cliAccountSyncedAt = try c.decodeIfPresent(Date.self, forKey: .cliAccountSyncedAt)
        customKeychainServiceName = try c.decodeIfPresent(String.self, forKey: .customKeychainServiceName)
        oauthAccountJSON = try c.decodeIfPresent(String.self, forKey: .oauthAccountJSON)
        // A re-fetchable cache: a malformed one degrades to nil
        claudeUsage = (try? c.decodeIfPresent(ClaudeUsage.self, forKey: .claudeUsage)) ?? nil
        checkOverageLimitEnabled = try c.decodeIfPresent(Bool.self, forKey: .checkOverageLimitEnabled) ?? true
        isSelectedForDisplay = try c.decodeIfPresent(Bool.self, forKey: .isSelectedForDisplay) ?? true
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(provider, forKey: .provider)
        if (encoder.userInfo[Profile.includeSecretsKey] as? Bool) == true {
            try c.encodeIfPresent(claudeSessionKey, forKey: .claudeSessionKey)
            try c.encodeIfPresent(cliCredentialsJSON, forKey: .cliCredentialsJSON)
            try c.encodeIfPresent(codexCredentialsJSON, forKey: .codexCredentialsJSON)
            try c.encodeIfPresent(antigravityCredentialsJSON, forKey: .antigravityCredentialsJSON)
        }
        try c.encodeIfPresent(organizationId, forKey: .organizationId)
        try c.encode(hasCliAccount, forKey: .hasCliAccount)
        try c.encodeIfPresent(cliAccountSyncedAt, forKey: .cliAccountSyncedAt)
        try c.encodeIfPresent(customKeychainServiceName, forKey: .customKeychainServiceName)
        try c.encodeIfPresent(oauthAccountJSON, forKey: .oauthAccountJSON)
        try c.encodeIfPresent(claudeUsage, forKey: .claudeUsage)
        try c.encode(checkOverageLimitEnabled, forKey: .checkOverageLimitEnabled)
        try c.encode(isSelectedForDisplay, forKey: .isSelectedForDisplay)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(lastUsedAt, forKey: .lastUsedAt)
    }

    // MARK: - Computed Properties

    var hasClaudeAI: Bool {
        claudeSessionKey != nil && organizationId != nil
    }

    /// True if the profile has credentials that can fetch usage right now.
    /// (Anthropic's system-keychain fallback for the default-login profile is
    /// handled in AnthropicUsageProvider.)
    var hasUsageCredentials: Bool {
        switch provider {
        case .anthropic:
            return hasClaudeAI || hasValidCLIOAuth
        case .codex:
            return codexCredentialsJSON != nil || CodexAuthService.shared.authFileExists()
        case .antigravity:
            return antigravityCredentialsJSON != nil
        }
    }

    /// True if profile has CLI OAuth credentials that are not expired
    var hasValidCLIOAuth: Bool {
        guard let cliJSON = cliCredentialsJSON else { return false }
        return !ClaudeCodeSyncService.shared.isTokenExpired(cliJSON)
    }

    /// Like `hasUsageCredentials`, but also counts expired CLI tokens (the
    /// Anthropic provider refreshes them) and pinned keychain entries.
    var hasAnyCredentials: Bool {
        switch provider {
        case .anthropic:
            return hasClaudeAI || cliCredentialsJSON != nil || customKeychainServiceName != nil
        case .codex:
            return codexCredentialsJSON != nil || CodexAuthService.shared.authFileExists()
        case .antigravity:
            return antigravityCredentialsJSON != nil
        }
    }
}

// MARK: - ProfileCredentials

/// The Keychain-stored Claude credentials of one profile
struct ProfileCredentials {
    var claudeSessionKey: String?
    var organizationId: String?
    var cliCredentialsJSON: String?

    var hasClaudeAI: Bool {
        claudeSessionKey != nil && organizationId != nil
    }

    var hasCLI: Bool {
        cliCredentialsJSON != nil
    }
}
