//
//  ProviderRegistry.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-07-15.
//

import Foundation

/// The single seam between the app and its usage providers. Everything that
/// needs provider-specific data or behavior resolves it here — descriptors
/// for declarative facts (branding, capabilities), services for fetching.
///
/// Adding a provider = one descriptor entry + one service entry + a folder
/// under `Shared/Services/Providers/<Name>/`. See docs/ADDING_A_PROVIDER.md.
enum ProviderRegistry {

    // MARK: - Descriptors

    private static let descriptors: [Provider: ProviderDescriptor] = [
        .anthropic: ProviderDescriptor(
            id: .anthropic,
            displayName: "Claude",
            logoAssetName: "ProviderLogoAnthropic",
            logoSystemSymbolFallback: "sparkle",
            statusPageURL: URL(string: "https://status.claude.com/api/v2/status.json"),
            capabilities: ProviderCapabilities(cliAccountSync: true),
            credentialSections: [.claudeAI, .cliAccount]
        ),
        .codex: ProviderDescriptor(
            id: .codex,
            displayName: "OpenAI Codex",
            logoAssetName: "ProviderLogoOpenAI",
            logoSystemSymbolFallback: "circle.hexagongrid",
            statusPageURL: URL(string: "https://status.openai.com/api/v2/status.json"),
            capabilities: ProviderCapabilities(cliAccountSync: false),
            credentialSections: [.codexAccount]
        ),
        .antigravity: ProviderDescriptor(
            id: .antigravity,
            displayName: "Google Antigravity",
            logoAssetName: "ProviderLogoGoogle",
            logoSystemSymbolFallback: "sparkles",
            statusPageURL: nil,
            capabilities: ProviderCapabilities(cliAccountSync: false),
            credentialSections: [.antigravityAccount]
        ),
    ]

    static func descriptor(for provider: Provider) -> ProviderDescriptor {
        guard let descriptor = descriptors[provider] else {
            fatalError("ProviderRegistry: missing descriptor for \(provider.rawValue)")
        }
        return descriptor
    }

    // MARK: - Services

    static func service(for provider: Provider) -> UsageProviderService {
        switch provider {
        case .anthropic:
            return AnthropicUsageProvider.shared
        case .codex:
            return CodexUsageProvider.shared
        case .antigravity:
            return AntigravityUsageProvider.shared
        }
    }
}
