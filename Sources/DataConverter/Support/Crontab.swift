//
//  Crontab.swift
//  DataConverter
//
//  A crontab(5) file as its environment assignments and its jobs, commented-out jobs
//  included, and the line edits a table makes to it.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A crontab(5) file: `NAME=value` assignments and jobs (`m h dom mon dow command`, or an
/// `@reboot`-style shorthand and a command). A commented-out line that still reads as a job is
/// a DISABLED job; other comments are prose. A job keeps its command exactly as written (a `#`
/// inside a command is literal to cron). Edits rewrite one line in place.
public enum Crontab {

    /// One `NAME=value` line.
    public struct Assignment: Equatable, Sendable {
        /// 1-based line.
        public let line: Int
        /// The variable's name.
        public let key: String
        /// The value, quotes removed.
        public let value: String
        /// Creates an assignment.
        public init(line: Int, key: String, value: String) { self.line = line; self.key = key; self.value = value }
    }

    /// One job.
    public struct Job: Equatable, Sendable {
        /// 1-based line.
        public let line: Int
        /// The schedule as written: five fields joined by single spaces, or the `@` shorthand.
        public let schedule: String
        /// The command, exactly as written.
        public let command: String
        /// False for a job commented out.
        public let isEnabled: Bool
        /// True for a Debian-style `-` prefix (the job is not logged to syslog).
        public let isQuiet: Bool
        /// Creates a job.
        public init(line: Int, schedule: String, command: String, isEnabled: Bool, isQuiet: Bool) {
            self.line = line; self.schedule = schedule; self.command = command
            self.isEnabled = isEnabled; self.isQuiet = isQuiet
        }
    }

    /// A parsed crontab.
    public struct File: Equatable, Sendable {
        /// The assignments, in file order.
        public let assignments: [Assignment]
        /// The jobs, in file order.
        public let jobs: [Job]
    }

    /// The assignments and jobs of `text`.
    public static func parse(_ text: String) -> File {
        var assignments: [Assignment] = []
        var jobs: [Job] = []
        for (i, raw) in LineText.lines(text).enumerated() {
            let line = LineText.clean(raw)
            if let body = LineText.uncommented(line) {
                if let job = job(body, line: i + 1, enabled: false) { jobs.append(job) }
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if let assignment = assignment(trimmed, line: i + 1) {
                assignments.append(assignment)
            } else if let job = job(trimmed, line: i + 1, enabled: true) {
                jobs.append(job)
            }
        }
        return File(assignments: assignments, jobs: jobs)
    }

    /// `text` with the schedule of the job on `line` replaced; nil-safe — an invalid schedule
    /// leaves the file alone.
    public static func replacingSchedule(in text: String, line: Int, with schedule: String) -> String {
        let clean = schedule.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        guard CronSchedule.isValid(clean) else { return text }
        return rewrite(text, line: line) { $0.schedule = clean }
    }

    /// `text` with the command of the job on `line` replaced.
    public static func replacingCommand(in text: String, line: Int, with command: String) -> String {
        let clean = command.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, !clean.contains("\n") else { return text }
        return rewrite(text, line: line) { $0.command = clean }
    }

    /// `text` with the value of the assignment on `line` replaced, quoted when it needs to be.
    public static func replacingValue(in text: String, line: Int, with value: String) -> String {
        let lines = LineText.lines(text)
        guard line >= 1, line <= lines.count, !value.contains("\n") else { return text }
        let current = LineText.clean(lines[line - 1])
        guard let eq = current.firstIndex(of: "=") else { return text }
        let head = current[...eq]
        let after = current[current.index(after: eq)...]
        let space = String(after.prefix { $0 == " " })
        let quoted = value.contains(where: { $0 == " " || $0 == "#" }) || value.isEmpty && after.contains("\"")
        return LineText.replacingLine(line, in: text, with: head + space + (quoted ? "\"\(value)\"" : value))
    }

    /// `text` with the job on `line` enabled (leading `#` removed) or disabled (`#` put in front).
    public static func settingEnabled(in text: String, line: Int, _ enabled: Bool) -> String {
        let lines = LineText.lines(text)
        guard line >= 1, line <= lines.count else { return text }
        let current = LineText.clean(lines[line - 1])
        let indent = String(current.prefix { $0 == " " || $0 == "\t" })
        if enabled {
            guard let body = LineText.uncommented(current) else { return text }
            return LineText.replacingLine(line, in: text, with: indent + body)
        }
        guard LineText.uncommented(current) == nil else { return text }
        return LineText.replacingLine(line, in: text, with: indent + "#" + current.dropFirst(indent.count))
    }

    // MARK: - Reading

    /// `NAME=value` (spaces allowed around `=`, as cronie reads them).
    static func assignment(_ line: String, line number: Int) -> Assignment? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        let key = line[..<eq].trimmingCharacters(in: .whitespaces)
        guard let first = key.first, first.isLetter || first == "_",
            key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
        else { return nil }
        var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let q = value.first, q == "\"" || q == "'", value.last == q { value = String(value.dropFirst().dropLast()) }
        return Assignment(line: number, key: key, value: value)
    }

