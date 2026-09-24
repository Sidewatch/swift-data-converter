//
//  StructuredEdit.swift
//  DataConverter
//
//  The vocabulary every tree editor shares: a path into a document, a scalar's kind, an edit site, quoting.
//
//  Created by David Sherlock on 9/25/26.
//

import Foundation

/// What every tree editor has in common (25 Sep 2026; JSON and YAML first, then TOML, XML,
/// property lists, INI, `.properties` and `.strings`): how a member is addressed, what kind of
/// scalar a typed replacement should stay, WHERE a member's key and value sit (the finder's
/// answer), and the one double-quoted escaper the JSON-shaped formats write (`\"`, `\\`, `\n`,
/// `\r`, `\t`, and `\u00XX` for the other control characters — valid in JSON and in a YAML
/// double-quoted scalar alike).
public enum StructuredEdit {
    /// One step of a path: an object / mapping member by key, or an array / sequence element by index.
    public enum PathComponent: Equatable, Sendable { case key(String), index(Int) }

    /// The UTF-16 ranges of one member: its value, and its key when it sits in a mapping and can
    /// be renamed on its own (an XML element's name is written twice, so it has none).
    public struct EditSite: Equatable, Sendable {
        public let key: NSRange?
        public let value: NSRange
        public init(key: NSRange?, value: NSRange) { self.key = key; self.value = value }
    }

    /// The kind a typed replacement keeps: a string stays a string whatever was typed, a number
    /// stays a number only when the text is one.
    public enum ScalarKind: Sendable { case string, number, bool, null }

    /// `s` as a double-quoted, escaped token.
    public static func doubleQuoted(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case let c where c.value < 0x20: out += String(format: "\\u%04X", c.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}
