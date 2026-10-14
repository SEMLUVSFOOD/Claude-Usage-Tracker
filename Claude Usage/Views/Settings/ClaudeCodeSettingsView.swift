//
//  ClaudeCodeSettingsView.swift
//  Claude Usage
//
//  Settings → Claude Code: keep the Mac awake while Claude Code works, and
//  alerts (Mac notification / Discord) when it needs input or finishes.
//

import SwiftUI

struct ClaudeCodeSettingsView: View {
    @ObservedObject private var monitor = ClaudeCodeActivityMonitor.shared
    @State private var webhook = ClaudeCodeActivityMonitor.shared.discordWebhookURL
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var folders = ClaudeCodeHookInstaller.status()

    private func binding(_ keyPath: WritableKeyPath<ClaudeCodeActivitySettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { monitor.settings[keyPath: keyPath] },
            set: { value in
                monitor.update { $0[keyPath: keyPath] = value }
                folders = ClaudeCodeHookInstaller.status()
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "Claude Code",
                    subtitle: "Keep your Mac awake and get alerts while Claude Code works."
                )

                SettingsSectionCard(title: "While you're working", subtitle: nil) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                        SettingToggle(
                            title: "Pulse the menu bar icon",
                            description: "A heartbeat on the icon while any session is working",
                            isOn: binding(\.pulseIcon)
                        )
                        SettingToggle(
                            title: "Also count usage on websites and apps",
                            description: "An account whose usage rises (claude.ai, the Claude app, Codex, Antigravity; checked every minute) counts as active for 5 minutes. Gemini app usage isn't visible: Google meters it separately from Antigravity.",
                            isOn: binding(\.countAccountUsage)
                        )
                        SettingToggle(
                            title: "Keep Mac awake while active",
                            description: "Prevents idle sleep while a Claude Code session works or an account is in use. The screen can still turn off. Closing the lid still sleeps a MacBook unless it's on power with an external display.",
                            isOn: binding(\.keepAwake)
                        )
                    }
                }

                SettingsSectionCard(title: "Alerts", subtitle: nil) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                        SettingToggle(title: "When Claude Code needs permission or input", description: nil,
                                      isOn: binding(\.alertOnNeedsInput))
                        SettingToggle(title: "When Claude Code finishes", description: "After every completed turn",
                                      isOn: binding(\.alertOnFinished))
                        SettingToggle(title: "Only when I'm away", description: "No alerts while you're using the Mac (idle for 2+ minutes)",
                                      isOn: binding(\.onlyWhenAway))

                        Divider()

                        SettingToggle(title: "Mac notification", description: nil, isOn: binding(\.macNotifications))
                        SettingToggle(title: "Discord", description: "Server Settings → Integrations → Webhooks → New Webhook → Copy URL",
                                      isOn: binding(\.discord))

                        if monitor.settings.discord {
                            HStack {
                                SecureField("https://discord.com/api/webhooks/…", text: $webhook)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit { monitor.discordWebhookURL = webhook }
                                Button(isTesting ? "Sending…" : "Send test") {
                                    monitor.discordWebhookURL = webhook
                                    isTesting = true
                                    Task {
                                        let error = await monitor.sendDiscordTest()
                                        testResult = error ?? "Sent. Check your Discord channel."
                                        isTesting = false
                                    }
                                }
                                .disabled(isTesting || webhook.isEmpty)
                            }
                            if let testResult {
                                Text(testResult)
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                SettingsSectionCard(
                    title: "Claude Code hooks",
                    subtitle: "Added to these folders while any option above is on, and removed when all are off"
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(folders) { folder in
                            HStack(spacing: 8) {
                                Image(systemName: folder.error != nil ? "exclamationmark.triangle.fill"
                                      : folder.installed ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(folder.error != nil ? .orange : folder.installed ? .green : .secondary)
                                Text((folder.path as NSString).abbreviatingWithTildeInPath)
                                    .font(DesignTokens.Typography.caption)
                                if let error = folder.error {
                                    Text(error)
                                        .font(DesignTokens.Typography.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        ForEach(monitor.installProblems, id: \.self) { problem in
                            Text(problem)
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(.orange)
                        }
                        Text("Running Claude Code sessions pick up the hooks when they restart.")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.secondary)
                        if monitor.settings.anyFeatureOn {
                            Button("Reinstall hooks") {
                                monitor.reinstallHooks()
                                folders = ClaudeCodeHookInstaller.status()
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            .padding()
        }
        .onDisappear { monitor.discordWebhookURL = webhook }
    }
}
