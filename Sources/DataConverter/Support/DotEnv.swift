//
//  DotEnv.swift
//  DataConverter
//
//  A dotenv file as its KEY=value entries, read the way the dotenv loaders read it, and the
//  rule for which of them a screen should not show.
//
//  Created by David Sherlock on 9/22/26.
//

import Foundation

/// A `.env` file as entries, the way the dotenv loaders read it: `export` dropped, a
/// double-quoted value with its escapes resolved (and allowed to run over lines), a
/// single-quoted value literal, an unquoted value cut at ` #` and trimmed; blank lines,
/// comment lines and lines without `=` skipped. ``shouldMask(key:value:)`` names the entries a
/// preview shows as bullets until asked: keys that say secret, and values that carry
/// credentials in a URL.
public enum DotEnv {

    /// One `KEY=value` line.
    public struct Entry: Equatable, Sendable {
        public let key: String
        public let value: String
        /// 1-based line of the key.
        public let line: Int
        public init(key: String, value: String, line: Int) { self.key = key; self.value = value; self.line = line }
    }

    /// What a masked value shows: a fixed run of bullets, so the length leaks nothing.
    public static let mask = "••••••••"

    /// The entries of `text`, in file order.
    public static func parse(_ text: String) -> [Entry] {
        var out: [Entry] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let number = i + 1
            // `.whitespacesAndNewlines`: a CRLF file leaves a CR on every line (`.whitespaces` keeps it).
            var line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            i += 1
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            guard isKey(key) else { continue }
            var raw = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if raw.hasPrefix("\"") {
                // Runs to the closing unescaped quote, over following lines when it must.
                while closingDoubleQuote(in: raw) == nil, i < lines.count { raw += "\n" + lines[i]; i += 1 }
                if let close = closingDoubleQuote(in: raw) {
                    out.append(Entry(key: key, value: unescape(String(raw[raw.index(after: raw.startIndex)..<close])), line: number))
                } else {
                    out.append(Entry(key: key, value: String(raw.dropFirst()), line: number))
                }
            } else if raw.hasPrefix("'") {
                let rest = raw.dropFirst()
                out.append(Entry(key: key, value: rest.firstIndex(of: "'").map { String(rest[..<$0]) } ?? String(rest), line: number))
            } else {
                if let hash = raw.range(of: " #") { raw = String(raw[..<hash.lowerBound]) }
                if raw.hasPrefix("#") { raw = "" }
                out.append(Entry(key: key, value: raw.trimmingCharacters(in: .whitespaces), line: number))
            }
        }
        return out
    }

    /// `text` with the value on `line` (1-based, an ``Entry``'s) replaced by `value`, everything
    /// else on the line kept: `export`, the key, the spacing around `=`, and a trailing comment.
    /// A value that needs quoting — spaces, a `#`, a quote, a newline, or nothing at all when the
    /// old one was quoted — goes in double quotes with `\\` and `"` escaped (and `\n` for a newline);
    /// a plain value stays bare. The old line's quoting style is kept when it still fits.
    ///
    /// - Returns: The rewritten text, or `text` unchanged when `line` is not an entry.
    /// One entry's NAME rewritten in place, keeping `export`, the spacing around the `=` and
    /// everything after it (25 Sep 2026, David: "it's not possible to edit key in preview mode of
    /// .env"). The new name is taken as typed with the characters a `.env` name cannot hold
    /// removed — whitespace, `=` and `#` — and an empty result leaves the file alone, since a
    /// nameless entry is not something a table should be able to write.
    public static func replacingKey(in text: String, line: Int, with key: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard line >= 1, line <= lines.count else { return text }
        let old = lines[line - 1]
        let trimmed = old.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let eq = old.firstIndex(of: "="), !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return text }
        let clean = sanitisedKey(key)
        guard !clean.isEmpty else { return text }
        // The head is everything before the `=`: leading spaces, an `export`, the old name and
        // any spaces before the sign. Only the NAME inside it changes.
        let head = String(old[..<eq])
        let leading = head.prefix { $0 == " " || $0 == "\t" }
        var body = String(head.dropFirst(leading.count))
        let trailing = String(body.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())
        body = String(body.dropLast(trailing.count))
        var prefix = ""
        if body.hasPrefix("export "), body.count > 7 {
            let afterExport = body.dropFirst(7)
            prefix = "export " + String(afterExport.prefix { $0 == " " })
        }
        let tail = String(old[eq...])
        var rebuilt = String(leading)
        rebuilt += prefix
        rebuilt += clean
        rebuilt += trailing
        rebuilt += tail
        lines[line - 1] = rebuilt
        return lines.joined(separator: "\n")
    }

    /// `key` as a `.env` name: what the format cannot hold, removed.
    public static func sanitisedKey(_ key: String) -> String {
        String(key.filter { !$0.isWhitespace && $0 != "=" && $0 != "#" })
    }

    public static func replacingValue(in text: String, line: Int, with value: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard line >= 1, line <= lines.count else { return text }
        let old = lines[line - 1]
        let trimmed = old.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let eq = old.firstIndex(of: "="), !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return text }
        let head = String(old[...eq])
        var rest = String(old[old.index(after: eq)...])
        let leading = rest.prefix { $0 == " " }
        rest = String(rest.dropFirst(leading.count))
        var comment = ""
        var wasQuoted = false
        if rest.hasPrefix("\"") {
            wasQuoted = true
            if let close = closingDoubleQuote(in: rest) { comment = String(rest[rest.index(after: close)...]) }
        } else if rest.hasPrefix("'") {
            wasQuoted = true
            let body = rest.dropFirst()
            if let close = body.firstIndex(of: "'") { comment = String(body[body.index(after: close)...]) }
        } else if let hash = rest.range(of: " #") {
            comment = String(rest[hash.lowerBound...])
        }
        let needsQuotes = wasQuoted || value.isEmpty || value.contains(where: { $0 == " " || $0 == "#" || $0 == "\"" || $0 == "'" || $0 == "\n" || $0 == "\t" })
        let rendered = needsQuotes ? "\"" + escape(value) + "\"" : value
        lines[line - 1] = head + leading + rendered + comment
        return lines.joined(separator: "\n")
    }

    /// `\\`, `"` and the newline / tab escapes for a double-quoted value.
    private static func escape(_ s: String) -> String {
        var out = ""
        for c in s {
            switch c {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            default: out.append(c)
            }
        }
        return out
    }

    /// Whether a preview should show the value as ``mask`` until asked: the key names a
    /// secret (KEY, TOKEN, SECRET, PASSWORD, PASSWD, PWD, PRIVATE, CREDENTIAL(S), AUTH,
    /// SIGNATURE, SALT, DSN, as a word), or the value is a URL carrying `user:pass@`.
    public static func shouldMask(key: String, value: String) -> Bool {
        let words = key.uppercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if words.contains(where: { secretWords.contains($0) }) { return true }
        if let scheme = value.range(of: "://"), value[scheme.upperBound...].contains("@") {
            let authority = value[scheme.upperBound...].prefix { $0 != "/" && $0 != "?" }
            return authority.contains(":") && authority.contains("@")
        }
        return false
    }

    private static let secretWords: Set<String> = [
        "KEY", "TOKEN", "SECRET", "PASSWORD", "PASSWD", "PWD", "PRIVATE", "CREDENTIAL", "CREDENTIALS",
        "AUTH", "SIGNATURE", "SALT", "DSN", "APIKEY", "ACCESSKEY", "SECRETKEY",
    ]

    private static func isKey(_ key: String) -> Bool {
        guard let first = key.first, first.isLetter || first == "_" else { return false }
        return key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-" }
    }

    /// The index of the closing `"` of a value that opens with one, or nil.
    private static func closingDoubleQuote(in raw: String) -> String.Index? {
        var i = raw.index(after: raw.startIndex)
        while i < raw.endIndex {
            if raw[i] == "\\" { i = raw.index(i, offsetBy: 2, limitedBy: raw.endIndex) ?? raw.endIndex; continue }
            if raw[i] == "\"" { return i }
            i = raw.index(after: i)
        }
        return nil
    }

    /// The escapes dotenv resolves inside double quotes: `\n`, `\t`, `\r`, `\"`, `\\`, `\$`.
    private static func unescape(_ s: String) -> String {
        guard s.contains("\\") else { return s }
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            guard c == "\\", let e = it.next() else { out.append(c); continue }
            switch e {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            default: out.append(e)
            }
        }
        return out
    }
}
