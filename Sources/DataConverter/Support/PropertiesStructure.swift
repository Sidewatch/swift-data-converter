//
//  PropertiesStructure.swift
//  DataConverter
//
//  A Java .properties file as ordered structure, and where each key and value sits.
//
//  Created by David Sherlock on 9/25/26.
//

import Foundation

/// A `.properties` file as the structure a tree shows, and the site of any key or value in it
/// (25 Sep 2026), by `java.util.Properties`' own rules: a logical line spans physical lines
/// while it ends in an odd run of backslashes (the next line's leading whitespace dropped); `#`
/// and `!` open a comment line; the key runs to the first unescaped `=`, `:` or whitespace, an
/// optional separator follows, the rest is the value; `\t \n \f \r \\ \uXXXX` are escapes and
/// `\X` is `X` for any other character (so `\=` and `\ ` are literal). A value is typed for the
/// tree the way INI's is (`25`, `1.5`, `true`), else a string. Keys are listed in file order,
/// duplicates included; a path finds the first.
public enum PropertiesStructure {
    public typealias PathComponent = StructuredEdit.PathComponent
    public typealias EditSite = StructuredEdit.EditSite

    // MARK: - Reading

    /// The file as a mapping in file order, or nil when it holds no key.
    public static func value(of text: String) -> StructuredValue? {
        let entries = parse(text)
        guard !entries.isEmpty else { return nil }
        return .mapping(entries.map { StructuredPair(key: $0.key, value: INIStructure.typed($0.value)) })
    }

    // MARK: - Editing

    /// Where the member at `[key]` sits: the raw key token and the raw value (escapes as written,
    /// a continued value whole, to the end of its last physical line).
    public static func site(in text: String, path: [PathComponent]) -> EditSite? {
        guard path.count == 1, case .key(let key) = path[0], let entry = parse(text).first(where: { $0.key == key }) else { return nil }
        return EditSite(key: entry.keyRange, value: entry.valueRange)
    }

    /// The one edit a typed key or value means; a key that had no separator gains `=`.
    public static func replacement(in text: String, path: [PathComponent], key: Bool, with typed: String) -> (range: NSRange, replacement: String)? {
        guard path.count == 1, case .key(let name) = path[0], let entry = parse(text).first(where: { $0.key == name }) else { return nil }
        if key { return (entry.keyRange, encodedKey(typed)) }
        return (entry.valueRange, (entry.separated ? "" : "=") + encodedValue(typed))
    }

    /// `typed` as a value: backslashes, line breaks, tabs and a leading space escaped.
    public static func encodedValue(_ typed: String) -> String {
        var out = escaped(typed, alsoEscaping: "")
        if out.hasPrefix(" ") { out = "\\" + out }
        return out
    }

    /// `key` as a key: the separators and comment starters escaped too.
    public static func encodedKey(_ key: String) -> String { escaped(key, alsoEscaping: " =:#!") }

    private static func escaped(_ s: String, alsoEscaping extra: String) -> String {
        var out = ""
        for c in s {
            switch c {
            case "\\": out += "\\\\"
            case "\n", "\r\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{0C}": out += "\\f"
            case let c where extra.contains(c): out += "\\\(c)"
            default: out.append(c)
            }
        }
        return out
    }

    // MARK: - Parsing

    struct Entry { let key: String, keyRange: NSRange, value: String, valueRange: NSRange, separated: Bool }

