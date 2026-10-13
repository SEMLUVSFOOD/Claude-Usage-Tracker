import SwiftUI
import Charts

// MARK: - Always-active vibrancy background
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let container = NSView()

        // Base vibrancy layer
        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.isEmphasized = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(effectView)

        // Solid tint overlay for more density
        let tintView = NSView()
        tintView.wantsLayer = true
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        } else {
            tintView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.4).cgColor
        }
        tintView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tintView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: container.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            tintView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: container.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Update tint for appearance changes
        if let tintView = nsView.subviews.last {
            tintView.wantsLayer = true
            if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
            } else {
                tintView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.4).cgColor
            }
        }
    }
}

/// Native macOS popover interface - minimal, flat, system-style
struct PopoverContentView: View {
    @ObservedObject var manager: MenuBarManager
    let onRefresh: () -> Void
    let onPreferences: () -> Void

    @State private var isRefreshing = false
    // Custom entrance animation: the native NSPopover animation is disabled
    // (see MenuBarManager) because its animated resize recurses on macOS 26/27.
    @State private var appeared = false
    @StateObject private var profileManager = ProfileManager.shared
    @ObservedObject private var followService = ClaudeCodeFollowService.shared
    @ObservedObject private var activity = ClaudeCodeActivityMonitor.shared

