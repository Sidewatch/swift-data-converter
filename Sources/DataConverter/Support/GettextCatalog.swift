//
//  GettextCatalog.swift
//  DataConverter
//
//  A gettext .po / .pot catalog as its messages — source, translation, context, flags — and
//  the edits a table makes to one message's translation and fuzzy flag.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A gettext catalog: one message per `msgid`, with its `msgctxt`, `msgid_plural`, `msgstr` (or
/// `msgstr[n]` plural forms), flags (`#, fuzzy`) and references (`#: file:line`). Continued
/// strings (`""` lines) are joined and C escapes resolved. Obsolete (`#~`) messages are skipped;
/// the header (`msgid ""`) is reported with `isHeader`.
public enum GettextCatalog {

    /// One message.
    public struct Message: Equatable, Sendable {
        /// 1-based line of the `msgid`.
        public let line: Int
        /// The `msgctxt`, if any.
        public let context: String?
        /// The source text.
        public let source: String
        /// The plural source, if any.
        public let plural: String?
        /// The translation: one string, or one per plural form.
        public let translations: [String]
        /// The `#,` flags (`fuzzy`, `c-format`).
        public let flags: [String]
        /// The `#:` references.
        public let references: [String]
        /// 1-based first and last line of the message, comments included.
        public let lines: ClosedRange<Int>
        /// 1-based lines of the `msgstr` block(s).
        public let translationLines: ClosedRange<Int>?

        /// The header entry (`msgid ""`).
        public var isHeader: Bool { source.isEmpty && context == nil }
        /// Marked for review.
        public var isFuzzy: Bool { flags.contains("fuzzy") }
        /// No translation yet.
        public var isUntranslated: Bool { translations.allSatisfy(\.isEmpty) }
    }

    /// The messages of `text`, header included, in file order.
    public static func parse(_ text: String) -> [Message] {
        var out: [Message] = []
        var b = Builder()
        var field: String?  // which string a continuation line extends
        let lines = LineText.lines(text)
        func flush() {
            if let message = b.message() { out.append(message) }
            b = Builder()
            field = nil
        }
        for (i, raw) in lines.enumerated() {
            let number = i + 1
            let line = LineText.clean(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("#~") { continue }
            if line.hasPrefix("#") {
                if b.sawMsgstr { flush() }
                b.first = b.first ?? number
                if line.hasPrefix("#,") {
                    b.flags += line.dropFirst(2).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                } else if line.hasPrefix("#:") {
                    b.references += line.dropFirst(2).split(separator: " ").map(String.init)
                }
                b.last = number
                continue
            }
            if line.hasPrefix("\"") {
                guard let f = field else { continue }
                b.append(unquote(line), to: f, line: number)
                b.last = number
                continue
            }
            let keyword = String(line.prefix { $0 != " " && $0 != "\t" })
            let value = unquote(line.dropFirst(keyword.count).trimmingCharacters(in: .whitespaces))
            // A message without a blank line before it starts at its msgctxt or msgid.
            if (keyword == "msgctxt" || keyword == "msgid") && b.sawMsgstr || keyword == "msgctxt" && b.sawMsgid { flush() }
            b.first = b.first ?? number
            b.last = number
            field = keyword
            b.set(keyword, value, line: number)
        }
        flush()
        return out
    }

    /// `text` with `message`'s translation replaced by `translation` (singular messages only;
    /// a plural message is left alone), written as one `msgstr` line.
    public static func replacingTranslation(in text: String, message: Message, with translation: String) -> String {
        guard message.plural == nil, let range = message.translationLines else { return text }
        var lines = LineText.lines(text)
        guard range.upperBound <= lines.count else { return text }
        let indent = lines[range.lowerBound - 1].prefix { $0 == " " || $0 == "\t" }
        let cr = lines[range.upperBound - 1].hasSuffix("\r") ? "\r" : ""
        lines.replaceSubrange((range.lowerBound - 1)...(range.upperBound - 1), with: [indent + "msgstr \"\(escape(translation))\"" + cr])
        return lines.joined(separator: "\n")
    }

    /// `text` with `message`'s `fuzzy` flag set or cleared, other flags kept.
    public static func settingFuzzy(in text: String, message: Message, _ fuzzy: Bool) -> String {
        guard message.isFuzzy != fuzzy else { return text }
        var lines = LineText.lines(text)
        let span = (message.lines.lowerBound - 1)..<min(message.line - 1, lines.count)
        if let flagLine = span.first(where: { LineText.clean(lines[$0]).trimmingCharacters(in: .whitespaces).hasPrefix("#,") }) {
            let cr = lines[flagLine].hasSuffix("\r") ? "\r" : ""
            var flags = message.flags.filter { $0 != "fuzzy" }
            if fuzzy { flags.insert("fuzzy", at: 0) }
            if flags.isEmpty {
                lines.remove(at: flagLine)
            } else {
                lines[flagLine] = "#, " + flags.joined(separator: ", ") + cr
            }
        } else if fuzzy {
            // Flags go right before the msgctxt / msgid, after any other comments.
            let cr = lines[max(0, message.line - 1)].hasSuffix("\r") ? "\r" : ""
            let anchor = firstKeywordLine(lines, from: message.lines.lowerBound - 1, to: message.line - 1)
            lines.insert("#, fuzzy" + cr, at: anchor)
        }
        return lines.joined(separator: "\n")
    }

    static func firstKeywordLine(_ lines: [String], from: Int, to: Int) -> Int {
        (from...max(from, to)).first { LineText.clean(lines[$0]).trimmingCharacters(in: .whitespaces).hasPrefix("msg") } ?? to
    }

    // MARK: - Strings

    /// A quoted PO string's content with escapes resolved; the input without quotes if unquoted.
    static func unquote(_ s: String) -> String {
        var body = Substring(s)
        if body.hasPrefix("\"") { body = body.dropFirst() }
        if body.hasSuffix("\"") { body = body.dropLast() }
        var out = ""
        var i = body.startIndex
        while i < body.endIndex {
            let c = body[i]
            if c == "\\", body.index(after: i) < body.endIndex {
                let next = body[body.index(after: i)]
                switch next {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                default: out.append(next)
                }
                i = body.index(i, offsetBy: 2)
            } else {
                out.append(c)
                i = body.index(after: i)
            }
        }
        return out
    }

    /// `s` escaped for a PO string.
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
    }

