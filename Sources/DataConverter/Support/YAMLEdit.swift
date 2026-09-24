//
//  YAMLEdit.swift
//  DataConverter
//
//  How a typed replacement for a YAML key or scalar is written.
//
//  Created by David Sherlock on 9/25/26.
//

import Foundation

/// The writing half of a YAML cell edit (25 Sep 2026). Finding WHERE the member sits needs the
/// grammar and lives with it (`YAMLStructure.site(in:path:)` in swift-code-highlighting); what to
/// write there is plain string rules and lives here beside `JSONEdit`: a scalar stays plain when
/// YAML would read it back as the same text, and is double-quoted when it would not — a string
/// that looks like a number or a bool, one that starts with an indicator, holds `: ` or ` #`, or
/// spans lines.
public enum YAMLEdit {
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

    static func looksNumeric(_ t: String) -> Bool {
        t.range(of: "^[-+]?(\\d[\\d_]*(\\.\\d*)?|\\.\\d+)([eE][-+]?\\d+)?$|^0x[0-9a-fA-F]+$|^0o[0-7]+$|^[-+]?\\.(inf|Inf|INF)$|^\\.(nan|NaN|NAN)$", options: .regularExpression) != nil
    }

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
