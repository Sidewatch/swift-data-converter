//
//  StringsStructure.swift
//  DataConverter
//
//  A .strings file as ordered structure, and where each key and value sits.
//
//  Created by David Sherlock on 9/25/26.
//

import Foundation

/// A `.strings` file — `"key" = "value";` with `/* */` and `//` comments — as the structure a
/// tree shows, and the site of any key or value in it (25 Sep 2026). Keys may be bare
/// identifiers (the old-style plist syntax); `"key";` alone means the value is the key;
/// escapes are `\" \\ \n \t \r \0` and `\UXXXX` / `\uXXXX`. Every value is a string. A compiled
/// `.strings` (a binary plist, what Xcode ships in a bundle) is not text — read it with
/// `PropertyListStructure`.
public enum StringsStructure {
    public typealias PathComponent = StructuredEdit.PathComponent
    public typealias EditSite = StructuredEdit.EditSite

    // MARK: - Reading

    /// The file as a mapping in file order, or nil when it holds no entry.
    public static func value(of text: String) -> StructuredValue? {
        let entries = parse(text)
        guard !entries.isEmpty else { return nil }
        return .mapping(entries.map { StructuredPair(key: $0.key, value: .string($0.value)) })
    }

    // MARK: - Editing

    /// Where the member at `[key]` sits: the key token and the value token, quotes included.
    public static func site(in text: String, path: [PathComponent]) -> EditSite? {
        guard path.count == 1, case .key(let key) = path[0], let entry = parse(text).first(where: { $0.key == key }) else { return nil }
        return EditSite(key: entry.keyRange, value: entry.valueRange ?? NSRange(location: NSMaxRange(entry.keyRange), length: 0))
    }

    /// The one edit a typed key or value means; a `"key";` shorthand gains ` = "value"`.
    public static func replacement(in text: String, path: [PathComponent], key: Bool, with typed: String) -> (range: NSRange, replacement: String)? {
        guard path.count == 1, case .key(let name) = path[0], let entry = parse(text).first(where: { $0.key == name }) else { return nil }
        if key { return (entry.keyRange, encoded(typed)) }
        guard let valueRange = entry.valueRange else { return (NSRange(location: NSMaxRange(entry.keyRange), length: 0), " = " + encoded(typed)) }
        return (valueRange, encoded(typed))
    }

    /// `s` as a quoted, escaped token.
    public static func encoded(_ s: String) -> String {
        var out = "\""
        for c in s {
            switch c {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n", "\r\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.append(c)
            }
        }
        return out + "\""
    }

    // MARK: - Parsing

    struct Entry { let key: String, keyRange: NSRange, value: String, valueRange: NSRange? }

    static func parse(_ text: String) -> [Entry] {
        let chars = Array(text.utf16)
        var entries: [Entry] = []
        var i = 0
        func skipSpaceAndComments() {
            while i < chars.count {
                let c = chars[i]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { i += 1; continue }
                if c == 0x2F, i + 1 < chars.count, chars[i + 1] == 0x2A {   // /*
                    i += 2
                    while i + 1 < chars.count, !(chars[i] == 0x2A && chars[i + 1] == 0x2F) { i += 1 }
                    i = min(chars.count, i + 2); continue
                }
                if c == 0x2F, i + 1 < chars.count, chars[i + 1] == 0x2F {   // //
                    while i < chars.count, chars[i] != 0x0A { i += 1 }
                    continue
                }
                break
            }
        }
        /// A `"…"` token or a bare identifier starting at `i`; nil when neither is here.
        func token() -> (text: String, range: NSRange)? {
            guard i < chars.count else { return nil }
            let start = i
            if chars[i] == 0x22 {
                i += 1
                var raw = ""
                while i < chars.count, chars[i] != 0x22 {
                    if chars[i] == 0x5C, i + 1 < chars.count { raw.append(Character(Unicode.Scalar(chars[i])!)); i += 1 }
                    raw += String(utf16CodeUnits: [chars[i]], count: 1); i += 1
                }
                i = min(chars.count, i + 1)
                return (unescaped(raw), NSRange(location: start, length: i - start))
            }
            while i < chars.count, isBare(chars[i]) { i += 1 }
            guard i > start else { return nil }
            return (String(utf16CodeUnits: Array(chars[start..<i]), count: i - start), NSRange(location: start, length: i - start))
        }
        while i < chars.count {
            skipSpaceAndComments()
            guard let key = token() else { i += 1; continue }
            skipSpaceAndComments()
            var value: (text: String, range: NSRange)?
            if i < chars.count, chars[i] == 0x3D {   // =
                i += 1; skipSpaceAndComments()
                value = token()
            }
            skipSpaceAndComments()
            if i < chars.count, chars[i] == 0x3B { i += 1 }   // ;
            entries.append(Entry(key: key.text, keyRange: key.range, value: value?.text ?? key.text, valueRange: value?.range))
        }
        return entries
    }

    private static func isBare(_ c: UInt16) -> Bool {
        (0x30...0x39).contains(c) || (0x41...0x5A).contains(c) || (0x61...0x7A).contains(c) || c == 0x5F || c == 0x2E || c == 0x2D || c == 0x2F || c == 0x24
    }

    /// The escapes resolved: `\" \\ \n \t \r \0 \a \b \f \v`, `\UXXXX` and `\uXXXX`.
    static func unescaped(_ s: String) -> String {
        guard s.contains("\\") else { return s }
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            guard c == "\\", let e = it.next() else { out.append(c); continue }
            switch e {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            case "0": out.append("\0")
            case "a": out.append("\u{07}")
            case "b": out.append("\u{08}")
            case "f": out.append("\u{0C}")
            case "v": out.append("\u{0B}")
            case "U", "u":
                var hex = ""
                for _ in 0..<4 { if let h = it.next() { hex.append(h) } }
                if let v = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(v) { out.unicodeScalars.append(scalar) } else { out += "\\\(e)" + hex }
            default: out.append(e)
            }
        }
        return out
    }
}
