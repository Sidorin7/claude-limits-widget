import XCTest
@testable import ClaudeLimitsCore

final class ParsingTests: XCTestCase {
    func testDecodesFullResponse() throws {
        let json = """
        {"five_hour":{"utilization":42.0,"resets_at":"2026-10-27T20:00:00.123456+00:00"},
         "seven_day":{"utilization":18,"resets_at":"2026-10-30T10:00:00+00:00"},
         "seven_day_opus":null,
         "seven_day_sonnet":{"utilization":3.5,"resets_at":null},
         "extra_usage":{"is_enabled":false}}
        """.data(using: .utf8)!
        let r = try UsageResponse.decode(json)
        XCTAssertEqual(r.fiveHour?.utilization, 42)
        XCTAssertEqual(r.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_793_131_200))
        XCTAssertEqual(r.sevenDay?.utilization, 18)
        XCTAssertNil(r.sevenDayOpus)
        XCTAssertEqual(r.sevenDaySonnet?.utilization, 3.5)
        XCTAssertNil(r.sevenDaySonnet?.resetsAt)
    }

    func testToleratesMissingAndOddFields() throws {
        let r = try UsageResponse.decode(#"{"five_hour":{"utilization":"oops"}}"#.data(using: .utf8)!)
        XCTAssertNotNil(r.fiveHour)
        XCTAssertNil(r.fiveHour?.utilization)
        XCTAssertNil(r.sevenDay)
    }

    func testParsesDatesWithAndWithoutZone() {
        XCTAssertNotNil(parseISODate("2026-10-27T20:00:00Z"))
        XCTAssertNotNil(parseISODate("2026-10-27T20:00:00.5Z"))
        XCTAssertEqual(parseISODate("2026-10-27T20:00:00"), parseISODate("2026-10-27T20:00:00Z"))
        XCTAssertNil(parseISODate("not a date"))
    }

    func testParsesCredentials() {
        let json = #"{"claudeAiOauth":{"accessToken":"abc","refreshToken":"r","expiresAt":1793131200000}}"#
        let c = OAuthCredentials.parse(json.data(using: .utf8)!)
        XCTAssertEqual(c?.accessToken, "abc")
        XCTAssertEqual(c?.expiresAt, Date(timeIntervalSince1970: 1_793_131_200))
        XCTAssertNil(OAuthCredentials.parse(#"{"other":{}}"#.data(using: .utf8)!))
    }
}

final class FetchPolicyTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testMinimumGapBetweenRequests() {
        var p = FetchPolicy()
        XCTAssertTrue(p.canFetch(now: t0))
        p.recordAttempt(now: t0)
        p.recordSuccess(now: t0)
        XCTAssertFalse(p.canFetch(now: t0 + 59))
        XCTAssertTrue(p.canFetch(now: t0 + 60))
    }

    func testNextAllowedReportsWait() {
        var p = FetchPolicy()
        XCTAssertNil(p.nextAllowed(now: t0))
        p.recordAttempt(now: t0)
        XCTAssertEqual(p.nextAllowed(now: t0 + 10), t0 + 60)
        p.recordRateLimit(now: t0, retryAfter: 300)
        XCTAssertEqual(p.nextAllowed(now: t0 + 10), t0 + 300)
    }

    func testRateLimitBackoffDoublesUpToOneHour() {
        var p = FetchPolicy()
        p.recordRateLimit(now: t0, retryAfter: nil)
        XCTAssertEqual(p.blockedUntil, t0 + 15 * 60)
        XCTAssertFalse(p.canFetch(now: t0 + 15 * 60 - 1))
        XCTAssertTrue(p.canFetch(now: t0 + 15 * 60))
        p.recordRateLimit(now: t0, retryAfter: nil)
        XCTAssertEqual(p.blockedUntil, t0 + 30 * 60)
        p.recordRateLimit(now: t0, retryAfter: nil)
        XCTAssertEqual(p.blockedUntil, t0 + 60 * 60)
        p.recordRateLimit(now: t0, retryAfter: nil)
        XCTAssertEqual(p.blockedUntil, t0 + 60 * 60)
        p.recordSuccess(now: t0)
        XCTAssertNil(p.blockedUntil)
        XCTAssertEqual(p.rateLimitStrikes, 0)
    }

    func testRetryAfterHeaderWins() {
        var p = FetchPolicy()
        p.recordRateLimit(now: t0, retryAfter: 300)
        XCTAssertEqual(p.blockedUntil, t0 + 300)
    }

    func testNetworkBackoffCappedAt15Minutes() {
        var p = FetchPolicy()
        for _ in 0..<10 { p.recordNetworkError(now: t0) }
        XCTAssertEqual(p.blockedUntil, t0 + 15 * 60)
    }

    func testRejectedTokenIsNotRetried() {
        var p = FetchPolicy()
        p.recordAuthRejected(token: "old")
        XCTAssertTrue(p.isRejected(token: "old"))
        XCTAssertFalse(p.isRejected(token: "new"))
    }
}

final class ThresholdTests: XCTestCase {
    let reset = Date(timeIntervalSince1970: 2_000_000)

    func testEachThresholdFiresOnce() {
        var t = ThresholdTracker()
        XCTAssertNil(t.check(window: "w", utilization: 50, resetsAt: reset))
        XCTAssertEqual(t.check(window: "w", utilization: 81, resetsAt: reset), 80)
        XCTAssertNil(t.check(window: "w", utilization: 85, resetsAt: reset))
        XCTAssertEqual(t.check(window: "w", utilization: 96, resetsAt: reset), 95)
        XCTAssertNil(t.check(window: "w", utilization: 99, resetsAt: reset))
    }

    func testJumpStraightToHighestThreshold() {
        var t = ThresholdTracker()
        XCTAssertEqual(t.check(window: "w", utilization: 97, resetsAt: reset), 95)
        XCTAssertNil(t.check(window: "w", utilization: 97, resetsAt: reset))
    }

    func testNewWindowStartsOver() {
        var t = ThresholdTracker()
        XCTAssertEqual(t.check(window: "w", utilization: 90, resetsAt: reset), 80)
        // Small drift of the reset time = same window.
        XCTAssertNil(t.check(window: "w", utilization: 90, resetsAt: reset + 30))
        XCTAssertEqual(t.check(window: "w", utilization: 90, resetsAt: reset + 5 * 3600), 80)
    }

    func testLevels() {
        XCTAssertEqual(Level.of(nil), .normal)
        XCTAssertEqual(Level.of(79.9), .normal)
        XCTAssertEqual(Level.of(80), .warning)
        XCTAssertEqual(Level.of(95), .critical)
    }
}

final class FormattingTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_793_131_200)

    func testUntil() {
        XCTAssertEqual(Fmt.until(now + 30, now: now), "скоро")
        XCTAssertEqual(Fmt.until(now + 14 * 60, now: now), "через 14м")
        XCTAssertEqual(Fmt.until(now + 2 * 3600 + 14 * 60, now: now), "через 2ч 14м")
        XCTAssertEqual(Fmt.until(now + 3 * 86_400 + 4 * 3600, now: now), "через 3д 4ч")
    }

    func testAgo() {
        XCTAssertEqual(Fmt.ago(now - 10, now: now), "только что")
        XCTAssertEqual(Fmt.ago(now - 5 * 60, now: now), "5 мин назад")
        XCTAssertEqual(Fmt.ago(now - 2 * 3600, now: now), "2 ч назад")
    }

    func testPercent() {
        XCTAssertEqual(Fmt.percent(42.4), "42%")
        XCTAssertEqual(Fmt.percent(nil), "—")
    }

    func testDayTime() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let base = parseISODate("2026-10-27T12:00:00Z")!   // Tuesday
        XCTAssertEqual(Fmt.dayTime(parseISODate("2026-10-27T20:00:00Z")!, now: base, calendar: cal), "сегодня 20:00")
        XCTAssertEqual(Fmt.dayTime(parseISODate("2026-10-28T10:00:00Z")!, now: base, calendar: cal), "завтра 10:00")
        XCTAssertEqual(Fmt.dayTime(parseISODate("2026-10-29T10:00:00Z")!, now: base, calendar: cal), "чт 10:00")
    }
}

