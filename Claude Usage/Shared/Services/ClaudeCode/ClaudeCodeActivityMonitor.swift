//
//  ClaudeCodeActivityMonitor.swift
//  Claude Usage
//
//  Follows Claude Code sessions through the hook events (see
//  ClaudeCodeHookInstaller) to keep the Mac awake while Claude works and to
//  alert when it needs input or finishes.
//

import AppKit
import Combine
import IOKit.pwr_mgt
import UserNotifications

struct ClaudeCodeActivitySettings: Codable, Equatable {
    /// Heartbeat-pulse the menu bar icon while a session is working
    var pulseIcon = true
    var keepAwake = false
    var alertOnNeedsInput = false
    var alertOnFinished = false
    var macNotifications = true
    var discord = false
    /// Only alert after the Mac has been idle for a couple of minutes
    var onlyWhenAway = true

    var anyFeatureOn: Bool { pulseIcon || keepAwake || alertOnNeedsInput || alertOnFinished }

    init() {}

    /// Missing keys (settings saved by an older version) keep their defaults
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ClaudeCodeActivitySettings()
        pulseIcon = try c.decodeIfPresent(Bool.self, forKey: .pulseIcon) ?? d.pulseIcon
        keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? d.keepAwake
        alertOnNeedsInput = try c.decodeIfPresent(Bool.self, forKey: .alertOnNeedsInput) ?? d.alertOnNeedsInput
        alertOnFinished = try c.decodeIfPresent(Bool.self, forKey: .alertOnFinished) ?? d.alertOnFinished
        macNotifications = try c.decodeIfPresent(Bool.self, forKey: .macNotifications) ?? d.macNotifications
        discord = try c.decodeIfPresent(Bool.self, forKey: .discord) ?? d.discord
        onlyWhenAway = try c.decodeIfPresent(Bool.self, forKey: .onlyWhenAway) ?? d.onlyWhenAway
    }
}

final class ClaudeCodeActivityMonitor: NSObject, ObservableObject {
    static let shared = ClaudeCodeActivityMonitor()

    enum SessionState { case working, waiting, idle }

    struct Session {
        var state: SessionState
        var lastEvent: Date
        var project: String
        var folder: String
        var lastFinishedAlert: Date?
    }

    @Published private(set) var settings: ClaudeCodeActivitySettings
    @Published private(set) var sessions: [String: Session] = [:]
    @Published private(set) var installProblems: [String] = []
    @Published private(set) var isKeepingAwake = false

    var workingCount: Int { sessions.values.filter { $0.state == .working }.count }

    private static let settingsKey = "claudeCodeActivitySettings"
    private static let discordAccount = "discordWebhookURL"
    /// A "working" session with no events for this long is considered ended
    /// (Claude Code crashed or was closed mid-turn). Long enough for a single
    /// slow tool call such as a big build.
    private static let staleAfter: TimeInterval = 2 * 3600
    /// Hook events older than this (app wasn't running) are ignored
    private static let maxEventAge: TimeInterval = 10 * 60
    private static let awayAfter: TimeInterval = 120

    private var timer: Timer?
    private var assertionID: IOPMAssertionID = 0

