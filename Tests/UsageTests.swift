import XCTest
@testable import CodexMacCore

final class UsageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1000)
    func snapshot(_ used: Int, at time: Double, reset: Double, owner: String = "A") -> Snapshot {
        Snapshot(owner: owner, date: Date(timeIntervalSince1970: time),
                 session: Window(usedPercent: used, windowDurationMins: 300, resetsAt: reset), week: nil)
    }
    func decode(_ json: String) throws -> Snapshot {
        try JSONDecoder().decode(LimitResponse.self, from: Data(json.utf8)).snapshot(owner: "A", at: now)
    }
    func testMatchesExplicitDurationsAndBucket() throws {
        let s = try decode(#"{"rateLimitsByLimitId":{"codex":{"primary":{"windowDurationMins":10080,"usedPercent":75},"secondary":{"windowDurationMins":300,"usedPercent":7}},"other":{"primary":{"usedPercent":76,"windowDurationMins":300}}}}"#)
        XCTAssertEqual(s.week?.remaining, 25); XCTAssertEqual(s.session?.remaining, 93)
    }
    func testUnknownWindowAndBucketAreUnavailable() throws {
        XCTAssertFalse(try decode(#"{"rateLimits":{"primary":{"windowDurationMins":15,"usedPercent":20}}}"#).hasData)
        XCTAssertFalse(try decode(#"{"rateLimits":{"limitId":"other","primary":{"windowDurationMins":300,"usedPercent":20}}}"#).hasData)
        XCTAssertFalse(try decode(#"{"rateLimitsByLimitId":{"other":{"primary":{"windowDurationMins":300,"usedPercent":0}}}}"#).hasData)
    }
    func testLegacyPartialAndInvalidPercent() throws {
        let s = try decode(#"{"rateLimits":{"primary":{"windowDurationMins":300,"usedPercent":100},"secondary":{"windowDurationMins":10080,"usedPercent":-1}}}"#)
        XCTAssertEqual(s.session?.remaining, 0); XCTAssertNil(s.week)
    }
    func testExpiredClockCannotConfirmReset() {
        let s = snapshot(90, at: 800, reset: 900)
        let same = snapshot(90, at: 1000, reset: 900)
        XCTAssertEqual(countdown(to: s.session?.reset, now: now), "Due")
        XCTAssertTrue(limitEvents(from: s, to: same, thresholds: [10], resets: true).isEmpty)
    }
    func testConfirmedResetRequiresFreshMatchingAccount() {
        let old = snapshot(99, at: 800, reset: 900)
        let new = snapshot(2, at: 1000, reset: 2000)
        XCTAssertEqual(limitEvents(from: old, to: new, thresholds: [10], resets: true), [LimitEvent(period: .session, threshold: nil)])
        XCTAssertTrue(limitEvents(from: old, to: snapshot(2, at: 1000, reset: 2000, owner: "B"), thresholds: [], resets: true).isEmpty)
    }
    func testThresholdCrossingsAndDuplicates() {
        let old = snapshot(70, at: 800, reset: 2000)
        for (used, threshold) in [(75, nil), (76, 25), (90, 25), (91, 10), (100, 0)] {
            let next = snapshot(used, at: 900, reset: 2000)
            let events = limitEvents(from: old, to: next, thresholds: [25,10,0], resets: true)
            XCTAssertEqual(events, threshold.map { [LimitEvent(period: .session, threshold: $0)] } ?? [])
            XCTAssertTrue(limitEvents(from: next, to: next, thresholds: [25,10,0], resets: true).isEmpty)
        }
    }
    func testStatusAndCacheRoundTrip() throws {
        var r = Reading(snapshot: snapshot(50, at: 800, reset: 1200), liveUntil: now.addingTimeInterval(60))
        XCTAssertEqual(r.status(at: now), "Live")
        XCTAssertEqual(r.status(at: now.addingTimeInterval(60)), "Cached")
        r.issue = "Offline"
        let cached = try JSONDecoder().decode(Reading.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(cached.status(at: now), "Cached")
        XCTAssertEqual(Reading.empty.status(at: now), "Unavailable")
    }
    func testCountdownUnits() {
        XCTAssertEqual(countdown(to: nil, now: now), "—")
        XCTAssertEqual(countdown(to: now.addingTimeInterval(1), now: now), "1m")
        XCTAssertEqual(countdown(to: now.addingTimeInterval(3700), now: now), "1h 2m")
    }
}

extension UsageTests {
    func testAvailableCreditsKeepReportedCountAndSortAvailableRows() throws {
        let value = try decode("""
        {"rateLimitResetCredits":{"availableCount":3,"credits":[
          {"id":"later","status":"available","expiresAt":2000},
          {"id":"past","status":"redeemed","expiresAt":800},
          {"id":"first","status":"available","title":"Full reset","description":"Restores both limits","expiresAt":1200}
        ]}}
        """)
        let summary = try XCTUnwrap(value.resetCredits)
        XCTAssertEqual(summary.availableCount, 3)
        XCTAssertEqual(summary.available.map(\.id), ["first", "later"])
        XCTAssertEqual(summary.available.first?.label, "Full reset")
        XCTAssertEqual(summary.available.first?.expiresAt, 1200)
        XCTAssertTrue(value.hasData)
        let saved = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(saved.resetCredits?.available.first?.description, "Restores both limits")
    }

    func testCountOnlyZeroAndMissingAreDistinct() throws {
        XCTAssertEqual(try decode(#"{"rateLimitResetCredits":{"availableCount":2,"credits":null}}"#).resetCredits?.availableCount, 2)
        XCTAssertEqual(try decode(#"{"rateLimitResetCredits":{"availableCount":0,"credits":[]}}"#).resetCredits?.availableCount, 0)
        XCTAssertNil(try decode(#"{"rateLimitResetCredits":null}"#).resetCredits)
        let legacy = Data(#"{"owner":"A","date":0}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(Snapshot.self, from: legacy).resetCredits)
    }
}
