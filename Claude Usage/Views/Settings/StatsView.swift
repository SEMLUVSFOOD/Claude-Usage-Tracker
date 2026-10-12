//
//  StatsView.swift
//  Claude Usage
//
//  Settings → Stats: usage history per account — headline numbers, session and
//  weekly charts, use per day and per hour, and a daily table.
//

import SwiftUI
import Charts

struct StatsView: View {
    enum TimeRange: String, CaseIterable, Identifiable {
        case day = "24h", week = "7d", month = "30d", quarter = "90d"
        var id: String { rawValue }
        var interval: TimeInterval {
            switch self {
            case .day: return 86_400
            case .week: return 7 * 86_400
            case .month: return 30 * 86_400
            case .quarter: return 90 * 86_400
            }
        }
    }

    @StateObject private var profileManager = ProfileManager.shared
    @ObservedObject private var history = UsageHistoryStore.shared
    @State private var selectedProfileId: UUID?
    @State private var timeRange: TimeRange = .week

    private var profile: Profile? {
        selectedProfileId.flatMap { id in profileManager.profiles.first { $0.id == id } }
            ?? profileManager.menuBarProfile
            ?? profileManager.profiles.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "Stats",
                    subtitle: "Usage history recorded on this Mac while Claude Usage runs."
                )

                // One filter row scopes everything below
                HStack {
                    Picker("Account", selection: Binding(
                        get: { profile?.id },
                        set: { selectedProfileId = $0 }
                    )) {
                        ForEach(profileManager.profiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                    .frame(maxWidth: 220)

                    Spacer()

                    Picker("Range", selection: $timeRange) {
                        ForEach(TimeRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }

                if let profile {
                    content(for: profile)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func content(for profile: Profile) -> some View {
        let now = Date()
        let samples = history.samples[profile.id] ?? []
        let stats = UsageStats(samples: samples, range: now.addingTimeInterval(-timeRange.interval)...now, now: now)

        if stats.sampleCount < 2 {
            emptyState(firstSample: samples.first?.date)
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatTile(title: "Average session", value: percent(stats.averageSession), caption: "time-weighted")
                StatTile(title: "Average window peak", value: percent(stats.averageWindowPeak),
                         caption: "\(stats.windowCount) window\(stats.windowCount == 1 ? "" : "s") used")
                StatTile(title: "Limit hits", value: "\(stats.limitHits)", caption: "windows that reached 100%")
                StatTile(title: "Weekly use per day", value: percent(stats.weeklyPerDay), caption: "of the weekly limit")
                StatTile(title: "Weekly at reset", value: percent(stats.projectedWeekly), caption: "projected at current pace")
                StatTile(title: "Busiest hour", value: stats.busiestHour.map(hourLabel) ?? "–", caption: "most session use")
            }

            ChartCard(title: "Session usage", subtitle: "5-hour window, % used") {
                UsageLineChart(points: stats.sessionSeries, range: timeRange)
            }

            ChartCard(title: "Weekly usage", subtitle: "% of the weekly limit used") {
                UsageLineChart(points: stats.weeklySeries, range: timeRange)
            }

            if stats.days.count > 1 {
                ChartCard(title: "Weekly limit used per day", subtitle: "percentage points of the weekly limit") {
                    DailyBarChart(days: stats.days)
                }
            }

            ChartCard(title: "Session use by hour of day", subtitle: "average percentage points per day") {
                HourlyBarChart(hours: stats.hours)
            }

            DailyTable(days: stats.days)
        }
    }

    private func emptyState(firstSample: Date?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Collecting data…")
                .font(.system(size: 13, weight: .semibold))
            Text(firstSample.map { "History started \($0.formatted(date: .abbreviated, time: .shortened)). Stats appear once there are a few readings in this range." }
                 ?? "Stats appear here as Claude Usage refreshes this account (every minute while it runs).")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignTokens.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.cardBackground)
        .cornerRadius(DesignTokens.Radius.card)
    }

    private func percent(_ value: Double?) -> String {
        value.map { String(format: $0 >= 10 ? "%.0f%%" : "%.1f%%", $0) } ?? "–"
    }
}

/// "14:00" or "2 PM", following the system clock setting
private func hourLabel(_ hour: Int) -> String {
    if Date.systemUses24HourTime { return String(format: "%02d:00", hour) }
    let h = hour % 12 == 0 ? 12 : hour % 12
    return "\(h) \(hour < 12 ? "AM" : "PM")"
}

// MARK: - Pieces

/// The one series color: blue, a step lighter in dark mode (validated for
/// contrast against both surfaces).
private let seriesColor = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 0x39 / 255, green: 0x87 / 255, blue: 0xE5 / 255, alpha: 1)
        : NSColor(red: 0x2A / 255, green: 0x78 / 255, blue: 0xD6 / 255, alpha: 1)
})

