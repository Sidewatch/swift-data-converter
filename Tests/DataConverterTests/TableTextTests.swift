//
//  TableTextTests.swift
//  DataConverterTests
//
//  A table's rows as CSV, TSV, a Markdown table and JSON.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import XCTest

@testable import DataConverter

final class TableTextTests: XCTestCase {
    /// CSV quotes a field only when it must: a comma, a quote, a line break, whitespace at an end. NULL is empty.
    func testCSVQuotesOnlyWhatNeedsIt() {
        let rows: [[TableCell]] = [
            [.integer(1), .text("a, b")], [.null, .text("say \"hi\"")], [.real(2.5), .text(" padded ")],
            [.integer(4), .text("two\nlines")],
        ]
        XCTAssertEqual(
            TableText.csv(columns: ["id", "note"], rows: rows),
            "id,note\n1,\"a, b\"\n,\"say \"\"hi\"\"\"\n2.5,\" padded \"\n4,\"two\nlines\"\n")
    }

    /// TSV pastes into a spreadsheet: no header unless asked, a field quoted only for a tab, a quote or a line break.
    func testTSVForAPaste() {
        let rows: [[TableCell]] = [[.integer(1), .text("x\ty")], [.text("two\nlines"), .null], [.text("plain, text"), .text("ok")]]
        XCTAssertEqual(TableText.tsv(columns: ["a", "b"], rows: rows), "1\t\"x\ty\"\n\"two\nlines\"\t\nplain, text\tok\n")
        XCTAssertEqual(TableText.tsv(columns: ["a", "b"], rows: [[.integer(1), .integer(2)]], header: true), "a\tb\n1\t2\n")
    }

    /// A Markdown table keeps its cells in their cells (`|` escaped, line breaks as `<br>`), says NULL, and aligns a
    /// column of numbers right.
    func testMarkdownEscapesAndAlignsNumbers() {
        let rows: [[TableCell]] = [
            [.integer(1), .text("a|b"), .blob(nil, count: 9)], [.real(2.5), .text("x\ny"), .null], [.null, .null, .null],
        ]
        XCTAssertEqual(
            TableText.markdown(columns: ["n", "", "data"], rows: rows),
            "| n |   | data |\n| ---: | --- | --- |\n| 1 | a\\|b | ‹blob 9 bytes› |\n| 2.5 | x<br>y | NULL |\n| NULL | NULL | NULL |\n")
    }

    /// JSON keeps each cell's type and the column order, makes a repeated column name distinct, writes a number that is
    /// not finite as a string, a kept blob in base64 and an unkept one by its size; it parses.
    func testJSONKeepsTypesOrderAndDistinctKeys() throws {
        let columns = ["id", "id", "name", "score", "ratio", "blob", "big", "none"]
        let row: [TableCell] = [
            .integer(7), .integer(8), .text("Zoë \"Q\"\n"), .real(.infinity), .real(0.5), .blob(Data([1, 2, 3]), count: 3),
            .blob(nil, count: 1_000_000), .null,
        ]
        let text = TableText.json(columns: columns, rows: [row])
        XCTAssertEqual(
            text,
            """
            [
              {
                "id": 7,
                "id_2": 8,
                "name": "Zoë \\"Q\\"\\n",
                "score": "Infinity",
                "ratio": 0.5,
                "blob": "AQID",
                "big": "‹blob 1000000 bytes›",
                "none": null
              }
            ]

            """)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
        XCTAssertEqual(parsed.first?["id_2"] as? Int, 8)
        XCTAssertTrue(parsed.first?["none"] is NSNull)
        XCTAssertEqual(TableText.json(columns: ["a"], rows: []), "[]\n")
    }

    /// A row shorter than the header reads as empty text; a longer one names its extra columns.
    func testRaggedRowsTakeTheWidestShape() {
        XCTAssertEqual(TableText.csv(columns: ["a"], rows: [[.text("1"), .text("2")], []]), "a,column_2\n1,2\n,\n")
    }

    /// One cell as Copy Cell copies it.
    func testPlainCell() {
        XCTAssertEqual(TableText.plain(.null), "NULL")
        XCTAssertEqual(TableText.plain(.integer(3)), "3")
        XCTAssertEqual(TableText.plain(.blob(Data([255]), count: 1)), "/w==")
        XCTAssertEqual(TableText.plain(.text("x")), "x")
    }
}