    /// Collects one message as its lines arrive.
    struct Builder {
        var first: Int?
        var last: Int = 0
        var msgidLine: Int?
        var context: String?
        var source: String?
        var plural: String?
        var translations: [Int: String] = [:]
        var flags: [String] = []
        var references: [String] = []
        var msgstrFirst: Int?
        var msgstrLast: Int?
        var sawMsgid: Bool { source != nil }
        var sawMsgstr: Bool { msgstrFirst != nil }

        mutating func set(_ keyword: String, _ value: String, line: Int) {
            switch keyword {
            case "msgctxt": context = value
            case "msgid": source = value; msgidLine = line
            case "msgid_plural": plural = value
            default:
                if keyword == "msgstr" || keyword.hasPrefix("msgstr[") {
                    let index = keyword == "msgstr" ? 0 : Int(keyword.dropFirst(7).dropLast()) ?? 0
                    translations[index] = value
                    msgstrFirst = msgstrFirst ?? line
                    msgstrLast = line
                }
            }
        }

        mutating func append(_ value: String, to keyword: String, line: Int) {
            switch keyword {
            case "msgctxt": context = (context ?? "") + value
            case "msgid": source = (source ?? "") + value
            case "msgid_plural": plural = (plural ?? "") + value
            default:
                if keyword == "msgstr" || keyword.hasPrefix("msgstr[") {
                    let index = keyword == "msgstr" ? 0 : Int(keyword.dropFirst(7).dropLast()) ?? 0
                    translations[index] = (translations[index] ?? "") + value
                    msgstrLast = line
                }
            }
        }

        func message() -> Message? {
            guard let source, let msgidLine, let first else { return nil }
            let forms = translations.keys.sorted().map { translations[$0] ?? "" }
            return Message(
                line: msgidLine, context: context, source: source, plural: plural, translations: forms, flags: flags,
                references: references, lines: first...max(first, last),
                translationLines: msgstrFirst.flatMap { a in msgstrLast.map { a...$0 } })
        }
    }
}