    private func refreshWithSpinner() {
        withAnimation(.easeInOut(duration: 0.3)) { isRefreshing = true }
        onRefresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.3)) { isRefreshing = false }
        }
    }

    private var headerControls: AnyView {
        AnyView(CombinedHeaderControls(
            status: manager.status,
            isRefreshing: isRefreshing,
            onRefresh: refreshWithSpinner,
            onPreferences: onPreferences
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lastRefresh = manager.lastSuccessfulRefreshTime,
               Date().timeIntervalSince(lastRefresh) > 300 {
                StatusBannerView(
                    icon: "clock.fill",
                    message: "Updated \(Int(Date().timeIntervalSince(lastRefresh) / 60)) min ago",
                    color: .orange,
                    onTap: onRefresh
                )
            }

            let profiles = profileManager.popoverProfiles
            let menuBarProfileId = profileManager.menuBarProfile?.id

            if profiles.isEmpty {
                emptyState
            }

            ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                if index > 0 {
                    PopoverDivider()
                        .padding(.top, 6)
                }
                ProfileUsageTag(
                    profile: profile,
                    menuBarSelection: profiles.count > 1
                        ? (profile.id == menuBarProfileId ? .shown : .selectable)
                        : nil,
                    onShowInMenuBar: { profileManager.setMenuBarProfile(profile.id) },
                    accessory: index == 0 ? headerControls : nil
                )
                if profile.provider == .antigravity && !profile.hasUsageCredentials {
                    AntigravitySignInCard(profileId: profile.id)
                } else if !profileManager.canFetchUsage(for: profile) {
                    NotSignedInCard(onOpenSettings: onPreferences)
                } else {
                    SmartUsageDashboard(usage: profile.claudeUsage ?? .empty, provider: profile.provider)
                }
            }

            if profiles.count > 1 {
                PopoverDivider()
                    .padding(.top, 6)
                FollowClaudeCodeToggle(
                    isOn: profileManager.multiProfileConfig.followClaudeCode,
                    folderName: followService.currentFolder?.name,
                    isLinked: profileManager.followedClaudeCodeProfile != nil,
                    hasSwitcher: followService.currentFolder != nil,
                    onChange: { profileManager.setFollowClaudeCode($0) }
                )
            }

            if profiles.contains(where: { $0.provider.descriptor.capabilities.cliAccountSync }) {
                KeepAwakeToggle(
                    isOn: activity.settings.keepAwake,
                    workingCount: activity.workingCount,
                    onChange: { on in activity.update { $0.keepAwake = on } }
                )
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 14)
        .frame(width: 280)
        .background(VisualEffectBackground())
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.96, anchor: .top)
        .onAppear {
            appeared = false
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { appeared = true }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("No accounts shown")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                headerControls
            }
            Text("Add a Claude, Codex or Google account in Settings.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Profile Usage Tag

/// Avatar + name row that labels each account's section in the dropdown.
/// It doubles as the control for choosing the menu bar account.
struct ProfileUsageTag: View {
    enum MenuBarSelection {
        case shown       // This profile drives the menu bar icon
        case selectable  // Clicking the row makes this profile drive the icon
    }

    let profile: Profile
    var menuBarSelection: MenuBarSelection? = nil
    var onShowInMenuBar: () -> Void = {}
    /// Extra controls at the trailing edge (top row: status, refresh, settings)
    var accessory: AnyView? = nil

    @State private var isHovered = false

    var body: some View {
        let row = HStack(spacing: 8) {
            ProviderBrandMark(provider: profile.provider, size: 20)

            Text(profile.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            switch menuBarSelection {
            case .shown:
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .help("Shown in the menu bar")
            case .selectable:
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.secondary)
                    .opacity(isHovered ? 1 : 0.35)
            case nil:
                EmptyView()
            }

            if let accessory = accessory {
                accessory
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(isHovered && menuBarSelection == .selectable ? 0.07 : 0.03))
        )
        .padding(.horizontal, 10)
        .padding(.top, 6)

        if menuBarSelection == .selectable {
            Button(action: onShowInMenuBar) {
                row.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show \(profile.name) in the menu bar")
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
        } else {
            row
        }
    }
}

// MARK: - Not Signed In

/// Shown instead of empty 0% bars for an account without credentials.
struct NotSignedInCard: View {
    let onOpenSettings: () -> Void

    var body: some View {
        HStack {
            Text("Not signed in")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Button("Open Settings", action: onOpenSettings)
                .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }
}

// MARK: - Provider Brand Mark

/// Colored provider logo used as the profile avatar in the dropdown. Drawn in
/// code (the asset catalog has no provider logos): Claude's coral starburst and
/// Gemini's gradient four-point star; other providers fall back to their symbol.
struct ProviderBrandMark: View {
    let provider: Provider
    var size: CGFloat = 20

    var body: some View {
        switch provider {
        case .anthropic:
            ClaudeStarburst()
                .stroke(Color(red: 0.85, green: 0.47, blue: 0.34),
                        style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                .frame(width: size * 0.82, height: size * 0.82)
                .frame(width: size, height: size)
        case .antigravity:
            GeminiStar()
                .fill(LinearGradient(
                    colors: [Color(red: 0.11, green: 0.49, blue: 1.0),
                             Color(red: 0.61, green: 0.45, blue: 0.80),
                             Color(red: 0.85, green: 0.42, blue: 0.47)],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                ))
                .frame(width: size * 0.9, height: size * 0.9)
                .frame(width: size, height: size)
        case .codex:
            ProviderLogoView(provider: provider, size: size * 0.8)
                .foregroundColor(.primary)
                .frame(width: size, height: size)
        }
    }
}

/// Rays radiating from the center with slightly varying lengths.
private struct ClaudeStarburst: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let lengths: [CGFloat] = [1.0, 0.78, 0.92, 0.72, 0.98, 0.8, 0.9, 0.74, 1.0, 0.82, 0.88, 0.76]
        var path = Path()
        for (index, length) in lengths.enumerated() {
            let angle = CGFloat(index) / CGFloat(lengths.count) * 2 * .pi - .pi / 2
            let inner = radius * 0.12
            path.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            path.addLine(to: CGPoint(x: center.x + cos(angle) * radius * length,
                                     y: center.y + sin(angle) * radius * length))
        }
        return path
    }
}

/// Four-point star with concave sides.
private struct GeminiStar: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: c.y), control: c)
        path.addQuadCurve(to: CGPoint(x: c.x, y: rect.maxY), control: c)
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: c.y), control: c)
        path.addQuadCurve(to: CGPoint(x: c.x, y: rect.minY), control: c)
        path.closeSubpath()
        return path
    }
}

// MARK: - Follow Claude Code Toggle

/// Footer switch in the dropdown: when on, the menu bar icon shows whichever
/// account Claude Code is using (as set by e.g. the VS Code profile switcher).
struct FollowClaudeCodeToggle: View {
    let isOn: Bool
    let folderName: String?
    let isLinked: Bool
    /// False when ~/.claude isn't a switcher-managed symlink
    let hasSwitcher: Bool
    let onChange: (Bool) -> Void

