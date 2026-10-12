//
//  ProfileManager.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-07.
//

import Foundation
import Combine

@MainActor
class ProfileManager: ObservableObject {
    static let shared = ProfileManager()

    @Published var profiles: [Profile] = []
    /// The Claude profile that may use Claude Code's default login (the system
    /// keychain entry) as a credential fallback. Choosing it never writes to
    /// Claude Code — account switching belongs to the VS Code profile switcher.
    @Published var activeProfile: Profile?
    @Published var multiProfileConfig: MultiProfileDisplayConfig = .default
    /// The profile whose sign-in page is open in Settings
    @Published var editingProfileId: UUID?

    private let profileStore = ProfileStore.shared

    private init() {}

    // MARK: - Loading

    func loadProfiles() {
        profiles = profileStore.loadProfiles()

        if profiles.isEmpty {
            profiles = [Profile(name: "Claude")]
            profileStore.saveProfiles(profiles)
        }

        if let activeId = profileStore.loadActiveProfileId(),
           let profile = profiles.first(where: { $0.id == activeId }) {
            activeProfile = profile
        } else {
            activeProfile = profiles.first
            if let first = profiles.first { profileStore.saveActiveProfileId(first.id) }
        }

        multiProfileConfig = profileStore.loadMultiProfileConfig()
        LoggingService.shared.log("ProfileManager: Loaded \(profiles.count) profile(s)")
    }

    // MARK: - Profile Operations

    func createProfile(name: String, provider: Provider = .anthropic) -> Profile {
        let profile = Profile(name: name, provider: provider)
        profiles.append(profile)
        profileStore.saveProfiles(profiles)
        LoggingService.shared.log("Created new profile: \(profile.name)")
        return profile
    }

    func updateProfile(_ profile: Profile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        if activeProfile?.id == profile.id { activeProfile = profile }
        profileStore.saveProfiles(profiles)
    }

    func deleteProfile(_ id: UUID) throws {
        guard profiles.count > 1 else { throw ProfileError.cannotDeleteLastProfile }
        profiles.removeAll { $0.id == id }
        profileStore.deleteProfileSecrets(id)
        if activeProfile?.id == id, let first = profiles.first {
            activateProfile(first.id)
        }
        profileStore.saveProfiles(profiles)
        NotificationCenter.default.post(name: .multiProfileConfigChanged, object: nil)
    }

    func toggleProfileSelection(_ id: UUID) {
        // Async: avoids "Publishing changes from within view updates"
        DispatchQueue.main.async { [weak self] in
            guard let self, let index = self.profiles.firstIndex(where: { $0.id == id }) else { return }
            self.profiles[index].isSelectedForDisplay.toggle()
            self.profileStore.saveProfiles(self.profiles)
            NotificationCenter.default.post(name: .multiProfileConfigChanged, object: nil)
        }
    }

    /// Marks the profile that uses Claude Code's default login.
    func activateProfile(_ id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        activeProfile = profile
        profileStore.saveActiveProfileId(id)
        NotificationCenter.default.post(name: .credentialsChanged, object: nil)
    }

    /// Profile edited by the Settings sign-in pages (defaults to the
    /// default-login profile).
    var editingProfile: Profile? {
        editingProfileId.flatMap { id in profiles.first { $0.id == id } } ?? activeProfile
    }

    // MARK: - Menu bar profile

    /// The selected profile whose usage drives the menu bar icon: the profile
    /// Claude Code is using (when following it), else the user's explicit
    /// choice, else the default-login profile, else the first selected.
    var menuBarProfile: Profile? {
        let selected = profiles.filter { $0.isSelectedForDisplay }
        if let followed = followedClaudeCodeProfile,
           let match = selected.first(where: { $0.id == followed.id }) {
            return match
        }
        if let id = multiProfileConfig.menuBarProfileId,
           let chosen = selected.first(where: { $0.id == id }) {
            return chosen
        }
        if let active = activeProfile, let match = selected.first(where: { $0.id == active.id }) {
            return match
        }
        return selected.first
    }

