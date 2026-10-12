//
//  AntigravityAccountView.swift
//  Claude Usage
//
//  Google sign-in for Antigravity profiles: a reusable sign-in controller, the
//  inline card shown in the dropdown for a signed-out Google profile, and the
//  settings page (sign out / try another sign-in client).
//

import SwiftUI

// MARK: - Sign-in controller

/// Runs "Sign in with Google" for one Antigravity profile, verifies the result
/// by fetching usage once, and stores both on the profile.
@MainActor
final class AntigravitySignInController: ObservableObject {
    static let shared = AntigravitySignInController()

    enum State: Equatable {
        case idle
        case waitingForBrowser
        case verifying
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var stateProfileId: UUID?
    /// Which discovered OAuth client the next sign-in uses ("Try another sign-in")
    @Published private(set) var clientIndex = 0

    private var task: Task<Void, Never>?

    var canTryAnotherClient: Bool { AntigravityAuthService.shared.clientCount > 1 }

    func signIn(profileId: UUID) {
        task?.cancel()
        stateProfileId = profileId
        state = .waitingForBrowser
        task = Task {
            do {
                let credentials = try await AntigravityAuthService.shared.signIn(clientIndex: clientIndex)
                state = .verifying
                guard var profile = ProfileManager.shared.profiles.first(where: { $0.id == profileId }) else {
                    state = .idle
                    return
                }
                profile.antigravityCredentialsJSON = credentials.serialized()
                ProfileManager.shared.updateProfile(profile)
                do {
                    let usage = try await AntigravityUsageProvider.shared.fetchUsage(for: profile)
                    ProfileManager.shared.saveClaudeUsage(usage, for: profileId)
                } catch let error as AppError where error.code == .providerAuthExpired {
                    // Google rejected this grant (e.g. wrong client for the account
                    // type); don't keep a login that can never fetch usage.
                    signOut(profileId: profileId)
                    throw error
                }
                NotificationCenter.default.post(name: .multiProfileConfigChanged, object: nil)
                state = .idle
            } catch is CancellationError {
                state = .idle
            } catch {
                let message = (error as? AppError)?.message ?? error.localizedDescription
                state = .failed(message)
            }
        }
    }

    func tryAnotherClient(profileId: UUID) {
        clientIndex += 1
        signIn(profileId: profileId)
    }

    func cancel() {
        task?.cancel()
        AntigravityAuthService.shared.cancelSignIn()
        state = .idle
    }

    func signOut(profileId: UUID) {
        guard var profile = ProfileManager.shared.profiles.first(where: { $0.id == profileId }) else { return }
        profile.antigravityCredentialsJSON = nil
        profile.claudeUsage = nil
        ProfileManager.shared.updateProfile(profile)
        NotificationCenter.default.post(name: .multiProfileConfigChanged, object: nil)
    }
}

// MARK: - Dropdown card

/// Shown in place of the usage bars for a Google profile that isn't signed in.
struct AntigravitySignInCard: View {
    let profileId: UUID
    @ObservedObject private var controller = AntigravitySignInController.shared

    private var state: AntigravitySignInController.State {
        controller.stateProfileId == profileId ? controller.state : .idle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch state {
            case .waitingForBrowser:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Finish signing in in your browser…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Cancel") { controller.cancel() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            case .verifying:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading your Antigravity limits…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            case .idle, .failed:
                Text("Sign in with your Google account to show Antigravity usage (Gemini and Claude/GPT models).")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .failed(let message) = state {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Button("Sign in with Google") { controller.signIn(profileId: profileId) }
                        .controlSize(.small)
                    if case .failed = state, controller.canTryAnotherClient {
                        Button("Try another sign-in") { controller.tryAnotherClient(profileId: profileId) }
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }
}

// MARK: - Settings page

struct AntigravityAccountView: View {
    @StateObject private var profileManager = ProfileManager.shared
    @ObservedObject private var controller = AntigravitySignInController.shared

    /// The active profile when it's a Google one, else the first Google profile.
    private var profile: Profile? {
        if let active = profileManager.activeProfile, active.provider == .antigravity { return active }
        return profileManager.profiles.first { $0.provider == .antigravity }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "Google Antigravity",
                    subtitle: "Shows your Antigravity limits for Gemini and Claude/GPT models."
                )

                if let profile = profile {
                    accountCard(for: profile)
                } else {
                    Text("Create a profile with the Google Antigravity provider in Manage Profiles first.")
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }

    private func accountCard(for profile: Profile) -> some View {
        let credentials = AntigravityCredentials.parse(profile.antigravityCredentialsJSON)
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            HStack(spacing: DesignTokens.Spacing.medium) {
                Circle()
                    .fill(credentials != nil ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: DesignTokens.StatusDot.standard, height: DesignTokens.StatusDot.standard)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                    Text(credentials != nil ? "Signed in" : "Not signed in")
                        .font(DesignTokens.Typography.bodyMedium)
                    if let email = credentials?.email {
                        Text(email)
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if credentials != nil {
                    Button("Sign out") { controller.signOut(profileId: profile.id) }
                }
            }

            if credentials == nil || controller.stateProfileId == profile.id {
                AntigravitySignInCard(profileId: profile.id)
                    .padding(.horizontal, -10)
            }

            Text("Sign-in uses the Google sign-in built into your installed Antigravity app. Google can change this private API at any time.")
                .font(DesignTokens.Typography.caption)
                .foregroundColor(.secondary)
        }
        .padding(DesignTokens.Spacing.medium)
        .background(DesignTokens.Colors.cardBackground)
        .cornerRadius(DesignTokens.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .strokeBorder(DesignTokens.Colors.cardBorder, lineWidth: 1)
        )
    }
}
