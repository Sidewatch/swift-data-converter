//
//  JQPath.swift
//  DataConverter
//
//  A path into a structured document as jq writes it.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A path into a document as jq writes it, to paste into a jq filter: `.users[0].name`; `.["key with spaces"]` for a
/// key that is not a bare name; `.` for the whole document.
public enum JQPath {
    /// `components` as a jq path.
    public static func path(_ components: [StructuredEdit.PathComponent]) -> String {
        guard !components.isEmpty else { return "." }
        var out = ""
        for component in components {
            switch component {
            case .key(let key) where isBareName(key):
                out += ".\(key)"
            case .key(let key):
                out += (out.isEmpty ? "." : "") + "[\(StructuredValue.jsonString(key))]"
            case .index(let index):
                out += (out.isEmpty ? "." : "") + "[\(index)]"
            }
        }
        return out
    }

    /// The words jq reads as its own, which a bare `.name` cannot spell.
    private static let keywords: Set<String> = [
        "and", "or", "not", "if", "then", "elif", "else", "end", "as", "def", "reduce", "foreach", "try", "catch",
        "label", "import", "include", "__loc__",
    ]

    /// Whether jq takes `key` after a dot: ASCII letters, digits and `_`, not starting with a digit, not a keyword.
    static func isBareName(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first, !keywords.contains(key) else { return false }
        func letter(_ s: Unicode.Scalar) -> Bool { (s >= "a" && s <= "z") || (s >= "A" && s <= "Z") || s == "_" }
        return letter(first) && key.unicodeScalars.allSatisfy { letter($0) || ($0 >= "0" && $0 <= "9") }
    }
}
