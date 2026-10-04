//
//  CronSchedule.swift
//  DataConverter
//
//  A cron schedule (five fields or an @ shorthand) validated and put into plain words, with a
//  warning for a date that never comes.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A cron schedule — `m h dom mon dow`, or `@reboot` / `@daily` / … — checked and described:
/// "At 02:30 every day", "Every 15 minutes, between 08:00 and 18:59", "At 17:00 on Monday to
/// Friday". Day of month and day of week both restricted means EITHER, as cron runs them. A
/// day no month listed has (`30 2`) is reported as never running; the 29th of February as leap
/// years only.
public enum CronSchedule {

    /// A schedule in words.
    public struct Description: Equatable, Sendable {
        /// The schedule as a sentence, first letter capitalised.
        public let text: String
        /// Set when the schedule never runs, or only in leap years.
        public let warning: String?
        /// True when the schedule can never run.
        public let neverRuns: Bool
    }

    /// The shorthands and the five fields each stands for (`@reboot` has none).
    static let shorthands: [String: String?] = [
        "@reboot": nil, "@yearly": "0 0 1 1 *", "@annually": "0 0 1 1 *", "@monthly": "0 0 1 * *",
        "@weekly": "0 0 * * 0", "@daily": "0 0 * * *", "@midnight": "0 0 * * *", "@hourly": "0 * * * *",
    ]

    /// Whether `schedule` is a shorthand or five fields cron accepts.
    public static func isValid(_ schedule: String) -> Bool {
        let s = schedule.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("@") { return shorthands[s.lowercased()] != nil }
        return fields(s) != nil
    }

    /// `schedule` in words, or nil when it is not a valid schedule.
    public static func describe(_ schedule: String) -> Description? {
        let s = schedule.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("@") {
            guard let expansion = shorthands[s.lowercased()] else { return nil }
            guard let five = expansion else {
                return Description(
                    text: capitalised(
                        String(localized: "at startup", bundle: .module, comment: "Cron @reboot: the job runs when the machine starts")),
                    warning: nil, neverRuns: false)
            }
            return describe(five)
        }
        guard let f = fields(s) else { return nil }
        let time = timePhrase(minute: f[0], hour: f[1])
        var parts = [time.text]
        let day = dayPhrase(dom: f[2], dow: f[4])
        if let day, !(day.isEveryDay && !time.isAtTimes) { parts.append(day.text) }
        if !f[3].isAny {
            parts.append(
                String(
                    localized: "in \(listText(f[3], kind: .month))", bundle: .module,
                    comment: "Cron: months the job runs in, e.g. 'in January and July'"))
        }
        let text = parts.dropFirst().reduce(parts[0]) { joined, next in
            String(
                localized: "\(joined) \(next)", bundle: .module, comment: "Cron: two parts of a schedule in words, joined (time then days)")
        }
        let (warning, never) = impossibility(dom: f[2], month: f[3], dow: f[4])
        return Description(text: capitalised(text), warning: warning, neverRuns: never)
    }

    // MARK: - Fields

    enum Kind {
        case minute, hour, dayOfMonth, month, dayOfWeek
        var bounds: ClosedRange<Int> {
            switch self {
            case .minute: 0...59
            case .hour: 0...23
            case .dayOfMonth: 1...31
            case .month: 1...12
            case .dayOfWeek: 0...7
            }
        }
        var names: [String] {
            switch self {
            case .month: ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
            case .dayOfWeek: ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
            default: []
            }
        }
        /// The value a name stands for: months from 1, weekdays from 0.
        func value(_ token: String) -> Int? {
            if let n = Int(token), bounds.contains(n) { return n }
            guard let i = names.firstIndex(of: token.lowercased()) else { return nil }
            return self == .month ? i + 1 : i
        }
    }

    /// One comma-separated item: a value, a range, or either (or `*`) with a step.
    enum Item: Equatable {
        case value(Int)
        case range(Int, Int)
        case step(from: Int, to: Int, by: Int, fromStar: Bool)
    }

    /// One field: its items and every value it matches.
    struct Field {
        let raw: String
        let items: [Item]
        let values: Set<Int>
        let kind: Kind
        /// `*`, or a set that covers the whole range.
        var isAny: Bool {
            if raw == "*" { return true }
            let full = Set(kind.bounds).subtracting(kind == .dayOfWeek ? [7] : [])
            return full.isSubset(of: values.map { kind == .dayOfWeek && $0 == 7 ? 0 : $0 })
        }
    }