    /// Profiles listed in the dropdown, menu bar profile first.
    var popoverProfiles: [Profile] {
        let selected = profiles.filter { $0.isSelectedForDisplay }
        guard let first = menuBarProfile else { return selected }
        return [first] + selected.filter { $0.id != first.id }
    }

    /// Whether a refresh can fetch this profile's usage, including the
    /// default-login profile's system keychain fallback.
    func canFetchUsage(for profile: Profile) -> Bool {
        profile.hasAnyCredentials
            || (profile.id == activeProfile?.id && ProviderRegistry.service(for: profile.provider).hasCredentials(for: profile))
    }

    /// Profile Claude Code currently uses, when "Follow Claude Code" is on.
    var followedClaudeCodeProfile: Profile? {
        guard multiProfileConfig.followClaudeCode else { return nil }
        return ClaudeCodeFollowService.shared.followedProfile(in: profiles, config: multiProfileConfig)
    }

    /// Turns following the Claude Code account on/off. Off keeps the icon on
    /// whatever profile it shows right now.
    func setFollowClaudeCode(_ follow: Bool) {
        var config = multiProfileConfig
        if !follow, let shown = menuBarProfile {
            config.menuBarProfileId = shown.id
        }
        config.followClaudeCode = follow
        updateMultiProfileConfig(config)
    }

    /// Links a profile to the Claude Code config folder it uses (nil = automatic).
    func setClaudeCodeFolder(_ path: String?, for profileId: UUID) {
        var config = multiProfileConfig
        if let path {
            // A folder belongs to one profile
            config.claudeCodeFolders = config.claudeCodeFolders.filter { $0.value != path }
        }
        config.claudeCodeFolders[profileId.uuidString] = path
        updateMultiProfileConfig(config)
    }

    /// Chooses which profile the menu bar icon shows; picking by hand stops
    /// following Claude Code.
    func setMenuBarProfile(_ id: UUID) {
        guard multiProfileConfig.menuBarProfileId != id || menuBarProfile?.id != id else { return }
        var config = multiProfileConfig
        config.menuBarProfileId = id
        config.followClaudeCode = false
        updateMultiProfileConfig(config)
    }

    func updateMultiProfileConfig(_ config: MultiProfileDisplayConfig) {
        multiProfileConfig = config
        profileStore.saveMultiProfileConfig(config)
        NotificationCenter.default.post(name: .multiProfileConfigChanged, object: nil)
    }

    // MARK: - Credentials

    func loadCredentials(for profileId: UUID) throws -> ProfileCredentials {
        try profileStore.loadProfileCredentials(profileId)
    }

    func removeClaudeAICredentials(for profileId: UUID) throws {
        var credentials = try profileStore.loadProfileCredentials(profileId)
        credentials.claudeSessionKey = nil
        credentials.organizationId = nil
        try profileStore.saveProfileCredentials(profileId, credentials: credentials)
        if let index = profiles.firstIndex(where: { $0.id == profileId }) {
            profiles[index].claudeSessionKey = nil
            profiles[index].organizationId = nil
            profiles[index].claudeUsage = nil
            if activeProfile?.id == profileId { activeProfile = profiles[index] }
            profileStore.saveProfiles(profiles)
        }
        NotificationCenter.default.post(name: .credentialsChanged, object: nil)
    }

    // MARK: - Usage Data

    func saveClaudeUsage(_ usage: ClaudeUsage, for profileId: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        profiles[index].claudeUsage = usage
        if activeProfile?.id == profileId { activeProfile = profiles[index] }
        profileStore.saveProfiles(profiles)
    }
}

// MARK: - ProfileError

enum ProfileError: LocalizedError {
    case cannotDeleteLastProfile

    var errorDescription: String? {
        "Cannot delete the last profile. At least one profile is required."
    }
}
