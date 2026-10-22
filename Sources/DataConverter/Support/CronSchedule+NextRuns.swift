//
//  CronSchedule+NextRuns.swift
//  DataConverter
//
//  When a cron schedule fires next, as cron itself would run it.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

extension CronSchedule {
    /// The next `count` times `schedule` fires after `date`, in `timeZone`'s wall clock, the way
    /// cronie runs it: the days are the months' days that match the day-of-month and day-of-week
    /// fields — BOTH when either field starts with `*`, EITHER when both are restricted — and
    /// weekday 7 is Sunday. Empty for `@reboot`, a schedule that is not valid, and one that never
    /// comes (the 30th of February). A wall-clock time a daylight-saving change skips is left
    /// out (cron implementations differ there); one it repeats fires once, the first time.
    ///
    /// Looks at most `CronSchedule.searchYears` years ahead, so a schedule for the 29th of February
    /// lists two runs at most, and one that matches rarer days than that may list none.
    public static func nextRuns(_ schedule: String, after date: Date, count: Int, in timeZone: TimeZone = .current) -> [Date] {
        guard count > 0, let f = expandedFields(schedule), !impossibility(dom: f[2], month: f[3], dow: f[4]).1 else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let minutes = f[0].values.sorted()
        let hours = f[1].values.sorted()
        let months = f[3].values
        let weekdays = Set(f[4].values.map { $0 % 7 })
        let either = !f[2].raw.hasPrefix("*") && !f[4].raw.hasPrefix("*")
        let start = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        guard var year = start.year, var month = start.month, var day = start.day, let firstWeekday = start.weekday else { return [] }
        // The days are walked by counting, the weekday stepping along: the calendar is asked
        // only for the times that might run, never for every day passed.
        var weekday = firstWeekday - 1
        let lastYear = year + searchYears
        var runs: [Date] = []
        while runs.count < count, year <= lastYear {
            let length = daysIn(month: month, year: year)
            guard months.contains(month) else {
                weekday = (weekday + length - day + 1) % 7
                (year, month, day) = month == 12 ? (year + 1, 1, 1) : (year, month + 1, 1)
                continue
            }
            if matchesDay(dayOfMonth: f[2].values.contains(day), weekday: weekdays.contains(weekday), either: either) {
                runs += times(
                    on: (year, month, day), hours: hours, minutes: minutes, after: date, calendar: calendar, limit: count - runs.count)
            }
            weekday = (weekday + 1) % 7
            if day < length {
                day += 1
            } else {
                (year, month, day) = month == 12 ? (year + 1, 1, 1) : (year, month + 1, 1)
            }
        }
        return runs
    }

    /// How far ahead `nextRuns` looks.
    public static let searchYears = 8

    /// The five fields of `schedule`, a shorthand expanded; nil for `@reboot` or an invalid one.
    static func expandedFields(_ schedule: String) -> [Field]? {
        let s = schedule.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("@") {
            guard let expansion = shorthands[s.lowercased()], let five = expansion else { return nil }
            return fields(five)
        }
        return fields(s)
    }

    /// The number of days in `month` of `year`, Gregorian leap years included.
    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Whether a day runs: both fields matching, or either one when both are restricted.
    static func matchesDay(dayOfMonth: Bool, weekday: Bool, either: Bool) -> Bool {
        either ? dayOfMonth || weekday : dayOfMonth && weekday
    }

    /// The day's run times after `date`, at most `limit`: every hour and minute the schedule
    /// names, skipping a wall-clock time the day does not have.
    private static func times(
        on day: (year: Int, month: Int, day: Int), hours: [Int], minutes: [Int], after date: Date, calendar: Calendar, limit: Int
    ) -> [Date] {
        var found: [Date] = []
        for hour in hours {
            for minute in minutes {
                let wanted = DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute)
                guard let time = calendar.date(from: wanted), time > date else { continue }
                let got = calendar.dateComponents([.day, .hour, .minute], from: time)
                guard got.day == day.day, got.hour == hour, got.minute == minute else { continue }
                found.append(time)
                if found.count == limit { return found }
            }
        }
        return found
    }
}