    static func fields(_ schedule: String) -> [Field]? {
        let parts = schedule.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard parts.count == 5 else { return nil }
        let kinds: [Kind] = [.minute, .hour, .dayOfMonth, .month, .dayOfWeek]
        var out: [Field] = []
        for (raw, kind) in zip(parts, kinds) {
            guard let field = field(raw, kind: kind) else { return nil }
            out.append(field)
        }
        return out
    }

    static func field(_ raw: String, kind: Kind) -> Field? {
        var items: [Item] = []
        var values = Set<Int>()
        for part in raw.split(separator: ",", omittingEmptySubsequences: false).map(String.init) {
            guard !part.isEmpty else { return nil }
            let pieces = part.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard pieces.count <= 2 else { return nil }
            var step: Int?
            if pieces.count == 2 {
                guard let n = Int(pieces[1]), n > 0 else { return nil }
                step = n
            }
            let base = pieces[0]
            let lo: Int, hi: Int, star: Bool
            if base == "*" {
                lo = kind.bounds.lowerBound; hi = kind == .dayOfWeek ? 6 : kind.bounds.upperBound; star = true
            } else if let dash = base.firstIndex(of: "-") {
                guard let a = kind.value(String(base[..<dash])), let b = kind.value(String(base[base.index(after: dash)...])), a <= b
                else { return nil }
                lo = a; hi = b; star = false
            } else {
                guard let v = kind.value(base) else { return nil }
                lo = v; hi = step == nil ? v : (kind == .dayOfWeek ? 6 : kind.bounds.upperBound); star = false
            }
            if let step {
                items.append(.step(from: lo, to: hi, by: step, fromStar: star))
                values.formUnion(stride(from: lo, through: hi, by: step))
            } else if base == "*" {
                items.append(.range(lo, hi))
                values.formUnion(lo...hi)
            } else if lo == hi {
                items.append(.value(lo))
                values.insert(lo)
            } else {
                items.append(.range(lo, hi))
                values.formUnion(lo...hi)
            }
        }
        return Field(raw: raw, items: items, values: values, kind: kind)
    }

    // MARK: - Words

    /// The time of day, and whether it names exact times ("at 02:30") — only then does
    /// "every day" read naturally after it.
    static func timePhrase(minute m: Field, hour h: Field) -> (text: String, isAtTimes: Bool) {
        let everyMinute = String(localized: "every minute", bundle: .module, comment: "Cron: the job runs every minute")
        // Every n minutes (or every minute), all day or within a range of hours.
        if m.isAny || isPlainStep(m) {
            let base = m.isAny ? everyMinute : every(stepOf(m), .minute)
            if h.isAny { return (base, false) }
            if h.items.count == 1, case .range(let a, let b) = h.items[0] {
                return (
                    String(
                        localized: "\(base), between \(clock(a, 0)) and \(clock(b, 59))", bundle: .module,
                        comment: "Cron: a repeating job limited to hours, e.g. 'every 15 minutes, between 08:00 and 18:59'"), false
                )
            }
        }
        // Fixed minutes.
        if !m.items.contains(where: { if case .step = $0 { return true } else { return false } }) || m.values.count <= 6 {
            let minutes = m.values.sorted()
            if h.isAny, minutes.count <= 6 {
                let marks = list(minutes.map { ":" + String(format: "%02d", $0) })
                return (
                    String(
                        localized: "every hour at \(marks)", bundle: .module,
                        comment: "Cron: minutes past every hour, e.g. 'every hour at :15'"),
                    false
                )
            }
            if isPlainStep(h), minutes.count == 1 {
                return (
                    String(
                        localized: "\(every(stepOf(h), .hour)) at :\(String(format: "%02d", minutes[0]))", bundle: .module,
                        comment: "Cron: e.g. 'every 2 hours at :00'"), false
                )
            }
            let hours = h.values.sorted()
            if !h.isAny, minutes.count * hours.count <= 6 {
                let times = hours.flatMap { hr in minutes.map { clock(hr, $0) } }
                return (
                    String(localized: "at \(list(times))", bundle: .module, comment: "Cron: exact times, e.g. 'at 06:00, 12:00 and 18:00'"),
                    true
                )
            }
        }
        return (
            String(
                localized: "at minute \(m.raw) of hour \(h.raw)", bundle: .module,
                comment: "Cron fallback: the raw minute and hour fields when no simpler wording fits"), false
        )
    }

