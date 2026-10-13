//
//  UsageForecast.swift
//  Claude Usage
//
//  "At this pace" projection for a usage window: extends the average rate so
//  far in the window (used % ÷ time elapsed) to the window's reset.
//

import Foundation

enum UsageForecast: Equatable {
    /// The limit is reached before the window resets
    case runsOut(at: Date)
    /// The window resets first, at roughly this usage
    case endsAt(percent: Double)

    /// Nil when there isn't enough signal yet: nothing used, already at the
    /// limit, or too early in the window for the rate to mean anything.
    static func make(usedPercentage used: Double, resetTime: Date?, windowDuration: TimeInterval, now: Date = Date()) -> UsageForecast? {
        guard let resetTime, resetTime > now, used > 0, used < 100 else { return nil }
        let remaining = resetTime.timeIntervalSince(now)
        let elapsed = min(windowDuration - remaining, windowDuration)
        // At least 15 minutes and 5% of the window, so a single burst right
        // after a reset doesn't project a wildly early "full" time
        guard elapsed >= max(15 * 60, windowDuration * 0.05) else { return nil }

        let rate = used / elapsed  // percentage points per second
        let projected = used + rate * remaining
        if projected >= 100 {
            return .runsOut(at: now.addingTimeInterval((100 - used) / rate))
        }
        return .endsAt(percent: projected)
    }

    /// e.g. "At this pace: full around 16:40" / "…~62% at reset"
    func text(now: Date = Date(), calendar: Calendar = .current) -> String {
        switch self {
        case .runsOut(let date):
            let formatter = DateFormatter()
            formatter.dateFormat = Date.systemUses24HourTime ? "HH:mm" : "h:mma"
            let time = formatter.string(from: date)
            if calendar.isDate(date, inSameDayAs: now) {
                return "At this pace: full around \(time)"
            } else if calendar.isDateInTomorrow(date) {
                return "At this pace: full tomorrow around \(time)"
            }
            formatter.dateFormat = "EEE"
            return "At this pace: full \(formatter.string(from: date)) around \(time)"
        case .endsAt(let percent):
            return "At this pace: ~\(Int(percent.rounded()))% at reset"
        }
    }

    var runsOut: Bool {
        if case .runsOut = self { return true }
        return false
    }
}