    /// The parts of a job line: its quiet prefix, schedule and command, with where the command
    /// starts — or nil when the line is not a job.
    static func split(_ body: String) -> (quiet: Bool, schedule: String, command: String, commandOffset: Int)? {
        var text = Substring(body.drop { $0 == " " || $0 == "\t" })
        var quiet = false
        if text.hasPrefix("-") { quiet = true; text = text.dropFirst() }
        let tokens = LineText.tokens(String(text))
        let source = String(text)
        if let first = tokens.first, first.text.hasPrefix("@") {
            guard CronSchedule.shorthands[first.text.lowercased()] != nil, tokens.count >= 2 else { return nil }
            let start = tokens[1].range.lowerBound
            let offset = body.count - source.count + source.distance(from: source.startIndex, to: start)
            return (quiet, first.text, String(source[start...]).trimmingCharacters(in: .whitespaces), offset)
        }
        guard tokens.count >= 6 else { return nil }
        let schedule = tokens.prefix(5).map(\.text).joined(separator: " ")
        guard CronSchedule.isValid(schedule) else { return nil }
        let start = tokens[5].range.lowerBound
        let offset = body.count - source.count + source.distance(from: source.startIndex, to: start)
        return (quiet, schedule, String(source[start...]).trimmingCharacters(in: .whitespaces), offset)
    }

    static func job(_ body: String, line: Int, enabled: Bool) -> Job? {
        guard let parts = split(body) else { return nil }
        return Job(line: line, schedule: parts.schedule, command: parts.command, isEnabled: enabled, isQuiet: parts.quiet)
    }

    // MARK: - Rewriting

    struct Parts { var schedule: String; var command: String }

    /// Applies `edit` to the job on `line` and writes it back: indentation, a disabling `#`, the
    /// quiet `-` and the original field spacing (when the schedule did not change) are kept.
    static func rewrite(_ text: String, line: Int, _ edit: (inout Parts) -> Void) -> String {
        let lines = LineText.lines(text)
        guard line >= 1, line <= lines.count else { return text }
        let current = LineText.clean(lines[line - 1])
        let indent = String(current.prefix { $0 == " " || $0 == "\t" })
        var rest = String(current.dropFirst(indent.count))
        var prefix = indent
        if rest.hasPrefix("#") {
            let hashes = rest.prefix { $0 == "#" }
            rest = String(rest.dropFirst(hashes.count))
            let space = rest.hasPrefix(" ") ? " " : ""
            rest = String(rest.dropFirst(space.count))
            prefix += hashes + space
        }
        let lead = String(rest.prefix { $0 == " " || $0 == "\t" })
        rest = String(rest.dropFirst(lead.count))
        guard let parts = split(rest) else { return text }
        var edited = Parts(schedule: parts.schedule, command: parts.command)
        edit(&edited)
        // The schedule as written (its own spacing) when it did not change.
        let quietText = parts.quiet ? "-" : ""
        let writtenSchedule = String(rest.prefix(parts.commandOffset).dropFirst(quietText.count))
        let scheduleText = edited.schedule == parts.schedule ? writtenSchedule : edited.schedule + " "
        return LineText.replacingLine(line, in: text, with: prefix + lead + quietText + scheduleText + edited.command)
    }
}
