//
//  SSHConfig.swift
//  DataConverter
//
//  An ssh_config(5) file as its Host and Match blocks with their options, and the line edit a
//  table makes to one option's value.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// An ssh_config(5) file: options before the first block apply to every host; each `Host` or
/// `Match` line opens a block whose options follow it. `Keyword value` and `Keyword=value`
/// are both read; keywords are case-insensitive and kept as written.
public enum SSHConfig {

    /// One `Keyword value` line.
    public struct Option: Equatable, Sendable {
        /// 1-based line.
        public let line: Int
        /// The keyword as written (`HostName`).
        public let keyword: String
        /// The value, quotes removed.
        public let value: String
    }

    /// A `Host` or `Match` block (or the global options, `patterns` empty).
    public struct Block: Equatable, Sendable {
        /// 1-based line of the `Host` / `Match` line; 0 for the global options.
        public let line: Int
        /// `Host` or `Match`; empty for the global options.
        public let kind: String
        /// The patterns or criteria after the keyword.
        public let patterns: String
        /// The block's options, in file order.
        public let options: [Option]

        /// The first value of `keyword` (case-insensitive), if the block sets it.
        public func value(_ keyword: String) -> String? { option(keyword)?.value }
        /// The first option named `keyword` (case-insensitive).
        public func option(_ keyword: String) -> Option? { options.first { $0.keyword.caseInsensitiveCompare(keyword) == .orderedSame } }
    }

    /// The blocks of `text`; a leading block of global options when the file has any.
    public static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var current: (line: Int, kind: String, patterns: String, options: [Option]) = (0, "", "", [])
        for (i, raw) in LineText.lines(text).enumerated() {
            guard let (keyword, value) = keywordValue(LineText.clean(raw)) else { continue }
            let lower = keyword.lowercased()
            if lower == "host" || lower == "match" {
                if current.line > 0 || !current.options.isEmpty {
                    blocks.append(Block(line: current.line, kind: current.kind, patterns: current.patterns, options: current.options))
                }
                current = (i + 1, keyword, value, [])
            } else {
                current.options.append(Option(line: i + 1, keyword: keyword, value: value))
            }
        }
        if current.line > 0 || !current.options.isEmpty {
            blocks.append(Block(line: current.line, kind: current.kind, patterns: current.patterns, options: current.options))
        }
        return blocks
    }

    /// `text` with the value of the option (or the patterns of the `Host` line) on `line`
    /// replaced, the keyword and its separator kept.
    public static func replacingValue(in text: String, line: Int, with value: String) -> String {
        let clean = value.trimmingCharacters(in: .whitespaces)
        let lines = LineText.lines(text)
        guard !clean.isEmpty, !clean.contains("\n"), line >= 1, line <= lines.count else { return text }
        let current = LineText.clean(lines[line - 1])
        guard keywordValue(current) != nil else { return text }
        let indent = current.prefix { $0 == " " || $0 == "\t" }
        let rest = current.dropFirst(indent.count)
        let keyword = rest.prefix { $0 != " " && $0 != "\t" && $0 != "=" }
        let separator = rest.dropFirst(keyword.count).prefix { $0 == " " || $0 == "\t" || $0 == "=" }
        let quoted = clean.contains(" ") && !keyword.lowercased().hasPrefix("host") && !keyword.lowercased().hasPrefix("match")
        return LineText.replacingLine(line, in: text, with: indent + keyword + separator + (quoted ? "\"\(clean)\"" : clean))
    }

    /// A line's keyword and value, or nil for a blank or comment line.
    static func keywordValue(_ line: String) -> (String, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        let keyword = trimmed.prefix { $0 != " " && $0 != "\t" && $0 != "=" }
        guard !keyword.isEmpty else { return nil }
        var value = trimmed.dropFirst(keyword.count).drop { $0 == " " || $0 == "\t" || $0 == "=" }
        if value.count >= 2, value.first == "\"", value.last == "\"" { value = value.dropFirst().dropLast() }
        return (String(keyword), String(value))
    }
}
