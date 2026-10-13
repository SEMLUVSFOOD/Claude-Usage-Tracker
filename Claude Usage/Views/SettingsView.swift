import SwiftUI
import UserNotifications

// MARK: - Visual Effect Backgrounds

/// Full-window vibrancy background — same approach as the popover's VisualEffectBackground.
/// Using NSViewRepresentable inside SwiftUI means the entire view tree is SwiftUI-managed,
/// so there is no opaque flash on deminiaturize or appearance change.
struct SettingsBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let container = NSView()

        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.isEmphasized = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(effectView)

        let tintView = NSView()
        tintView.wantsLayer = true
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
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
        if let tintView = nsView.subviews.last {
            tintView.wantsLayer = true
            if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
            } else {
                tintView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.4).cgColor
            }
        }
    }
}

struct SidebarVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let container = NSView()

        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.isEmphasized = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(effectView)

        let tintView = NSView()
        tintView.wantsLayer = true
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        } else {
            tintView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.5).cgColor
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
        if let tintView = nsView.subviews.last {
            tintView.wantsLayer = true
            if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
            } else {
                tintView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.5).cgColor
            }
        }
    }
}

/// Borderless window that keeps rounded corners, shadow, and drag-to-move.
final class BorderlessSettingsWindow: NSWindow {
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask,
                  backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .miniaturizable],
                   backing: backing, defer: flag)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isRestorable = false

        // Round corners via the content view's layer
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 10
        contentView?.layer?.masksToBounds = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Borderless windows don't route Cmd+W to performClose: automatically (and
    // performClose: needs a close button, which a borderless window lacks), so
    // close directly to support the standard shortcut (#223, #252). close()
    // still fires windowWillClose, so MenuBarManager's dock-icon cleanup runs.
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            close()
            return
        }
        super.keyDown(with: event)
    }
}

/// Builds the settings window — fully borderless, no system titlebar.
enum SettingsWindowBuilder {
    static func makeWindow(size: CGSize) -> NSWindow {
        let window = BorderlessSettingsWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        let hostingView = NSHostingView(rootView:
            SettingsView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        window.contentView?.addSubview(hostingView)
        if let contentView = window.contentView {
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ])
        }

        return window
    }
}

// MARK: - Custom Traffic Light Buttons

struct TrafficLightButtons: View {
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        HStack(spacing: 8) {
            TrafficLightButton(type: .close)
            TrafficLightButton(type: .miniaturize)
        }
    }
}

struct TrafficLightButton: View {
    enum ButtonType {
        case close, miniaturize, zoom

        var activeColor: Color {
            switch self {
            case .close: return Color(nsColor: NSColor(red: 1.0, green: 0.38, blue: 0.34, alpha: 1.0))
            case .miniaturize: return Color(nsColor: NSColor(red: 1.0, green: 0.74, blue: 0.18, alpha: 1.0))
            case .zoom: return Color(nsColor: NSColor(red: 0.15, green: 0.78, blue: 0.24, alpha: 1.0))
            }
        }

        var icon: String {
            switch self {
            case .close: return "xmark"
            case .miniaturize: return "minus"
            case .zoom: return "plus"
            }
        }
    }

    let type: ButtonType
    @State private var isHovered = false
    @Environment(\.controlActiveState) private var controlActiveState

    private var isActive: Bool { controlActiveState == .key }

    var body: some View {
        Circle()
            .fill(isActive ? type.activeColor : Color.primary.opacity(0.15))
            .frame(width: 12, height: 12)
            .overlay {
                if isHovered && isActive {
                    Image(systemName: type.icon)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.black.opacity(0.5))
                }
            }
            .onHover { isHovered = $0 }
            .onTapGesture { performAction() }
    }

    private func performAction() {
        guard let window = NSApp.keyWindow else { return }
        switch type {
        case .close: window.close()
        case .miniaturize: window.miniaturize(nil)
        case .zoom: window.zoom(nil)
        }
    }
}