    /// The VS Code extension that switches Claude Code accounts by repointing ~/.claude
    private static let switcherURL = URL(string: "vscode:extension/sairambkrishnan.claude-code-profile-switcher")!

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isOn ? .accentColor : .secondary)
                    .frame(width: 12)

                Text("Follow Claude Code")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)

                if isOn && hasSwitcher {
                    if isLinked, let folderName {
                        Text(folderName)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("not linked")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                            .help("Link this Claude Code folder to a profile in Settings → Profiles")
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(get: { isOn }, set: onChange))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .focusEffectDisabled()
            }

            if isOn && !hasSwitcher {
                Button {
                    NSWorkspace.shared.open(Self.switcherURL)
                } label: {
                    Text("Needs the Claude Code Profile Switcher for VS Code →")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Following works by watching which account that extension selects")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .help("Show the account Claude Code is currently using in the menu bar")
    }
}

// MARK: - Keep Awake Toggle

/// Keeps the Mac from idle-sleeping while a Claude Code session is working.
struct KeepAwakeToggle: View {
    let isOn: Bool
    let workingCount: Int
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isOn && workingCount > 0 ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isOn ? .accentColor : .secondary)
                .frame(width: 12)

            Text("Keep Mac awake")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)

            if isOn {
                Text(workingCount > 0
                     ? "\(workingCount) session\(workingCount == 1 ? "" : "s") working"
                     : "while Claude Code works")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: Binding(get: { isOn }, set: onChange))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .focusEffectDisabled()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .help("Prevents idle sleep while a Claude Code session is working; the screen can still turn off")
    }
}

// MARK: - Combined Header Controls

/// Service status dot + refresh + settings, shown on the top profile row in
/// the dropdown.
struct CombinedHeaderControls: View {
    let status: ClaudeStatus
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onPreferences: () -> Void

    private var statusColor: Color {
        switch status.indicator.color {
        case .green: return .adaptiveGreen
        case .yellow: return .yellow
        case .orange: return .orange
        case .red: return .red
        case .gray: return .gray
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button(action: {
                if let url = URL(string: "https://status.claude.com") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .frame(width: 18, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(status.description)

            HeaderIconButton(
                icon: "arrow.clockwise",
                isRefreshing: isRefreshing,
                action: onRefresh
            )
            .disabled(isRefreshing)

            HeaderIconButton(
                icon: "gearshape.fill",
                fontSize: 12,
                action: onPreferences
            )
        }
        .padding(.vertical, -4)
        .padding(.trailing, -6)
    }
}

// MARK: - Native Divider

struct PopoverDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 16)
    }
}

