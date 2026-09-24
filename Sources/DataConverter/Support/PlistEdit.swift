//
//  PlistEdit.swift
//  DataConverter
//
//  How a typed replacement for an XML property list's key or value is written.
//
//  Created by David Sherlock on 9/25/26.
//

import Foundation

/// The writing half of a property-list tree edit (25 Sep 2026); the finder lives with the
/// grammar (`PlistStructure.site(in:path:)` in swift-code-highlighting). A string's content is
/// XML-escaped; a number stays bare only when the text is one (the tree reads a non-number in
/// an `<integer>` as a string, so the file stays readable either way); a boolean's site is its
/// whole element, so `true` / `false` write `<true/>` / `<false/>` and any other text a
/// `<string>` element in its place.
public enum PlistEdit {
    public typealias ScalarKind = StructuredEdit.ScalarKind

    /// `typed` as the content (or element) that replaces one of `kind`.
    public static func encodedScalar(_ typed: String, kind: ScalarKind) -> String {
        let t = typed.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .number: return XMLEdit.encodedText(t)
        case .bool:
            if t == "true" { return "<true/>" }
            if t == "false" { return "<false/>" }
            return "<string>" + XMLEdit.encodedText(typed) + "</string>"
        default: return XMLEdit.encodedText(typed)
        }
    }

    /// `key` as a `<key>`'s content.
    public static func encodedKey(_ key: String) -> String { XMLEdit.encodedText(key) }
}
