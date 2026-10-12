//
//  Spacing.swift
//  Claude Usage - Settings Design System
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

/// Spacing system for Settings UI
/// Follows 4px grid system for consistent spacing
enum Spacing {
    // MARK: - Core Spacing (4px grid)

    /// 4px - Minimal spacing
    static let xs: CGFloat = 4

    /// 8px - Small spacing between related elements
    static let sm: CGFloat = 8

    /// 12px - Medium spacing within components
    static let md: CGFloat = 12

    /// 16px - Standard spacing between components
    static let lg: CGFloat = 16

    /// 20px - Large spacing for section separation
    static let xl: CGFloat = 20

    /// 24px - Extra large spacing

    /// 32px - Maximum spacing for major sections

    // MARK: - Semantic Spacing

    /// Spacing between settings sections (20px)

    /// Spacing between cards (16px)

    /// Spacing within cards (20px)
    static let cardPadding: CGFloat = 20

    /// Spacing for input fields (12px)

    /// Padding for input fields (12px)

    /// Content padding from edges (28px)
    static let contentPadding: CGFloat = 28

    /// Compact content padding (16px)
    static let compactPadding: CGFloat = 16

    // MARK: - Component Spacing

    /// Spacing between toggle and description (4px)

    /// Spacing between icon and text (8px)

    /// Spacing between buttons in a row (10px)

    /// Spacing in form rows (12px)

    // MARK: - Radius

    /// Small corner radius (4px)

    /// Medium corner radius (6px)

    /// Standard corner radius (8px)

    /// Large corner radius for cards (12px)

    /// Extra large radius (16px)
}

/// View modifiers for consistent spacing
extension View {
    /// Apply standard card padding
    func cardPadding() -> some View {
        self.padding(Spacing.cardPadding)
    }

    /// Apply content padding
    func contentPadding() -> some View {
        self.padding(Spacing.contentPadding)
    }

    /// Apply compact padding
    func compactPadding() -> some View {
        self.padding(Spacing.compactPadding)
    }
}
