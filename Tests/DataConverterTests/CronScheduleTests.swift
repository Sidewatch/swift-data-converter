//
//  CronScheduleTests.swift
//  DataConverterTests
//
//  Cron schedules validated and put into words, impossible dates flagged.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import DataConverter

final class CronScheduleTests: XCTestCase {
    private func words(_ s: String) -> String { CronSchedule.describe(s)?.text ?? "nil" }
    private func list(_ items: [String]) -> String { ListFormatter.localizedString(byJoining: items) }
    private var weekdays: [String] { Calendar.current.standaloneWeekdaySymbols }
    private var months: [String] { Calendar.current.standaloneMonthSymbols }

    func testValidity() {
        for ok in ["* * * * *", "*/15 8-18 * * *", "0-30/10 9 * * *", "0 9 * jan,jul MON-FRI", "0 12 * * MON-FRI/2", "@reboot", "@WEEKLY"] {
            XCTAssertTrue(CronSchedule.isValid(ok), ok)
        }
        for bad in [
            "* * * *", "60 * * * *", "* 24 * * *", "* * 0 * *", "* * * 13 *", "* * * * 8", "*/0 * * * *", "5-1 * * * *", "m h dom mon dow",
            "@sometimes", "a b c d e",
        ] {
            XCTAssertFalse(CronSchedule.isValid(bad), bad)
        }
    }

    func testTimesOfDay() {
        XCTAssertEqual(words("30 2 * * *"), "At 02:30 every day")
        XCTAssertEqual(words("* * * * *"), "Every minute")
        XCTAssertTrue(words("*/5 * * * *").hasPrefix("Every 5"), words("*/5 * * * *"))
        XCTAssertTrue(words("*/15 8-18 * * *").hasSuffix("between 08:00 and 18:59"), words("*/15 8-18 * * *"))
        XCTAssertEqual(words("0 6,12,18 * * *"), "At \(list(["06:00", "12:00", "18:00"])) every day")
        XCTAssertEqual(words("17 * * * *"), "Every hour at :17")
        XCTAssertTrue(words("0 */2 * * *").hasSuffix("at :00"), words("0 */2 * * *"))
        XCTAssertEqual(words("0-30/10 9 * * *"), "At \(list(["09:00", "09:10", "09:20", "09:30"])) every day")
    }

    func testDays() {
        XCTAssertEqual(words("0 22 * * 1-5"), "At 22:00 on \(weekdays[1]) to \(weekdays[5])")
        XCTAssertEqual(words("0 17 * * mon-fri"), "At 17:00 on \(weekdays[1]) to \(weekdays[5])")
        XCTAssertEqual(words("0 9 * * 1,3,5"), "At 09:00 on \(list([weekdays[1], weekdays[3], weekdays[5]]))")
        XCTAssertEqual(words("0 3 * * 7"), "At 03:00 on \(weekdays[0])", "7 is Sunday")
        XCTAssertEqual(words("0 8 1,15 * *"), "At 08:00 on day \(list(["1", "15"])) of the month")
        XCTAssertEqual(words("0 0 13 * 5"), "At 00:00 on day 13 of the month or on \(weekdays[5])", "both restricted is EITHER")
        XCTAssertEqual(words("0 10 * * SUN-SAT"), "At 10:00 every day", "every weekday is every day")
        XCTAssertEqual(words("0 12 * * MON-FRI/2"), "At 12:00 on MON-FRI/2", "a stepped weekday field stays as written")
    }

    func testMonths() {
        XCTAssertEqual(words("0 7 * jan,jul *"), "At 07:00 every day in \(list([months[0], months[6]]))")
        XCTAssertEqual(words("0 4 * 3-5 *"), "At 04:00 every day in \(months[2]) to \(months[4])")
    }

    func testShorthands() {
        XCTAssertEqual(words("@reboot"), "At startup")
        XCTAssertEqual(words("@daily"), words("0 0 * * *"))
        XCTAssertEqual(words("@midnight"), words("0 0 * * *"))
        XCTAssertEqual(words("@weekly"), "At 00:00 on \(weekdays[0])")
        XCTAssertEqual(words("@hourly"), "Every hour at :00")
        XCTAssertEqual(words("@yearly"), words("0 0 1 1 *"))
        XCTAssertEqual(words("@annually"), words("@yearly"))
    }

    func testImpossibleDates() {
        let never = CronSchedule.describe("0 0 30 2 *")
        XCTAssertEqual(never?.neverRuns, true)
        XCTAssertNotNil(never?.warning)
        XCTAssertEqual(CronSchedule.describe("0 0 31 4,6 *")?.neverRuns, true, "April and June have 30 days")
        XCTAssertEqual(CronSchedule.describe("0 0 31 4,7 *")?.neverRuns, false, "July has a 31st")
        let leap = CronSchedule.describe("0 0 29 2 *")
        XCTAssertEqual(leap?.neverRuns, false)
        XCTAssertNotNil(leap?.warning, "the 29th of February is leap years only")
        XCTAssertNil(CronSchedule.describe("0 0 30 2 5")?.warning, "a weekday restriction lets it run on Fridays")
        XCTAssertNil(CronSchedule.describe("0 0 1 * *")?.warning)
    }

    /// Every job in the corpus crontab has a description.
    func testTheCorpusCrontabDescribesEveryJob() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
            "../../../../TestFiles/languages/crontab/crontab")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw XCTSkip("corpus not cloned") }
        let jobs = Crontab.parse(text).jobs
        XCTAssertGreaterThan(jobs.count, 50)
        for job in jobs { XCTAssertNotNil(CronSchedule.describe(job.schedule), "\(job.line): \(job.schedule)") }
    }

    /// A long crontab's distinct schedules are described quickly (the table describes each once).
    func testDescribingThousandsOfSchedulesIsQuick() {
        let schedules =
            (0..<5_000).map { "\($0 % 60) \($0 % 24) * * \($0 % 7)" } + (0..<1_000).map { "*/\($0 % 30 + 1) \($0 % 24) 1-15 * *" }
        let start = CFAbsoluteTimeGetCurrent()
        let described = schedules.compactMap { CronSchedule.describe($0) }.count
        let seconds = CFAbsoluteTimeGetCurrent() - start
        print(String(format: "described %d schedules in %.0f ms", described, seconds * 1000))
        XCTAssertEqual(described, schedules.count)
        XCTAssertLessThan(seconds, 1.0)
    }
}
