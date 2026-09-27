//
//  YAMLEdit.swift
//  DataConverter
//
//  How a typed replacement for a YAML key or scalar is written.
//
//  Created by David Sherlock on 9/25/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The writing half of a YAML cell edit; finding WHERE the member sits needs the grammar and
/// lives with it (`YAMLStructure.site(in:path:)` in swift-code-kit's CodeHighlighting). A scalar stays plain
/// when YAML would read it back as the same text, and is double-quoted when it would not.
public enum YAMLEdit {
    /// The kind of scalar a value was before the edit.
    public typealias ScalarKind = StructuredEdit.ScalarKind

    /// `typed` as the scalar that replaces a value of `kind`.
    public static func encodedScalar(_ typed: String, kind: ScalarKind) -> String {
        let t = typed.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .number where looksNumeric(t): return t
        case .bool where ["true", "false"].contains(t): return t
        case .null where ["null", "~"].contains(t): return t
        default: return needsQuotes(typed) ? StructuredEdit.doubleQuoted(typed) : typed
        }
    }

    /// `key` as a mapping key.
    public static func encodedKey(_ key: String) -> String { needsQuotes(key) ? StructuredEdit.doubleQuoted(key) : key }

    /// Whether `t` reads as a YAML number (decimal, hex, octal, `.inf`, `.nan`).
    static func looksNumeric(_ t: String) -> Bool {
        t.range(of: "^[-+]?(\\d[\\d_]*(\\.\\d*)?|\\.\\d+)([eE][-+]?\\d+)?$|^0x[0-9a-fA-F]+$|^0o[0-7]+$|^[-+]?\\.(inf|Inf|INF)$|^\\.(nan|NaN|NAN)$", options: .regularExpression) != nil
    }

    /// Whether plain `t` would read back as a number, boolean (YAML 1.1 words too) or null.
    static func looksLikeAnotherType(_ t: String) -> Bool {
        looksNumeric(t) || ["true", "false", "yes", "no", "on", "off", "null", "~", "True", "False", "Yes", "No", "On", "Off", "Null", "TRUE", "FALSE", "YES", "NO", "ON", "OFF", "NULL"].contains(t)
    }

    /// Whether a plain scalar would read back as something else — or not at all.
    public static func needsQuotes(_ s: String) -> Bool {
        guard let first = s.first, let last = s.last else { return true }
        if first.isWhitespace || last.isWhitespace || s.contains(where: \.isNewline) { return true }
        if "-?:,[]{}#&*!|>'\"%@`".contains(first) { return true }
        if s.contains(": ") || s.contains(" #") || s.hasSuffix(":") { return true }
        return looksLikeAnotherType(s)
    }
}
