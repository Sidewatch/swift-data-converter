//
//  YAMLEditTests.swift
//  DataConverterTests
//
//  A typed YAML replacement keeps its kind and is quoted only when YAML would misread it.
//
//  Created by David Sherlock on 9/25/26.
//

import XCTest
@testable import DataConverter

final class YAMLEditTests: XCTestCase {
    func testEncodingKeepsTheKindAndQuotesWhatYAMLWouldMisread() {
        XCTAssertEqual(YAMLEdit.encodedScalar("nginx", kind: .string), "nginx")
        XCTAssertEqual(YAMLEdit.encodedScalar("42", kind: .string), "\"42\"", "a string that looks like a number is quoted")
        XCTAssertEqual(YAMLEdit.encodedScalar("yes", kind: .string), "\"yes\"")
        XCTAssertEqual(YAMLEdit.encodedScalar("a: b", kind: .string), "\"a: b\"")
        XCTAssertEqual(YAMLEdit.encodedScalar("- item", kind: .string), "\"- item\"")
        XCTAssertEqual(YAMLEdit.encodedScalar("two\nlines", kind: .string), "\"two\\nlines\"")
        XCTAssertEqual(YAMLEdit.encodedScalar("", kind: .string), "\"\"")
        XCTAssertEqual(YAMLEdit.encodedScalar("42", kind: .number), "42")
        XCTAssertEqual(YAMLEdit.encodedScalar("lots", kind: .number), "lots", "not a number: a plain string")
        XCTAssertEqual(YAMLEdit.encodedScalar("true", kind: .bool), "true")
        XCTAssertEqual(YAMLEdit.encodedScalar("null", kind: .null), "null")
        XCTAssertEqual(YAMLEdit.encodedKey("plain-key"), "plain-key")
        XCTAssertEqual(YAMLEdit.encodedKey("with: colon"), "\"with: colon\"")
        XCTAssertEqual(StructuredEdit.doubleQuoted("a \"q\" \\ \n\ttab\u{1}"), "\"a \\\"q\\\" \\\\ \\n\\ttab\\u0001\"", "the one escaper both formats share")
    }
}
