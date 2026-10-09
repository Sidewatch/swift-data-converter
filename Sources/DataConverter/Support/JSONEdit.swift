//
//  JSONEdit.swift
//  DataConverter
//
//  Where one key or value sits in a JSON file, and how a typed replacement is written.
//
//  Created by David Sherlock on 9/25/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One key or value of a JSON file edited in place — what a cell edited in a JSON tree writes
/// back. `site(in:path:)` scans the text once and answers the raw token ranges of the member at
/// `path`, so the caller replaces only that range and the rest of the file keeps its formatting.
/// `encodedValue` writes a typed replacement the way the value's kind wants it. The scanner also
/// reads JSONC and JSON5 (`tsconfig.json`, `devcontainer.json`, `.json5`): comments are skipped,
/// a trailing comma closes its container, and a key may be bare or single-quoted.
public enum JSONEdit {
    /// One step of a path into the tree.
    public typealias PathComponent = StructuredEdit.PathComponent
    /// The kind of scalar a value was before the edit.
    public typealias ScalarKind = StructuredEdit.ScalarKind

    /// The raw token ranges of a member: its value, and its key when it is an object member.
    public struct Site: Equatable, Sendable {
        /// The key token, quotes included; nil for an array element.
        public let key: Range<String.Index>?
        /// The value token, quotes included for a string.
        public let value: Range<String.Index>
        /// Creates a site from its ranges.
        public init(key: Range<String.Index>?, value: Range<String.Index>) { self.key = key; self.value = value }
    }

    /// The member at `path`, or nil when the path is not in the document (or the text is not JSON).
    public static func site(in text: String, path: [PathComponent]) -> Site? {
        var scanner = Scanner(bytes: Array(text.utf8), target: path)
        _ = scanner.value(path: [])
        guard let hit = scanner.found else { return nil }
        func index(_ b: Int) -> String.Index { text.utf8.index(text.utf8.startIndex, offsetBy: b) }
        return Site(
            key: hit.key.map { index($0.lowerBound)..<index($0.upperBound) },
            value: index(hit.value.lowerBound)..<index(hit.value.upperBound))
    }

