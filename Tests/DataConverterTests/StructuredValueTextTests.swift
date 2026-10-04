//
//  StructuredValueTextTests.swift
//  DataConverterTests
//
//  A structured value written out as JSON or YAML keeps the file's key order and reads back.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import DataConverter

final class StructuredValueTextTests: XCTestCase {
    private let value: StructuredValue = .mapping([
        StructuredPair(key: "zeta", value: .integer(1)),
        StructuredPair(key: "alpha", value: .sequence([.string("text"), .string("yes"), .number(1.5)])),
        StructuredPair(
            key: "nested",
            value: .mapping([
                StructuredPair(key: "on", value: .bool(true)), StructuredPair(key: "note", value: .string("a: b")),
                StructuredPair(key: "none", value: .null),
            ])),
        StructuredPair(key: "rows", value: .sequence([.mapping([StructuredPair(key: "id", value: .integer(7))])])),
    ])

    /// JSON keeps file order (zeta before alpha) and parses back to the same shape.
    func testJSONKeepsFileOrderAndParses() throws {
        let json = value.jsonText()
        XCTAssertLessThan(json.range(of: "\"zeta\"")!.lowerBound, json.range(of: "\"alpha\"")!.lowerBound)
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        XCTAssertEqual((parsed?["nested"] as? [String: Any])?["note"] as? String, "a: b")
        XCTAssertEqual(JSONStructure.value(of: json), value)
    }

    /// YAML keeps file order and quotes only what YAML would misread ("yes", "a: b", the key "on").
    func testYAMLQuotesOnlyWhatItMust() {
        XCTAssertEqual(
            value.yamlText(),
            """
            zeta: 1
            alpha:
              - text
              - "yes"
              - 1.5
            nested:
              "on": true
              note: "a: b"
              none: null
            rows:
              - id: 7

            """)
    }

    /// One branch by its path, as the tree's row menu copies it.
    func testValueAtPath() {
        XCTAssertEqual(value.value(at: [.key("nested"), .key("note")]), .string("a: b"))
        XCTAssertEqual(value.value(at: [.key("alpha"), .index(2)]), .number(1.5))
        XCTAssertNil(value.value(at: [.key("alpha"), .index(9)]))
    }
}
