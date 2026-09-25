//
//  JSONStructureTests.swift
//  DataConverterTests
//
//  JSON read as ordered structure: key order kept, scalars keeping their type.
//
//  Created by David Sherlock on 9/26/26.
//

import XCTest
@testable import DataConverter

final class JSONStructureTests: XCTestCase {
    private func keys(_ value: StructuredValue?) -> [String] {
        guard case .mapping(let pairs)? = value else { return [] }
        return pairs.map(\.key)
    }

    /// The whole point: `JSONSerialization` would hand back an unordered dictionary.
    func testKeysKeepTheFilesOrder() {
        let json = #"{"zebra": 1, "apple": 2, "mango": 3, "banana": 4}"#
        XCTAssertEqual(keys(JSONStructure.value(of: json)), ["zebra", "apple", "mango", "banana"])
    }

    func testScalarsKeepTheirType() {
        let json = #"{"i": 42, "d": 1.5, "e": 2e3, "t": true, "f": false, "n": null, "s": "42"}"#
        guard case .mapping(let pairs)? = JSONStructure.value(of: json) else { return XCTFail("did not parse") }
        let by = Dictionary(uniqueKeysWithValues: pairs.map { ($0.key, $0.value) })
        XCTAssertEqual(by["i"], .integer(42))
        XCTAssertEqual(by["d"], .number(1.5))
        XCTAssertEqual(by["e"], .number(2000))
        XCTAssertEqual(by["t"], .bool(true))
        XCTAssertEqual(by["f"], .bool(false))
        XCTAssertEqual(by["n"], .null)
        XCTAssertEqual(by["s"], .string("42"), "a quoted number is a string")
    }

    func testNegativeAndLargeNumbers() {
        guard case .sequence(let items)? = JSONStructure.value(of: "[-7, -1.25, 9007199254740993]") else {
            return XCTFail("did not parse")
        }
        XCTAssertEqual(items[0], .integer(-7))
        XCTAssertEqual(items[1], .number(-1.25))
        if case .integer = items[2] {} else { XCTFail("an integer that fits Int should stay one: \(items[2])") }
    }

    func testNestingAndEmptyContainers() {
        let json = #"{"a": {"b": [1, {"c": []}]}, "d": {}}"#
        guard case .mapping(let pairs)? = JSONStructure.value(of: json) else { return XCTFail("did not parse") }
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[1].value, .mapping([]))
        guard case .mapping(let a) = pairs[0].value, case .sequence(let b) = a[0].value else {
            return XCTFail("shape wrong")
        }
        XCTAssertEqual(b[0], .integer(1))
        XCTAssertEqual(b[1], .mapping([StructuredPair(key: "c", value: .sequence([]))]))
    }

    func testStringEscapesAreResolvedBecauseTheTreeShowsTheText() {
        let json = #"{"s": "a\"b\\c\nd\te\/fAé"}"#
        guard case .mapping(let pairs)? = JSONStructure.value(of: json) else { return XCTFail("did not parse") }
        XCTAssertEqual(pairs[0].value, .string("a\"b\\c\nd\te/fAé"))
    }

    /// An emoji written as a surrogate pair must come back as one character, not two broken ones.
    func testSurrogatePairsBecomeOneScalar() {
        guard case .mapping(let pairs)? = JSONStructure.value(of: #"{"s": "😀"}"#) else {
            return XCTFail("did not parse")
        }
        XCTAssertEqual(pairs[0].value, .string("😀"))
    }

    func testUnicodeOutsideEscapesSurvives() {
        guard case .mapping(let pairs)? = JSONStructure.value(of: #"{"s": "héllo 😀 世界"}"#) else {
            return XCTFail("did not parse")
        }
        XCTAssertEqual(pairs[0].value, .string("héllo 😀 世界"))
    }

    func testWhitespaceAndNewlinesBetweenTokens() {
        let json = "{\n  \"a\" :\t1 ,\r\n  \"b\" : [ 2 , 3 ]\n}"
        XCTAssertEqual(keys(JSONStructure.value(of: json)), ["a", "b"])
    }

    func testARootScalarOrArrayIsAValidDocument() {
        XCTAssertEqual(JSONStructure.value(of: "42"), .integer(42))
        XCTAssertEqual(JSONStructure.value(of: #""hi""#), .string("hi"))
        XCTAssertEqual(JSONStructure.value(of: "[1,2]"), .sequence([.integer(1), .integer(2)]))
    }

    /// Half a record shown as fact is worse than no record, so a broken document yields nil.
    func testMalformedDocumentsYieldNilRatherThanAPartialTree() {
        for bad in [#"{"a": 1"#, #"{"a" 1}"#, #"{a: 1}"#, "[1, 2", #""unterminated"#,
                    "{}{}", "", "   ", "tru", #"{"a": }"#, #"{"a": 1,}"#] {
            XCTAssertNil(JSONStructure.value(of: bad), "should not parse: \(bad)")
        }
    }

    /// Trailing content is a document boundary problem, and it is exactly what makes a whole-file
    /// JSON reader fail on a JSON Lines file.
    func testTwoDocumentsInOneTextDoNotParse() {
        XCTAssertNil(JSONStructure.value(of: #"{"a":1}"# + "\n" + #"{"a":2}"#))
    }
}
