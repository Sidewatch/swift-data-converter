//
//  XMLEdit.swift
//  DataConverter
//
//  How a typed replacement for an XML attribute or text node is written.
//
//  Created by David Sherlock on 9/25/26.
//

import Foundation

/// The writing half of an XML tree edit (25 Sep 2026); the finder lives with the grammar
/// (`XMLStructure.site(in:path:)` in swift-code-highlighting). Text content escapes `&`, `<` and
/// `>`; an attribute value is double-quoted and escapes `"` too; an attribute name is written as
/// typed, without the `@` the tree shows it with.
public enum XMLEdit {
    /// `text` as element content.
    public static func encodedText(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    /// `text` as a double-quoted attribute value.
    public static func encodedAttribute(_ text: String) -> String {
        "\"" + encodedText(text).replacingOccurrences(of: "\"", with: "&quot;") + "\""
    }

    /// `key` as an attribute name: the tree's `@` dropped, whitespace removed.
    public static func encodedAttributeName(_ key: String) -> String {
        String((key.hasPrefix("@") ? String(key.dropFirst()) : key).filter { !$0.isWhitespace })
    }

    /// The five predefined entities and numeric character references resolved; anything else
    /// (a DTD's own entity) is left as written, since that is what the file says.
    public static func decodedReferences(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            rest = rest[amp...]
            guard let semi = rest.firstIndex(of: ";"), rest.distance(from: rest.startIndex, to: semi) <= 10 else { out.append("&"); rest = rest.dropFirst(); continue }
            let name = rest[rest.index(after: rest.startIndex)..<semi]
            let decoded: String?
            switch name {
            case "amp": decoded = "&"
            case "lt": decoded = "<"
            case "gt": decoded = ">"
            case "quot": decoded = "\""
            case "apos": decoded = "'"
            default:
                if name.hasPrefix("#x"), let v = UInt32(name.dropFirst(2), radix: 16), let s = Unicode.Scalar(v) { decoded = String(s) }
                else if name.hasPrefix("#"), let v = UInt32(name.dropFirst(1)), let s = Unicode.Scalar(v) { decoded = String(s) }
                else { decoded = nil }
            }
            if let decoded { out += decoded; rest = rest[rest.index(after: semi)...] }
            else { out.append("&"); rest = rest.dropFirst() }
        }
        return out + rest
    }
}
