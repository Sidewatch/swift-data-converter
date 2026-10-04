//
//  StructuredValue+Text.swift
//  DataConverter
//
//  A structured value written out as JSON or YAML, in the file's own key order.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

extension StructuredValue {
    /// The member at `path` (keys and indexes from the root), or nil when the path leads nowhere.
    public func value(at path: [StructuredEdit.PathComponent]) -> StructuredValue? {
        var current = self
        for component in path {
            switch (component, current) {
            case (.key(let key), .mapping(let pairs)):
                guard let next = pairs.first(where: { $0.key == key })?.value else { return nil }
                current = next
            case (.index(let i), .sequence(let items)):
                guard items.indices.contains(i) else { return nil }
                current = items[i]
            default:
                return nil
            }
        }
        return current
    }

    /// Pretty JSON, two-space indent, keys in file order (a `JSONSerialization` round trip would
    /// sort them).
    public func jsonText() -> String {
        var out = ""
        writeJSON(into: &out, indent: "")
        return out
    }

    private func writeJSON(into out: inout String, indent: String) {
        let inner = indent + "  "
        switch self {
        case .mapping(let pairs):
            guard !pairs.isEmpty else { out += "{}"; return }
            out += "{\n"
            for (i, pair) in pairs.enumerated() {
                out += inner + Self.jsonString(pair.key) + ": "
                pair.value.writeJSON(into: &out, indent: inner)
                out += i < pairs.count - 1 ? ",\n" : "\n"
            }
            out += indent + "}"
        case .sequence(let items):
            guard !items.isEmpty else { out += "[]"; return }
            out += "[\n"
            for (i, item) in items.enumerated() {
                out += inner
                item.writeJSON(into: &out, indent: inner)
                out += i < items.count - 1 ? ",\n" : "\n"
            }
            out += indent + "]"
        case .string(let s): out += Self.jsonString(s)
        case .integer(let n): out += String(n)
        case .number(let d): out += d.isFinite ? String(d) : "null"
        case .bool(let b): out += b ? "true" : "false"
        case .null: out += "null"
        }
    }

    /// Block-style YAML, two-space indent, keys in file order; strings quoted only when YAML would
    /// otherwise read them as something else.
    public func yamlText() -> String {
        switch self {
        case .mapping(let pairs) where pairs.isEmpty: return "{}\n"
        case .sequence(let items) where items.isEmpty: return "[]\n"
        case .mapping, .sequence:
            var out = ""
            writeYAML(into: &out, indent: "")
            return out
        default:
            return Self.yamlScalar(self) + "\n"
        }
    }

    private func writeYAML(into out: inout String, indent: String) {
        switch self {
        case .mapping(let pairs):
            for pair in pairs {
                let key = Self.yamlKey(pair.key)
                switch pair.value {
                case .mapping(let inner) where !inner.isEmpty:
                    out += indent + key + ":\n"
                    pair.value.writeYAML(into: &out, indent: indent + "  ")
                case .sequence(let inner) where !inner.isEmpty:
                    out += indent + key + ":\n"
                    pair.value.writeYAML(into: &out, indent: indent + "  ")
                default:
                    out += indent + key + ": " + Self.yamlScalar(pair.value) + "\n"
                }
            }
        case .sequence(let items):
            for item in items {
                switch item {
                case .mapping(let inner) where !inner.isEmpty:
                    // The first member shares the dash's line, the rest line up under it.
                    var nested = ""
                    item.writeYAML(into: &nested, indent: indent + "  ")
                    out += indent + "- " + nested.dropFirst(indent.count + 2)
                case .sequence(let inner) where !inner.isEmpty:
                    out += indent + "-\n"
                    item.writeYAML(into: &out, indent: indent + "  ")
                default:
                    out += indent + "- " + Self.yamlScalar(item) + "\n"
                }
            }
        default:
            out += indent + Self.yamlScalar(self) + "\n"
        }
    }

    private static func yamlScalar(_ value: StructuredValue) -> String {
        switch value {
        case .string(let s): return yamlString(s)
        case .integer(let n): return String(n)
        case .number(let d): return d.isFinite ? String(d) : (d.isNaN ? ".nan" : (d > 0 ? ".inf" : "-.inf"))
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .mapping: return "{}"
        case .sequence: return "[]"
        }
    }

    private static func yamlKey(_ key: String) -> String { yamlString(key) }

    /// A string bare when YAML reads it back as the same string, else double-quoted.
    private static func yamlString(_ s: String) -> String {
        let reserved: Set<String> = ["", "~", "null", "true", "false", "yes", "no", "on", "off", "y", "n"]
        let special = CharacterSet(charactersIn: ":#{}[],&*!|>'\"%@`\\\n\t")
        let needsQuotes =
            reserved.contains(s.lowercased()) || s.rangeOfCharacter(from: special) != nil || s.first == " " || s.last == " "
            || s.first == "-" || s.first == "?" || Double(s) != nil
        return needsQuotes ? jsonString(s) : s
    }

    /// `s` as a JSON string literal.
    static func jsonString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}