    /// The days: every day, weekdays, days of the month, or either.
    static func dayPhrase(dom: Field, dow: Field) -> (text: String, isEveryDay: Bool)? {
        switch (dom.isAny, dow.isAny) {
        case (true, true):
            return (String(localized: "every day", bundle: .module, comment: "Cron: no day restriction"), true)
        case (true, false):
            return (
                String(
                    localized: "on \(listText(dow, kind: .dayOfWeek))", bundle: .module,
                    comment: "Cron: weekdays, e.g. 'on Monday to Friday'"), false
            )
        case (false, true):
            return (
                String(
                    localized: "on day \(listText(dom, kind: .dayOfMonth)) of the month", bundle: .module,
                    comment: "Cron: days of the month, e.g. 'on day 1 and 15 of the month'"),
                false
            )
        case (false, false):
            return (
                String(
                    localized: "on day \(listText(dom, kind: .dayOfMonth)) of the month or on \(listText(dow, kind: .dayOfWeek))",
                    bundle: .module,
                    comment: "Cron: day of month OR weekday, as cron runs them, e.g. 'on day 13 of the month or on Friday'"), false
            )
        }
    }

    /// A field's items as words: names for months and weekdays, "1 to 5" for a range; a field
    /// with steps comes back as written.
    static func listText(_ f: Field, kind: Kind) -> String {
        if f.items.contains(where: { if case .step = $0 { return true } else { return false } }) { return f.raw }
        let words = f.items.map { item -> String in
            switch item {
            case .value(let v): return name(v, kind)
            case .range(let a, let b):
                return String(
                    localized: "\(name(a, kind)) to \(name(b, kind))", bundle: .module,
                    comment: "Cron: an inclusive range, e.g. 'Monday to Friday'")
            case .step: return f.raw
            }
        }
        return list(words)
    }

    static func name(_ v: Int, _ kind: Kind) -> String {
        switch kind {
        case .month: return monthNames[v - 1]
        case .dayOfWeek: return weekdayNames[v % 7]
        default: return String(v)
        }
    }
    /// The calendar's names, read once: building them on every description made a long crontab slow.
    static let monthNames = Calendar.current.standaloneMonthSymbols
    static let weekdayNames = Calendar.current.standaloneWeekdaySymbols

    /// "5 minutes", "2 hours" — the system's own wording, plurals included.
    static func every(_ n: Int, _ unit: NSCalendar.Unit) -> String {
        if n == 1 {
            return unit == .hour
                ? String(localized: "every hour", bundle: .module, comment: "Cron: the job runs every hour")
                : String(localized: "every minute", bundle: .module, comment: "Cron: the job runs every minute")
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = unit
        let amount = formatter.string(from: unit == .hour ? TimeInterval(n * 3600) : TimeInterval(n * 60)) ?? String(n)
        return String(localized: "every \(amount)", bundle: .module, comment: "Cron: an interval, e.g. 'every 5 minutes'")
    }

    static func isPlainStep(_ f: Field) -> Bool {
        if f.items.count == 1, case .step(_, _, _, true) = f.items[0] { return true }
        return false
    }
    static func stepOf(_ f: Field) -> Int {
        if case .step(_, _, let by, _) = f.items[0] { return by }
        return 1
    }

    static func clock(_ h: Int, _ m: Int) -> String { String(format: "%02d:%02d", h, m) }

    static func list(_ items: [String]) -> String {
        ListFormatter.localizedString(byJoining: items)
    }

    static func capitalised(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).localizedUppercase + s.dropFirst()
    }

    // MARK: - Dates that never come

    /// A day of the month that none of the allowed months has (the 30th of February) never
    /// runs — unless a weekday restriction lets the job run anyway; the 29th of February runs
    /// in leap years only.
    static func impossibility(dom: Field, month: Field, dow: Field) -> (String?, Bool) {
        guard !dom.isAny, dow.isAny else { return (nil, false) }
        let lengths = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        let months = month.isAny ? Array(1...12) : month.values.sorted()
        let days = dom.values.sorted()
        let possible = months.contains { m in days.contains { $0 <= lengths[m - 1] } }
        if !possible {
            let monthNames = list(months.map { name($0, .month) })
            let dayList = list(days.map(String.init))
            return (
                String(
                    localized: "Never runs: \(monthNames) has no day \(dayList)", bundle: .module,
                    comment: "Cron warning: e.g. 'Never runs: February has no day 30'"),
                true
            )
        }
        if months == [2], days.allSatisfy({ $0 >= 29 }), days.contains(29) {
            return (String(localized: "Runs in leap years only", bundle: .module, comment: "Cron warning: a job on 29 February"), false)
        }
        return (nil, false)
    }
}
