//
//  CrontabTests.swift
//  DataConverterTests
//
//  A crontab read as assignments and jobs, disabled jobs included, and edited a line at a time.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import DataConverter

final class CrontabTests: XCTestCase {
    private let text = """
        # m h dom mon dow command
        MAILTO=ops@example.com
        USER = warehouse
        LOGDIR="/var/log/warehouse"
        30 2 * * * /opt/bin/nightly --all
         5   4   *   *   *   /opt/bin/extra-spaces
        @reboot /opt/bin/start
        #0 0 * * * /opt/bin/disabled
        # ── not a job: * * * * * ──
        -*/5 * * * * /opt/bin/quiet
        20 1 * * * echo "at $(date +\\%H)" # literal to cron
        """

    func testAssignmentsAndJobs() {
        let file = Crontab.parse(text)
        XCTAssertEqual(file.assignments.map(\.key), ["MAILTO", "USER", "LOGDIR"])
        XCTAssertEqual(file.assignments[2].value, "/var/log/warehouse", "quotes removed")
        XCTAssertEqual(file.jobs.map(\.line), [5, 6, 7, 8, 10, 11])
        XCTAssertEqual(file.jobs[0].schedule, "30 2 * * *")
        XCTAssertEqual(file.jobs[0].command, "/opt/bin/nightly --all")
        XCTAssertEqual(file.jobs[1].schedule, "5 4 * * *", "irregular spacing normalised in the schedule")
        XCTAssertEqual(file.jobs[2].schedule, "@reboot")
        XCTAssertFalse(file.jobs[3].isEnabled, "a commented-out job is disabled, not dropped")
        XCTAssertTrue(file.jobs[4].isQuiet)
        XCTAssertEqual(file.jobs[5].command, "echo \"at $(date +\\%H)\" # literal to cron", "# inside a command is literal")
    }

    func testEditsKeepTheLine() {
        let schedule = Crontab.replacingSchedule(in: text, line: 5, with: "0  3 * * 1-5")
        XCTAssertTrue(schedule.contains("\n0 3 * * 1-5 /opt/bin/nightly --all\n"), schedule)
        XCTAssertEqual(Crontab.replacingSchedule(in: text, line: 5, with: "61 * * * *"), text, "an invalid schedule is refused")
        let spaced = Crontab.replacingCommand(in: text, line: 6, with: "/opt/bin/other")
        XCTAssertTrue(spaced.contains("\n 5   4   *   *   *   /opt/bin/other\n"), "the field spacing survives a command edit")
        let disabled = Crontab.replacingCommand(in: text, line: 8, with: "/opt/bin/renamed")
        XCTAssertTrue(disabled.contains("\n#0 0 * * * /opt/bin/renamed\n"), "a disabled job stays disabled")
        let quiet = Crontab.replacingCommand(in: text, line: 10, with: "/opt/bin/q2")
        XCTAssertTrue(quiet.contains("\n-*/5 * * * * /opt/bin/q2\n"))
        let value = Crontab.replacingValue(in: text, line: 4, with: "/srv/logs with space")
        XCTAssertTrue(value.contains("LOGDIR=\"/srv/logs with space\""))
        XCTAssertTrue(Crontab.replacingValue(in: text, line: 3, with: "ops").contains("USER = ops"), "spacing around = kept")
    }

    func testEnableAndDisable() {
        let on = Crontab.settingEnabled(in: text, line: 8, true)
        XCTAssertTrue(on.contains("\n0 0 * * * /opt/bin/disabled\n"))
        XCTAssertTrue(Crontab.parse(on).jobs.first { $0.line == 8 }?.isEnabled == true)
        let off = Crontab.settingEnabled(in: text, line: 5, false)
        XCTAssertTrue(off.contains("\n#30 2 * * * /opt/bin/nightly --all\n"))
        XCTAssertEqual(Crontab.settingEnabled(in: text, line: 5, true), text, "already enabled")
    }

    func testCRLFKeepsItsLineEnds() {
        let crlf = "30 2 * * * /a\r\n0 1 * * * /b\r\n"
        XCTAssertEqual(Crontab.parse(crlf).jobs.map(\.command), ["/a", "/b"])
        XCTAssertEqual(Crontab.replacingCommand(in: crlf, line: 1, with: "/c"), "30 2 * * * /c\r\n0 1 * * * /b\r\n")
    }
}