    static func parse(_ text: String) -> [Entry] {
        let ns = text as NSString
        var entries: [Entry] = []
        var position = 0
        while position < ns.length {
            // One logical line: physical lines joined while the line ends in an odd run of backslashes.
            var pieces: [(text: String, location: Int)] = []
            var continuing = true
            while continuing, position < ns.length {
                let lineRange = ns.lineRange(for: NSRange(location: position, length: 0))
                var body = ns.substring(with: lineRange).trimmingCharacters(in: .newlines)
                var location = lineRange.location
                position = NSMaxRange(lineRange)
                if !pieces.isEmpty {   // a continuation's leading whitespace is dropped
                    let dropped = body.prefix { $0 == " " || $0 == "\t" || $0 == "\u{0C}" }.count
                    body = String(body.dropFirst(dropped)); location += dropped
                }
                continuing = body.reversed().prefix { $0 == "\\" }.count % 2 == 1
                if continuing { body.removeLast() }
                pieces.append((body, location))
                if lineRange.length == 0 { break }
            }
            guard let first = pieces.first else { break }
            let lead = first.text.prefix { $0 == " " || $0 == "\t" || $0 == "\u{0C}" }.count
            let head = String(first.text.dropFirst(lead))
            if head.isEmpty || head.hasPrefix("#") || head.hasPrefix("!") { continue }
            entries.append(entry(from: pieces, lead: lead))
        }
        return entries
    }

    /// The key, the separator and the value out of one logical line's pieces.
    private static func entry(from pieces: [(text: String, location: Int)], lead: Int) -> Entry {
        // Scan the joined text for the key's end, tracking which piece a character falls in.
        let joined = pieces.map(\.text).joined()
        let chars = Array(joined.utf16)
        var i = lead
        var keyEnd = chars.count
        var escaped = false
        while i < chars.count {
            let c = chars[i]
            if escaped { escaped = false; i += 1; continue }
            if c == 0x5C { escaped = true; i += 1; continue }   // backslash
            if c == 0x3D || c == 0x3A || c == 0x20 || c == 0x09 || c == 0x0C { keyEnd = i; break }
            i += 1
        }
        var valueStart = keyEnd
        while valueStart < chars.count, [0x20, 0x09, 0x0C].contains(chars[valueStart]) { valueStart += 1 }
        var separated = false
        if valueStart < chars.count, chars[valueStart] == 0x3D || chars[valueStart] == 0x3A { separated = true; valueStart += 1 }
        while valueStart < chars.count, [0x20, 0x09, 0x0C].contains(chars[valueStart]) { valueStart += 1 }
        let keyRaw = String(utf16CodeUnits: Array(chars[lead..<keyEnd]), count: keyEnd - lead)
        let valueRaw = String(utf16CodeUnits: Array(chars[valueStart...]), count: chars.count - valueStart)
        // Map joined offsets back into the file: piece boundaries are where continuations were.
        func location(ofJoined offset: Int) -> Int {
            var remaining = offset
            for piece in pieces {
                let n = (piece.text as NSString).length
                if remaining <= n { return piece.location + remaining }
                remaining -= n
            }
            return (pieces.last?.location ?? 0) + ((pieces.last?.text as NSString?)?.length ?? 0)
        }
        let keyRange = NSRange(location: location(ofJoined: lead), length: keyEnd - lead)
        let valueLocation = location(ofJoined: valueStart)
        // The raw value runs to the end of the last physical line (the earlier lines' trailing backslashes inside it).
        let valueRange = NSRange(location: valueLocation, length: max(0, lastLineEnd(pieces) - valueLocation))
        return Entry(key: unescaped(keyRaw), keyRange: keyRange, value: unescaped(valueRaw), valueRange: valueRange, separated: separated)
    }

    /// Where the last physical line's text ends (a continuation line's own backslash included).
    private static func lastLineEnd(_ pieces: [(text: String, location: Int)]) -> Int {
        guard let last = pieces.last else { return 0 }
        return last.location + (last.text as NSString).length
    }

    /// The escapes resolved: `\t \n \f \r \\ \uXXXX`, `\X` → `X`.
    static func unescaped(_ s: String) -> String {
        guard s.contains("\\") else { return s }
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            guard c == "\\", let e = it.next() else { out.append(c); continue }
            switch e {
            case "t": out.append("\t")
            case "n": out.append("\n")
            case "f": out.append("\u{0C}")
            case "r": out.append("\r")
            case "u":
                var hex = ""
                for _ in 0..<4 { if let h = it.next() { hex.append(h) } }
                if let v = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(v) { out.unicodeScalars.append(scalar) } else { out += "\\u" + hex }
            default: out.append(e)
            }
        }
        return out
    }
}
