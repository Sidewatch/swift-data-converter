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

    private static func isContainer(_ v: Any) -> Bool { v is [String: Any] || v is [Any] }

    // MARK: - YAML (emit)

    private static func yaml(_ v: Any, _ indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        if let d = v as? [String: Any] {
            if d.isEmpty { return "\(pad){}" }
            return d.keys.sorted().map { k in
                let val = d[k] ?? NSNull()
                return isContainer(val) && !isEmptyContainer(val)
                    ? "\(pad)\(k):\n\(yaml(val, indent + 1))"
                    : "\(pad)\(k): \(scalar(val))"
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
    private static func isEmptyContainer(_ v: Any) -> Bool {
        (v as? [String: Any])?.isEmpty == true || (v as? [Any])?.isEmpty == true
    }
    private static func scalar(_ v: Any) -> String {
        if v is NSNull { return "null" }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return "\(n)"
        }
        if let s = v as? String {
            let needsQuote = s.isEmpty || s.contains(where: { ":#{}[],&*\n\t\\\"".contains($0) }) || s.first == " " || s.last == " "
            return needsQuote ? "\"\(escapeDQ(s))\"" : s
        }
        if isContainer(v) { return v is [Any] ? "[]" : "{}" }
        return "\(v)"
    }

    // MARK: - TOML (emit)

    private static func toml(_ dict: [String: Any], path: [String]) -> String {
        var scalars = "", subs = ""
        for k in dict.keys.sorted() {
            let val = dict[k] ?? NSNull()
            if let d = val as? [String: Any] {
                let p = path + [k]
                subs += "\n[\(p.joined(separator: "."))]\n" + toml(d, path: p)
            } else if let a = val as? [Any], !a.isEmpty, a.allSatisfy({ $0 is [String: Any] }) {
                let p = path + [k]
                for item in a { if let d = item as? [String: Any] { subs += "\n[[\(p.joined(separator: "."))]]\n" + toml(d, path: p) } }
            } else {
                scalars += "\(k) = \(tomlValue(val))\n"
            }
        }
        return scalars + subs
    }
    private static func tomlValue(_ v: Any) -> String {
        if v is NSNull { return "\"\"" }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return "\(n)"
        }
        if let s = v as? String { return "\"\(escapeDQ(s))\"" }
        if let a = v as? [Any] { return "[" + a.map(tomlValue).joined(separator: ", ") + "]" }
        return "\"\(v)\""
    }

    /// Escape a string for a YAML/TOML double-quoted scalar (backslash first).
    private static func escapeDQ(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\t", with: "\\t")
    }

    // MARK: - CSV

    private static func csv(_ v: Any) -> String {
        guard let arr = v as? [Any] else { return "⚠︎ CSV output needs a JSON array of objects." }
        let objs = arr.compactMap { $0 as? [String: Any] }
        guard !objs.isEmpty else { return "⚠︎ CSV output needs an array of objects." }
        var keys: [String] = []
        for o in objs { for k in o.keys.sorted() where !keys.contains(k) { keys.append(k) } }
        var rows = [keys.map(esc).joined(separator: ",")]
        for o in objs {
            rows.append(keys.map { esc(cell(o[$0])) }.joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }
    private static func cell(_ v: Any?) -> String {
        guard let v, !(v is NSNull) else { return "" }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return "\(n)"
        }
        return "\(v)"
    }
    private static func esc(_ s: String) -> String {
        (s.contains(",") || s.contains("\"") || s.contains("\n")) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    public static func parseCSV(_ text: String) -> [[String: Any]] {
        let records = csvRecords(text)
        guard records.count > 1 else { return [] }
        let headers = records[0]
        return records.dropFirst().map { cells in
            var d: [String: Any] = [:]
            for (i, h) in headers.enumerated() { d[h] = i < cells.count ? cells[i] : "" }
            return d
        }
    }

    /// Quote-aware tokenizer: a newline only ends a record when NOT inside quotes,
    /// so multiline quoted fields survive. Normalizes CR/CRLF. Shared with the CSV preview table.
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
                case "\r": break          // swallow CR; the paired LF (or EOF) ends the row
                case "\n": endRow()
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { endRow() }   // flush a final row with no trailing newline
        return records
    }
}