final class WidgetSnapshotTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_793_131_200)

    func testBuiltFromUsage() {
        let usage = UsageResponse(fiveHour: UsageWindow(utilization: 42, resetsAt: now + 3600),
                                  sevenDay: UsageWindow(utilization: 18, resetsAt: nil))
        let s = WidgetSnapshot(usage: usage, updatedAt: now, isStale: true)
        XCTAssertEqual(s, WidgetSnapshot(fiveHour: 42, sevenDay: 18, fiveHourResetsAt: now + 3600,
                                         updatedAt: now, isStale: true))
    }

    func testRoundTrip() throws {
        let s = WidgetSnapshot(fiveHour: 42, sevenDay: nil, fiveHourResetsAt: now, updatedAt: now, isStale: false)
        XCTAssertEqual(try WidgetSnapshot.decode(s.encoded()), s)
    }

    func testResetText() {
        XCTAssertEqual(WidgetSnapshot().resetText(now: now), "нажмите ↻")
        let s = WidgetSnapshot(fiveHourResetsAt: now + 2 * 3600 + 14 * 60, updatedAt: now)
        XCTAssertEqual(s.resetText(now: now), "сброс через 2ч 14м")
        XCTAssertEqual(s.resetText(now: now + 3 * 3600), "сессия сброшена")
    }

    func testCountdownDatesFollowMinuteBoundaries() {
        let s = WidgetSnapshot(fiveHourResetsAt: now + 150)   // 2.5 minutes left
        let dates = s.countdownDates(now: now)
        XCTAssertEqual(dates, [now, now + 31, now + 91, now + 150])
        // Text changes within the second before each entry, never earlier.
        for (a, b) in zip(dates, dates.dropFirst()) {
            XCTAssertEqual(s.resetText(now: a), s.resetText(now: b - 1))
            XCTAssertNotEqual(s.resetText(now: a), s.resetText(now: b))
        }
    }

    func testCountdownDatesWithoutResetOrCapped() {
        XCTAssertEqual(WidgetSnapshot().countdownDates(now: now), [now])
        let far = WidgetSnapshot(fiveHourResetsAt: now + 5 * 3600)
        XCTAssertEqual(far.countdownDates(now: now, limit: 10).count, 10)
    }
}
