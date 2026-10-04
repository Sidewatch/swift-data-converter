//
//  HostsFile.swift
//  DataConverter
//
//  A hosts(5) file as its address entries, commented-out entries included, and the line edits
//  a table makes to it.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A hosts(5) file as entries: an address, its host names and a trailing comment, in file
/// order. A line commented out whose text still reads as an entry (`#192.0.2.9 old.example`)
/// is a DISABLED entry; a decorated comment (`# ── Loopback ──`) is a section title; every
/// other comment is prose and becomes nothing. Edits rewrite one line and keep its spacing.
public enum HostsFile {

    /// One address line.
    public struct Entry: Equatable, Sendable {
        /// 1-based line.
        public let line: Int
        /// The address as written (`127.0.0.1`, `fe80::1%lo0`).
        public let address: String
        /// The canonical name and its aliases, in order.
        public let names: [String]
        /// The trailing comment's text, without the `#`; nil when there is none.
        public let comment: String?
        /// False for an entry commented out.
        public let isEnabled: Bool
        /// The section title above this entry, if the file has one.
        public let section: String?

        /// Whether the address is IPv6.
        public var isIPv6: Bool { address.contains(":") }
        /// Whether the entry points its names nowhere — `0.0.0.0` or `::` — the way block lists do.
        public var isBlocked: Bool { HostsFile.blockingAddresses.contains(address) }

        /// Creates an entry from its parts.
        public init(line: Int, address: String, names: [String], comment: String?, isEnabled: Bool, section: String?) {
            self.line = line; self.address = address; self.names = names
            self.comment = comment; self.isEnabled = isEnabled; self.section = section
        }
    }

    static let blockingAddresses: Set<String> = ["0.0.0.0", "::", "0:0:0:0:0:0:0:0"]

    /// The entries of `text`, in file order.
    public static func parse(_ text: String) -> [Entry] {
        var out: [Entry] = []
        var section: String?
        for (i, raw) in LineText.lines(text).enumerated() {
            let line = LineText.clean(raw)
            if let body = LineText.uncommented(line) {
                if let title = sectionTitle(body) { section = title; continue }
                if let entry = entry(body, line: i + 1, enabled: false, section: section, strict: true) { out.append(entry) }
                continue
            }
            if let entry = entry(line, line: i + 1, enabled: true, section: section, strict: false) { out.append(entry) }
        }
        return out
    }

    /// `text` with the address on `line` replaced; spacing and the rest of the line kept.
    public static func replacingAddress(in text: String, line: Int, with address: String) -> String {
        let clean = address.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, !clean.contains(where: { $0 == " " || $0 == "\t" || $0 == "#" }) else { return text }
        return rewrite(text, line: line) { parts in
            parts.address = clean
        }
    }

