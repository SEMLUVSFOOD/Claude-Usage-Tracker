//
//  SettingsColors.swift
//  Claude Usage - Settings Design System
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

/// Semantic color palette for Settings UI
/// Provides consistent colors across all settings views
enum SettingsColors {
    // MARK: - Status Colors

    /// Success state (green)
    static let success = Color.adaptiveGreen

    /// Error state (red)
    static let error = Color.red

    /// Warning state (orange)
    static let warning = Color.orange

    /// Informational state (blue)
    static let info = Color.blue

    /// Caution state (yellow)

    // MARK: - Semantic UI Colors

    /// Primary action color (system accent)
    static let primary = Color.accentColor

    /// Secondary elements
    static let secondary = Color.secondary

    /// Card background — translucent to work with vibrancy
    static let cardBackground = Color.primary.opacity(0.04)

    /// Input field background — translucent to work with vibrancy
    static let inputBackground = Color.primary.opacity(0.06)

    /// Border color for inputs and cards — subtle for vibrancy
    static let border = Color.primary.opacity(0.08)

    // MARK: - Feature-Specific Colors

    /// Icon color for feature highlights

    /// Beta badge color
    static let betaBadge = Color.orange

    /// Pro feature badge
    static let proBadge = Color.purple

    // MARK: - Threshold Colors (for usage indicators)

    /// Low usage (0-50%)

    /// Medium usage (50-75%)

    /// High usage (75-90%)

    /// Critical usage (90%+)

    // MARK: - Opacity Variants

}
