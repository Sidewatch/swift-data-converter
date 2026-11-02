//
//  StructuredInputTests.swift
//  DataConverterTests
//
//  Pasted text as the JSON a query runs over: JSON untouched, PHP serialize read, base64 unwrapped.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import DataConverter

final class StructuredInputTests: XCTestCase {
    let php = #"a:2:{s:4:"name";s:4:"Shop";s:4:"meta";s:13:"{"theme":"x"}";}"#

    func testJSONPassesThroughUntouched() {
        for text in [#"{"a": 1}"#, "[1, 2]", "  \"text\"  ", "12345678", "null", "{not json"] {
            XCTAssertEqual(StructuredInput.reading(text), StructuredInputReading(json: text, source: .json, wasBase64: false), text)
        }
    }

    func testPHPIsReadWithItsNestedValuesExpanded() throws {
        let reading = StructuredInput.reading(php)
        XCTAssertEqual(reading.source, .phpSerialized)
        XCTAssertFalse(reading.wasBase64)
        XCTAssertEqual(reading.expandedCount, 1)
        XCTAssertEqual(JSONStructure.value(of: reading.json), JSONStructure.value(of: #"{"name": "Shop", "meta": {"theme": "x"}}"#))
    }

    func testBase64IsUnwrappedWhenItHoldsPHPOrJSON() throws {
        let wrapped = Data(php.utf8).base64EncodedString(options: .lineLength64Characters)
        let reading = StructuredInput.reading(wrapped)
        XCTAssertEqual(reading.source, .phpSerialized)
        XCTAssertTrue(reading.wasBase64)
        // URL-safe, unpadded JSON (a JWT's payload); this one encodes to both `-` and `_`.
        let payload = Data(#"{"sub":"user-1","q":"???>>>"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let jwt = StructuredInput.reading(payload)
        XCTAssertEqual(jwt.source, .json)
        XCTAssertTrue(jwt.wasBase64)
        XCTAssertEqual(jwt.json, #"{"sub":"user-1","q":"???>>>"}"#)
        // Base64 of anything else is left as it was.
        let other = Data("plain words, not data".utf8).base64EncodedString()
        XCTAssertEqual(StructuredInput.reading(other), StructuredInputReading(json: other, source: .json, wasBase64: false))
    }

    func testPHPThatCannotBeReadSaysWhy() {
        let reading = StructuredInput.reading(#"a:2:{i:0;s:1:"a";"#)
        XCTAssertEqual(reading.source, .phpSerialized)
        XCTAssertEqual(reading.json, "")
        XCTAssertEqual(reading.problem?.reason, .unexpectedEnd)
    }

    func testRepairsAreReported() {
        let reading = StructuredInput.reading(#"a:1:{s:4:"home";s:19:"https://www.example.org/";}"#)
        XCTAssertEqual(reading.repairs.count, 1)
        XCTAssertNil(reading.problem)
    }
}
