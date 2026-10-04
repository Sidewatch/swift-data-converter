//
//  LineText.swift
//  DataConverter
//
//  Line-addressed reads and rewrites shared by the line-oriented formats (hosts, crontab,
//  Procfile, ssh config).
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Line-addressed reads and rewrites for the line-oriented formats. Lines are split on `\n`
/// only, so a CRLF file keeps its `\r` on every line; a rewrite puts it back.
enum LineText {
    /// The lines of `text`, `\r` included where the file has one.
    static func lines(_ text: String) -> [String] { text.components(separatedBy: "\n") }

    /// `text` with 1-based `line` replaced by `body` (a trailing `\r` the line had is kept);
    /// unchanged when the line does not exist.
    static func replacingLine(_ line: Int, in text: String, with body: String) -> String {
        var all = lines(text)
        guard line >= 1, line <= all.count else { return text }
        let hadCR = all[line - 1].hasSuffix("\r")
        all[line - 1] = hadCR && !body.hasSuffix("\r") ? body + "\r" : body
        return all.joined(separator: "\n")
    }

    /// The line without its `\r`, for parsing.
    static func clean(_ line: String) -> String { line.hasSuffix("\r") ? String(line.dropLast()) : line }

    /// The whitespace-separated tokens of `line` with their ranges, so an edit can replace one
    /// token and leave the spacing around it alone.
    static func tokens(_ line: String) -> [(text: String, range: Range<String.Index>)] {
        var out: [(String, Range<String.Index>)] = []
        var i = line.startIndex
        while i < line.endIndex {
            while i < line.endIndex, line[i] == " " || line[i] == "\t" { i = line.index(after: i) }
            guard i < line.endIndex else { break }
            let start = i
            while i < line.endIndex, line[i] != " ", line[i] != "\t" { i = line.index(after: i) }
            out.append((String(line[start..<i]), start..<i))
        }
        return out
    }

    /// The text after the run of `#` (and one following space) that comments a line out, or nil
    /// for a line that is not a comment. Leading indentation is allowed.
    static func uncommented(_ line: String) -> String? {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        guard trimmed.first == "#" else { return nil }
        let rest = trimmed.drop { $0 == "#" }
        return String(rest.first == " " ? rest.dropFirst() : rest)
    }
}
