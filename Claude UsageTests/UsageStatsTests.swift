import XCTest
@testable import Claude_Usage

final class UsageStatsTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-01-05 00:00 UTC
    private let day0 = 1_767_571_200

    private func sample(_ minutes: Int, s: Double, w: Double, sr: Int, wr: Int) -> UsageSample {
        UsageSample(t: day0 + minutes * 60, s: s, w: w, sr: sr, wr: wr)
    }

    private func stats(_ samples: [UsageSample], hours: Double = 24) -> UsageStats {
        let start = Date(timeIntervalSince1970: TimeInterval(day0))
        let end = start.addingTimeInterval(hours * 3600)
        return UsageStats(samples: samples, range: start...end, now: end, calendar: calendar)
    }

    func testUsageAddedWithinOneWindow() {
        let sr = day0 + 5 * 3600, wr = day0 + 7 * 86_400
        let result = stats([
            sample(60, s: 10, w: 2, sr: sr, wr: wr),
            sample(65, s: 25, w: 3, sr: sr, wr: wr),
            sample(70, s: 40, w: 5, sr: sr, wr: wr),
        ])
        // The very first reading ever doesn't count: its usage predates recording
        XCTAssertEqual(result.days.first?.sessionAdded ?? -1, 30, accuracy: 0.001)
        XCTAssertEqual(result.days.first?.weeklyAdded ?? -1, 3, accuracy: 0.001)
        XCTAssertEqual(result.windowCount, 1)
        XCTAssertEqual(result.averageWindowPeak ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(result.busiestHour, 1)
    }

    func testNewWindowCountsItsFirstReadingInFull() {
        let wr = day0 + 7 * 86_400
        let result = stats([
            sample(60, s: 50, w: 10, sr: day0 + 5 * 3600, wr: wr),
            sample(65, s: 60, w: 11, sr: day0 + 5 * 3600, wr: wr),
            // window reset at 05:00; next reading in the new window
            sample(310, s: 8, w: 12, sr: day0 + 10 * 3600, wr: wr),
        ])
        XCTAssertEqual(result.days.first?.sessionAdded ?? -1, 10 + 8, accuracy: 0.001)
        XCTAssertEqual(result.windowCount, 2)
    }

    func testDecreasesWithinAWindowAreIgnored() {
        let sr = day0 + 5 * 3600, wr = day0 + 7 * 86_400
        let result = stats([
            sample(60, s: 20, w: 5, sr: sr, wr: wr),
            sample(65, s: 19, w: 4.9, sr: sr, wr: wr),
            sample(70, s: 21, w: 5.2, sr: sr, wr: wr),
        ])
        XCTAssertEqual(result.days.first?.sessionAdded ?? -1, 2, accuracy: 0.001)
        XCTAssertEqual(result.days.first?.weeklyAdded ?? -1, 0.3, accuracy: 0.001)
    }

    func testGapsAndResetsBreakTheChartLine() {
        let sr1 = day0 + 5 * 3600, sr2 = day0 + 10 * 3600, wr = day0 + 7 * 86_400
        let result = stats([
            sample(60, s: 10, w: 1, sr: sr1, wr: wr),
            sample(65, s: 12, w: 1, sr: sr1, wr: wr),
            sample(120, s: 20, w: 2, sr: sr1, wr: wr),   // 55 min gap
            sample(310, s: 1, w: 2, sr: sr2, wr: wr),    // window reset (and a gap)
        ])
        XCTAssertEqual(result.sessionSeries.map(\.segment), [0, 0, 1, 2])
        XCTAssertEqual(result.weeklySeries.map(\.segment), [0, 0, 1, 2])
    }

    func testLimitHitsCountWindowsThatReached100() {
        let wr = day0 + 7 * 86_400
        let result = stats([
            sample(60, s: 90, w: 10, sr: day0 + 5 * 3600, wr: wr),
            sample(65, s: 100, w: 11, sr: day0 + 5 * 3600, wr: wr),
            sample(310, s: 30, w: 12, sr: day0 + 10 * 3600, wr: wr),
        ])
        XCTAssertEqual(result.limitHits, 1)
        XCTAssertEqual(result.days.first?.limitHits, 1)
    }

    func testTooFewSamples() {
        let result = stats([])
        XCTAssertEqual(result.sampleCount, 0)
        XCTAssertNil(result.averageSession)
        XCTAssertNil(result.weeklyPerDay)
        XCTAssertTrue(result.days.isEmpty)
    }
}
