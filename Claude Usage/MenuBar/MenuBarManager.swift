import Cocoa
import SwiftUI
import Combine

/// Owns the single menu bar item and its dropdown. The icon shows one profile
/// (chosen in the dropdown, or the one Claude Code is using when following it);
/// the dropdown lists every selected profile.
final class MenuBarManager: NSObject, ObservableObject {
    @Published private(set) var status: ClaudeStatus = .unknown
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastSuccessfulRefreshTime: Date?

    private let profileManager = ProfileManager.shared
    private let renderer = MenuBarIconRenderer()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var refreshTimer: Timer?
    private var eventMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var appearanceObserver: NSKeyValueObservation?
    private var lastAppearanceName: NSAppearance.Name?

    /// The click that dismisses the popover also fires the status item action;
    /// without this debounce it would immediately re-open the popover.
    private var lastPopoverCloseDate: Date = .distantPast

    /// Fixed autosaveName so the icon keeps its menu bar position (and its spot
    /// in tools like Ice) no matter which profile it shows.
    private static let autosaveName: NSStatusItem.AutosaveName = "claudeUsageTracker.multiProfile.combined"
    private static let refreshInterval: TimeInterval = 60

    // MARK: - Lifecycle

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: 32)
        item.autosaveName = Self.autosaveName
        item.isVisible = true  // override a persisted false from an old cmd-drag
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        popover = makePopover()
        observeChanges()
        ClaudeCodeFollowService.shared.start()
        updateIcon()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.refreshUsage()
        }
        refreshTimer?.tolerance = Self.refreshInterval * 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshUsage()
        }
    }

    func cleanup() {
        refreshTimer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        appearanceObserver?.invalidate()
        stopMonitoringForOutsideClicks()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    private func observeChanges() {
        let center = NotificationCenter.default
        for name in [Notification.Name.multiProfileConfigChanged, .credentialsChanged] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                self?.updateIcon()
                if notification.name == .credentialsChanged { self?.refreshUsage() }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.refreshUsage() }
        })
        // Redraw on light/dark changes. Observe the app, never the button:
        // setting button.image triggers the button's appearance KVO.
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, change in
            guard let self, change.newValue?.name != self.lastAppearanceName else { return }
            self.lastAppearanceName = change.newValue?.name
            self.updateIcon()
        }
        // Usage saved by a refresh or a Google sign-in redraws the icon
        profileManager.$profiles
            .dropFirst()
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Refresh

    /// Fetches usage for every selected profile with credentials, plus the
    /// service status, then redraws the icon.
    func refreshUsage() {
        guard !isRefreshing else { return }
        let profiles = profileManager.profiles.filter { $0.isSelectedForDisplay && profileManager.canFetchUsage(for: $0) }
        isRefreshing = true

        Task {
            if let newStatus = try? await statusService.fetchStatus() {
                status = newStatus
            }
            var anySuccess = false
            for profile in profiles {
                do {
                    let usage = try await ProviderRegistry.service(for: profile.provider).fetchUsage(for: profile)
                    profileManager.saveClaudeUsage(usage, for: profile.id)
                    anySuccess = true
                } catch {
                    let appError = AppError.wrap(error)
                    LoggingService.shared.logError("Refresh failed for '\(profile.name)': [\(appError.code.rawValue)] \(appError.message)")
                }
            }
            if anySuccess || profiles.isEmpty { lastSuccessfulRefreshTime = Date() }
            isRefreshing = false
            updateIcon()
        }
    }

    /// Status page of the provider shown in the menu bar (Anthropic by default).
    private var statusService: ClaudeStatusService {
        if let url = profileManager.menuBarProfile?.provider.descriptor.statusPageURL {
            return ClaudeStatusService(statusURL: url)
        }
        return ClaudeStatusService()
    }

    // MARK: - Icon

    private func updateIcon() {
        guard let statusItem, let button = statusItem.button else { return }
        let isDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let image: NSImage
        if let profile = profileManager.menuBarProfile, profileManager.canFetchUsage(for: profile) {
            image = renderIcon(for: profile, config: profileManager.multiProfileConfig, isDark: isDark)
        } else {
            image = renderer.createDefaultAppLogo(isDarkMode: isDark)
            image.isTemplate = true
        }
        // macOS 26: changing a status item's length re-runs a recursive layout
        // solve, so pin a coarse, stable width and only assign real changes.
        let length = ceil(image.size.width / 32) * 32
        if abs(statusItem.length - length) > 0.5 { statusItem.length = length }
        button.image = image
    }

    private func renderIcon(for profile: Profile, config: MultiProfileDisplayConfig, isDark: Bool) -> NSImage {
        let usage = profile.claudeUsage ?? .empty
        let showRemaining = config.showRemainingPercentage
        let sessionUsed = usage.effectiveSessionPercentage
        let weekUsed = usage.weeklyPercentage
        let sessionDisplay = UsageStatusCalculator.getDisplayPercentage(usedPercentage: sessionUsed, showRemaining: showRemaining)
        let weekDisplay = UsageStatusCalculator.getDisplayPercentage(usedPercentage: weekUsed, showRemaining: showRemaining)
        let sessionElapsed = UsageStatusCalculator.elapsedFraction(
            resetTime: usage.sessionResetTime, duration: Constants.sessionWindow, showRemaining: false)
        let weekElapsed = UsageStatusCalculator.elapsedFraction(
            resetTime: usage.weeklyResetTime, duration: Constants.weeklyWindow, showRemaining: false)
        let sessionStatus = UsageStatusCalculator.calculateStatus(
            usedPercentage: sessionUsed, showRemaining: showRemaining,
            elapsedFraction: config.usePaceColoring ? sessionElapsed : nil)
        let weekStatus = UsageStatusCalculator.calculateStatus(
            usedPercentage: weekUsed, showRemaining: showRemaining,
            elapsedFraction: config.usePaceColoring ? weekElapsed : nil)
        let monochrome = config.useSystemColor
        let sessionMarker: CGFloat? = config.showTimeMarker
            ? sessionElapsed.map { CGFloat(showRemaining ? 1 - $0 : $0) } : nil
        let weekMarker: CGFloat? = config.showTimeMarker && config.showWeek
            ? weekElapsed.map { CGFloat(showRemaining ? 1 - $0 : $0) } : nil
        let sessionPace: PaceStatus? = config.showPaceMarker
            ? sessionElapsed.flatMap { PaceStatus.calculate(usedPercentage: sessionUsed, elapsedFraction: $0) } : nil
        let weekPace: PaceStatus? = config.showPaceMarker && config.showWeek
            ? weekElapsed.flatMap { PaceStatus.calculate(usedPercentage: weekUsed, elapsedFraction: $0) } : nil

        let image: NSImage
        switch config.iconStyle {
        case .concentric:
            if config.showProfileLabel {
                image = renderer.createConcentricIconWithLabel(
                    sessionPercentage: sessionDisplay, weekPercentage: config.showWeek ? weekDisplay : 0,
                    sessionStatus: sessionStatus, weekStatus: weekStatus, profileName: profile.name,
                    monochromeMode: monochrome, isDarkMode: isDark, useSystemColor: false,
                    sessionTimeMarker: sessionMarker, weekTimeMarker: weekMarker,
                    sessionPaceStatus: sessionPace, weekPaceStatus: weekPace, showPaceMarker: config.showPaceMarker)
            } else {
                image = renderer.createConcentricIcon(
                    sessionPercentage: sessionDisplay, weekPercentage: config.showWeek ? weekDisplay : 0,
                    sessionStatus: sessionStatus, weekStatus: weekStatus, profileInitial: String(profile.name.prefix(1)),
                    monochromeMode: monochrome, isDarkMode: isDark, useSystemColor: false,
                    sessionTimeMarker: sessionMarker, weekTimeMarker: weekMarker,
                    sessionPaceStatus: sessionPace, weekPaceStatus: weekPace, showPaceMarker: config.showPaceMarker)
            }
        case .progressBar:
            image = renderer.createMultiProfileProgressBar(
                sessionPercentage: sessionDisplay, weekPercentage: config.showWeek ? weekDisplay : nil,
                sessionStatus: sessionStatus, weekStatus: weekStatus,
                profileName: config.showProfileLabel ? profile.name : nil,
                monochromeMode: monochrome, isDarkMode: isDark, useSystemColor: false,
                sessionTimeMarker: sessionMarker, weekTimeMarker: weekMarker,
                sessionPaceStatus: sessionPace, weekPaceStatus: weekPace, showPaceMarker: config.showPaceMarker)
        case .compact:
            image = renderer.createCompactDot(
                percentage: sessionDisplay, status: sessionStatus,
                profileInitial: config.showProfileLabel ? String(profile.name.prefix(1)) : nil,
                monochromeMode: monochrome, isDarkMode: isDark, useSystemColor: false,
                paceStatus: sessionPace, showPaceMarker: config.showPaceMarker)
        case .percentage:
            image = renderer.createMultiProfilePercentage(
                sessionPercentage: sessionDisplay, weekPercentage: config.showWeek ? weekDisplay : nil,
                sessionStatus: sessionStatus, weekStatus: weekStatus,
                profileName: config.showProfileLabel ? profile.name : nil,
                monochromeMode: monochrome, isDarkMode: isDark, useSystemColor: false,
                sessionPaceStatus: sessionPace, weekPaceStatus: weekPace, showPaceMarker: config.showPaceMarker)
        }
        image.isTemplate = monochrome && !config.showPaceMarker
        return image
    }

    // MARK: - Popover

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .semitransient
        // Animation off: on macOS 26/27 the animated resize recurses into layout
        // forever. PopoverContentView animates its own entrance instead.
        popover.animates = false
        popover.delegate = self
        return popover
    }

    private func makeContentViewController() -> NSHostingController<PopoverContentView> {
        let controller = NSHostingController(rootView: PopoverContentView(
            manager: self,
            onRefresh: { [weak self] in self?.refreshUsage() },
            onPreferences: { [weak self] in self?.openSettings() }
        ))
        controller.sizingOptions = .preferredContentSize
        return controller
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        guard let popover else { return }
        if popover.isShown {
            closePopover()
        } else if Date().timeIntervalSince(lastPopoverCloseDate) > 0.25 {
            popover.contentViewController = makeContentViewController()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            if let window = popover.contentViewController?.view.window {
                window.enableDisplayOnFullScreenSpaces()
                // Nothing needs initial focus; avoids a focus ring in the dropdown
                window.makeFirstResponder(nil)
            }
            startMonitoringForOutsideClicks()
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        stopMonitoringForOutsideClicks()
    }

    private func startMonitoringForOutsideClicks() {
        stopMonitoringForOutsideClicks()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func stopMonitoringForOutsideClicks() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshClicked), keyEquivalent: "r")
        let settings = NSMenuItem(title: "Settings…", action: #selector(settingsClicked), keyEquivalent: ",")
        let quit = NSMenuItem(title: "Quit", action: #selector(quitClicked), keyEquivalent: "q")
        [refresh, settings, quit].forEach { $0.target = self }
        menu.addItem(refresh)
        menu.addItem(.separator())
        menu.addItem(settings)
        menu.addItem(quit)
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil  // keep left click opening the popover
    }

    @objc private func refreshClicked() { refreshUsage() }
    @objc private func settingsClicked() { openSettings() }
    @objc private func quitClicked() { NSApp.terminate(nil) }

    // MARK: - Settings window

    func openSettings() {
        closePopover()
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Show a Dock icon while the window is open
            NSApp.setActivationPolicy(.regular)
            let window = SettingsWindowBuilder.makeWindow(size: Constants.WindowSizes.settingsWindow)
            window.title = "Claude Usage - Settings"
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.settingsWindow = window
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - NSPopoverDelegate

extension MenuBarManager: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        lastPopoverCloseDate = Date()
        stopMonitoringForOutsideClicks()
    }
}

// MARK: - NSWindowDelegate

extension MenuBarManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) == settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
        settingsWindow = nil
    }
}
