//
//  TOMLEdit.swift
//  DataConverter
//
//  How a typed replacement for a TOML key or value is written.
//
//  Created by David Sherlock on 9/25/26.
//

import Foundation

/// The writing half of a TOML cell edit (25 Sep 2026); the finder lives with the grammar
/// (`TOMLStructure.site(in:path:)` in swift-code-highlighting). A string is a basic `"…"` string
/// with escapes; a number stays a number only when the text is one; a key is bare when TOML
/// allows it (`A-Za-z0-9_-`) and quoted otherwise.
public enum TOMLEdit {
    public typealias ScalarKind = StructuredEdit.ScalarKind

    /// `typed` as the value that replaces one of `kind`.
    public static func encodedScalar(_ typed: String, kind: ScalarKind) -> String {
        let t = typed.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .number where looksNumeric(t): return t
        case .bool where ["true", "false"].contains(t): return t
        default: return StructuredEdit.doubleQuoted(typed)
        }
    }

    /// `key` as a key: bare when TOML allows it, quoted otherwise.
    public static func encodedKey(_ key: String) -> String {
        key.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil ? key : StructuredEdit.doubleQuoted(key)
    }

    static func looksNumeric(_ t: String) -> Bool {
        t.range(of: "^[-+]?(\\d[\\d_]*)(\\.\\d[\\d_]*)?([eE][-+]?\\d+)?$|^0x[0-9A-Fa-f_]+$|^0o[0-7_]+$|^0b[01_]+$|^[-+]?(inf|nan)$", options: .regularExpression) != nil
    }
}
