//
//  AccountsSettingsView.swift
//  Claude Usage
//
//  Settings pages: the account list, the menu bar icon, and general options.
//

import SwiftUI

// MARK: - Accounts

struct AccountsSettingsView: View {
    @StateObject private var profileManager = ProfileManager.shared
    @State private var newName = ""
    @State private var newProvider: Provider = .anthropic
    @State private var errorMessage: String?
    /// Opens an account's sign-in page in the settings sidebar
    let onOpenAccount: (UUID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "Accounts",
                    subtitle: "Every account shown in the dropdown. Click one to sign in."
                )

                SettingsContentCard {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                        ForEach(profileManager.profiles) { profile in
                            AccountRow(profile: profile, onOpen: { onOpenAccount(profile.id) }, onError: { errorMessage = $0 })
                            if profile.id != profileManager.profiles.last?.id {
                                Divider()
                            }
                        }
                    }
                }

                SettingsSectionCard(title: "Add an account", subtitle: nil) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                        HStack(spacing: 8) {
                            ForEach(Provider.allCases, id: \.self) { provider in
                                ProviderChoiceCard(provider: provider, isSelected: newProvider == provider) {
                                    newProvider = provider
                                }
                            }
                        }
                        HStack {
                            TextField("Name (e.g. Work)", text: $newName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(addAccount)
                            Button("Add", action: addAccount)
                                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.system(size: 11))
                }
            }
            .padding()
        }
    }

    private func addAccount() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let profile = profileManager.createProfile(name: name, provider: newProvider)
        newName = ""
        NotificationCenter.default.post(name: .multiProfileConfigChanged, object: nil)
        onOpenAccount(profile.id)
    }
}

private struct AccountRow: View {
    let profile: Profile
    let onOpen: () -> Void
    let onError: (String) -> Void
    @StateObject private var profileManager = ProfileManager.shared
    @State private var isEditing = false
    @State private var editedName = ""
    @State private var confirmingDelete = false

    private var isDefaultLogin: Bool { profileManager.activeProfile?.id == profile.id }

