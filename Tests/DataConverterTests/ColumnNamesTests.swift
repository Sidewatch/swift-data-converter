//
//  ColumnNamesTests.swift
//  DataConverterTests
//
//  Column names made distinct for the keys of a JSON object.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest

@testable import DataConverter

final class ColumnNamesTests: XCTestCase {
    /// Repeats are numbered in order; a suffix another column already has is skipped.
    func testRepeatsAreNumberedAroundNamesAlreadyTaken() {
        XCTAssertEqual(ColumnNames.unique(["id", "name", "id", "id"]), ["id", "name", "id_2", "id_3"])
        XCTAssertEqual(ColumnNames.unique(["id", "id_2", "id"]), ["id", "id_2", "id_3"])
        XCTAssertEqual(ColumnNames.unique(["a", "b"]), ["a", "b"])
        XCTAssertEqual(ColumnNames.unique([]), [])
    }

    /// The converter's CSV reader names repeated headers the same way.
    func testTheCSVReaderUsesTheSameNames() {
        let rows = DataConverter.parseCSV("id,id_2,id\n1,2,3\n")
        XCTAssertEqual(rows.first?["id_3"] as? String, "3")
        XCTAssertEqual(rows.first?["id_2"] as? String, "2")
    }
}
