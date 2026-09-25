//
//  JSONStructure.swift
//  DataConverter
//
//  JSON read as ordered structure: the file's key order kept, scalars keeping their type.
//
//  Created by David Sherlock on 9/26/26.
//

import Foundation

/// JSON read into `StructuredValue`, **in the file's own key order**.
///
/// `JSONSerialization` hands back a `[String: Any]`, which has no order at all — so a tree built
/// from it must either sort the keys or show them in whatever order the hash gave. A config file's
/// order is the author's, and a record's order is the writer's, so this reads the text directly
/// and keeps it. Scalars keep the type JSON gives them: an integer stays an integer, `1.5` a
/// number, `true` a boolean, `null` null.
///
/// It is deliberately strict about structure and lenient about nothing: a document that does not
/// parse returns nil rather than a partial tree, because half a record shown as fact is worse
/// than no record.
public enum JSONStructure {
    /// The document as ordered structure, or nil if it is not one JSON value.
    public static func value(of text: String) -> StructuredValue? {
        var parser = Parser(bytes: Array(text.utf8))
        guard let value = parser.parseValue() else { return nil }
        parser.skipWhitespace()
        return parser.atEnd ? value : nil
    }

    // MARK: - Parser

    private struct Parser {
        let bytes: [UInt8]
        var i = 0
        init(bytes: [UInt8]) { self.bytes = bytes }

        var atEnd: Bool { i >= bytes.count }
        private var current: UInt8? { i < bytes.count ? bytes[i] : nil }

        mutating func skipWhitespace() {
            while let c = current, c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { i += 1 }
        }

        /// Depth is bounded so a pathological document cannot exhaust the stack.
        mutating func parseValue(depth: Int = 0) -> StructuredValue? {
            guard depth < 256 else { return nil }
            skipWhitespace()
            switch current {
            case UInt8(ascii: "{"): return parseObject(depth: depth)
            case UInt8(ascii: "["): return parseArray(depth: depth)
            case UInt8(ascii: "\""): return parseString().map { .string($0) }
            case UInt8(ascii: "t"): return literal("true") ? .bool(true) : nil
            case UInt8(ascii: "f"): return literal("false") ? .bool(false) : nil
            case UInt8(ascii: "n"): return literal("null") ? StructuredValue.null : nil
            default: return parseNumber()
            }
        }

        private mutating func literal(_ word: String) -> Bool {
            let w = Array(word.utf8)
            guard i + w.count <= bytes.count, Array(bytes[i..<(i + w.count)]) == w else { return false }
            i += w.count
            return true
        }

        private mutating func parseObject(depth: Int) -> StructuredValue? {
            i += 1                                     // {
            var pairs: [StructuredPair] = []
            skipWhitespace()
            if current == UInt8(ascii: "}") { i += 1; return .mapping(pairs) }
            while true {
                skipWhitespace()
                guard current == UInt8(ascii: "\""), let key = parseString() else { return nil }
                skipWhitespace()
                guard current == UInt8(ascii: ":") else { return nil }
                i += 1
                guard let value = parseValue(depth: depth + 1) else { return nil }
                pairs.append(StructuredPair(key: key, value: value))
                skipWhitespace()
                switch current {
                case UInt8(ascii: ","): i += 1
                case UInt8(ascii: "}"): i += 1; return .mapping(pairs)
                default: return nil
                }
            }
        }

        private mutating func parseArray(depth: Int) -> StructuredValue? {
            i += 1                                     // [
            var items: [StructuredValue] = []
            skipWhitespace()
            if current == UInt8(ascii: "]") { i += 1; return .sequence(items) }
            while true {
                guard let value = parseValue(depth: depth + 1) else { return nil }
                items.append(value)
                skipWhitespace()
                switch current {
                case UInt8(ascii: ","): i += 1
                case UInt8(ascii: "]"): i += 1; return .sequence(items)
                default: return nil
                }
            }
        }

