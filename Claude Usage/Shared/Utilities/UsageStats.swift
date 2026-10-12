//
//  UsageStats.swift
//  Claude Usage
//
//  Everything the Stats page shows, derived from recorded UsageSamples.
//
//  "Usage added" between two consecutive readings is the increase within the
//  same window; when a window resets, the new window's first reading counts in
//  full (windows start at 0%). Sums of usage added give per-day and per-hour use.
//

import Foundation

struct UsageStats {
    struct Point: Identifiable {
        let date: Date
        let value: Double
        /// Lines break between segments (app not running, or window reset)
        let segment: Int
        var id: Date { date }
    }

    struct Day: Identifiable {
        let day: Date
        /// Weekly-limit percentage points used that day
        let weeklyAdded: Double
        /// Session percentage points used that day (summed over windows)
        let sessionAdded: Double
        let peakSession: Double
        /// 5-hour windows that started being used that day
        let windows: Int
        /// Windows that reached the limit
        let limitHits: Int
        var id: Date { day }
    }

    struct Hour: Identifiable {
        let hour: Int
        /// Average session percentage points used in this hour, per day
        let averageSessionAdded: Double
        var id: Int { hour }
    }

    let sessionSeries: [Point]
    let weeklySeries: [Point]
    let days: [Day]
    let hours: [Hour]
    let sampleCount: Int
    /// Time-weighted average session usage
    let averageSession: Double?
    /// Average peak of the 5-hour windows that were used
    let averageWindowPeak: Double?
    let windowCount: Int
    let limitHits: Int
    /// Average weekly-limit points used per day with data
    let weeklyPerDay: Double?
    /// Weekly usage at reset if the current pace continues
    let projectedWeekly: Double?
    let busiestHour: Int?

    /// A gap longer than this between readings breaks the chart line
    private static let segmentGap = 20 * 60
    /// A reading stands for at most this long in time-weighted averages
    private static let maxSampleWeight = 15 * 60

    init(samples allSamples: [UsageSample], range: ClosedRange<Date>, now: Date = Date(), calendar: Calendar = .current) {
        let all = allSamples.sorted { $0.t < $1.t }
        let lower = Int(range.lowerBound.timeIntervalSince1970)
        let upper = Int(range.upperBound.timeIntervalSince1970)
        let samples = all.filter { $0.t >= lower && $0.t <= upper }
        sampleCount = samples.count

        // Chart series, broken into segments at gaps and window resets
        var sessionPoints: [Point] = []
        var weeklyPoints: [Point] = []
        var sessionSegment = 0
        var weeklySegment = 0
        for (index, sample) in samples.enumerated() {
            if index > 0 {
                let previous = samples[index - 1]
                let gap = sample.t - previous.t > Self.segmentGap
                if gap || sample.sr != previous.sr { sessionSegment += 1 }
                if gap || sample.wr != previous.wr { weeklySegment += 1 }
            }
            sessionPoints.append(Point(date: sample.date, value: sample.s, segment: sessionSegment))
            weeklyPoints.append(Point(date: sample.date, value: sample.w, segment: weeklySegment))
        }
        sessionSeries = sessionPoints
        weeklySeries = weeklyPoints

        // Time-weighted average session usage
        var weightedSum = 0.0
        var totalWeight = 0.0
        for (index, sample) in samples.enumerated() {
            let next = index + 1 < samples.count ? samples[index + 1].t : min(sample.t + 300, upper)
            let weight = Double(max(0, min(next - sample.t, Self.maxSampleWeight)))
            weightedSum += sample.s * weight
            totalWeight += weight
        }
        averageSession = totalWeight > 0 ? weightedSum / totalWeight : nil

        // 5-hour windows: peak per window, attributed to the day of its first reading
        var windowPeaks: [Int: (peak: Double, firstDate: Date)] = [:]
        for sample in samples {
            if let existing = windowPeaks[sample.sr] {
                windowPeaks[sample.sr] = (max(existing.peak, sample.s), existing.firstDate)
            } else {
                windowPeaks[sample.sr] = (sample.s, sample.date)
            }
        }
        let usedWindows = windowPeaks.values.filter { $0.peak > 0 }
        windowCount = usedWindows.count
        limitHits = usedWindows.filter { $0.peak >= 99.5 }.count
        averageWindowPeak = usedWindows.isEmpty ? nil : usedWindows.map(\.peak).reduce(0, +) / Double(usedWindows.count)

        // Usage added between consecutive readings (using the reading just before
        // the range too, so the first in-range reading counts correctly)
        var weeklyByDay: [Date: Double] = [:]
        var sessionByDay: [Date: Double] = [:]
        var sessionByHour = [Double](repeating: 0, count: 24)
        for index in all.indices where all[index].t >= lower && all[index].t <= upper {
            let sample = all[index]
            let sessionAdded: Double
            let weeklyAdded: Double
            if index > 0 {
                let previous = all[index - 1]
                sessionAdded = sample.sr == previous.sr ? max(0, sample.s - previous.s) : sample.s
                weeklyAdded = sample.wr == previous.wr ? max(0, sample.w - previous.w) : sample.w
            } else {
                // Very first reading ever: its earlier usage happened before recording began
                sessionAdded = 0
                weeklyAdded = 0
            }
            let day = calendar.startOfDay(for: sample.date)
            weeklyByDay[day, default: 0] += weeklyAdded
            sessionByDay[day, default: 0] += sessionAdded
            sessionByHour[calendar.component(.hour, from: sample.date)] += sessionAdded
        }

        // One row per calendar day from the first reading to the end of the range
        var dayRows: [Day] = []
        if let first = samples.first {
            var day = calendar.startOfDay(for: first.date)
            let lastDay = calendar.startOfDay(for: min(range.upperBound, now))
            while day <= lastDay {
                let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
                let daySamples = samples.filter { $0.date >= day && $0.date < nextDay }
                let dayWindows = usedWindows.filter { $0.firstDate >= day && $0.firstDate < nextDay }
                dayRows.append(Day(
                    day: day,
                    weeklyAdded: weeklyByDay[day] ?? 0,
                    sessionAdded: sessionByDay[day] ?? 0,
                    peakSession: daySamples.map(\.s).max() ?? 0,
                    windows: dayWindows.count,
                    limitHits: dayWindows.filter { $0.peak >= 99.5 }.count
                ))
                day = nextDay
            }
        }
        days = dayRows

        // Averages per day over the time actually covered (a partial first day
        // would otherwise drag them down)
        let coveredSeconds = samples.first.map { Double(min(upper, Int(now.timeIntervalSince1970)) - $0.t) } ?? 0
        let dayCount = max(coveredSeconds / 86_400, 1)
        hours = (0..<24).map { Hour(hour: $0, averageSessionAdded: sessionByHour[$0] / dayCount) }
        let totalSession = sessionByHour.reduce(0, +)
        busiestHour = totalSession > 0 ? hours.max { $0.averageSessionAdded < $1.averageSessionAdded }?.hour : nil
        weeklyPerDay = dayRows.isEmpty ? nil : weeklyByDay.values.reduce(0, +) / dayCount

        // Projection from the latest reading in the current week
        if let latest = all.last {
            let weekEnd = Date(timeIntervalSince1970: TimeInterval(latest.wr))
            let elapsed = 1 - weekEnd.timeIntervalSince(now) / Constants.weeklyWindow
            projectedWeekly = weekEnd > now && elapsed >= 0.1 ? min(latest.w / elapsed, 999) : nil
        } else {
            projectedWeekly = nil
        }
    }
}