    private override init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(ClaudeCodeActivitySettings.self, from: data) {
            settings = decoded
        } else {
            settings = ClaudeCodeActivitySettings()
        }
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        UNUserNotificationCenter.current().delegate = self
        apply(previous: nil)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        releaseAssertion()
    }

    /// Changes settings; installs or removes the hooks as features turn on/off.
    func update(_ change: (inout ClaudeCodeActivitySettings) -> Void) {
        let previous = settings
        change(&settings)
        guard settings != previous else { return }
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
        apply(previous: previous)
    }

    private func apply(previous: ClaudeCodeActivitySettings?) {
        if settings.anyFeatureOn {
            // Refresh on every launch too, so newly added Claude Code folders get hooks
            if previous?.anyFeatureOn != true {
                installProblems = ClaudeCodeHookInstaller.installEverywhere()
            }
            if timer == nil {
                purgeOldEvents()
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
                timer?.tolerance = 0.3
            }
            let wantsMacAlerts = (settings.alertOnNeedsInput || settings.alertOnFinished) && settings.macNotifications
            let wantedBefore = previous.map { ($0.alertOnNeedsInput || $0.alertOnFinished) && $0.macNotifications } ?? false
            if wantsMacAlerts && !wantedBefore {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
        } else {
            if previous?.anyFeatureOn == true {
                ClaudeCodeHookInstaller.removeEverywhere()
                installProblems = []
            }
            timer?.invalidate()
            timer = nil
            sessions = [:]
        }
        updateAssertion()
    }

    /// Re-installs hooks (e.g. after adding a Claude Code folder)
    func reinstallHooks() {
        guard settings.anyFeatureOn else { return }
        installProblems = ClaudeCodeHookInstaller.installEverywhere()
    }

    // MARK: - Discord

    var discordWebhookURL: String {
        get { KeychainService.shared.loadAppSecret(account: Self.discordAccount) ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            KeychainService.shared.saveAppSecret(trimmed.isEmpty ? nil : trimmed, account: Self.discordAccount)
            objectWillChange.send()
        }
    }

    /// Sends a test message; returns an error description on failure
    func sendDiscordTest() async -> String? {
        await postToDiscord(title: "Claude Usage", body: "Test message: Claude Code alerts will arrive here.")
    }

    // MARK: - Events

    private func poll() {
        let directory = ClaudeCodeHookInstaller.eventsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let now = Date()
        for name in files.filter({ $0.hasSuffix(".json") }).sorted() {
            let url = directory.appendingPathComponent(name)
            let contents = try? String(contentsOf: url, encoding: .utf8)
            try? FileManager.default.removeItem(at: url)
            guard let contents,
                  let stamp = Double(name.split(separator: "-").first ?? ""),
                  now.timeIntervalSince1970 - stamp < Self.maxEventAge else { continue }
            let lines = contents.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            guard lines.count == 2,
                  let data = lines[1].data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            handle(json, folder: String(lines[0]), at: Date(timeIntervalSince1970: stamp))
        }
        // Sessions that went quiet mid-turn
        for (id, session) in sessions where session.state == .working && now.timeIntervalSince(session.lastEvent) > Self.staleAfter {
            sessions[id]?.state = .idle
        }
        updateAssertion()
    }

    private func handle(_ json: [String: Any], folder: String, at date: Date) {
        guard let id = json["session_id"] as? String, !id.isEmpty,
              let event = json["hook_event_name"] as? String else { return }
        var session = sessions[id] ?? Session(state: .idle, lastEvent: date, project: "", folder: folder)
        session.lastEvent = date
        if let cwd = json["cwd"] as? String, !cwd.isEmpty {
            session.project = URL(fileURLWithPath: cwd).lastPathComponent
        }

        switch event {
        case "UserPromptSubmit", "PostToolUse":
            session.state = .working
        case "Notification":
            session.state = .waiting
            let message = json["message"] as? String ?? "Claude Code needs your attention"
            let type = json["notification_type"] as? String
            let isIdlePrompt = type == "idle_prompt" || message.localizedCaseInsensitiveContains("waiting for your input")
            // The idle prompt follows a finished turn; don't alert twice
            let justAlertedFinished = session.lastFinishedAlert.map { date.timeIntervalSince($0) < 600 } ?? false
            if settings.alertOnNeedsInput && !(isIdlePrompt && settings.alertOnFinished && justAlertedFinished) {
                alert(title: isIdlePrompt ? "Claude Code is waiting for you" : "Claude Code needs your input",
                      body: "\(label(for: session)): \(message)")
            }
        case "Stop":
            session.state = .idle
            if settings.alertOnFinished {
                alert(title: "Claude Code finished", body: "\(label(for: session)) is done and waiting for your next prompt.")
                session.lastFinishedAlert = date
            }
        case "SessionEnd":
            sessions[id] = nil
            return
        default:
            break
        }
        sessions[id] = session
    }

    /// "Werk · my-project"
    private func label(for session: Session) -> String {
        let manager = ProfileManager.shared
        let folder = ClaudeCodeFollowService.Folder(path: session.folder, name: URL(fileURLWithPath: session.folder).lastPathComponent)
        let account = ClaudeCodeFollowService.shared.profile(for: folder, in: manager.profiles, config: manager.multiProfileConfig)?.name
        return [account, session.project.isEmpty ? nil : session.project].compactMap { $0 }.joined(separator: " · ")
            .nonEmpty ?? "Claude Code"
    }

    private func purgeOldEvents() {
        let directory = ClaudeCodeHookInstaller.eventsDirectory
        let cutoff = Date().timeIntervalSince1970 - Self.maxEventAge
        for name in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] {
            if let stamp = Double(name.split(separator: "-").first ?? ""), stamp < cutoff {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }

    // MARK: - Keep awake

    private func updateAssertion() {
        let shouldHold = settings.keepAwake && workingCount > 0
        if shouldHold && assertionID == 0 {
            // Prevents idle *system* sleep; the display may still turn off
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Claude Code is working" as CFString,
                &assertionID
            )
            if result != kIOReturnSuccess { assertionID = 0 }
        } else if !shouldHold && assertionID != 0 {
            releaseAssertion()
        }
        if isKeepingAwake != (assertionID != 0) { isKeepingAwake = assertionID != 0 }
    }

    private func releaseAssertion() {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        isKeepingAwake = false
    }

    // MARK: - Alerts

    private var userIsAway: Bool {
        let anyInput = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) >= Self.awayAfter
    }

    private func alert(title: String, body: String) {
        guard !settings.onlyWhenAway || userIsAway else { return }
        if settings.macNotifications {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            )
        }
        if settings.discord {
            Task { _ = await postToDiscord(title: title, body: body) }
        }
    }

    private func postToDiscord(title: String, body: String) async -> String? {
        guard let url = URL(string: discordWebhookURL), url.scheme == "https" else {
            return "Add a Discord webhook URL first."
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "username": "Claude Usage",
            "content": "**\(title)**\n\(body)",
        ])
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<300).contains(status) ? nil : "Discord answered with status \(status)."
        } catch {
            return error.localizedDescription
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension ClaudeCodeActivityMonitor: UNUserNotificationCenterDelegate {
    /// Show banners even while the Settings window is in front
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
