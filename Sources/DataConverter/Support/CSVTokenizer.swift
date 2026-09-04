import Foundation

/// Tokenizes CSV text into records of raw fields, header row included.
///
/// Quote-aware: a newline only ends a record when NOT inside quotes, so multiline quoted fields
/// survive; doubled quotes (`""`) unescape to one quote; LF, CRLF and bare CR all end a record.
/// Scans UTF-8 bytes rather than Characters so a multi-MB file avoids grapheme segmentation.
struct CSVTokenizer {
    private let bytes: [UInt8]
    private var index = 0
    /// Start of the pending byte run that belongs to `field`.
    private var runStart = 0
    private var inQuotes = false
    private var field = ""
    private var row: [String] = []
    private var records: [[String]] = []

    private init(_ text: String) { bytes = Array(text.utf8) }

    /// Every record of `text`, as raw fields.
    static func records(in text: String) -> [[String]] {
        var tokenizer = CSVTokenizer(text)
        return tokenizer.run()
    }

    private mutating func run() -> [[String]] {
        while index < bytes.count {
            if inQuotes { scanQuoted() } else { scanUnquoted() }
        }
        // A final row with no trailing newline still counts.
        if runStart < bytes.count || !field.isEmpty || !row.isEmpty { endRow() }
        return records
    }

    // MARK: - The two states

    private mutating func scanQuoted() {
        guard bytes[index] == ASCII.quote else { index += 1; return }
        flush()
        if next(is: ASCII.quote) {
            field.append("\"")          // "" → one literal quote
            advance(by: 2)
        } else {
            inQuotes = false
            advance(by: 1)
        }
    }

    private mutating func scanUnquoted() {
        switch bytes[index] {
        case ASCII.quote:
            flush(); inQuotes = true; advance(by: 1)
        case ASCII.comma:
            endField(); advance(by: 1)
        case ASCII.cr:
            endRow(); advance(by: next(is: ASCII.lf) ? 2 : 1)   // CRLF is one terminator; bare CR also ends a row
        case ASCII.lf:
            endRow(); advance(by: 1)
        default:
            index += 1
        }
    }

    // MARK: - Steps

    /// Whether the byte after the current one is `byte`.
    private func next(is byte: UInt8) -> Bool { index + 1 < bytes.count && bytes[index + 1] == byte }

    /// Moves past `n` bytes and starts a fresh run there.
    private mutating func advance(by n: Int) { index += n; runStart = index }

    /// Appends the pending run to the field.
    private mutating func flush() {
        if index > runStart { field += String(decoding: bytes[runStart..<index], as: UTF8.self) }
    }

    private mutating func endField() { flush(); row.append(field); field = "" }

    private mutating func endRow() { endField(); records.append(row); row = [] }
}
