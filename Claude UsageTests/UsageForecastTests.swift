import XCTest
@testable import Claude_Usage

final class UsageForecastTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_767_600_000)
    private let fiveHours: TimeInterval = 5 * 3600

    func testProjectsUsageAtReset() {
        // 2h into a 5h window at 20% → 10%/h → 50% at reset
        let forecast = UsageForecast.make(usedPercentage: 20, resetTime: now.addingTimeInterval(3 * 3600),
                                          windowDuration: fiveHours, now: now)
        guard case .endsAt(let percent) = forecast else { return XCTFail("expected endsAt, got \(String(describing: forecast))") }
        XCTAssertEqual(percent, 50, accuracy: 0.001)
    }

    func testRunsOutBeforeReset() {
        // 1h in at 40% → 40%/h → full 1.5h from now, reset is 4h away
        let forecast = UsageForecast.make(usedPercentage: 40, resetTime: now.addingTimeInterval(4 * 3600),
                                          windowDuration: fiveHours, now: now)
        guard case .runsOut(let date) = forecast else { return XCTFail("expected runsOut") }
        XCTAssertEqual(date.timeIntervalSince(now), 1.5 * 3600, accuracy: 1)
    }

    func testNoForecastWithoutSignal() {
        let reset = now.addingTimeInterval(3 * 3600)
        XCTAssertNil(UsageForecast.make(usedPercentage: 0, resetTime: reset, windowDuration: fiveHours, now: now))
        XCTAssertNil(UsageForecast.make(usedPercentage: 100, resetTime: reset, windowDuration: fiveHours, now: now))
        XCTAssertNil(UsageForecast.make(usedPercentage: 30, resetTime: nil, windowDuration: fiveHours, now: now))
        // Reset already passed
        XCTAssertNil(UsageForecast.make(usedPercentage: 30, resetTime: now.addingTimeInterval(-60), windowDuration: fiveHours, now: now))
        // Only 10 minutes into the window: too early
        XCTAssertNil(UsageForecast.make(usedPercentage: 30, resetTime: now.addingTimeInterval(fiveHours - 600),
                                        windowDuration: fiveHours, now: now))
    }

    func testWeeklyNeedsFivePercentOfTheWeek() {
        let week: TimeInterval = 7 * 86_400
        // 6 hours in (< 8.4h = 5%): no forecast yet
        XCTAssertNil(UsageForecast.make(usedPercentage: 5, resetTime: now.addingTimeInterval(week - 6 * 3600),
                                        windowDuration: week, now: now))
        // 2 days in at 20% → ~70% at reset
        let forecast = UsageForecast.make(usedPercentage: 20, resetTime: now.addingTimeInterval(5 * 86_400),
                                          windowDuration: week, now: now)
        guard case .endsAt(let percent) = forecast else { return XCTFail() }
        XCTAssertEqual(percent, 70, accuracy: 0.001)
    }

    func testText() {
        XCTAssertEqual(UsageForecast.endsAt(percent: 61.6).text(now: now), "At this pace: ~62% at reset")
        XCTAssertTrue(UsageForecast.runsOut(at: now.addingTimeInterval(60)).text(now: now).hasPrefix("At this pace: full"))
    }
}