        /// A JSON string with its escapes resolved, including surrogate pairs — the tree shows the
        /// TEXT, so `A` must read as `A` and an emoji written as a pair must survive.
        private mutating func parseString() -> String? {
            i += 1                                     // opening quote
            var scalars = String.UnicodeScalarView()
            var pendingHigh: UInt32?

            func flushHigh() {
                if let high = pendingHigh, let s = Unicode.Scalar(high) { scalars.append(s) }
                pendingHigh = nil
            }

            while let c = current {
                if c == UInt8(ascii: "\"") {
                    i += 1
                    flushHigh()
                    return String(scalars)
                }
                if c == UInt8(ascii: "\\") {
                    i += 1
                    guard let e = current else { return nil }
                    i += 1
                    switch e {
                    case UInt8(ascii: "\""): flushHigh(); scalars.append("\"")
                    case UInt8(ascii: "\\"): flushHigh(); scalars.append("\\")
                    case UInt8(ascii: "/"):  flushHigh(); scalars.append("/")
                    case UInt8(ascii: "b"):  flushHigh(); scalars.append(Unicode.Scalar(8))
                    case UInt8(ascii: "f"):  flushHigh(); scalars.append(Unicode.Scalar(12))
                    case UInt8(ascii: "n"):  flushHigh(); scalars.append("\n")
                    case UInt8(ascii: "r"):  flushHigh(); scalars.append("\r")
                    case UInt8(ascii: "t"):  flushHigh(); scalars.append("\t")
                    case UInt8(ascii: "u"):
                        guard let code = hex4() else { return nil }
                        if let high = pendingHigh {
                            if code >= 0xDC00, code <= 0xDFFF {
                                let combined = 0x10000 + ((high - 0xD800) << 10) + (code - 0xDC00)
                                pendingHigh = nil
                                if let s = Unicode.Scalar(combined) { scalars.append(s) }
                            } else {
                                flushHigh()
                                if code >= 0xD800, code <= 0xDBFF { pendingHigh = code }
                                else if let s = Unicode.Scalar(code) { scalars.append(s) }
                            }
                        } else if code >= 0xD800, code <= 0xDBFF {
                            pendingHigh = code
                        } else if let s = Unicode.Scalar(code) {
                            scalars.append(s)
                        } else {
                            return nil
                        }
                    default: return nil
                    }
                    continue
                }
                flushHigh()
                // Copy the raw UTF-8 run up to the next quote or backslash in one go.
                let start = i
                while let c = current, c != UInt8(ascii: "\""), c != UInt8(ascii: "\\") { i += 1 }
                guard let run = String(bytes: bytes[start..<i], encoding: .utf8) else { return nil }
                scalars.append(contentsOf: run.unicodeScalars)
            }
            return nil                                  // unterminated
        }

        private mutating func hex4() -> UInt32? {
            guard i + 4 <= bytes.count else { return nil }
            var value: UInt32 = 0
            for _ in 0..<4 {
                guard let digit = current.flatMap(Self.hexDigit) else { return nil }
                value = value << 4 | UInt32(digit)
                i += 1
            }
            return value
        }

        private static func hexDigit(_ c: UInt8) -> UInt8? {
            switch c {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): return c - UInt8(ascii: "A") + 10
            default: return nil
            }
        }

        /// An integer stays an integer; anything with a fraction or an exponent, or too big for
        /// `Int`, is a number. The tree shows the difference and the encoders keep it.
        private mutating func parseNumber() -> StructuredValue? {
            let start = i
            if current == UInt8(ascii: "-") { i += 1 }
            var isInteger = true
            while let c = current {
                if c >= UInt8(ascii: "0"), c <= UInt8(ascii: "9") { i += 1 }
                else if c == UInt8(ascii: ".") || c == UInt8(ascii: "e") || c == UInt8(ascii: "E")
                            || c == UInt8(ascii: "+") || c == UInt8(ascii: "-") { isInteger = false; i += 1 }
                else { break }
            }
            guard i > start, let text = String(bytes: bytes[start..<i], encoding: .utf8) else { return nil }
            if isInteger, let n = Int(text) { return .integer(n) }
            guard let d = Double(text) else { return nil }
            return .number(d)
        }
    }
}
