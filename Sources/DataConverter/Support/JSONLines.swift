//
//  JSONLines.swift
//  DataConverter
//
//  JSON Lines: one JSON document per line, read as an ordered sequence of records.
//
//  Created by David Sherlock on 9/26/26.
//

import Foundation

/// JSON Lines (`.jsonl`, `.ndjson`): one complete JSON document per line, which is the shape every
/// agent transcript, log shipper and dataset export writes.
///
/// It is NOT one JSON document, so a whole-file JSON reader sees a syntax error on line two and
/// gives up — which is why these files show as plain text until something splits them. This splits
/// them, keeping each record's range so an edit made in the tree can be written back to the one
/// line it belongs to.
///
/// Blank lines are skipped, since a trailing newline is normal and an empty line is not a record.
public enum JSONLines {
    /// One record: its position in the file and the UTF-16 range of its text.
    public struct Record: Equatable, Sendable {
        /// The record's index among the NON-BLANK lines, which is what the tree addresses.
        public let index: Int
        /// The 1-based line number in the file, for anything that reports a position to a person.
        public let line: Int
        /// The UTF-16 range of the record's text, trailing newline excluded.
        public let range: NSRange
        public init(index: Int, line: Int, range: NSRange) {
            self.index = index
            self.line = line
            self.range = range
        }
    }

    /// Every non-blank line, with its range. Split on `\n` through `NSString` so a CRLF file
    /// behaves: the `\r` is left inside the record's range, where the JSON reader treats it as
    /// the whitespace it is.
    public static func records(in text: String) -> [Record] {
        let ns = text as NSString
        var records: [Record] = []
        var start = 0
        var line = 1
        var index = 0
        while start <= ns.length {
            let searchRange = NSRange(location: start, length: ns.length - start)
            let newline = ns.range(of: "\n", options: [], range: searchRange)
            let end = newline.location == NSNotFound ? ns.length : newline.location
            let range = NSRange(location: start, length: end - start)
            if !ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                records.append(Record(index: index, line: line, range: range))
                index += 1
            }
            if newline.location == NSNotFound { break }
            start = newline.location + 1
            line += 1
        }
        return records
    }

    /// The whole document as an ordered sequence of records, or nil when NO line parses — a file
    /// that is not JSON Lines at all should fall back to its source rather than show one row.
    ///
    /// A line that does not parse becomes a string of its own text rather than dropping out. The
    /// alternative is a tree whose record numbers silently disagree with the file's lines, which
    /// for a transcript being read as evidence is the worse failure.
    public static func value(of text: String) -> StructuredValue? {
        let records = records(in: text)
        guard !records.isEmpty else { return nil }
        let ns = text as NSString
        var parsedAny = false
        let items: [StructuredValue] = records.map { record in
            let line = ns.substring(with: record.range)
            if let value = JSONStructure.value(of: line) { parsedAny = true; return value }
            return .string(line)
        }
        guard parsedAny else { return nil }
        return .sequence(items)
    }
}
