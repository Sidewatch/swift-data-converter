//
//  JSONFormatter.swift
//  SwiftDataConverter
//
//  Re-indents JSON without rewriting it.
//
//  Created by David Sherlock on 8/6/26.
//

import Foundation

/// Formats JSON by re-emitting its TOKENS, not by parsing and re-encoding it.
///
/// The obvious implementation — `JSONSerialization.jsonObject` then `.prettyPrinted` — is wrong
/// for a formatter, and wrong in a way that is easy to ship without noticing. Parsing yields a
/// `[String: Any]`, which is an unordered dictionary: the key order the author chose is gone.
/// Re-encoding then either emits an arbitrary order or, with `.sortedKeys`, alphabetises it. So
/// formatting a config file would silently rearrange it, and the diff would be the whole file.
///
/// It also destroys number literals. `1.0` round-trips through `Double` and comes back `1`;
/// `1e3` becomes `1000`; and an integer beyond `Double`'s exact range — an ID, a timestamp in
/// nanoseconds — comes back subtly different. A formatter must not change values.
///
/// Working on tokens avoids both. Strings are copied byte for byte, numbers are copied as
/// written, key order is whatever the file said, and only whitespace between tokens is decided
/// here. The output is the input with different spacing, which is the whole contract.
public enum JSONFormatter {

    /// Re-indents `json` with `indent` per level, or returns nil when the input is not valid JSON.
    ///
    /// Validity is checked with `JSONSerialization` before formatting: the token scanner is
    /// deliberately permissive (it does not know grammar, only structure), so on malformed input
    /// it would happily produce neatly-indented nonsense. Refusing is better — a formatter that
    /// "fixes" broken JSON into different broken JSON is worse than one that declines.
    ///
    /// - Parameters:
    ///   - json: The JSON text.
    ///   - indent: One level of indentation. Defaults to two spaces.
    /// - Returns: The formatted text, or nil if `json` is not valid JSON.
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
            case .colon:      out += ":"
            case .comma:      out += ","
            default:          out += text
            }
        }
        return out
    }

    /// Whether `json` is valid per RFC 8259 — which is stricter than `JSONSerialization`.
    ///
    /// `JSONSerialization` accepts trailing commas (`[1,2,]`, `{"a":1,}`) even though the spec
    /// forbids them. Delegating validity to it wholesale would matter here: the scanner would
    /// faithfully re-emit that comma on its own line, so formatting a file Apple's parser tolerates
    /// would hand back output that other parsers reject. The alternative — silently dropping the
    /// comma — is a content edit, and this formatter only moves whitespace. So it declines.
    public static func isValid(_ json: String) -> Bool {
        guard (try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])) != nil
        else { return false }
        var lastWasComma = false
        var trailing = false
        forEachToken(json) { kind, _ in
            switch kind {
            case .whitespace: break                          // does not separate a comma from a closer
            case .close:      if lastWasComma { trailing = true }; lastWasComma = false
            case .comma:      lastWasComma = true
            default:          lastWasComma = false
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
                    if escaped { escaped = false }
                    else if c == "\\" { escaped = true }
                    else if c == "\"" { end = json.index(after: end); break }
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
            // `isWhitespace` rather than matching " \t\n\r": Swift clusters CRLF into ONE
            // Character, which equals neither "\r" nor "\n". Matching the four individually let
            // every CRLF line ending fall through to the token branch below and be copied into
            // the output verbatim, so Windows files came back with their old breaks embedded.
            // Anything `isWhitespace` accepts here is legal JSON whitespace — validity is
            // already established, so a stray non-breaking space cannot reach this point.
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
        var pendingOpen: Character?     // held so `{}` and `[]` stay on one line

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
                depth += 1                  // only a container with content opens a level
                newline()
            }
            switch kind {
            case .whitespace:
                break                       // all original spacing is discarded
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
