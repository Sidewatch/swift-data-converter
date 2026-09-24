//
//  CSVEdit.swift
//  DataConverter
//
//  One field of a CSV rewritten in place; every other byte kept.
//
//  Created by David Sherlock on 9/24/26.
//

import Foundation

/// One cell of a CSV file changed in place — what an edited cell in a CSV table writes back
/// (24 Sep 2026, David: "should it be possible to edit the values in the preview? we support it
/// elsewhere"). The tokenizer's raw field ranges say exactly which bytes the old field occupied,
/// so the rest of the file — its line endings, its quoting, its ragged rows — is untouched; the
/// new value is quoted only when CSV needs it to be.
public enum CSVEdit {
    /// The bytes that would change in `text` if field `column` of `record` (both 0-based; the
    /// header is record 0) became `value`: the range of the old raw field and the text to put
    /// there. A record shorter than `column` gains the commas it needs. Nil when the record
    /// does not exist.
    public static func fieldReplacement(in text: String, record: Int, column: Int, with value: String) -> (range: Range<String.Index>, replacement: String)? {
        let records = CSVTokenizer.fieldRanges(in: text)
        guard records.indices.contains(record), column >= 0 else { return nil }
        let fields = records[record]
        let bytes = Array(text.utf8)
        func index(atByte b: Int) -> String.Index { text.utf8.index(text.utf8.startIndex, offsetBy: b) }
        if fields.indices.contains(column) {
            let r = fields[column]
            return (index(atByte: r.lowerBound)..<index(atByte: r.upperBound), encoded(value))
        }
        let end = fields.last?.upperBound ?? 0
        let missing = column - fields.count + 1
        _ = bytes
        return (index(atByte: end)..<index(atByte: end), String(repeating: ",", count: missing) + encoded(value))
    }

    /// `text` with field `column` of `record` replaced by `value`, or nil when the record does
    /// not exist.
    public static func replacingField(in text: String, record: Int, column: Int, with value: String) -> String? {
        guard let edit = fieldReplacement(in: text, record: record, column: column, with: value) else { return nil }
        var out = text
        out.replaceSubrange(edit.range, with: edit.replacement)
        return out
    }

    /// `value` as a CSV field: quoted, with quotes doubled, when it holds a comma, a quote, a
    /// line break, or leading / trailing whitespace; otherwise as it is.
    public static func encoded(_ value: String) -> String {
        let needsQuotes = value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline })
            || value.first?.isWhitespace == true || value.last?.isWhitespace == true
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
