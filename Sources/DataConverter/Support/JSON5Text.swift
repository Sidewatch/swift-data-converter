//
//  JSON5Text.swift
//  DataConverter
//
//  JSON5 that Foundation's JSON5 reader rejects (escapes, hex and out-of-range numbers), rewritten
//  so it reads.
//
//  Created by David Sherlock on 10/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The JSON5 `JSONSerialization`'s `.json5Allowed` reader rejects, rewritten so it reads the
/// document. Strings: that reader knows only JSON's escapes and line continuations, so `\v` → `\u000B`, `\xHH` → `\u00HH`, and any other escaped character stands for itself
/// (`\a` → `a`). `\0` and `\x00` become `␀` (U+2400): Foundation refuses a NUL in a string, and a
/// viewer is better served by the symbol than by the whole document failing. Comments are skipped,
/// so a quote inside one opens no string. Numbers: a hexadecimal one past `Int64` is written in
/// decimal (`0xFFFFFFFFFFFFFFFF`), and one past `Double`'s range as `Infinity` (`1E400`), which the
/// reader otherwise fails on as a whole.
public enum JSON5Text {
    /// `text` rewritten for `JSONSerialization`'s JSON5 reader; unchanged when it needs nothing.
    public static func foundationReadable(_ text: String) -> String {
        let units = Array(text.utf16)
        var out: [UInt16] = []
        out.reserveCapacity(units.count + 16)
        var i = 0
        var quote: UInt16?
        while i < units.count {
            let c = units[i]
            if let q = quote {
                if c == q {
                    quote = nil
                } else if c == backslash, i + 1 < units.count {
                    i += 1
                    out += escape(units, at: &i)
                    continue
                }
                out.append(c)
                i += 1
            } else if c == slash, i + 1 < units.count, units[i + 1] == slash || units[i + 1] == star {
                i = copyComment(units, from: i, into: &out)
            } else if isNumberStart(c), i == 0 || !isWordUnit(units[i - 1]) {
                i = copyNumber(units, from: i, into: &out)
            } else {
                if c == doubleQuote || c == singleQuote { quote = c }
                out.append(c)
                i += 1
            }
        }
        return String(utf16CodeUnits: out, count: out.count)
    }

    /// The JSON spelling of the escape whose letter is at `i`; leaves `i` after it.
    private static func escape(_ units: [UInt16], at i: inout Int) -> [UInt16] {
        let c = units[i]
        i += 1
        switch c {
        case unit("v"): return Array("\\u000B".utf16)
        case unit("0") where !(i < units.count && isDigit(units[i])): return Array("\\u2400".utf16)
        case unit("x") where i + 1 < units.count && isHex(units[i]) && isHex(units[i + 1]):
            defer { i += 2 }
            if units[i] == unit("0"), units[i + 1] == unit("0") { return Array("\\u2400".utf16) }
            return Array("\\u00".utf16) + [units[i], units[i + 1]]
        case doubleQuote, singleQuote, backslash, slash, 0x0A, 0x0D, 0x2028, 0x2029:
            return [backslash, c]
        case unit("b"), unit("f"), unit("n"), unit("r"), unit("t"),
            unit("u"):
            return [backslash, c]
        default:
            return [c]  // an identity escape
        }
    }

    /// Copies the number token starting at `start` (a sign, digits, letters, dots), written so the
    /// reader can hold it; returns the index after it.
    private static func copyNumber(_ units: [UInt16], from start: Int, into out: inout [UInt16]) -> Int {
        var i = start + 1
        while i < units.count, isWordUnit(units[i]) || ((units[i] == unit("+") || units[i] == unit("-")) && isExponent(units[i - 1])) {
            i += 1
        }
        let token = String(utf16CodeUnits: Array(units[start..<i]), count: i - start)
        out += Array(readable(token).utf16)
        return i
    }

    /// A number token as the reader can hold it: an out-of-range hexadecimal in decimal, an
    /// out-of-range decimal as a signed `Infinity`; anything else as written.
    private static func readable(_ token: String) -> String {
        let negative = token.hasPrefix("-")
        let unsigned = token.hasPrefix("-") || token.hasPrefix("+") ? token.dropFirst() : token[...]
        if unsigned.lowercased().hasPrefix("0x") {
            let digits = unsigned.dropFirst(2)
            guard Int64(digits, radix: 16) == nil, !digits.isEmpty, digits.allSatisfy(\.isHexDigit) else { return token }
            let magnitude =
                UInt64(digits, radix: 16).map(String.init) ?? String(digits.reduce(0.0) { $0 * 16 + Double($1.hexDigitValue ?? 0) })
            return (negative ? "-" : "") + magnitude
        }
        guard let value = Double(unsigned), value.isInfinite else { return token }
        return (negative ? "-" : "") + "Infinity"
    }

    private static func isNumberStart(_ c: UInt16) -> Bool { isDigit(c) || c == unit(".") || c == unit("+") || c == unit("-") }
    private static func isExponent(_ c: UInt16) -> Bool { c == unit("e") || c == unit("E") }
    /// A letter, digit, `.`, `_` or `$`: what a number token (or an identifier) is made of.
    private static func isWordUnit(_ c: UInt16) -> Bool {
        isDigit(c) || (c | 0x20 >= 0x61 && c | 0x20 <= 0x7A) || c == unit(".") || c == unit("_") || c == unit("$") || c >= 0x80
    }

    /// Copies the `//` or `/* */` comment starting at `start`; returns the index after it.
    private static func copyComment(_ units: [UInt16], from start: Int, into out: inout [UInt16]) -> Int {
        let block = units[start + 1] == star
        var i = start + 2
        while i < units.count {
            if block, units[i] == star, i + 1 < units.count, units[i + 1] == slash {
                i += 2
                break
            }
            if !block, units[i] == 0x0A { break }
            i += 1
        }
        out += units[start..<i]
        return i
    }

    private static func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }
    private static func isHex(_ c: UInt16) -> Bool { isDigit(c) || (c | 0x20 >= 0x61 && c | 0x20 <= 0x66) }

    private static func unit(_ scalar: Unicode.Scalar) -> UInt16 { UInt16(scalar.value) }

    private static let backslash = unit("\\")
    private static let slash = unit("/")
    private static let star = unit("*")
    private static let doubleQuote = unit("\"")
    private static let singleQuote = unit("'")
}
