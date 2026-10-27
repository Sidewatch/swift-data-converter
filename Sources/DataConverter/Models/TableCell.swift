//
//  TableCell.swift
//  DataConverter
//
//  One cell of a table copied out as text: its value, typed where the source knows the type.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One cell of a table written out by ``TableText``. A database cell keeps its storage class (a real NULL, a number,
/// text, a blob); a cell of a CSV file or a record table is text.
public enum TableCell: Sendable, Equatable {
    /// SQL NULL: `null` in JSON, an empty field in CSV and TSV, `NULL` in a Markdown table.
    case null
    /// A whole number.
    case integer(Int64)
    /// A floating-point number.
    case real(Double)
    /// Text, as the source holds it.
    case text(String)
    /// A blob of `count` bytes, with its bytes when the source kept them (nil for one too big to keep).
    case blob(Data?, count: Int)
}