/// Settings window: accounts (and each account's sign-in page), the menu bar
/// icon, and general options.
struct SettingsView: View {
    @State private var page: SettingsPage = .accounts
    @StateObject private var profileManager = ProfileManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    TrafficLightButtons()
                    Spacer()
                }
                .padding(.leading, 12)
                .padding(.top, 12)
                .padding(.bottom, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        SidebarItem(icon: "person.2.fill", title: "Accounts", description: "Add, rename or remove accounts",
                                    isSelected: page == .accounts) { open(.accounts) }

                        ForEach(profileManager.profiles) { profile in
                            accountItems(for: profile)
                        }

                        Divider().padding(.vertical, 8).padding(.horizontal, 8)

                        SidebarItem(icon: "chart.xyaxis.line", title: "Stats", description: "Usage history and charts per account",
                                    isSelected: page == .stats) { open(.stats) }
                        SidebarItem(icon: "terminal.fill", title: "Claude Code", description: "Keep awake and alerts",
                                    isSelected: page == .claudeCode) { open(.claudeCode) }
                        SidebarItem(icon: "menubar.rectangle", title: "Menu bar icon", description: "Icon style and Follow Claude Code",
                                    isSelected: page == .menuBarIcon) { open(.menuBarIcon) }
                        SidebarItem(icon: "gearshape.fill", title: "General", description: "Launch at login",
                                    isSelected: page == .general) { open(.general) }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .background(SidebarVisualEffect())
            .frame(width: 190)

            Group {
                switch page {
                case .accounts:
                    AccountsSettingsView(onOpenAccount: openFirstPage(of:))
                case .account(_, let section):
                    switch section {
                    case .claudeAI: PersonalUsageView()
                    case .cliAccount: CLIAccountView()
                    case .codexAccount: CodexAccountView()
                    case .antigravityAccount: AntigravityAccountView()
                    }
                case .stats:
                    StatsView()
                case .claudeCode:
                    ClaudeCodeSettingsView()
                case .menuBarIcon:
                    MenuBarIconSettingsView()
                case .general:
                    AppSettingsView()
                }
            }
            // Credential pages read ProfileManager.editingProfile; rebuild per account
            .id(page)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(colorScheme == .dark ? Color.black.opacity(0.15) : Color.white.opacity(0.3))
        }
        .frame(minWidth: 720, maxWidth: 720, maxHeight: .infinity)
        .background(SettingsBackground())
    }

    @ViewBuilder
    private func accountItems(for profile: Profile) -> some View {
        let sections = profile.provider.descriptor.credentialSections
        HStack(spacing: 6) {
            ProviderBrandMark(provider: profile.provider, size: 14)
            Text(profile.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .contentShape(Rectangle())
        .onTapGesture { openFirstPage(of: profile.id) }

        ForEach(sections, id: \.self) { section in
            SidebarItem(icon: section.icon, title: section.title, description: section.title,
                        isSelected: page == .account(profile.id, section)) {
                open(.account(profile.id, section))
            }
            .padding(.leading, 10)
        }
    }

    private func openFirstPage(of profileId: UUID) {
        guard let profile = profileManager.profiles.first(where: { $0.id == profileId }),
              let section = profile.provider.descriptor.credentialSections.first else { return }
        open(.account(profileId, section))
    }

    private func open(_ newPage: SettingsPage) {
        if case .account(let id, _) = newPage {
            profileManager.editingProfileId = id
        }
        page = newPage
    }
}

enum SettingsPage: Hashable {
    case accounts
    case account(UUID, SettingsSection)
    case stats
    case claudeCode
    case menuBarIcon
    case general
}

/// Sign-in pages a provider offers (listed in its ProviderDescriptor)
enum SettingsSection: String, CaseIterable {
    case claudeAI
    case cliAccount
    case codexAccount
    case antigravityAccount

    var title: String {
        switch self {
        case .claudeAI: return "Claude.ai session"
        case .cliAccount: return "Claude Code login"
        case .codexAccount: return "Codex CLI"
        case .antigravityAccount: return "Google account"
        }
    }

    var icon: String {
        switch self {
        case .claudeAI: return "key.fill"
        case .cliAccount: return "terminal.fill"
        case .codexAccount: return "terminal.fill"
        case .antigravityAccount: return "person.badge.key.fill"
        }
    }
}

// MARK: - Sidebar Item

struct SidebarItem: View {
    let icon: String
    let title: String
    let description: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .frame(width: 12)

                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .white : .primary)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? SettingsColors.primary : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
            )
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(description)
    }
}