private struct StatTile: View {
    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)
            Text(caption)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(DesignTokens.Colors.cardBackground)
        .cornerRadius(DesignTokens.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .strokeBorder(DesignTokens.Colors.cardBorder, lineWidth: 1)
        )
    }
}

private struct ChartCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            content
                .frame(height: 170)
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

/// Percentage over time; hovering shows a crosshair with the nearest reading.
private struct UsageLineChart: View {
    let points: [UsageStats.Point]
    let range: StatsView.TimeRange
    @State private var hoverDate: Date?

    private var hovered: UsageStats.Point? {
        guard let hoverDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(hoverDate)) < abs($1.date.timeIntervalSince(hoverDate)) }
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("Used", point.value),
                    series: .value("Segment", point.segment)
                )
                .foregroundStyle(seriesColor.opacity(0.12))
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Used", point.value),
                    series: .value("Segment", point.segment)
                )
                .foregroundStyle(seriesColor)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let hovered {
                RuleMark(x: .value("Time", hovered.date))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Time", hovered.date), y: .value("Used", hovered.value))
                    .foregroundStyle(seriesColor)
                    .symbolSize(64)
                    .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        Tooltip(title: hovered.date.formatted(date: range == .day ? .omitted : .abbreviated, time: .shortened),
                                value: String(format: "%.0f%%", hovered.value))
                    }
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel { if let v = value.as(Int.self) { Text("\(v)%") } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel(format: range == .day ? .dateTime.hour() : .dateTime.month(.abbreviated).day())
            }
        }
        .chartXSelection(value: $hoverDate)
    }
}

private struct DailyBarChart: View {
    let days: [UsageStats.Day]
    @State private var hoverDate: Date?

    private var hovered: UsageStats.Day? {
        guard let hoverDate else { return nil }
        let day = Calendar.current.startOfDay(for: hoverDate)
        return days.first { $0.day == day }
    }

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(
                    x: .value("Day", day.day, unit: .day),
                    y: .value("Weekly % used", day.weeklyAdded)
                )
                .foregroundStyle(seriesColor.opacity(hovered == nil || hovered?.day == day.day ? 1 : 0.45))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
            }
            if let hovered {
                RuleMark(x: .value("Day", hovered.day, unit: .day))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        Tooltip(title: hovered.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                value: String(format: "%.1f%% of weekly", hovered.weeklyAdded))
                    }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(v))%") } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 7)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
            }
        }
        .chartXSelection(value: $hoverDate)
    }
}

private struct HourlyBarChart: View {
    let hours: [UsageStats.Hour]
    @State private var hoverHour: Int?

    var body: some View {
        Chart {
            ForEach(hours) { hour in
                BarMark(
                    x: .value("Hour", hour.hour),
                    y: .value("Session % used", hour.averageSessionAdded),
                    width: .fixed(12)
                )
                .foregroundStyle(seriesColor.opacity(hoverHour == nil || hoverHour == hour.hour ? 1 : 0.45))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
            }
            if let hoverHour, let hour = hours.first(where: { $0.hour == hoverHour }) {
                RuleMark(x: .value("Hour", hour.hour))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        Tooltip(title: hourLabel(hour.hour), value: String(format: "%.1f%% per day", hour.averageSessionAdded))
                    }
            }
        }
        .chartXScale(domain: -1...24)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18]) { value in
                AxisValueLabel(anchor: .top) { if let h = value.as(Int.self) { Text(hourLabel(h)) } }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel { if let v = value.as(Double.self) { Text(String(format: "%.0f%%", v)) } }
            }
        }
        .chartXSelection(value: Binding(
            get: { hoverHour },
            set: { hoverHour = $0.map { min(max($0, 0), 23) } }
        ))
    }
}

private struct Tooltip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)
            Text(title)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
    }
}

/// The table twin of the charts: every daily value readable without hovering.
private struct DailyTable: View {
    let days: [UsageStats.Day]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup("Daily breakdown", isExpanded: $expanded) {
            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 5) {
                GridRow {
                    Text("Day").gridColumnAlignment(.leading)
                    Text("Weekly used")
                    Text("Session used")
                    Text("Peak session")
                    Text("Windows")
                    Text("Limit hits")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                Divider()
                ForEach(days.reversed()) { day in
                    GridRow {
                        Text(day.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        Text(String(format: "%.1f%%", day.weeklyAdded))
                        Text(String(format: "%.0f%%", day.sessionAdded))
                        Text(String(format: "%.0f%%", day.peakSession))
                        Text("\(day.windows)")
                        Text("\(day.limitHits)")
                    }
                    .font(.system(size: 11).monospacedDigit())
                }
            }
            .padding(.top, 6)
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(DesignTokens.Spacing.medium)
        .background(DesignTokens.Colors.cardBackground)
        .cornerRadius(DesignTokens.Radius.card)
    }
}
