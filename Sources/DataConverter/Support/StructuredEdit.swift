//
//  StructuredEdit.swift
//  DataConverter
//
//  The vocabulary the JSON and YAML editors share: a path into a document, a scalar's kind, quoting.
//
//  Created by David Sherlock on 9/25/26.
//

import Foundation

/// What `JSONEdit` and `YAMLEdit` have in common (25 Sep 2026): how a member is addressed, what
/// kind of scalar a typed replacement should stay, and the one double-quoted escaper both formats
/// write (`\"`, `\\`, `\n`, `\r`, `\t`, and `\u00XX` for the other control characters — valid in
/// JSON and in a YAML double-quoted scalar alike).
public enum StructuredEdit {
    /// One step of a path: an object / mapping member by key, or an array / sequence element by index.
    public enum PathComponent: Equatable, Sendable { case key(String), index(Int) }

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