    /// `text` with the host names on `line` replaced by `names` (split on spaces when given as
    /// one string by the caller), kept in one run separated by single spaces.
    public static func replacingNames(in text: String, line: Int, with names: [String]) -> String {
        let clean = names.flatMap { $0.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," }).map(String.init) }
            .filter { !$0.isEmpty && !$0.contains("#") }
        guard !clean.isEmpty else { return text }
        return rewrite(text, line: line) { parts in parts.names = clean.joined(separator: " ") }
    }

    /// `text` with the trailing comment on `line` replaced; an empty comment removes it.
    public static func replacingComment(in text: String, line: Int, with comment: String) -> String {
        let clean = comment.trimmingCharacters(in: .whitespaces)
        return rewrite(text, line: line) { parts in parts.comment = clean.isEmpty ? nil : clean }
    }

    /// `text` with the entry on `line` enabled (its leading `#` removed) or disabled (a `#` put
    /// in front, indentation kept).
    public static func settingEnabled(in text: String, line: Int, _ enabled: Bool) -> String {
        let lines = LineText.lines(text)
        guard line >= 1, line <= lines.count else { return text }
        let current = LineText.clean(lines[line - 1])
        let indent = String(current.prefix { $0 == " " || $0 == "\t" })
        if enabled {
            guard let body = LineText.uncommented(current) else { return text }
            return LineText.replacingLine(line, in: text, with: indent + body)
        }
        guard LineText.uncommented(current) == nil else { return text }
        return LineText.replacingLine(line, in: text, with: indent + "#" + current.dropFirst(indent.count))
    }

    // MARK: - Reading

    /// A comment's text as a section title when it is decorated as one: `── Title ──`,
    /// `== Title ==`, `-- Title --`; nil for prose.
    static func sectionTitle(_ body: String) -> String? {
        let decorations: Set<Character> = ["─", "━", "═", "=", "-", "*"]
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, let last = trimmed.last, decorations.contains(first), decorations.contains(last) else {
            return nil
        }
        let title = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "─━═=-* "))
        return title.isEmpty ? nil : title
    }

    /// `body` as an entry; `strict` (a commented-out line) also requires the address to look like
    /// one and every name like a host name, so commented prose never becomes an entry.
    static func entry(_ body: String, line: Int, enabled: Bool, section: String?, strict: Bool) -> Entry? {
        var content = body
        var comment: String?
        if let hash = body.firstIndex(of: "#") {
            content = String(body[..<hash])
            let text = body[body.index(after: hash)...].trimmingCharacters(in: .whitespaces)
            comment = text.isEmpty ? nil : text
        }
        let tokens = LineText.tokens(content).map(\.text)
        guard tokens.count >= 2 else { return nil }
        if strict, !looksLikeAddress(tokens[0]) || !tokens.dropFirst().allSatisfy(looksLikeHostName) { return nil }
        return Entry(
            line: line, address: tokens[0], names: Array(tokens.dropFirst()), comment: comment, isEnabled: enabled, section: section)
    }

    /// An IPv4 address (dotted, short, hex or octal parts, or one number) or an IPv6 one.
    static func looksLikeAddress(_ s: String) -> Bool {
        if s.contains(":") {
            let body = s.split(separator: "%", maxSplits: 1).first.map(String.init) ?? s
            return body.allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "." } && body.filter { $0 == ":" }.count >= 2
        }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return false }
        return parts.allSatisfy { part in
            let p = part.lowercased()
            if p.hasPrefix("0x") { return p.count > 2 && p.dropFirst(2).allSatisfy(\.isHexDigit) }
            return !p.isEmpty && p.allSatisfy(\.isNumber)
        }
    }

    /// Letters, digits, `-`, `_` and dots — a host name as hosts files write them.
    static func looksLikeHostName(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
    }

    // MARK: - Rewriting

    /// One line's parts, edited by a closure and written back in place.
    struct Parts {
        var address: String
        var names: String
        var comment: String?
    }

    /// Applies `edit` to the entry on `line` (enabled or commented out) and writes it back:
    /// the indentation, the `#` of a disabled entry, the gap between the address and the names,
    /// and the gap before the comment are all kept.
    static func rewrite(_ text: String, line: Int, _ edit: (inout Parts) -> Void) -> String {
        let lines = LineText.lines(text)
        guard line >= 1, line <= lines.count else { return text }
        let current = LineText.clean(lines[line - 1])
        let indent = String(current.prefix { $0 == " " || $0 == "\t" })
        var rest = String(current.dropFirst(indent.count))
        var prefix = indent
        if rest.hasPrefix("#") {
            let hashes = rest.prefix { $0 == "#" }
            rest = String(rest.dropFirst(hashes.count))
            let space = rest.hasPrefix(" ") ? " " : ""
            rest = String(rest.dropFirst(space.count))
            prefix += hashes + space
        }
        var content = rest
        var commentPart = ""
        if let hash = rest.firstIndex(of: "#") {
            content = String(rest[..<hash])
            commentPart = String(rest[hash...])
        }
        let tokens = LineText.tokens(content)
        guard tokens.count >= 2, let lastName = tokens.last else { return text }
        let gap = String(content[tokens[0].range.upperBound..<tokens[1].range.lowerBound])
        let trailing = String(content[lastName.range.upperBound...])
        let oldComment = commentPart.isEmpty ? nil : commentPart.dropFirst().trimmingCharacters(in: .whitespaces)
        var parts = Parts(
            address: tokens[0].text, names: tokens.dropFirst().map(\.text).joined(separator: " "), comment: oldComment)
        let originalNamesRun = String(content[tokens[1].range.lowerBound..<lastName.range.upperBound])
        edit(&parts)
        // The names keep their original spacing when they did not change.
        let namesRun = parts.names == tokens.dropFirst().map(\.text).joined(separator: " ") ? originalNamesRun : parts.names
        var body = prefix + parts.address + gap + namesRun
        if let comment = parts.comment {
            if comment == oldComment {
                body += trailing + commentPart
            } else {
                let space = trailing.isEmpty ? " " : trailing
                let hashSpace = commentPart.dropFirst().prefix { $0 == " " }
                body += space + "#" + (commentPart.isEmpty ? " " : String(hashSpace)) + comment
            }
        }
        return LineText.replacingLine(line, in: text, with: body)
    }
}
