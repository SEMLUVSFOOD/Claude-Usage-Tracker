//
//  MenuBarIconConfig.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-27.
//

import Foundation

/// How the menu bar icon draws a profile's session and weekly usage
enum MultiProfileIconStyle: String, Codable, CaseIterable {
    case concentric   // Concentric circles (session inner, week outer)
    case progressBar  // Horizontal progress bars stacked
    case compact      // Minimal dot indicators
    case percentage   // Percentage text (e.g. "30 · 4")

    var displayName: String {
        switch self {
        case .concentric:
            return "Concentric Circles"
        case .progressBar:
            return "Progress Bars"
        case .compact:
            return "Compact Dots"
        case .percentage:
            return "Percentage"
        }
    }

    var description: String {
        switch self {
        case .concentric:
            return "Session inside, week outside ring"
        case .progressBar:
            return "Horizontal bars stacked vertically"
        case .compact:
            return "Minimal colored dots"
        case .percentage:
            return "Session and week as colored numbers"
        }
    }

    var icon: String {
        switch self {
        case .concentric:
            return "circle.circle"
        case .progressBar:
            return "chart.bar.fill"
        case .compact:
            return "circle.fill"
        case .percentage:
            return "percent"
        }
    }
}

/// Configuration for multi-profile display mode
struct MultiProfileDisplayConfig: Codable, Equatable {
    var iconStyle: MultiProfileIconStyle
    var showWeek: Bool        // If false, only show session
    var showProfileLabel: Bool // Show profile name below icon
    var useSystemColor: Bool  // If true, use system accent color instead of status colors
    var showTimeMarker: Bool  // If true, show time-elapsed tick mark on progress indicators
    var showPaceMarker: Bool  // If true, color time marker by projected usage pace (6-tier)
    var usePaceColoring: Bool // If true, color indicators based on projected usage pace
    var showRemainingPercentage: Bool // If true, show remaining capacity instead of used percentage
    var showActiveProfileIndicator: Bool // If true, show a green underline on the active profile's icon
    var menuBarProfileId: UUID?     // Profile whose usage drives the single combined icon (nil = active profile)
    var followClaudeCode: Bool      // If true, the combined icon shows the profile Claude Code is currently using
    var claudeCodeFolders: [String: String] // Profile UUID string -> Claude Code config folder it uses

    init(
        iconStyle: MultiProfileIconStyle = .concentric,
        showWeek: Bool = true,
        showProfileLabel: Bool = true,
        useSystemColor: Bool = false,
        showTimeMarker: Bool = true,
        showPaceMarker: Bool = true,
        usePaceColoring: Bool = true,
        showRemainingPercentage: Bool = false,
        showActiveProfileIndicator: Bool = false,
        menuBarProfileId: UUID? = nil,
        followClaudeCode: Bool = false,
        claudeCodeFolders: [String: String] = [:]
    ) {
        self.iconStyle = iconStyle
        self.showWeek = showWeek
        self.showProfileLabel = showProfileLabel
        self.useSystemColor = useSystemColor
        self.showTimeMarker = showTimeMarker
        self.showPaceMarker = showPaceMarker
        self.usePaceColoring = usePaceColoring
        self.showRemainingPercentage = showRemainingPercentage
        self.showActiveProfileIndicator = showActiveProfileIndicator
        self.menuBarProfileId = menuBarProfileId
        self.followClaudeCode = followClaudeCode
        self.claudeCodeFolders = claudeCodeFolders
    }

    // MARK: - Codable (Custom decoder for backwards compatibility)

    enum CodingKeys: String, CodingKey {
        case iconStyle
        case showWeek
        case showProfileLabel
        case useSystemColor
        case showTimeMarker
        case showPaceMarker
        case usePaceColoring
        case showRemainingPercentage
        case showActiveProfileIndicator
        case menuBarProfileId
        case followClaudeCode
        case claudeCodeFolders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        iconStyle = try container.decode(MultiProfileIconStyle.self, forKey: .iconStyle)
        showWeek = try container.decode(Bool.self, forKey: .showWeek)
        showProfileLabel = try container.decode(Bool.self, forKey: .showProfileLabel)
        // New properties - provide default values if missing (backwards compatibility)
        useSystemColor = try container.decodeIfPresent(Bool.self, forKey: .useSystemColor) ?? false
        showTimeMarker = try container.decodeIfPresent(Bool.self, forKey: .showTimeMarker) ?? true
        showPaceMarker = try container.decodeIfPresent(Bool.self, forKey: .showPaceMarker) ?? false
        usePaceColoring = try container.decodeIfPresent(Bool.self, forKey: .usePaceColoring) ?? false
        showRemainingPercentage = try container.decodeIfPresent(Bool.self, forKey: .showRemainingPercentage) ?? false
        showActiveProfileIndicator = try container.decodeIfPresent(Bool.self, forKey: .showActiveProfileIndicator) ?? false
        menuBarProfileId = try container.decodeIfPresent(UUID.self, forKey: .menuBarProfileId)
        followClaudeCode = try container.decodeIfPresent(Bool.self, forKey: .followClaudeCode) ?? false
        claudeCodeFolders = try container.decodeIfPresent([String: String].self, forKey: .claudeCodeFolders) ?? [:]
    }

    static var `default`: MultiProfileDisplayConfig {
        MultiProfileDisplayConfig()
    }
}
