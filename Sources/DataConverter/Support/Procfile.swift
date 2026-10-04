//
//  Procfile.swift
//  DataConverter
//
//  A Procfile as its process types and commands, and the line edits a table makes to it.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A Procfile (Heroku, foreman, honcho, Overmind): `name: command` per line, `#` comments and
/// blank lines skipped. Edits rewrite one line, keeping the spacing after the colon.
public enum Procfile {

    /// One process type.
    public struct Entry: Equatable, Sendable {
        /// 1-based line.
        public let line: Int
        /// The process type (`web`, `worker`).
        public let process: String
        /// The command, as written.
        public let command: String
        /// Creates an entry.
        public init(line: Int, process: String, command: String) { self.line = line; self.process = process; self.command = command }
    }

    /// The entries of `text`, in file order.
    public static func parse(_ text: String) -> [Entry] {
        LineText.lines(text).enumerated().compactMap { i, raw in
            let line = LineText.clean(raw).trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let colon = line.firstIndex(of: ":") else { return nil }
            let name = String(line[..<colon])
            guard isProcessName(name) else { return nil }
            let command = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            return Entry(line: i + 1, process: name, command: command)
        }
    }

    /// `text` with the process name on `line` replaced; an invalid name leaves the file alone.
    public static func replacingProcess(in text: String, line: Int, with name: String) -> String {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard isProcessName(clean) else { return text }
        return rewrite(text, line: line) { $0.name = clean }
    }

    /// `text` with the command on `line` replaced.
    public static func replacingCommand(in text: String, line: Int, with command: String) -> String {
        let clean = command.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, !clean.contains("\n") else { return text }
        return rewrite(text, line: line) { $0.command = clean }
    }

    /// Letters, digits, `-` and `_` — what the runners accept as a process type.
    static func isProcessName(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    static func rewrite(_ text: String, line: Int, _ edit: (inout (name: String, command: String)) -> Void) -> String {
        let lines = LineText.lines(text)
        guard line >= 1, line <= lines.count else { return text }
        let current = LineText.clean(lines[line - 1])
        let indent = String(current.prefix { $0 == " " || $0 == "\t" })
        guard let colon = current.firstIndex(of: ":") else { return text }
        let afterColon = current[current.index(after: colon)...]
        let gap = String(afterColon.prefix { $0 == " " || $0 == "\t" })
        var parts = (name: current[..<colon].trimmingCharacters(in: .whitespaces), command: afterColon.trimmingCharacters(in: .whitespaces))
        edit(&parts)
        return LineText.replacingLine(line, in: text, with: indent + parts.name + ":" + (gap.isEmpty ? " " : gap) + parts.command)
    }
}
