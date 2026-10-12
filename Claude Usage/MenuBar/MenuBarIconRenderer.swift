//
//  MenuBarIconRenderer.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-27.
//

import Cocoa

/// Draws the menu bar icon styles for a profile's usage
final class MenuBarIconRenderer {

    // MARK: - Multi-Profile Concentric Icon

    /// Creates a compact concentric circle icon for multi-profile display mode
    /// - Parameters:
    ///   - sessionPercentage: Session usage percentage (0-100)
    ///   - weekPercentage: Week usage percentage (0-100)
    ///   - sessionStatus: Status level for session (for coloring)
    ///   - weekStatus: Status level for week (for coloring)
    ///   - profileInitial: Single character to display in center (e.g., "W" for Work)
    ///   - monochromeMode: If true, use foreground color for all elements
    ///   - isDarkMode: Whether the menu bar is in dark mode
    ///   - useSystemColor: If true, use system accent color instead of status colors
    /// - Returns: NSImage with concentric circles showing both metrics
    func createConcentricIcon(
        sessionPercentage: Double,
        weekPercentage: Double,
        sessionStatus: UsageStatusLevel,
        weekStatus: UsageStatusLevel,
        profileInitial: String,
        monochromeMode: Bool,
        isDarkMode: Bool,
        useSystemColor: Bool = false,
        sessionTimeMarker: CGFloat? = nil,
        weekTimeMarker: CGFloat? = nil,
        sessionPaceStatus: PaceStatus? = nil,
        weekPaceStatus: PaceStatus? = nil,
        showPaceMarker: Bool = false
    ) -> NSImage {
        let size: CGFloat = 24
        let image = NSImage(size: NSSize(width: size, height: size))

        image.lockFocus()
        defer { image.unlockFocus() }

        let center = NSPoint(x: size / 2, y: size / 2)

        // Use isDarkMode to determine correct foreground color for menu bar
        let foregroundColor = menuBarForegroundColor(isDarkMode: isDarkMode)
        let textColor: NSColor = foregroundColor
        let sessionColor: NSColor = getColor(for: sessionStatus, monochromeMode: monochromeMode, useSystemColor: useSystemColor, isDarkMode: isDarkMode)
        let weekColor: NSColor = getColor(for: weekStatus, monochromeMode: monochromeMode, useSystemColor: useSystemColor, isDarkMode: isDarkMode)
        let backgroundColor: NSColor = foregroundColor.withAlphaComponent(0.15)

        // Outer ring (Session) - larger radius, thicker stroke - Session is primary/more important
        let outerRadius: CGFloat = (size - 4) / 2  // 10pt radius
        let outerStrokeWidth: CGFloat = 3.0

        // Background ring for outer
        let outerBgPath = NSBezierPath()
        outerBgPath.appendArc(
            withCenter: center,
            radius: outerRadius,
            startAngle: 0,
            endAngle: 360,
            clockwise: false
        )
        backgroundColor.setStroke()
        outerBgPath.lineWidth = outerStrokeWidth
        outerBgPath.stroke()

        // Session progress ring (outer - primary metric, clockwise from 12 o'clock)
        if sessionPercentage > 0 {
            let sessionEndAngle = 90 - (360 * CGFloat(sessionPercentage / 100.0))
            let outerProgressPath = NSBezierPath()
            outerProgressPath.appendArc(
                withCenter: center,
                radius: outerRadius,
                startAngle: 90,
                endAngle: sessionEndAngle,
                clockwise: true
            )
            sessionColor.setStroke()
            outerProgressPath.lineWidth = outerStrokeWidth
            outerProgressPath.lineCapStyle = .round
            outerProgressPath.stroke()
        }

        // Session time marker on outer ring
        if let fraction = sessionTimeMarker {
            let tickAngle = (90 - 360 * fraction) * .pi / 180
            let innerR = outerRadius - 2.0
            let outerR = outerRadius + 2.0
            let tickPath = NSBezierPath()
            tickPath.move(to: NSPoint(x: center.x + innerR * cos(tickAngle), y: center.y + innerR * sin(tickAngle)))
            tickPath.line(to: NSPoint(x: center.x + outerR * cos(tickAngle), y: center.y + outerR * sin(tickAngle)))
            drawPaceMarkerTick(tickPath, paceStatus: sessionPaceStatus, showPaceMarker: showPaceMarker, isDarkMode: isDarkMode)
        }

        // Inner ring (Week) - smaller radius, thinner stroke - Week is secondary
        let innerRadius: CGFloat = outerRadius - 4.5  // 5.5pt radius
        let innerStrokeWidth: CGFloat = 2.0

        // Background ring for inner
        let innerBgPath = NSBezierPath()
        innerBgPath.appendArc(
            withCenter: center,
            radius: innerRadius,
            startAngle: 0,
            endAngle: 360,
            clockwise: false
        )
        backgroundColor.setStroke()
        innerBgPath.lineWidth = innerStrokeWidth
        innerBgPath.stroke()

        // Week progress ring (inner - secondary metric, clockwise from 12 o'clock)
        if weekPercentage > 0 {
            let weekEndAngle = 90 - (360 * CGFloat(weekPercentage / 100.0))
            let innerProgressPath = NSBezierPath()
            innerProgressPath.appendArc(
                withCenter: center,
                radius: innerRadius,
                startAngle: 90,
                endAngle: weekEndAngle,
                clockwise: true
            )
            weekColor.setStroke()
            innerProgressPath.lineWidth = innerStrokeWidth
            innerProgressPath.lineCapStyle = .round
            innerProgressPath.stroke()
        }

        // Week time marker on inner ring
        if let fraction = weekTimeMarker {
            let tickAngle = (90 - 360 * fraction) * .pi / 180
            let innerR = innerRadius - 2.0
            let outerR = innerRadius + 2.0
            let tickPath = NSBezierPath()
            tickPath.move(to: NSPoint(x: center.x + innerR * cos(tickAngle), y: center.y + innerR * sin(tickAngle)))
            tickPath.line(to: NSPoint(x: center.x + outerR * cos(tickAngle), y: center.y + outerR * sin(tickAngle)))
            drawPaceMarkerTick(tickPath, paceStatus: weekPaceStatus, showPaceMarker: showPaceMarker, isDarkMode: isDarkMode)
        }

        // Profile initial in center
        let initial = String(profileInitial.prefix(1)).uppercased()
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .bold),
            .foregroundColor: textColor
        ]
        let labelString = initial as NSString
        let labelSize = labelString.size(withAttributes: labelAttributes)
        let labelX = center.x - labelSize.width / 2
        let labelY = center.y - labelSize.height / 2
        labelString.draw(at: NSPoint(x: labelX, y: labelY), withAttributes: labelAttributes)

        return image
    }

    /// Creates a concentric icon with profile label below for multi-profile mode
    /// - Returns: NSImage with concentric circles and profile name label
    func createConcentricIconWithLabel(
        sessionPercentage: Double,
        weekPercentage: Double,
        sessionStatus: UsageStatusLevel,
        weekStatus: UsageStatusLevel,
        profileName: String,
        monochromeMode: Bool,
        isDarkMode: Bool,
        useSystemColor: Bool = false,
        sessionTimeMarker: CGFloat? = nil,
        weekTimeMarker: CGFloat? = nil,
        sessionPaceStatus: PaceStatus? = nil,
        weekPaceStatus: PaceStatus? = nil,
        showPaceMarker: Bool = false
    ) -> NSImage {
        let circleSize: CGFloat = 20
        let labelHeight: CGFloat = 10
        let spacing: CGFloat = 1
        let totalHeight = circleSize + spacing + labelHeight
        let labelWidth: CGFloat = max(circleSize, CGFloat(profileName.prefix(3).count) * 6 + 4)
        let totalWidth = max(circleSize, labelWidth)

        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight))

        image.lockFocus()
        defer { image.unlockFocus() }

        let circleCenter = NSPoint(x: totalWidth / 2, y: totalHeight - circleSize / 2)

        // Use isDarkMode to determine correct foreground color for menu bar
        let foregroundColor = menuBarForegroundColor(isDarkMode: isDarkMode)
        let textColor: NSColor = foregroundColor
        let sessionColor: NSColor = getColor(for: sessionStatus, monochromeMode: monochromeMode, useSystemColor: useSystemColor, isDarkMode: isDarkMode)
        let weekColor: NSColor = getColor(for: weekStatus, monochromeMode: monochromeMode, useSystemColor: useSystemColor, isDarkMode: isDarkMode)
        let backgroundColor: NSColor = foregroundColor.withAlphaComponent(0.15)

        // Outer ring (Session) - Session is primary/more important
        let outerRadius: CGFloat = (circleSize - 4) / 2
        let outerStrokeWidth: CGFloat = 2.5

        // Background ring for outer
        let outerBgPath = NSBezierPath()
        outerBgPath.appendArc(
            withCenter: circleCenter,
            radius: outerRadius,
            startAngle: 0,
            endAngle: 360,
            clockwise: false
        )
        backgroundColor.setStroke()
        outerBgPath.lineWidth = outerStrokeWidth
        outerBgPath.stroke()

        // Session progress ring (outer - primary metric, clockwise from 12 o'clock)
        if sessionPercentage > 0 {
            let sessionEndAngle = 90 - (360 * CGFloat(sessionPercentage / 100.0))
            let outerProgressPath = NSBezierPath()
            outerProgressPath.appendArc(
                withCenter: circleCenter,
                radius: outerRadius,
                startAngle: 90,
                endAngle: sessionEndAngle,
                clockwise: true
            )
            sessionColor.setStroke()
            outerProgressPath.lineWidth = outerStrokeWidth
            outerProgressPath.lineCapStyle = .round
            outerProgressPath.stroke()
        }

        // Session time marker on outer ring
        if let fraction = sessionTimeMarker {
            let tickAngle = (90 - 360 * fraction) * .pi / 180
            let innerR = outerRadius - 2.0
            let outerR = outerRadius + 2.0
            let tickPath = NSBezierPath()
            tickPath.move(to: NSPoint(x: circleCenter.x + innerR * cos(tickAngle), y: circleCenter.y + innerR * sin(tickAngle)))
            tickPath.line(to: NSPoint(x: circleCenter.x + outerR * cos(tickAngle), y: circleCenter.y + outerR * sin(tickAngle)))
            drawPaceMarkerTick(tickPath, paceStatus: sessionPaceStatus, showPaceMarker: showPaceMarker, isDarkMode: isDarkMode)
        }

        // Inner ring (Week) - Week is secondary
        let innerRadius: CGFloat = outerRadius - 3.5
        let innerStrokeWidth: CGFloat = 1.5

        // Background ring for inner
        let innerBgPath = NSBezierPath()
        innerBgPath.appendArc(
            withCenter: circleCenter,
            radius: innerRadius,
            startAngle: 0,
            endAngle: 360,
            clockwise: false
        )
        backgroundColor.setStroke()
        innerBgPath.lineWidth = innerStrokeWidth
        innerBgPath.stroke()

        // Week progress ring (inner - secondary metric, clockwise from 12 o'clock)
        if weekPercentage > 0 {
            let weekEndAngle = 90 - (360 * CGFloat(weekPercentage / 100.0))
            let innerProgressPath = NSBezierPath()
            innerProgressPath.appendArc(
                withCenter: circleCenter,
                radius: innerRadius,
                startAngle: 90,
                endAngle: weekEndAngle,
                clockwise: true
            )
            weekColor.setStroke()
            innerProgressPath.lineWidth = innerStrokeWidth
            innerProgressPath.lineCapStyle = .round
            innerProgressPath.stroke()
        }

        // Week time marker on inner ring
        if let fraction = weekTimeMarker {
            let tickAngle = (90 - 360 * fraction) * .pi / 180
            let innerR = innerRadius - 2.0
            let outerR = innerRadius + 2.0
            let tickPath = NSBezierPath()
            tickPath.move(to: NSPoint(x: circleCenter.x + innerR * cos(tickAngle), y: circleCenter.y + innerR * sin(tickAngle)))
            tickPath.line(to: NSPoint(x: circleCenter.x + outerR * cos(tickAngle), y: circleCenter.y + outerR * sin(tickAngle)))
            drawPaceMarkerTick(tickPath, paceStatus: weekPaceStatus, showPaceMarker: showPaceMarker, isDarkMode: isDarkMode)
        }

        // Profile label below the circle (first 3 characters)
        let label = String(profileName.prefix(3))
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .medium),
            .foregroundColor: textColor.withAlphaComponent(0.85)
        ]
        let labelString = label as NSString
        let labelSize = labelString.size(withAttributes: labelAttributes)
        let labelX = (totalWidth - labelSize.width) / 2
        let labelY: CGFloat = 0
        labelString.draw(at: NSPoint(x: labelX, y: labelY), withAttributes: labelAttributes)

        return image
    }

    // MARK: - Multi-Profile Progress Bar Style

    /// Creates a progress bar style icon for multi-profile mode
    func createMultiProfileProgressBar(
        sessionPercentage: Double,
        weekPercentage: Double?,
        sessionStatus: UsageStatusLevel,
        weekStatus: UsageStatusLevel,
        profileName: String?,
        monochromeMode: Bool,
        isDarkMode: Bool,
        useSystemColor: Bool = false,
        sessionTimeMarker: CGFloat? = nil,
        weekTimeMarker: CGFloat? = nil,
        sessionPaceStatus: PaceStatus? = nil,
        weekPaceStatus: PaceStatus? = nil,
        showPaceMarker: Bool = false
    ) -> NSImage {
        let barWidth: CGFloat = 24
        let barHeight: CGFloat = 4
        let spacing: CGFloat = 2
        let labelHeight: CGFloat = profileName != nil ? 10 : 0
        let hasWeek = weekPercentage != nil

        let totalHeight = barHeight + (hasWeek ? spacing + barHeight : 0) + (profileName != nil ? spacing + labelHeight : 0)
        let totalWidth = barWidth

        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight))

        image.lockFocus()
        defer { image.unlockFocus() }

        // Use isDarkMode to determine correct foreground color for menu bar
        let foregroundColor = menuBarForegroundColor(isDarkMode: isDarkMode)
        let sessionColor: NSColor = getColor(for: sessionStatus, monochromeMode: monochromeMode, useSystemColor: useSystemColor, isDarkMode: isDarkMode)
        let weekColor: NSColor = getColor(for: weekStatus, monochromeMode: monochromeMode, useSystemColor: useSystemColor, isDarkMode: isDarkMode)
        let backgroundColor: NSColor = foregroundColor.withAlphaComponent(0.2)

        var currentY = totalHeight

        // Session bar (top)
        currentY -= barHeight
        let sessionBgRect = NSRect(x: 0, y: currentY, width: barWidth, height: barHeight)
        backgroundColor.setFill()
        NSBezierPath(roundedRect: sessionBgRect, xRadius: 2, yRadius: 2).fill()

        let sessionFillWidth = barWidth * CGFloat(sessionPercentage / 100.0)
        let sessionFillRect = NSRect(x: 0, y: currentY, width: sessionFillWidth, height: barHeight)
        sessionColor.setFill()
        NSBezierPath(roundedRect: sessionFillRect, xRadius: 2, yRadius: 2).fill()

        // Session time marker tick
        if let fraction = sessionTimeMarker {
            let tickX = round(barWidth * fraction)
            let tickPath = NSBezierPath()
            tickPath.move(to: NSPoint(x: tickX, y: currentY))
            tickPath.line(to: NSPoint(x: tickX, y: currentY + barHeight))
            drawPaceMarkerTick(tickPath, paceStatus: sessionPaceStatus, showPaceMarker: showPaceMarker, isDarkMode: isDarkMode)
        }

        // Week bar (if shown)
        if let weekPct = weekPercentage {
            currentY -= (spacing + barHeight)
            let weekBgRect = NSRect(x: 0, y: currentY, width: barWidth, height: barHeight)
            backgroundColor.setFill()
            NSBezierPath(roundedRect: weekBgRect, xRadius: 2, yRadius: 2).fill()

            let weekFillWidth = barWidth * CGFloat(weekPct / 100.0)
            let weekFillRect = NSRect(x: 0, y: currentY, width: weekFillWidth, height: barHeight)
            weekColor.setFill()
            NSBezierPath(roundedRect: weekFillRect, xRadius: 2, yRadius: 2).fill()

            // Week time marker tick
            if let fraction = weekTimeMarker {
                let tickX = round(barWidth * fraction)
                let tickPath = NSBezierPath()
                tickPath.move(to: NSPoint(x: tickX, y: currentY))
                tickPath.line(to: NSPoint(x: tickX, y: currentY + barHeight))
                drawPaceMarkerTick(tickPath, paceStatus: weekPaceStatus, showPaceMarker: showPaceMarker, isDarkMode: isDarkMode)
            }
        }

        // Profile label (if shown)
        if let name = profileName {
            let label = String(name.prefix(3))
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8, weight: .medium),
                .foregroundColor: foregroundColor.withAlphaComponent(0.85)
            ]
            let labelString = label as NSString
            let labelSize = labelString.size(withAttributes: labelAttributes)
            let labelX = (totalWidth - labelSize.width) / 2
            labelString.draw(at: NSPoint(x: labelX, y: 0), withAttributes: labelAttributes)
        }

        return image
    }

    // MARK: - Multi-Profile Compact Dot Style

    /// Creates a minimal dot indicator for multi-profile mode
    func createCompactDot(
        percentage: Double,
        status: UsageStatusLevel,
        profileInitial: String?,
        monochromeMode: Bool,
        isDarkMode: Bool,
        useSystemColor: Bool = false,
        paceStatus: PaceStatus? = nil,
        showPaceMarker: Bool = false
    ) -> NSImage {
        let dotSize: CGFloat = 10
        let labelHeight: CGFloat = profileInitial != nil ? 10 : 0
        let spacing: CGFloat = profileInitial != nil ? 1 : 0
        let hasPaceDot = showPaceMarker && paceStatus != nil
        let paceDotExtra: CGFloat = hasPaceDot ? 6 : 0  // gap(2) + dot(4)

        let totalHeight = dotSize + spacing + labelHeight
        let totalWidth = max(dotSize + paceDotExtra, 16)

        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight))

        image.lockFocus()
        defer { image.unlockFocus() }

        // Use isDarkMode to determine correct foreground color for menu bar
        let foregroundColor = menuBarForegroundColor(isDarkMode: isDarkMode)
        let dotColor: NSColor = getColor(for: status, monochromeMode: monochromeMode, useSystemColor: useSystemColor, isDarkMode: isDarkMode)

        // Draw main status dot
        let mainDotX = (totalWidth - dotSize - paceDotExtra) / 2
        let dotRect = NSRect(
            x: mainDotX,
            y: totalHeight - dotSize,
            width: dotSize,
            height: dotSize
        )
        dotColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        // Pace dot next to main dot
        if showPaceMarker, let pace = paceStatus {
            let paceDotSize: CGFloat = 4.0
            let paceDotX = mainDotX + dotSize + 2
            let paceDotY = totalHeight - dotSize + (dotSize - paceDotSize) / 2
            let paceDotPath = NSBezierPath(ovalIn: NSRect(x: paceDotX, y: paceDotY, width: paceDotSize, height: paceDotSize))
            pace.color.setFill()
            paceDotPath.fill()
        }

        // Profile initial (if shown)
        if let initial = profileInitial {
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                .foregroundColor: foregroundColor.withAlphaComponent(0.85)
            ]
            let labelString = initial.uppercased() as NSString
            let labelSize = labelString.size(withAttributes: labelAttributes)
            let labelX = (totalWidth - labelSize.width) / 2
            labelString.draw(at: NSPoint(x: labelX, y: 0), withAttributes: labelAttributes)
        }

        return image
    }

    // MARK: - Default App Logo (for profiles without credentials)

    /// Creates a default app logo icon for the menu bar when no credentials are configured
    func createDefaultAppLogo(isDarkMode: Bool) -> NSImage {
        // Try to load the app logo from assets
        if let logo = NSImage(named: "HeaderLogo") {
            // Create a copy to avoid modifying the original
            let resizedLogo = NSImage(size: NSSize(width: 20, height: 20))
            resizedLogo.lockFocus()
            defer { resizedLogo.unlockFocus() }

            // Draw the logo centered
            logo.draw(in: NSRect(x: 0, y: 0, width: 20, height: 20),
                     from: NSRect.zero,
                     operation: .sourceOver,
                     fraction: 1.0)

            return resizedLogo
        }

        // Fallback: Create a simple circle icon if logo not found
        let size: CGFloat = 20
        let image = NSImage(size: NSSize(width: size, height: size))

        image.lockFocus()
        defer { image.unlockFocus() }

        // Use isDarkMode to determine correct foreground color for menu bar
        let color: NSColor = menuBarForegroundColor(isDarkMode: isDarkMode)

        // Draw a simple circle
        let circlePath = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: size - 4, height: size - 4))
        color.withAlphaComponent(0.7).setStroke()
        circlePath.lineWidth = 2.0
        circlePath.stroke()

        // Draw a small dot in the center
        let dotPath = NSBezierPath(ovalIn: NSRect(x: size/2 - 2, y: size/2 - 2, width: 4, height: 4))
        color.setFill()
        dotPath.fill()

        return image
    }

    // MARK: - Multi-Profile Percentage Style

    /// Creates a percentage text icon for multi-profile mode
    /// Format: "30 · 4" (session · week) with status colors, optional profile label below
    func createMultiProfilePercentage(
        sessionPercentage: Double,
        weekPercentage: Double?,
        sessionStatus: UsageStatusLevel,
        weekStatus: UsageStatusLevel,
        profileName: String?,
        monochromeMode: Bool,
        isDarkMode: Bool,
        useSystemColor: Bool = false,
        sessionPaceStatus: PaceStatus? = nil,
        weekPaceStatus: PaceStatus? = nil,
        showPaceMarker: Bool = false
    ) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        let foregroundColor = menuBarForegroundColor(isDarkMode: isDarkMode)
        let separatorColor = foregroundColor.withAlphaComponent(0.4)

        let sessionColor: NSColor = getColor(for: sessionStatus, monochromeMode: monochromeMode, useSystemColor: useSystemColor, isDarkMode: isDarkMode)
        let weekColor: NSColor = getColor(for: weekStatus, monochromeMode: monochromeMode, useSystemColor: useSystemColor, isDarkMode: isDarkMode)

        // Build the attributed string
        let attributed = NSMutableAttributedString()

        // Session number
        let sessionText = "\(Int(sessionPercentage))"
        attributed.append(NSAttributedString(string: sessionText, attributes: [
            .font: font,
            .foregroundColor: sessionColor
        ]))

        // Separator and week number (if shown)
        if let weekPct = weekPercentage {
            attributed.append(NSAttributedString(string: " · ", attributes: [
                .font: font,
                .foregroundColor: separatorColor
            ]))
            let weekText = "\(Int(weekPct))"
            attributed.append(NSAttributedString(string: weekText, attributes: [
                .font: font,
                .foregroundColor: weekColor
            ]))
        }

        let textSize = attributed.size()
        let hasPaceDot = showPaceMarker && sessionPaceStatus != nil
        let paceDotExtra: CGFloat = hasPaceDot ? 6 : 0  // gap(2) + dot(4)
        let labelHeight: CGFloat = profileName != nil ? 10 : 0
        let labelSpacing: CGFloat = profileName != nil ? 1 : 0
        let totalWidth = max(textSize.width + 2 + paceDotExtra, profileName != nil ? CGFloat(String(profileName!.prefix(3)).count) * 6 + 4 : 0)
        let totalHeight = textSize.height + labelSpacing + labelHeight

        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight))

        image.lockFocus()
        defer { image.unlockFocus() }

        // Draw percentage text at top, centered (shift left slightly if pace dot present)
        let textX = (totalWidth - textSize.width - paceDotExtra) / 2
        let textY = totalHeight - textSize.height
        attributed.draw(at: NSPoint(x: textX, y: textY))

        // Pace dot after the percentage text
        if showPaceMarker, let pace = sessionPaceStatus {
            let dotSize: CGFloat = 4.0
            let dotX = textX + textSize.width + 2
            let dotY = textY + (textSize.height - dotSize) / 2
            let dotPath = NSBezierPath(ovalIn: NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize))
            pace.color.setFill()
            dotPath.fill()
        }

        // Profile label below (if shown)
        if let name = profileName {
            let label = String(name.prefix(3))
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8, weight: .medium),
                .foregroundColor: foregroundColor.withAlphaComponent(0.85)
            ]
            let labelString = label as NSString
            let labelSize = labelString.size(withAttributes: labelAttributes)
            let labelX = (totalWidth - labelSize.width) / 2
            labelString.draw(at: NSPoint(x: labelX, y: 0), withAttributes: labelAttributes)
        }

        return image
    }

    // MARK: - Helper Methods

    /// Returns the appropriate foreground color for menu bar icons based on appearance
    /// This is needed because NSColor.labelColor doesn't resolve correctly in image drawing contexts
    private func menuBarForegroundColor(isDarkMode: Bool) -> NSColor {
        return isDarkMode ? .white : .black
    }

    private func getColorForStatusLevel(_ level: UsageStatusLevel) -> NSColor {
        switch level {
        case .safe:
            return NSColor.systemGreen
        case .moderate:
            return NSColor.systemOrange
        case .critical:
            return NSColor.systemRed
        }
    }

    /// Returns the appropriate color based on mode settings
    /// - Parameters:
    ///   - status: The usage status level
    ///   - monochromeMode: If true, return foreground color based on isDarkMode
    ///   - useSystemColor: If true, return foreground color (same as monochrome)
    ///   - isDarkMode: Whether the menu bar is in dark mode
    /// - Returns: The color to use for rendering
    private func getColor(for status: UsageStatusLevel, monochromeMode: Bool, useSystemColor: Bool, isDarkMode: Bool) -> NSColor {
        if monochromeMode || useSystemColor {
            return menuBarForegroundColor(isDarkMode: isDarkMode)
        } else {
            return getColorForStatusLevel(status)
        }
    }

    /// Draws a pace-colored tick mark. When showPaceMarker is on and pace data is available,
    /// the tick color reflects the 6-tier pace urgency (green→purple) regardless of color mode.
    /// Otherwise falls back to the menu bar foreground color (current upstream behavior).
    private func drawPaceMarkerTick(
        _ path: NSBezierPath,
        paceStatus: PaceStatus?,
        showPaceMarker: Bool,
        isDarkMode: Bool
    ) {
        let color: NSColor
        if showPaceMarker, let pace = paceStatus {
            color = pace.color
        } else {
            color = menuBarForegroundColor(isDarkMode: isDarkMode)
        }
        color.setStroke()
        path.lineWidth = 2.0
        path.lineCapStyle = .round
        path.stroke()
    }

}