    var body: some View {
        HStack(spacing: 10) {
            ProviderBrandMark(provider: profile.provider, size: 22)

            VStack(alignment: .leading, spacing: 3) {
                if isEditing {
                    TextField("Name", text: $editedName, onCommit: saveName)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Button(action: onOpen) {
                        Text(profile.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 6) {
                    Text(profile.provider.descriptor.displayName)
                    Text("·")
                    Text(profile.hasUsageCredentials ? "Signed in" : "Not signed in")
                        .foregroundColor(profile.hasUsageCredentials ? .secondary : .orange)
                    if profile.provider == .anthropic && isDefaultLogin {
                        Text("·")
                        Text("Claude Code default login")
                    }
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("Show", isOn: Binding(
                get: { profile.isSelectedForDisplay },
                set: { _ in profileManager.toggleProfileSelection(profile.id) }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 11))
            .help("Show this account in the dropdown")

            Menu {
                Button("Rename") {
                    editedName = profile.name
                    isEditing = true
                }
                if profile.provider == .anthropic && !isDefaultLogin {
                    Button("Use Claude Code's default login") {
                        profileManager.activateProfile(profile.id)
                    }
                }
                if profileManager.profiles.count > 1 {
                    Divider()
                    Button("Delete…", role: .destructive) { confirmingDelete = true }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .alert("Delete \(profile.name)?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                do { try profileManager.deleteProfile(profile.id) } catch { onError(error.localizedDescription) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its saved sign-in is removed from the keychain.")
        }
    }

    private func saveName() {
        let name = editedName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            var updated = profile
            updated.name = name
            profileManager.updateProfile(updated)
            NotificationCenter.default.post(name: .multiProfileConfigChanged, object: nil)
        }
        isEditing = false
    }
}

struct ProviderChoiceCard: View {
    let provider: Provider
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ProviderBrandMark(provider: provider, size: 20)
                Text(provider.descriptor.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Provider mark: asset catalog image when present, SF Symbol fallback otherwise.
struct ProviderLogoView: View {
    let provider: Provider
    var size: CGFloat = 14

    var body: some View {
        if let image = NSImage(named: provider.descriptor.logoAssetName) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: provider.descriptor.logoSystemSymbolFallback)
                .font(.system(size: size * 0.85, weight: .medium))
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Menu bar icon

struct MenuBarIconSettingsView: View {
    @StateObject private var profileManager = ProfileManager.shared

    private func binding(_ keyPath: WritableKeyPath<MultiProfileDisplayConfig, Bool>) -> Binding<Bool> {
        Binding(
            get: { profileManager.multiProfileConfig[keyPath: keyPath] },
            set: { value in
                var config = profileManager.multiProfileConfig
                config[keyPath: keyPath] = value
                profileManager.updateMultiProfileConfig(config)
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "Menu bar icon",
                    subtitle: "The icon shows one account; pick which one from the dropdown."
                )

                SettingsSectionCard(title: "Style", subtitle: nil) {
                    Picker("", selection: Binding(
                        get: { profileManager.multiProfileConfig.iconStyle },
                        set: { style in
                            var config = profileManager.multiProfileConfig
                            config.iconStyle = style
                            profileManager.updateMultiProfileConfig(config)
                        }
                    )) {
                        ForEach(MultiProfileIconStyle.allCases, id: \.self) { style in
                            Label(style.displayName, systemImage: style.icon).tag(style)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }

                SettingsSectionCard(title: "Display", subtitle: nil) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                        SettingToggle(title: "Show weekly usage", description: nil, isOn: binding(\.showWeek))
                        SettingToggle(title: "Show account name", description: nil, isOn: binding(\.showProfileLabel))
                        SettingToggle(title: "Monochrome icon", description: nil, isOn: binding(\.useSystemColor))
                        SettingToggle(title: "Show time marker", description: "Tick for how much of the window has passed", isOn: binding(\.showTimeMarker))
                        SettingToggle(title: "Color the time marker by pace", description: nil, isOn: binding(\.showPaceMarker))
                        SettingToggle(title: "Pace-aware bar colors", description: nil, isOn: binding(\.usePaceColoring))
                        SettingToggle(title: "Show remaining instead of used", description: nil, isOn: binding(\.showRemainingPercentage))
                    }
                }

                SettingsSectionCard(
                    title: "Follow Claude Code",
                    subtitle: "Used by the switch at the bottom of the dropdown"
                ) {
                    ClaudeCodeFolderLinks()
                }
            }
            .padding()
        }
    }
}

/// Links each Claude account to the Claude Code config folder it logs in with,
/// so "Follow Claude Code" knows which account to show.
private struct ClaudeCodeFolderLinks: View {
    @StateObject private var profileManager = ProfileManager.shared
    @ObservedObject private var followService = ClaudeCodeFollowService.shared

    var body: some View {
        let folders = followService.availableFolders()
        VStack(alignment: .leading, spacing: 6) {
            Text("Matches are found automatically by login email or name (e.g. Werk → Work) and remembered, so renaming keeps working.")
                .font(DesignTokens.Typography.caption)
                .foregroundColor(.secondary)

            ForEach(profileManager.profiles.filter { $0.provider == .anthropic }) { profile in
                HStack {
                    Text(profile.name)
                        .font(DesignTokens.Typography.caption)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { profileManager.multiProfileConfig.claudeCodeFolders[profile.id.uuidString] ?? "" },
                        set: { profileManager.setClaudeCodeFolder($0.isEmpty ? nil : $0, for: profile.id) }
                    )) {
                        Text(automaticLabel(for: profile, folders: folders)).tag("")
                        ForEach(folders) { folder in
                            Text("\(folder.name) (\((folder.path as NSString).abbreviatingWithTildeInPath))").tag(folder.path)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }
            }
        }
    }

    private func automaticLabel(for profile: Profile, folders: [ClaudeCodeFollowService.Folder]) -> String {
        let config = profileManager.multiProfileConfig
        let match = folders.first {
            followService.profile(for: $0, in: profileManager.profiles, config: config)?.id == profile.id
        }
        return match.map { "Automatic (\($0.name))" } ?? "Automatic (no match)"
    }
}
