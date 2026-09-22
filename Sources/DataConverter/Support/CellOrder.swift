//
//  CellOrder.swift
//  DataConverter
//
//  How one grid cell orders against another: numeric when both cells are numbers, Finder-style
//  otherwise, with SQL NULL first when a grid asks for it.
//
//  Created by David Sherlock on 9/17/26.
//

import Foundation

/// How one grid cell orders against another.
///
/// Numeric when BOTH cells parse as numbers (so "10" sorts after "9", and scientific or
/// negative values order correctly); otherwise Finder-style string order, which already
/// handles digit-suffixed names. Mixed columns fall to the string path.
///
/// One rule for every grid: a CSV viewer and a database grid that look identical must not
/// sort differently, and a second copy of the rule is how they start to.
public enum CellOrder {

    /// A database grid's display string for SQL NULL. Ordered before every value when
    /// `nullsFirst` is asked for, which is what SQLite itself does ascending — a NULL is "less
    /// than" anything, not the literal four-letter word sorted among the Ns.
    public static let null = "NULL"

    /// `a` against `b`.
    ///
    /// - Parameters:
    ///   - a: One cell's display text.
    ///   - b: The other's.
    ///   - nullsFirst: Whether ``null`` is special: first ascending, equal to itself.
    /// - Returns: Numeric order when both parse as `Double`, otherwise
    ///   `localizedStandardCompare` (Finder order).
    public static func compare(_ a: String, _ b: String, nullsFirst: Bool = false) -> ComparisonResult {
        if nullsFirst, a == null || b == null {
            if a == b { return .orderedSame }
            return a == null ? .orderedAscending : .orderedDescending
        }
        if let x = Double(a), let y = Double(b) {
            return x == y ? .orderedSame : (x < y ? .orderedAscending : .orderedDescending)
        }
        return a.localizedStandardCompare(b)
    }

    /// `rows` ordered by column `index`, as a permutation of row indices.
    ///
    /// Stable: equal cells keep the order they arrived in, because a grid that shuffles ties on
    /// every click reads as broken. A row too short for `index` sorts as an empty cell. The
    /// permutation lets a caller reorder a parallel array (a database grid's rowids) with
    /// exactly the same moves.
    ///
    /// - Parameters:
    ///   - rows: The grid's rows, each a list of cell texts.
    ///   - index: The column to order by.
    ///   - ascending: `false` reverses the order of unequal cells; ties still keep arrival order.
    ///   - nullsFirst: Passed to ``compare(_:_:nullsFirst:)``.
    /// - Returns: The row indices in display order.
    public static func permutation(of rows: [[String]], by index: Int, ascending: Bool,
                                   nullsFirst: Bool = false) -> [Int] {
        func cell(_ row: [String]) -> String { index >= 0 && index < row.count ? row[index] : "" }
        return rows.indices.sorted { i, j in
            let r = compare(cell(rows[i]), cell(rows[j]), nullsFirst: nullsFirst)
            if r != .orderedSame { return ascending ? r == .orderedAscending : r == .orderedDescending }
            return i < j
        }
    }
}
