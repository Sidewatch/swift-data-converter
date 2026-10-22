//
//  CronNextRunsTests.swift
//  DataConverterTests
//
//  When a cron schedule fires next: against croniter on 300 random schedules, and by hand for
//  the rules croniter reads differently or cannot show.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import DataConverter

final class CronNextRunsTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
    private func iso(_ date: Date, _ zone: TimeZone? = nil) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = zone ?? utc
        return f.string(from: date)
    }
    private func runs(_ schedule: String, after: String, _ count: Int = 3, in zone: TimeZone? = nil) -> [String] {
        CronSchedule.nextRuns(schedule, after: date(after), count: count, in: zone ?? utc).map { iso($0, zone) }
    }

    // MARK: - Against an independent implementation

    /// 300 random schedules (ranges with two ends, steps, lists; no names) and their next five runs as
    /// croniter computes them; `Fixtures/cron-next-runs.py` writes the file.
    func testThreeHundredSchedulesMatchCroniter() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "cron-next-runs", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let after = date(try XCTUnwrap(fixture["after"] as? String))
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 300)
        var mismatches: [String] = []
        for c in cases {
            let schedule = try XCTUnwrap(c["schedule"] as? String)
            let want = try XCTUnwrap(c["runs"] as? [String])
            let got = CronSchedule.nextRuns(schedule, after: after, count: want.count, in: utc).map { iso($0) }
            if got != want { mismatches.append("\(schedule): \(got) ≠ \(want)") }
        }
        XCTAssertTrue(mismatches.isEmpty, "\(mismatches.count) differ: \(mismatches.prefix(5))")
    }

    // MARK: - By hand

    func testEveryFifteenMinutesStartsAfterTheGivenTime() {
        XCTAssertEqual(
            runs("*/15 * * * *", after: "2026-10-22T10:07:00Z"), ["2026-10-22T10:15:00Z", "2026-10-22T10:30:00Z", "2026-10-22T10:45:00Z"])
        XCTAssertEqual(runs("*/15 * * * *", after: "2026-10-22T10:15:00Z", 1), ["2026-10-22T10:30:00Z"], "a run AT the time is not next")
    }

    func testWeekdaysSkipTheWeekend() {
        // 23 Oct 2026 is a Friday.
        XCTAssertEqual(
            runs("0 9 * * 1-5", after: "2026-10-23T10:00:00Z"), ["2026-10-26T09:00:00Z", "2026-10-27T09:00:00Z", "2026-10-28T09:00:00Z"])
    }

    func testWeekdaySevenIsSundayAndNamesWork() {
        XCTAssertEqual(runs("0 0 * * 7", after: "2026-10-22T00:00:00Z", 1), ["2026-10-25T00:00:00Z"])
        XCTAssertEqual(runs("0 0 * jan sun", after: "2026-10-22T00:00:00Z", 1), ["2027-01-03T00:00:00Z"])
    }

    func testAOneValueRangeIsThatValue() {
        // croniter 6.2.4 reads `48-48` as every minute and `3-3/3` as 3 and 6; cron reads one value.
        XCTAssertEqual(runs("48-48 * * * *", after: "2026-10-22T14:37:00Z", 2), ["2026-10-22T14:48:00Z", "2026-10-22T15:48:00Z"])
        XCTAssertEqual(runs("0 0 * * 3-3/3", after: "2026-10-22T14:37:00Z", 2), ["2026-10-28T00:00:00Z", "2026-11-04T00:00:00Z"])
    }

    func testBothDayFieldsRestrictedMeansEither() {
        // The 13th, or any Friday: Friday 23 Oct, Friday 30 Oct, then Friday 6 Nov… and the 13th.
        XCTAssertEqual(
            runs("0 0 13 * 5", after: "2026-10-22T00:00:00Z", 4),
            ["2026-10-23T00:00:00Z", "2026-10-30T00:00:00Z", "2026-11-06T00:00:00Z", "2026-11-13T00:00:00Z"])
    }

    func testADayFieldStartingWithAStarMeansBoth() {
        // cronie: `*/2` is a star field, so the day must be odd AND a Monday (croniter reads it as either).
        // Mondays after 22 Oct 2026: 26 Oct (even), 2 Nov (even), 9 Nov (odd), 16, 23 (odd), 30, 7 Dec (odd).
        XCTAssertEqual(
            runs("0 0 */2 * 1", after: "2026-10-22T00:00:00Z", 3), ["2026-11-09T00:00:00Z", "2026-11-23T00:00:00Z", "2026-12-07T00:00:00Z"])
    }

    func testTheTwentyNinthOfFebruaryWaitsForALeapYear() {
        XCTAssertEqual(runs("0 0 29 2 *", after: "2026-10-22T00:00:00Z", 2), ["2028-02-29T00:00:00Z", "2032-02-29T00:00:00Z"])
    }

    func testSchedulesThatNeverRunHaveNoNextRun() {
        XCTAssertEqual(runs("0 0 30 2 *", after: "2026-10-22T00:00:00Z"), [])
        XCTAssertEqual(runs("@reboot", after: "2026-10-22T00:00:00Z"), [])
        XCTAssertEqual(runs("not a schedule", after: "2026-10-22T00:00:00Z"), [])
        XCTAssertEqual(runs("* * * * *", after: "2026-10-22T00:00:00Z", 0), [])
    }

    func testShorthandsExpand() {
        XCTAssertEqual(runs("@daily", after: "2026-10-22T10:00:00Z", 2), ["2026-10-23T00:00:00Z", "2026-10-24T00:00:00Z"])
        XCTAssertEqual(runs("@HOURLY", after: "2026-10-22T10:00:00Z", 1), ["2026-10-22T11:00:00Z"])
    }

    func testTheWallClockIsTheGivenTimeZones() throws {
        let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        XCTAssertEqual(runs("0 9 * * *", after: "2026-10-21T23:00:00Z", 1, in: tokyo), ["2026-10-22T09:00:00+09:00"])
        XCTAssertEqual(
            runs("0 9 * * *", after: "2026-10-22T00:00:00Z", 1, in: tokyo), ["2026-10-23T09:00:00+09:00"], "09:00 itself is not next")
    }

    func testDaylightSavingSkipsAMissingTimeAndRunsARepeatedOneOnce() throws {
        let london = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        // 29 Mar 2026: 01:00 GMT jumps to 02:00 BST, so that day has no 01:30.
        XCTAssertEqual(
            runs("30 1 * * *", after: "2026-03-28T12:00:00Z", 2, in: london), ["2026-03-30T01:30:00+01:00", "2026-03-31T01:30:00+01:00"])
        // 25 Oct 2026: 02:00 BST falls back to 01:00 GMT, so 01:30 comes twice; it runs once, the first time.
        XCTAssertEqual(
            runs("30 1 * * *", after: "2026-10-24T12:00:00Z", 2, in: london), ["2026-10-25T01:30:00+01:00", "2026-10-26T01:30:00Z"])
    }

    func testMonthLengthsFollowTheGregorianLeapRule() {
        XCTAssertEqual(CronSchedule.daysIn(month: 2, year: 2028), 29)
        XCTAssertEqual(CronSchedule.daysIn(month: 2, year: 2027), 28)
        XCTAssertEqual(CronSchedule.daysIn(month: 2, year: 2100), 28, "a century is not a leap year")
        XCTAssertEqual(CronSchedule.daysIn(month: 2, year: 2000), 29, "unless it divides by 400")
        XCTAssertEqual([4, 6, 9, 11].map { CronSchedule.daysIn(month: $0, year: 2026) }, [30, 30, 30, 30])
        XCTAssertEqual([1, 3, 5, 7, 8, 10, 12].map { CronSchedule.daysIn(month: $0, year: 2026) }, [31, 31, 31, 31, 31, 31, 31])
        // Walked across the century: 2100 has no 29 February, so the run after 2096's is 2104's.
        XCTAssertEqual(runs("0 0 29 2 *", after: "2097-01-01T00:00:00Z", 1), ["2104-02-29T00:00:00Z"])
    }

    func testACrontabNamesItsTimeZone() {
        XCTAssertEqual(Crontab.parse("CRON_TZ=Asia/Tokyo\n0 9 * * * backup\n").timeZone?.identifier, "Asia/Tokyo")
        XCTAssertNil(Crontab.parse("0 9 * * * backup\n").timeZone)
        XCTAssertNil(Crontab.parse("CRON_TZ=Nowhere/Atlantis\n0 9 * * * backup\n").timeZone, "a name the system does not know")
        XCTAssertEqual(Crontab.parse("CRON_TZ=UTC\nCRON_TZ=Europe/Paris\n").timeZone?.identifier, "Europe/Paris", "the last one wins")
    }
}
