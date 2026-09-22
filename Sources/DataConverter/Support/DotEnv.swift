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
