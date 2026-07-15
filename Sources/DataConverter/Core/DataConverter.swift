//
//  DataConverter.swift
//  SwiftDataConverter
//
//  Dependency-free data-format conversion through a JSON value hub.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

/// Dependency-free data-format conversion via a JSON value hub. Input JSON or CSV,
/// output pretty JSON / YAML / TOML / CSV. (YAML/TOML are emit-only — parsing them
/// back would need a real library.)
public enum DataConverter {
    /// Convert `input` from one text format to another, routing through a JSON value hub.
    ///
    /// - Parameters:
    ///   - input: The source text.
    ///   - from: The input format — `"CSV"` uses the CSV parser; anything else is parsed as JSON.
    ///   - to: The output format — `"YAML"`, `"TOML"`, or `"CSV"`; anything else emits pretty-printed,
    ///     key-sorted JSON.
    /// - Returns: The converted text, or a human-readable `"⚠︎ …"` message when the input can't be
    ///   parsed or the value's shape doesn't fit the target (e.g. TOML needs a top-level object).
    /// - Note: Never throws — errors come back as `"⚠︎"`-prefixed strings, so callers showing the
    ///   result verbatim (a converter UI) need no error path.
    public static func convert(_ input: String, from: String, to: String) -> String {
        let value: Any?
        switch from {
        case "CSV":  value = parseCSV(input)
        default:     value = (try? JSONSerialization.jsonObject(with: Data(input.utf8), options: [.fragmentsAllowed]))
        }
        guard let value else { return "⚠︎ Couldn't parse the input as \(from)." }
        switch to {
        case "YAML": return yaml(value)
        case "TOML": return (value as? [String: Any]).map { toml($0, path: []) } ?? "⚠︎ TOML needs a top-level object."
        case "CSV":  return csv(value)
        default:
            guard let d = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) else { return "⚠︎ Not serializable." }
            return String(data: d, encoding: .utf8) ?? ""
        }
    }

    /// True when the value is a JSON container (object or array).
    private static func isContainer(_ v: Any) -> Bool { v is [String: Any] || v is [Any] }

    // MARK: - YAML (emit)

    /// Emit a JSON value as block-style YAML, sorted keys, two-space indent per level.
    private static func yaml(_ v: Any, _ indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        if let d = v as? [String: Any] {
            if d.isEmpty { return "\(pad){}" }
            return d.keys.sorted().map { k in
                let val = d[k] ?? NSNull()
                return isContainer(val) && !isEmptyContainer(val)
                    ? "\(pad)\(scalar(k)):\n\(yaml(val, indent + 1))"
                    : "\(pad)\(scalar(k)): \(scalar(val))"
            }.joined(separator: "\n")
        }
        if let a = v as? [Any] {
            if a.isEmpty { return "\(pad)[]" }
            return a.map { val in
                isContainer(val) && !isEmptyContainer(val)
                    ? "\(pad)-\n\(yaml(val, indent + 1))"
                    : "\(pad)- \(scalar(val))"
            }.joined(separator: "\n")
        }
        return "\(pad)\(scalar(v))"
    }
    /// True for an empty object or array — emitted inline as `{}` / `[]` instead of a nested block.
    private static func isEmptyContainer(_ v: Any) -> Bool {
        (v as? [String: Any])?.isEmpty == true || (v as? [Any])?.isEmpty == true
    }
    /// Render one YAML scalar: bools/numbers/null as bare lexemes, strings quoted only when needed.
    private static func scalar(_ v: Any) -> String {
        if v is NSNull { return "null" }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return "\(n)"
        }
        if let s = v as? String {
            return yamlNeedsQuote(s) ? "\"\(escapeDQ(s))\"" : s
        }
        if isContainer(v) { return v is [Any] ? "[]" : "{}" }
        return "\(v)"
    }
    /// True when a bare YAML scalar would be misparsed: structural/escape characters,
    /// leading/trailing space, a leading indicator, a type lexeme (true/null/yes/…), or a number.
    private static func yamlNeedsQuote(_ s: String) -> Bool {
        if s.isEmpty || s.first == " " || s.last == " " { return true }
        if s.contains(where: { ":#{}[],&*\n\t\r\\\"".contains($0) }) { return true }
        if let f = s.first, "-?!|>'%@`".contains(f) { return true }
        if ["true", "false", "null", "~", "yes", "no", "on", "off"].contains(s.lowercased()) { return true }
        if Double(s) != nil { return true }
        return false
    }

    // MARK: - TOML (emit)

    /// Emit a dictionary as TOML: scalar keys first, then nested objects as `[a.b]` tables and
    /// arrays-of-objects as `[[a.b]]` array-of-tables, recursing with the dotted key path.
    private static func toml(_ dict: [String: Any], path: [String]) -> String {
        var scalars = "", subs = ""
        for k in dict.keys.sorted() {
            let val = dict[k] ?? NSNull()
            if let d = val as? [String: Any] {
                let p = path + [k]
                subs += "\n[\(p.map(tomlKey).joined(separator: "."))]\n" + toml(d, path: p)
            } else if let a = val as? [Any], !a.isEmpty, a.allSatisfy({ $0 is [String: Any] }) {
                let p = path + [k]
                for item in a { if let d = item as? [String: Any] { subs += "\n[[\(p.map(tomlKey).joined(separator: "."))]]\n" + toml(d, path: p) } }
            } else {
                scalars += "\(tomlKey(k)) = \(tomlValue(val))\n"
            }
        }
        return scalars + subs
    }
    /// Render one TOML value: quoted string, bool/number lexeme, inline array, or inline table.
    /// TOML has no null, so `NSNull` degrades to an empty string.
    private static func tomlValue(_ v: Any) -> String {
        if v is NSNull { return "\"\"" }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return "\(n)"
        }
        if let s = v as? String { return "\"\(escapeDQ(s))\"" }
        if let a = v as? [Any] { return "[" + a.map(tomlValue).joined(separator: ", ") + "]" }
        if let d = v as? [String: Any] {
            if d.isEmpty { return "{}" }
            return "{ " + d.keys.sorted().map { "\(tomlKey($0)) = \(tomlValue(d[$0] ?? NSNull()))" }.joined(separator: ", ") + " }"
        }
        return "\"\(escapeDQ("\(v)"))\""
    }
    /// Quote a TOML key unless it's a valid bare key ([A-Za-z0-9_-]+).
    private static func tomlKey(_ k: String) -> String {
        let bare = !k.isEmpty && k.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
        return bare ? k : "\"\(escapeDQ(k))\""
    }

    /// Escape a string for a YAML/TOML double-quoted scalar (backslash first);
    /// C0 control characters that lack a short escape become \uXXXX.
    private static func escapeDQ(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            switch u {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04X", u.value) }
                else { out.unicodeScalars.append(u) }
            }
        }
        return out
    }

    // MARK: - CSV

    /// Emit an array of objects as CSV: header = union of all keys (first-seen order, keys sorted
    /// per object), one row per object, missing keys as empty cells.
    private static func csv(_ v: Any) -> String {
        guard let arr = v as? [Any] else { return "⚠︎ CSV output needs a JSON array of objects." }
        let objs = arr.compactMap { $0 as? [String: Any] }
        guard !objs.isEmpty, objs.count == arr.count else { return "⚠︎ CSV output needs an array of objects." }
        var keys: [String] = []
        for o in objs { for k in o.keys.sorted() where !keys.contains(k) { keys.append(k) } }
        var rows = [keys.map(esc).joined(separator: ",")]
        for o in objs {
            rows.append(keys.map { esc(cell(o[$0])) }.joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }
    /// Render one CSV cell value: null/missing → empty, bool/number lexemes, nested containers as
    /// compact JSON.
    private static func cell(_ v: Any?) -> String {
        guard let v, !(v is NSNull) else { return "" }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return "\(n)"
        }
        if isContainer(v) {
            guard let d = try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys]),
                  let s = String(data: d, encoding: .utf8) else { return "" }
            return s
        }
        return "\(v)"
    }
    /// RFC-4180 field quoting: wrap in quotes (doubling embedded quotes) only when the cell
    /// contains a comma, quote, or line break.
    private static func esc(_ s: String) -> String {
        (s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r")) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    /// Parse CSV text into one dictionary per data row, keyed by the header row.
    ///
    /// Repeated header names are de-duplicated (`name`, `name_2`, …); rows shorter than the header
    /// are padded with empty strings. All values are `String`s.
    ///
    /// - Returns: The row objects, or `[]` when there is no data row after the header.
    public static func parseCSV(_ text: String) -> [[String: Any]] {
        let records = csvRecords(text)
        guard records.count > 1 else { return [] }
        var headers: [String] = [], seen: [String: Int] = [:]
        for h in records[0] {                     // de-dupe repeated headers: name, name_2, …
            let n = (seen[h] ?? 0) + 1
            seen[h] = n
            headers.append(n == 1 ? h : "\(h)_\(n)")
        }
        return records.dropFirst().map { cells in
            var d: [String: Any] = [:]
            for (i, h) in headers.enumerated() { d[h] = i < cells.count ? cells[i] : "" }
            return d
        }
    }

    /// Tokenize CSV text into records of raw fields, header row included.
    ///
    /// Quote-aware: a newline only ends a record when NOT inside quotes, so multiline quoted
    /// fields survive; doubled quotes (`""`) unescape to one quote. LF, CRLF, and bare CR all
    /// end a record. Reusable on its own (e.g. to drive a table view without header mapping).
    public static func csvRecords(_ text: String) -> [[String]] {
        var records: [[String]] = [], row: [String] = [], field = "", inQuotes = false
        let chars = Array(text)
        var i = 0
        func endField() { row.append(field); field = "" }
        func endRow() { endField(); records.append(row); row = [] }
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": endField()
                case "\r\n", "\r", "\n": endRow()   // CRLF is a single grapheme Character; bare CR also ends a row
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { endRow() }   // flush a final row with no trailing newline
        return records
    }
}