    /// `typed` as the JSON token that replaces a value of `kind`.
    public static func encodedValue(_ typed: String, kind: ScalarKind) -> String {
        let t = typed.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .string: return jsonString(typed)
        case .number: return isNumber(t) ? t : jsonString(typed)
        case .bool: return (t == "true" || t == "false") ? t : jsonString(typed)
        case .null: return t == "null" ? t : jsonString(typed)
        }
    }

    /// `key` as a JSON object key token.
    public static func encodedKey(_ key: String) -> String { jsonString(key) }

    /// A JSON string token: quoted, with the escapes JSON needs.
    public static func jsonString(_ s: String) -> String { StructuredEdit.doubleQuoted(s) }

    /// Whether `t` is a number token as RFC 8259 spells one.
    static func isNumber(_ t: String) -> Bool {
        t.range(of: "^-?(0|[1-9]\\d*)(\\.\\d+)?([eE][+-]?\\d+)?$", options: .regularExpression) != nil
    }

    // MARK: - The scanner

    /// A byte scanner that walks the document once, carrying the path, and stops at the target.
    private struct Scanner {
        let bytes: [UInt8]
        let target: [PathComponent]
        var pos = 0
        var found: (key: Range<Int>?, value: Range<Int>)?
        /// How many containers the scan is inside: a document nested past `maxDepth` is refused,
        /// the way the structure reader refuses it, instead of being followed down the stack.
        var depth = 0
        static let maxDepth = 256

        init(bytes: [UInt8], target: [PathComponent]) { self.bytes = bytes; self.target = target }

        /// Skips whitespace and comments, both `// line` and `/* block */`.
        mutating func skipSpace() {
            while pos < bytes.count {
                if [0x20, 0x09, 0x0A, 0x0D].contains(bytes[pos]) {
                    pos += 1
                } else if bytes[pos] == UInt8(ascii: "/"), pos + 1 < bytes.count, bytes[pos + 1] == UInt8(ascii: "/") {
                    while pos < bytes.count, bytes[pos] != 0x0A { pos += 1 }
                } else if bytes[pos] == UInt8(ascii: "/"), pos + 1 < bytes.count, bytes[pos + 1] == UInt8(ascii: "*") {
                    pos += 2
                    while pos + 1 < bytes.count, !(bytes[pos] == UInt8(ascii: "*") && bytes[pos + 1] == UInt8(ascii: "/")) { pos += 1 }
                    pos = min(pos + 2, bytes.count)
                } else {
                    return
                }
            }
        }

        /// Parses one value at `pos`; returns its byte range, or nil on malformed input.
        mutating func value(path: [PathComponent]) -> Range<Int>? {
            skipSpace()
            guard pos < bytes.count, found == nil else { return nil }
            let start = pos
            switch bytes[pos] {
            case UInt8(ascii: "{"): return object(path: path, start: start)
            case UInt8(ascii: "["): return array(path: path, start: start)
            case UInt8(ascii: "\""), UInt8(ascii: "'"): return string()
            case UInt8(ascii: "t"): return literal("true")
            case UInt8(ascii: "f"): return literal("false")
            case UInt8(ascii: "n"): return literal("null")
            default: return number()
            }
        }

        mutating func object(path: [PathComponent], start: Int) -> Range<Int>? {
            guard depth < Self.maxDepth else { return nil }
            depth += 1
            defer { depth -= 1 }
            pos += 1
            while true {
                skipSpace()
                guard pos < bytes.count else { return nil }
                if bytes[pos] == UInt8(ascii: "}") { pos += 1; return start..<pos }
                guard let keyRange = key() else { return nil }
                let key = decodedString(keyRange)
                skipSpace()
                guard pos < bytes.count, bytes[pos] == UInt8(ascii: ":") else { return nil }
                pos += 1
                let memberPath = path + [.key(key)]
                guard let valueRange = value(path: memberPath) else { return found == nil ? nil : start..<pos }
                if found == nil, memberPath == target { found = (keyRange, valueRange); return start..<pos }
                skipSpace()
                guard pos < bytes.count else { return nil }
                if bytes[pos] == UInt8(ascii: ",") { pos += 1; continue }
                if bytes[pos] == UInt8(ascii: "}") { pos += 1; return start..<pos }
                return nil
            }
        }

        mutating func array(path: [PathComponent], start: Int) -> Range<Int>? {
            guard depth < Self.maxDepth else { return nil }
            depth += 1
            defer { depth -= 1 }
            pos += 1
            var i = 0
            while true {
                skipSpace()
                guard pos < bytes.count else { return nil }
                if bytes[pos] == UInt8(ascii: "]") { pos += 1; return start..<pos }
                let elementPath = path + [.index(i)]
                guard let valueRange = value(path: elementPath) else { return found == nil ? nil : start..<pos }
                if found == nil, elementPath == target { found = (nil, valueRange); return start..<pos }
                i += 1
                skipSpace()
                guard pos < bytes.count else { return nil }
                if bytes[pos] == UInt8(ascii: ",") { pos += 1; continue }
                if bytes[pos] == UInt8(ascii: "]") { pos += 1; return start..<pos }
                return nil
            }
        }

        /// A key token: a string in either quote, or a JSON5 bare identifier.
        mutating func key() -> Range<Int>? {
            if bytes[pos] == UInt8(ascii: "\"") || bytes[pos] == UInt8(ascii: "'") { return string() }
            let start = pos
            while pos < bytes.count, Self.isIdentifierByte(bytes[pos]) { pos += 1 }
            return pos > start ? start..<pos : nil
        }

        /// A letter, digit, `_`, `$` or any byte of a non-ASCII character: what a bare key is made of.
        static func isIdentifierByte(_ b: UInt8) -> Bool {
            (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x5F || b == 0x24 || b >= 0x80
        }

        /// A string token at `pos` (the opening quote, double or single), quotes included.
        mutating func string() -> Range<Int>? {
            let start = pos
            let quote = bytes[pos]
            pos += 1
            while pos < bytes.count {
                let b = bytes[pos]
                if b == UInt8(ascii: "\\") { pos += 2; continue }
                pos += 1
                if b == quote { return start..<pos }
            }
            return nil
        }

        mutating func literal(_ word: String) -> Range<Int>? {
            let start = pos
            let w = Array(word.utf8)
            guard pos + w.count <= bytes.count, Array(bytes[pos..<pos + w.count]) == w else { return nil }
            pos += w.count
            return start..<pos
        }

        /// A number token; JSON5's hex, `Infinity` and `NaN` are letters, so letters are taken too.
        mutating func number() -> Range<Int>? {
            let start = pos
            while pos < bytes.count, Self.isIdentifierByte(bytes[pos]) || "+-.".utf8.contains(bytes[pos]) { pos += 1 }
            return pos > start ? start..<pos : nil
        }

        /// The key a token spells, its escapes undone. A bare key spells itself; a single-quoted
        /// one is read as the double-quoted string it means.
        func decodedString(_ r: Range<Int>) -> String {
            guard bytes[r.lowerBound] == UInt8(ascii: "\"") || bytes[r.lowerBound] == UInt8(ascii: "'") else {
                return String(decoding: bytes[r], as: UTF8.self)
            }
            var raw = Data(bytes[r])
            if bytes[r.lowerBound] == UInt8(ascii: "'") {
                let inner = String(decoding: bytes[(r.lowerBound + 1)..<(r.upperBound - 1)], as: UTF8.self)
                raw = Data(
                    ("\"" + inner.replacingOccurrences(of: "\\'", with: "'").replacingOccurrences(of: "\"", with: "\\\"") + "\"").utf8)
            }
            if let s = try? JSONSerialization.jsonObject(with: raw, options: .fragmentsAllowed) as? String { return s }
            return String(decoding: bytes[(r.lowerBound + 1)..<(r.upperBound - 1)], as: UTF8.self)
        }
    }
}
