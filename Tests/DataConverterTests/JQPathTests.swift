//
//  JQPathTests.swift
//  DataConverterTests
//
//  A path into a document as jq writes it.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest

@testable import DataConverter

final class JQPathTests: XCTestCase {
    /// Bare names after a dot, indexes in brackets, `.` for the whole document.
    func testBareNamesAndIndexes() {
        XCTAssertEqual(JQPath.path([]), ".")
        XCTAssertEqual(JQPath.path([.key("users"), .index(0), .key("name")]), ".users[0].name")
        XCTAssertEqual(JQPath.path([.index(2)]), ".[2]")
        XCTAssertEqual(JQPath.path([.key("_x1")]), "._x1")
    }

    /// A key jq cannot take after a dot is quoted in brackets: spaces, dashes, a leading digit, a letter outside ASCII,
    /// a jq keyword, a quote.
    func testOtherKeysAreQuoted() {
        XCTAssertEqual(JQPath.path([.key("a b")]), #".["a b"]"#)
        XCTAssertEqual(JQPath.path([.key("a"), .key("b-c")]), #".a["b-c"]"#)
        XCTAssertEqual(JQPath.path([.key("9lives")]), #".["9lives"]"#)
        XCTAssertEqual(JQPath.path([.key("café")]), #".["café"]"#)
        XCTAssertEqual(JQPath.path([.key("if")]), #".["if"]"#)
        XCTAssertEqual(JQPath.path([.key(#"say "hi""#)]), #".["say \"hi\""]"#)
    }
}