// MARK: - Header Icon Button
struct HeaderIconButton: View {
    let icon: String
    var fontSize: CGFloat = 10.5
    var isRefreshing: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 10, height: 10)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: fontSize, weight: .medium))
                        .imageScale(.medium)
                }
            }
            .foregroundColor(isHovered ? .primary : .secondary)
            .frame(width: 24, height: 24, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Smart Usage Dashboard
struct SmartUsageDashboard: View {
    let usage: ClaudeUsage
    var provider: Provider = .anthropic
    @StateObject private var profileManager = ProfileManager.shared

    private var config: MultiProfileDisplayConfig { profileManager.multiProfileConfig }
    private var showRemainingPercentage: Bool { config.showRemainingPercentage }
    private var showTimeMarker: Bool { config.showTimeMarker }
    private var usePaceColoring: Bool { config.usePaceColoring }
    private var showPaceMarker: Bool { config.showPaceMarker }

    private let timeDisplay: PopoverTimeDisplay = .resetTime

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Primary: Session Usage
            UsageRow(
                title: "menubar.session_usage".localized,
                subtitle: "menubar.5_hour_window".localized,
                usedPercentage: usage.effectiveSessionPercentage,
                showRemaining: showRemainingPercentage,
                resetTime: usage.sessionResetTime,
                periodDuration: Constants.sessionWindow,
                showTimeMarker: showTimeMarker,
                showPaceMarker: showPaceMarker,
                usePaceColoring: usePaceColoring,
                timeDisplay: timeDisplay,
                forecast: UsageForecast.make(usedPercentage: usage.effectiveSessionPercentage,
                                             resetTime: usage.sessionResetTime,
                                             windowDuration: Constants.sessionWindow)
            )

            if usage.designWeeklyTokensUsed > 0 {
                UsageRow(
                    title: "menubar.design_usage".localized,
                    tag: "menubar.weekly".localized,
                    subtitle: nil,
                    usedPercentage: usage.designWeeklyPercentage,
                    showRemaining: showRemainingPercentage,
                    resetTime: usage.designWeeklyResetTime,
                    periodDuration: nil,
                    timeDisplay: timeDisplay
                )
            }

            // All Models (Weekly)
            UsageRow(
                title: "menubar.all_models".localized,
                tag: "menubar.weekly".localized,
                subtitle: nil,
                usedPercentage: usage.weeklyPercentage,
                showRemaining: showRemainingPercentage,
                resetTime: usage.weeklyResetTime,
                periodDuration: Constants.weeklyWindow,
                showTimeMarker: showTimeMarker,
                showPaceMarker: showPaceMarker,
                usePaceColoring: usePaceColoring,
                timeDisplay: timeDisplay,
                forecast: UsageForecast.make(usedPercentage: usage.weeklyPercentage,
                                             resetTime: usage.weeklyResetTime,
                                             windowDuration: Constants.weeklyWindow)
            )

            if usage.fableWeeklyTokensUsed > 0 {
                UsageRow(
                    title: "menubar.fable_usage".localized,
                    tag: "menubar.weekly".localized,
                    subtitle: nil,
                    usedPercentage: usage.fableWeeklyPercentage,
                    showRemaining: showRemainingPercentage,
                    resetTime: usage.fableWeeklyResetTime,
                    periodDuration: nil,
                    timeDisplay: timeDisplay
                )
            }

            if usage.opusWeeklyTokensUsed > 0 {
                UsageRow(
                    title: "menubar.opus_usage".localized,
                    tag: "menubar.weekly".localized,
                    subtitle: nil,
                    usedPercentage: usage.opusWeeklyPercentage,
                    showRemaining: showRemainingPercentage,
                    resetTime: nil,
                    periodDuration: nil
                )
            }

            if usage.sonnetWeeklyTokensUsed > 0 {
                UsageRow(
                    title: "menubar.sonnet_usage".localized,
                    subtitle: nil,
                    usedPercentage: usage.sonnetWeeklyPercentage,
                    showRemaining: showRemainingPercentage,
                    resetTime: usage.sonnetWeeklyResetTime,
                    periodDuration: nil,
                    timeDisplay: timeDisplay
                )
            }

            // Extra usage (cost-based)
            if let used = usage.costUsed, let limit = usage.costLimit, let currency = usage.costCurrency, limit > 0 {
                let usedPercentage = (used / limit) * 100.0
                UsageRow(
                    title: "menubar.extra_usage".localized,
                    subtitle: String(format: "%.2f / %.2f %@", used / 100.0, limit / 100.0, currency),
                    usedPercentage: usedPercentage,
                    showRemaining: showRemainingPercentage,
                    resetTime: nil,
                    periodDuration: nil
                )

                // Overage credit grant balance
                if let balance = usage.overageBalance, let balanceCurrency = usage.overageBalanceCurrency {
                    HStack {
                        Text("popover.overage_balance".localized)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.2f %@", balance / 100.0, balanceCurrency.uppercased()))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.adaptiveGreen)
                    }
                }
            }

            // Plan / credits (providers that report them, e.g. Codex)
            if usage.planType != nil || usage.creditsUnlimited == true || usage.creditsBalance != nil {
                HStack(spacing: 6) {
                    if let plan = usage.planType {
                        Text(plan.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }

                    Spacer()

                    if usage.creditsUnlimited == true {
                        Text("popover.credits_unlimited".localized)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.adaptiveGreen)
                    } else if let balance = usage.creditsBalance {
                        Text("popover.credits_balance".localized(with: String(format: "%.2f", balance)))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 2)
            }

        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Usage Row (flat, native style)
struct UsageRow: View {
    let title: String
    var tag: String? = nil
    let subtitle: String?
    let usedPercentage: Double
    let showRemaining: Bool
    let resetTime: Date?
    let periodDuration: TimeInterval?
    var showTimeMarker: Bool = true
    var showPaceMarker: Bool = true
    var usePaceColoring: Bool = true
    var timeDisplay: PopoverTimeDisplay = .resetTime
    /// "At this pace" projection, shown under the reset time
    var forecast: UsageForecast? = nil

    private var displayPercentage: Double {
        UsageStatusCalculator.getDisplayPercentage(
            usedPercentage: usedPercentage,
            showRemaining: showRemaining
        )
    }

    private var rawElapsedFraction: Double? {
        UsageStatusCalculator.elapsedFraction(
            resetTime: resetTime,
            duration: periodDuration ?? 0,
            showRemaining: false
        )
    }

    private var timeMarkerFraction: CGFloat? {
        guard showTimeMarker, let f = rawElapsedFraction else { return nil }
        return CGFloat(showRemaining ? 1.0 - f : f)
    }

    private var paceStatus: PaceStatus? {
        guard showPaceMarker, let elapsed = rawElapsedFraction else { return nil }
        return PaceStatus.calculate(usedPercentage: usedPercentage, elapsedFraction: elapsed)
    }

    private var timeMarkerColor: Color {
        if let pace = paceStatus {
            return pace.swiftUIColor
        }
        return Color(nsColor: .labelColor)
    }

    private var statusLevel: UsageStatusLevel {
        UsageStatusCalculator.calculateStatus(
            usedPercentage: usedPercentage,
            showRemaining: showRemaining,
            elapsedFraction: usePaceColoring ? rawElapsedFraction : nil
        )
    }

    private var statusColor: Color {
        switch statusLevel {
        case .safe: return .adaptiveGreen
        case .moderate: return .orange
        case .critical: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Title row with percentage
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)

                        if let tag = tag {
                            Text(tag)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule()
                                        .fill(Color.primary.opacity(0.08))
                                )
                        }
                    }

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Text("\(Int(displayPercentage))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(statusColor)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.primary.opacity(0.08))

                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(statusColor)
                        .frame(width: geometry.size.width * min(displayPercentage / 100.0, 1.0))
                        .animation(.easeInOut(duration: 0.6), value: displayPercentage)
                }
                .overlay(alignment: .leading) {
                    if let fraction = timeMarkerFraction {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(timeMarkerColor)
                            .frame(width: 2.5, height: 8)
                            .offset(x: round(geometry.size.width * fraction) - 0.75)
                    }
                }
            }
            .frame(height: 4)

            // Reset time
            if let reset = resetTime {
                Text(resetTimeText(for: reset))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            if let forecast {
                HStack(spacing: 3) {
                    if forecast.runsOut {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                    }
                    Text(forecast.text())
                        .font(.system(size: 9, weight: forecast.runsOut ? .medium : .regular))
                }
                .foregroundColor(forecast.runsOut ? .orange : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func resetTimeText(for reset: Date) -> String {
        switch timeDisplay {
        case .resetTime:
            return "menubar.resets_time".localized(with: reset.resetTimeString())
        case .remainingTime:
            return "menubar.resets_in".localized(with: reset.timeRemainingString())
        case .both:
            return "menubar.resets_both".localized(with: reset.timeRemainingString(), reset.resetTimeString())
        }
    }
}

// MARK: - Status Banner View
struct StatusBannerView: View {
    let icon: String
    let message: String
    let color: Color
    var onTap: (() -> Void)? = nil

    var body: some View {
        // A Button rather than a tap gesture: the popover belongs to an inactive
        // accessory app, and AppKit only delivers a click-through mouse-down to views
        // that accept first mouse, which a bare tap gesture does not.
        if let onTap {
            Button(action: onTap) {
                bannerContent
            }
            .buttonStyle(.plain)
        } else {
            bannerContent
        }
    }

    private var bannerContent: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .cornerRadius(6)
        .contentShape(Rectangle())
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }
}
