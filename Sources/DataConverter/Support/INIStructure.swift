//
//  INIStructure.swift
//  DataConverter
//
//  An INI file as ordered structure — sections of typed keys — and where each key and value sits.
//
//  Created by David Sherlock on 9/25/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// An INI file (`.ini`, `.cfg`, `tox.ini`, git's config…) as the structure a tree shows, and the
/// site of any key or value in it. Python `configparser` rules with git's separators: `[section]`
/// opens a mapping, `key = value` / `key: value` are members (root keys before the first
/// section), `;`/`#` open whole-line comments only (a `#` in a URL is data), a line indented deeper
/// than the key above continues its value (keys indented alike, as git and Samba write them, stay
/// keys), a key with no separator is null. Values are typed for the tree;
/// duplicate keys are all listed and a path finds the first.
public enum INIStructure {
    /// One step of a path into the tree.
    public typealias PathComponent = StructuredEdit.PathComponent
    /// The key and value ranges of one member.
    public typealias EditSite = StructuredEdit.EditSite

    // MARK: - Reading

    /// The file as structure, or nil when it holds no key and no section.
    public static func value(of text: String) -> StructuredValue? {
        let file = parse(text)
        guard !file.globals.isEmpty || !file.sections.isEmpty else { return nil }
        var pairs = file.globals.map { StructuredPair(key: $0.key, value: $0.typed) }
        pairs += file.sections.map {
            StructuredPair(key: $0.name, value: .mapping($0.entries.map { StructuredPair(key: $0.key, value: $0.typed) }))
        }
        return .mapping(pairs)
    }

    /// `raw` as the tree's typed value: integer, number, boolean, else the string unquoted.
    public static func typed(_ raw: String) -> StructuredValue {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if let i = Int(t) { return .integer(i) }
        if let d = Double(t), t.range(of: "^[-+]?(\\d+\\.?\\d*|\\.\\d+)([eE][-+]?\\d+)?$", options: .regularExpression) != nil {
            return .number(d)
        }
        switch t.lowercased() {
        case "true", "yes", "on": return .bool(true)
        case "false", "no", "off": return .bool(false)
        default: return .string(unquoted(t))
        }
    }

    /// A value's surrounding quotes removed when it has a matching pair.
    static func unquoted(_ t: String) -> String {
        guard t.count >= 2, let first = t.first, first == "\"" || first == "'", t.last == first else { return t }
        return String(t.dropFirst().dropLast())
    }

    // MARK: - Editing

    /// Where the member at `path` sits: `[section, key]` or `[key]` for a root member; a section's
    /// own site is its name in the brackets (its value the whole section body). A value's range
    /// excludes surrounding quotes, so the replacement lands inside them; a key with no separator
    /// has an empty value site at its end (see `replacement`).
    public static func site(in text: String, path: [PathComponent]) -> EditSite? {
        let file = parse(text)
        switch path.count {
        case 1:
            guard case .key(let name) = path[0] else { return nil }
            if let entry = file.globals.first(where: { $0.key == name }) { return entry.site }
            if let section = file.sections.first(where: { $0.name == name }) {
                return EditSite(key: section.nameRange, value: section.bodyRange)
            }
            return nil
        case 2:
            guard case .key(let name) = path[0], case .key(let key) = path[1],
                let section = file.sections.first(where: { $0.name == name }),
                let entry = section.entries.first(where: { $0.key == key })
            else { return nil }
            return entry.site
        default:
            return nil
        }
    }

    /// The one edit a typed key or value means: the range to replace and what to write there —
    /// a key with no separator gains ` = ` before its first value; a section rename touches only
    /// the name. Nil when nothing sits at `path`.
    public static func replacement(in text: String, path: [PathComponent], key: Bool, with typed: String) -> (
        range: NSRange, replacement: String
    )? {
        guard let site = site(in: text, path: path) else { return nil }
        if key { return site.key.map { ($0, encodedKey(typed)) } }
        let separated =
            site.value.length > 0
            || (text as NSString).substring(
                with: NSRange(
                    location: site.key?.location ?? site.value.location,
                    length: site.value.location - (site.key?.location ?? site.value.location))
            ).contains(where: { $0 == "=" || $0 == ":" })
        return (site.value, (separated ? "" : " = ") + encodedValue(typed))
    }

    /// `typed` as a value: a line break becomes an indented continuation line.
    public static func encodedValue(_ typed: String) -> String {
        typed.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\n    ")
    }

