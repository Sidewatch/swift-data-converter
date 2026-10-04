//
//  JupyterNotebook.swift
//  DataConverter
//
//  A Jupyter notebook (.ipynb) as one Markdown document: Markdown cells as written, code cells
//  as fenced blocks in the kernel's language, outputs as text blocks and inline images.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A Jupyter notebook read as Markdown, so a Markdown preview can show it as the notebook
/// reads: Markdown cells as they are, code cells fenced in the kernel's language and numbered
/// (`In [3]`), outputs after them — streams and plain-text results as `text` blocks, errors with
/// their ANSI colour codes removed, PNG and JPEG images inline as data URIs. HTML outputs are
/// not rendered (a notebook's HTML is code the preview would run); their plain-text form is
/// shown when the notebook carries one. Each cell opens with an empty `<div id="cell-N">` — a
/// block, so it never joins a paragraph — for a host to scroll the rendered page to;
/// ``cellIndex(atUTF16Offset:in:)`` finds which cell a place in the JSON belongs to.
public enum JupyterNotebook {

    /// Counts for a summary line.
    public struct Summary: Equatable, Sendable {
        /// Code cells.
        public let codeCells: Int
        /// Markdown cells.
        public let markdownCells: Int
        /// The kernel's language (`python`), if the notebook names one.
        public let language: String?
    }

    /// The notebook in `data` as Markdown, or nil when it is not a notebook.
    public static func markdown(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cells = root["cells"] as? [[String: Any]]
        else { return nil }
        let language = self.language(root) ?? ""
        var out: [String] = []
        for (index, cell) in cells.enumerated() {
            out.append("<div id=\"\(anchor(ofCell: index))\"></div>")
            let source = text(cell["source"])
            switch cell["cell_type"] as? String {
            case "markdown":
                out.append(source)
            case "code":
                let count = (cell["execution_count"] as? Int).map { "In [\($0)]" } ?? "In [ ]"
                out.append("*\(count):*\n\n" + fence(source, language: language))
                for output in cell["outputs"] as? [[String: Any]] ?? [] { out.append(contentsOf: rendered(output)) }
            default:
                if !source.isEmpty { out.append(fence(source, language: "text")) }
            }
        }
        return out.joined(separator: "\n\n") + "\n"
    }

    /// The id of cell `index`'s anchor in ``markdown(from:)``'s output.
    public static func anchor(ofCell index: Int) -> String { "cell-\(index)" }

    /// The index of the cell whose JSON holds the UTF-16 `offset` of the notebook `text`, or nil
    /// when the offset is outside every cell (the notebook's metadata). Each probe is one scan of
    /// the text; a binary search over the cells keeps it to a handful.
    public static func cellIndex(atUTF16Offset offset: Int, in text: String) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
            let count = (root["cells"] as? [Any])?.count, count > 0
        else { return nil }
        func span(_ index: Int) -> Range<Int>? {
            guard let site = JSONEdit.site(in: text, path: [.key("cells"), .index(index)]) else { return nil }
            return site.value.lowerBound.utf16Offset(in: text)..<site.value.upperBound.utf16Offset(in: text)
        }
        var low = 0, high = count - 1
        while low < high {  // the last cell starting at or before `offset`
            let mid = (low + high + 1) / 2
            guard let start = span(mid)?.lowerBound else { return nil }
            if start <= offset { low = mid } else { high = mid - 1 }
        }
        return span(low).map { $0.contains(offset) } == true ? low : nil
    }

    /// How many cells of each kind, and the language.
    public static func summary(from data: Data) -> Summary? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cells = root["cells"] as? [[String: Any]]
        else { return nil }
        return Summary(
            codeCells: cells.filter { $0["cell_type"] as? String == "code" }.count,
            markdownCells: cells.filter { $0["cell_type"] as? String == "markdown" }.count,
            language: language(root))
    }

    // MARK: - Pieces

    static func language(_ root: [String: Any]) -> String? {
        let meta = root["metadata"] as? [String: Any]
        return (meta?["language_info"] as? [String: Any])?["name"] as? String
            ?? (meta?["kernelspec"] as? [String: Any])?["language"] as? String
    }

    /// A notebook string field: one string, or an array of lines.
    static func text(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let lines = value as? [String] { return lines.joined() }
        return ""
    }

    /// One output as Markdown blocks.
    static func rendered(_ output: [String: Any]) -> [String] {
        switch output["output_type"] as? String {
        case "stream":
            let body = text(output["text"])
            return body.isEmpty ? [] : [fence(body, language: "text")]
        case "error":
            let trace =
                (output["traceback"] as? [String])?.joined(separator: "\n")
                ?? "\(output["ename"] as? String ?? ""): \(output["evalue"] as? String ?? "")"
            return [fence(stripANSI(trace), language: "text")]
        case "execute_result", "display_data":
            guard let data = output["data"] as? [String: Any] else { return [] }
            for type in ["image/png", "image/jpeg"] {
                if let base64 = (data[type] as? String) ?? (data[type] as? [String])?.joined() {
                    let compact = base64.filter { !$0.isWhitespace }
                    return ["![output](data:\(type);base64,\(compact))"]
                }
            }
            if let plain = data["text/plain"] {
                let body = text(plain)
                return body.isEmpty ? [] : [fence(body, language: "text")]
            }
            return []
        default:
            return []
        }
    }

    /// `body` in a fence long enough that a run of backticks inside cannot close it.
    static func fence(_ body: String, language: String) -> String {
        var longest = 0, run = 0
        for c in body { run = c == "`" ? run + 1 : 0; longest = max(longest, run) }
        let ticks = String(repeating: "`", count: max(3, longest + 1))
        let trimmed = body.hasSuffix("\n") ? String(body.dropLast()) : body
        return ticks + language + "\n" + trimmed + "\n" + ticks
    }

    /// `s` without ANSI escape sequences (tracebacks carry colour codes).
    static func stripANSI(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
    }
}
