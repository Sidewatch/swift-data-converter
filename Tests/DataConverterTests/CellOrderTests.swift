//
//  CellOrderTests.swift
//  DataConverterTests
//
//  Tests for the one cell-ordering rule every grid shares: numbers as numbers, names as Finder
//  sorts them, NULL first on request, and a stable permutation.
//
//  Created by David Sherlock on 9/22/26.
//

import XCTest
@testable import DataConverter

/// Tests for `CellOrder`: numeric when both cells are numbers, Finder order otherwise, SQL NULL
/// first when asked, and a permutation that keeps ties in arrival order.
final class CellOrderTests: XCTestCase {

    func testNumbersOrderAsNumbersNotAsText() {
        XCTAssertEqual(CellOrder.compare("9", "10"), .orderedAscending, "text order would put 10 before 9")
        XCTAssertEqual(CellOrder.compare("-2", "1"), .orderedAscending)
        XCTAssertEqual(CellOrder.compare("1e3", "999"), .orderedDescending, "scientific notation is a number")
        XCTAssertEqual(CellOrder.compare("2.50", "2.5"), .orderedSame)
    }

    func testTextOrdersFinderStyleWithDigitSuffixesInNumericOrder() {
        XCTAssertEqual(CellOrder.compare("file2", "file10"), .orderedAscending)
        XCTAssertEqual(CellOrder.compare("apple", "Banana"), .orderedAscending, "case does not split the alphabet")
        XCTAssertEqual(CellOrder.compare("same", "same"), .orderedSame)
    }

    func testAMixedPairFallsToTheStringPath() {
        XCTAssertEqual(CellOrder.compare("10", "abc"), "10".localizedStandardCompare("abc"))
        XCTAssertEqual(CellOrder.compare("", "0"), .orderedAscending, "an empty cell is text, before everything")
    }

    func testNullIsFirstOnlyWhenAsked() {
        XCTAssertEqual(CellOrder.compare("NULL", "a", nullsFirst: true), .orderedAscending)
        XCTAssertEqual(CellOrder.compare("a", "NULL", nullsFirst: true), .orderedDescending)
        XCTAssertEqual(CellOrder.compare("NULL", "NULL", nullsFirst: true), .orderedSame)
        XCTAssertEqual(CellOrder.compare("NULL", "a", nullsFirst: false), "NULL".localizedStandardCompare("a"),
                       "a CSV grid has no NULL: the word sorts among the Ns")
        XCTAssertEqual(CellOrder.compare("NULL", "-5", nullsFirst: true), .orderedAscending, "NULL is below every number too")
    }

    func testPermutationSortsByTheColumnAndKeepsTiesInArrivalOrder() {
        let rows = [["b", "2"], ["a", "10"], ["c", "2"], ["a", "9"]]
        XCTAssertEqual(CellOrder.permutation(of: rows, by: 0, ascending: true), [1, 3, 0, 2], "the two a-rows keep their arrival order")
        XCTAssertEqual(CellOrder.permutation(of: rows, by: 1, ascending: true), [0, 2, 3, 1], "2, 2, 9, 10 — numeric, ties in arrival order")
        XCTAssertEqual(CellOrder.permutation(of: rows, by: 1, ascending: false), [1, 3, 0, 2], "descending reverses unequal cells, not the ties")
    }

    func testAShortRowSortsAsAnEmptyCellAndAnOutOfRangeColumnChangesNothing() {
        let rows = [["b", "x"], ["a"], ["c", "y"]]
        XCTAssertEqual(CellOrder.permutation(of: rows, by: 1, ascending: true), [1, 0, 2], "the short row's missing cell is empty, first")
        XCTAssertEqual(CellOrder.permutation(of: rows, by: 7, ascending: true), [0, 1, 2], "every cell empty: arrival order")
        XCTAssertEqual(CellOrder.permutation(of: rows, by: -1, ascending: false), [0, 1, 2])
        XCTAssertEqual(CellOrder.permutation(of: [], by: 0, ascending: true), [])
    }

    func testPermutationHonoursNullsFirst() {
        let rows = [["1"], ["NULL"], ["0"]]
        XCTAssertEqual(CellOrder.permutation(of: rows, by: 0, ascending: true, nullsFirst: true), [1, 2, 0])
        XCTAssertEqual(CellOrder.permutation(of: rows, by: 0, ascending: false, nullsFirst: true), [0, 2, 1], "descending: NULL last")
    }
}
