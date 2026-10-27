//
//  TableText.swift
//  DataConverter
//
//  A table's rows as text to paste elsewhere: CSV, TSV, a Markdown table or JSON.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A table, column names and rows of ``TableCell``, as text to paste into a spreadsheet, a document or a message to
/// an agent. Every writer keeps the column order and writes every row it is given; a row shorter than the header is
/// read as empty text in the missing columns, and a longer one gets `column_N` names for the extra ones.
public enum TableText {
    /// CSV with a header row: a field is quoted when it holds a comma, a quote, a line break or whitespace at either
    /// end (``CSVEdit/encoded(_:)``). NULL is an empty field; a blob is its bytes in base64.
    public static func csv(columns: [String], rows: [[TableCell]]) -> String {
        let (names, rows) = shaped(columns, rows)
        return ([names] + rows.map { $0.map(field) }).map { $0.map(CSVEdit.encoded).joined(separator: ",") + "\n" }.joined()
    }

    /// Tab-separated, one row a line, with the header row when `header`: what a spreadsheet takes on paste. A field
    /// holding a tab, a quote or a line break is quoted the way CSV quotes it, as spreadsheets copy a multi-line cell
    /// (``DataConverter/tsvRecords(_:)`` reads tabs only, so it keeps such quotes as text). NULL is an empty field.
    public static func tsv(columns: [String], rows: [[TableCell]], header: Bool = false) -> String {
        let (names, rows) = shaped(columns, rows)
        return ((header ? [names] : []) + rows.map { $0.map(field) }).map { $0.map(tsvField).joined(separator: "\t") + "\n" }.joined()
    }

    /// A Markdown pipe table: `|` escaped, line breaks as `<br>`, NULL as `NULL`, a blob by its size, a column of
    /// numbers aligned right.
    public static func markdown(columns: [String], rows: [[TableCell]]) -> String {
        let (names, rows) = shaped(columns, rows)
        let alignments = names.indices.map { column -> String in
            let values = rows.map { $0[column] }.filter { $0 != .null }
            let numeric =
                !values.isEmpty && values.allSatisfy { if case .integer = $0 { true } else if case .real = $0 { true } else { false } }
            return numeric ? "---:" : "---"
        }
        func line(_ cells: [String]) -> String { "| " + cells.joined(separator: " | ") + " |\n" }
        return line(names.map { markdownText($0.isEmpty ? " " : $0) }) + line(alignments)
            + rows.map { line($0.map(markdownCell)) }.joined()
    }

    /// A JSON array of objects, indented by two spaces, each object's keys in column order (a repeated column name made
    /// distinct by ``ColumnNames/unique(_:)``). NULL is `null`, a number is a number (one that is not finite is a
    /// string), a blob is its bytes in base64, or the text "‹blob N bytes›" when its bytes were not kept.
    public static func json(columns: [String], rows: [[TableCell]]) -> String {
        let (names, rows) = shaped(columns, rows)
        let keys = ColumnNames.unique(names).map(StructuredValue.jsonString)
        guard !rows.isEmpty else { return "[]\n" }
        let objects = rows.map { row in
            "  {\n" + zip(keys, row).map { "    \($0): \(jsonValue($1))" }.joined(separator: ",\n") + "\n  }"
        }
        return "[\n" + objects.joined(separator: ",\n") + "\n]\n"
    }

    /// One cell as plain text, what Copy Cell copies: NULL as `NULL`, a blob as its bytes in base64.
    public static func plain(_ cell: TableCell) -> String {
        cell == .null ? "NULL" : field(cell)
    }

    // MARK: - Cells

    /// The header and rows at one width: the widest row's, extra columns named `column_N`, short rows padded with
    /// empty text.
    private static func shaped(_ columns: [String], _ rows: [[TableCell]]) -> ([String], [[TableCell]]) {
        let width = rows.reduce(columns.count) { max($0, $1.count) }
        let names = columns + (columns.count..<width).map { "column_\($0 + 1)" }
        return (names, rows.map { $0.count < width ? $0 + Array(repeating: .text(""), count: width - $0.count) : $0 })
    }

    /// A cell's text in a CSV or TSV field: NULL empty, a number as Swift writes it, a blob in base64.
    private static func field(_ cell: TableCell) -> String {
        switch cell {
        case .null: return ""
        case .integer(let value): return String(value)
        case .real(let value): return "\(value)"
        case .text(let text): return text
        case .blob(let bytes, let count): return bytes?.base64EncodedString() ?? blobPlaceholder(count)
        }
    }

    /// A TSV field: quoted, with quotes doubled, only when it holds a tab, a quote or a line break.
    private static func tsvField(_ text: String) -> String {
        guard text.contains(where: { $0 == "\t" || $0 == "\"" || $0.isNewline }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// A Markdown table cell's text.
    private static func markdownCell(_ cell: TableCell) -> String {
        switch cell {
        case .null: return "NULL"
        case .blob(_, let count): return blobPlaceholder(count)
        default: return markdownText(field(cell))
        }
    }

    /// Text that stays inside its Markdown table cell: pipes escaped, every line break a `<br>`.
    private static func markdownText(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>").replacingOccurrences(of: "\r", with: "<br>")
    }

    /// A cell as a JSON value.
    private static func jsonValue(_ cell: TableCell) -> String {
        switch cell {
        case .null: return "null"
        case .integer(let value): return String(value)
        case .real(let value) where value.isFinite: return "\(value)"
        case .real(let value): return StructuredValue.jsonString(value.isNaN ? "NaN" : value > 0 ? "Infinity" : "-Infinity")
        case .text(let text): return StructuredValue.jsonString(text)
        case .blob(let bytes, let count): return StructuredValue.jsonString(bytes?.base64EncodedString() ?? blobPlaceholder(count))
        }
    }

    /// What stands for a blob whose bytes are not written out.
    private static func blobPlaceholder(_ count: Int) -> String { "‹blob \(count) bytes›" }
}