    /// `key` as a key: trimmed, with no separator or bracket in it.
    public static func encodedKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).filter { !"=:[]\n".contains($0) }
    }

    // MARK: - Parsing

    /// One `key = value` line (continuations joined), with the ranges an edit replaces.
    struct Entry {
        let key: String, keyRange: NSRange
        let raw: String?  // nil: no separator on the line
        let valueRange: NSRange  // the value without surrounding quotes; empty at the key's end when there is none
        var typed: StructuredValue { raw.map(INIStructure.typed) ?? .null }
        var site: EditSite { EditSite(key: keyRange, value: valueRange) }
    }
    /// A `[section]`: its name's range inside the brackets and its body's range.
    struct Section { let name: String, nameRange: NSRange; var entries: [Entry]; var bodyRange: NSRange }
    /// The whole file: root keys before any section, then the sections in order.
    struct File { var globals: [Entry] = []; var sections: [Section] = [] }

    /// Reads `text` into entries and sections with their UTF-16 ranges.
    static func parse(_ text: String) -> File {
        let ns = text as NSString
        var file = File()
        var position = 0
        var lastEntry: (section: Int?, index: Int, indent: Int)?  // for continuation lines
        while position < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: position, length: 0))
            let line = ns.substring(with: lineRange)
            let body = line.trimmingCharacters(in: .newlines)
            let bodyRange = NSRange(location: lineRange.location, length: (body as NSString).length)
            position = NSMaxRange(lineRange)
            if lineRange.length == 0 { break }
            let trimmed = body.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix(";") || trimmed.hasPrefix("#") { continue }
            let indent = body.prefix { $0 == " " || $0 == "\t" }.count
            // A continuation of the value above when indented DEEPER than its key (configparser's
            // multi-line values). Samba, git and others indent every key the same: those are keys.
            if let last = lastEntry, indent > last.indent {
                // Its raw text grows, its range too.
                let more = trimmed
                if let s = last.section {
                    let e = file.sections[s].entries[last.index]
                    file.sections[s].entries[last.index] = continued(e, more: more, lineEnd: NSMaxRange(bodyRange))
                } else {
                    let e = file.globals[last.index]
                    file.globals[last.index] = continued(e, more: more, lineEnd: NSMaxRange(bodyRange))
                }
                continue
            }
            if trimmed.hasPrefix("["), let close = trimmed.lastIndex(of: "]") {
                let name = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close]).trimmingCharacters(in: .whitespaces)
                let leading = (body as NSString).length - (trimmed as NSString).length + 1  // to the name's first char
                let nameLocation = bodyRange.location + leading + ((trimmed.dropFirst().prefix { $0 == " " }).count)
                let nameRange = NSRange(location: nameLocation, length: (name as NSString).length)
                if var previous = file.sections.popLast() {
                    previous.bodyRange.length = lineRange.location - previous.bodyRange.location; file.sections.append(previous)
                }
                file.sections.append(
                    Section(name: name, nameRange: nameRange, entries: [], bodyRange: NSRange(location: position, length: 0)))
                lastEntry = nil
                continue
            }
            let entry = entry(in: body, at: bodyRange.location)
            if file.sections.isEmpty {
                file.globals.append(entry); lastEntry = (nil, file.globals.count - 1, indent)
            } else {
                file.sections[file.sections.count - 1].entries.append(entry);
                lastEntry = (file.sections.count - 1, file.sections[file.sections.count - 1].entries.count - 1, indent)
            }
        }
        if var last = file.sections.popLast() {
            last.bodyRange.length = max(0, ns.length - last.bodyRange.location); file.sections.append(last)
        }
        return file
    }

    /// One `key = value` line: the key up to the first `=` or `:`, the value after it, both trimmed.
    private static func entry(in body: String, at location: Int) -> Entry {
        let nsBody = body as NSString
        let separator = nsBody.rangeOfCharacter(from: CharacterSet(charactersIn: "=:"))
        let keyText = separator.location == NSNotFound ? body : nsBody.substring(to: separator.location)
        let keyRange = trimmedRange(of: keyText, at: location)
        let key = (keyText as NSString).substring(with: NSRange(location: keyRange.location - location, length: keyRange.length))
        guard separator.location != NSNotFound else {
            return Entry(key: key, keyRange: keyRange, raw: nil, valueRange: NSRange(location: NSMaxRange(keyRange), length: 0))
        }
        let valueStart = NSMaxRange(separator)
        let valueText = nsBody.substring(from: valueStart)
        var valueRange = trimmedRange(of: valueText, at: location + valueStart)
        let raw = (valueText as NSString).substring(
            with: NSRange(location: valueRange.location - location - valueStart, length: valueRange.length))
        if raw.count >= 2, let q = raw.first, q == "\"" || q == "'", raw.last == q {
            valueRange = NSRange(location: valueRange.location + 1, length: valueRange.length - 2)
        }
        return Entry(key: key, keyRange: keyRange, raw: raw, valueRange: valueRange)
    }

    private static func continued(_ e: Entry, more: String, lineEnd: Int) -> Entry {
        Entry(
            key: e.key, keyRange: e.keyRange, raw: (e.raw ?? "") + "\n" + more,
            valueRange: NSRange(location: e.valueRange.location, length: lineEnd - e.valueRange.location))
    }

    /// The range of `s` without its surrounding whitespace, offset by `base`.
    static func trimmedRange(of s: String, at base: Int) -> NSRange {
        let ns = s as NSString
        var start = 0, end = ns.length
        while start < end, CharacterSet.whitespaces.contains(Unicode.Scalar(ns.character(at: start)) ?? " ") { start += 1 }
        while end > start, CharacterSet.whitespaces.contains(Unicode.Scalar(ns.character(at: end - 1)) ?? " ") { end -= 1 }
        return NSRange(location: base + start, length: end - start)
    }
}
