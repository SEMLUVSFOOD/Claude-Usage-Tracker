import XCTest
@testable import Claude_Usage

final class UsageActivityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_767_600_000)

    private func usage(_ s: Double, _ w: Double, at date: Date, sessionReset: TimeInterval = 3 * 3600,
                       groups: [QuotaGroup]? = nil) -> ClaudeUsage {
        var u = ClaudeUsage.empty
        u.sessionPercentage = s
        u.sessionResetTime = now.addingTimeInterval(sessionReset)
        u.weeklyPercentage = w
        u.weeklyResetTime = now.addingTimeInterval(3 * 86_400)
        u.lastUpdated = date
        u.quotaGroups = groups
        return u
    }

    func testRiseInSessionOrWeeklyCounts() {
        let old = usage(10, 20, at: now.addingTimeInterval(-60))
        XCTAssertTrue(ClaudeCodeActivityMonitor.usageIncreased(from: old, to: usage(11, 20, at: now)))
        XCTAssertTrue(ClaudeCodeActivityMonitor.usageIncreased(from: old, to: usage(10, 21, at: now)))
        XCTAssertFalse(ClaudeCodeActivityMonitor.usageIncreased(from: old, to: usage(10, 20, at: now)))
        XCTAssertFalse(ClaudeCodeActivityMonitor.usageIncreased(from: old, to: usage(9, 20, at: now)))
    }

    func testStaleOrCachedReadingsDontCount() {
        // Saved before the app started: a jump since then isn't live activity
        XCTAssertFalse(ClaudeCodeActivityMonitor.usageIncreased(
            from: usage(10, 20, at: now.addingTimeInterval(-3600)), to: usage(40, 30, at: now)))
        // Cached reading with the same timestamp
        XCTAssertFalse(ClaudeCodeActivityMonitor.usageIncreased(
            from: usage(10, 20, at: now), to: usage(12, 20, at: now)))
    }

    func testNewWindowCountsFromZero() {
        // Old window reset 30s ago; first use of the new window
        let old = usage(80, 20, at: now.addingTimeInterval(-60), sessionReset: -30)
        XCTAssertTrue(ClaudeCodeActivityMonitor.usageIncreased(from: old, to: usage(2, 20, at: now, sessionReset: 5 * 3600)))
    }

    func testRiseInANonLimitingGroupCounts() {
        let before = [QuotaGroup(name: "Gemini Models", weeklyPercentage: 30), QuotaGroup(name: "Claude and GPT models", weeklyPercentage: 5)]
        let after = [QuotaGroup(name: "Gemini Models", weeklyPercentage: 30), QuotaGroup(name: "Claude and GPT models", weeklyPercentage: 7)]
        XCTAssertTrue(ClaudeCodeActivityMonitor.usageIncreased(
            from: usage(0, 30, at: now.addingTimeInterval(-60), groups: before), to: usage(0, 30, at: now, groups: after)))
    }
}
