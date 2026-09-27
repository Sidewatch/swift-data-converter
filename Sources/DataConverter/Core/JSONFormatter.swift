//
//  JSONFormatter.swift
//  DataConverter
//
//  Re-indents JSON without rewriting it.
//
//  Created by David Sherlock on 8/6/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Formats JSON by re-emitting its TOKENS, not by parsing and re-encoding it.
///
/// Parse-and-re-encode (`JSONSerialization` + `.prettyPrinted`) loses the author's key order and
/// rewrites number literals (`1.0` → `1`, `1e3` → `1000`, large integers drift through `Double`).
/// Here strings and numbers are copied as written, key order is the file's, and only whitespace
/// between tokens is decided: the output is the input with different spacing.
public enum JSONFormatter {

    /// Re-indents `json` with `indent` (default two spaces) per level, or returns nil when the
    /// input is not valid JSON.
    ///
    /// Validity is checked first because the token scanner knows structure, not grammar, and would
    /// turn malformed input into neatly indented nonsense.
    public static func format(_ json: String, indent: String = "  ") -> String? {
        guard isValid(json) else { return nil }
        return reindent(json, indent: indent)
    }

    /// Collapses `json` to one line, or nil when invalid. The inverse of ``format(_:indent:)``.
    public static func minify(_ json: String) -> String? {
        guard isValid(json) else { return nil }
        var out = ""
        out.reserveCapacity(json.count)
        forEachToken(json) { kind, text in
            switch kind {
            case .whitespace: break
            case .colon: out += ":"
            case .comma: out += ","
            default: out += text
            }
        }
        return out
    }

    /// Whether `json` is valid per RFC 8259 — which is stricter than `JSONSerialization`.
    ///
    /// `JSONSerialization` accepts trailing commas (`[1,2,]`), which the scanner would re-emit into
    /// output other parsers reject; dropping the comma would be a content edit, so it declines.
    public static func isValid(_ json: String) -> Bool {
        guard (try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])) != nil
        else { return false }
        var lastWasComma = false
        var trailing = false
        forEachToken(json) { kind, _ in
            switch kind {
            case .whitespace: break  // does not separate a comma from a closer
            case .close: if lastWasComma { trailing = true }; lastWasComma = false
            case .comma: lastWasComma = true
            default: lastWasComma = false
            }
        }
        return !trailing
    }

    /// JSON's structural characters. A number/keyword token runs until one of these or whitespace.
    private static func isStructural(_ c: Character) -> Bool {
        c == "{" || c == "}" || c == "[" || c == "]" || c == ":" || c == "," || c == "\""
    }

    // MARK: - Scanning

    private enum Kind { case string, number, open, close, colon, comma, whitespace }

    /// Walks `json` once, classifying each run. Strings are emitted whole — including their
    /// escapes — so nothing inside one is ever mistaken for structure. That is the single rule
    /// that makes token-level formatting safe: a `{` inside a string is text, not a brace.
    private static func forEachToken(_ json: String, _ body: (Kind, String) -> Void) {
        var iterator = json.startIndex
        while iterator < json.endIndex {
            let ch = json[iterator]
            switch ch {
            case "\"":
                var end = json.index(after: iterator)
                var escaped = false
                while end < json.endIndex {
                    let c = json[end]
                    if escaped {
                        escaped = false
                    } else if c == "\\" {
                        escaped = true
                    } else if c == "\"" {
                        end = json.index(after: end); break
                    }
                    end = json.index(after: end)
                }
                body(.string, String(json[iterator..<min(end, json.endIndex)]))
                iterator = min(end, json.endIndex)
            case "{", "[":
                body(.open, String(ch)); iterator = json.index(after: iterator)
            case "}", "]":
                body(.close, String(ch)); iterator = json.index(after: iterator)
            case ":":
                body(.colon, ":"); iterator = json.index(after: iterator)
            case ",":
                body(.comma, ","); iterator = json.index(after: iterator)
            // Must be `isWhitespace`, not a match on " \t\n\r": Swift clusters CRLF into ONE
            // Character equal to neither, so CRLF breaks would be copied into the output verbatim.
            // Validity is already established, so anything `isWhitespace` accepts is JSON whitespace.
            case let c where c.isWhitespace:
                var end = iterator
                while end < json.endIndex, json[end].isWhitespace { end = json.index(after: end) }
                body(.whitespace, String(json[iterator..<end]))
                iterator = end
            default:
                // Numbers, true/false/null — copied exactly as written so no literal is reformatted.
                var end = iterator
                while end < json.endIndex, !isStructural(json[end]), !json[end].isWhitespace {
                    end = json.index(after: end)
                }
                if end == iterator { end = json.index(after: iterator) }
                body(.number, String(json[iterator..<end]))
                iterator = end
            }
        }
    }

    private static func reindent(_ json: String, indent: String) -> String {
        var out = ""
        out.reserveCapacity(json.count * 2)
        var depth = 0
        var pendingOpen: Character?  // held so `{}` and `[]` stay on one line

        func newline() {
            out += "\n" + String(repeating: indent, count: max(0, depth))
        }

        forEachToken(json) { kind, text in
            // An opener is buffered until the next token is known: if it is the matching closer
            // the container is empty and should read `{}`, not a brace on its own line.
            if let open = pendingOpen {
                pendingOpen = nil
                if kind == .close {
                    // Empty container: `{}` on one line, and depth never rose, so nothing to undo.
                    out += String(open) + text
                    return
                }
                out += String(open)
                depth += 1  // only a container with content opens a level
                newline()
            }
            switch kind {
            case .whitespace:
                break  // all original spacing is discarded
            case .open:
                pendingOpen = Character(text)
            case .close:
                depth -= 1
                newline()
                out += text
            case .comma:
                out += ","
                newline()
            case .colon:
                out += ": "
            default:
                out += text
            }
        }
        if let open = pendingOpen { out += String(open) }
        return out
    }
}
