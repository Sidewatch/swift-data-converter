//
//  PropertyListStructureTests.swift
//  DataConverterTests
//
//  A property list's bytes as structure, in every format Foundation reads.
//
//  Created by David Sherlock on 9/25/26.
//

import XCTest
@testable import DataConverter

final class PropertyListStructureTests: XCTestCase {
    let object: [String: Any] = [
        "name": "Inventory", "count": 25, "ratio": 0.5, "on": true, "off": false,
        "when": Date(timeIntervalSince1970: 0), "blob": Data([1, 2, 3]),
        "list": ["a", 2], "dict": ["z": 1, "a": 2],
    ]
    func pairs(_ v: StructuredValue?) -> [StructuredPair] { if case .mapping(let p)? = v { return p } else { return [] } }

    func testBinaryAndXMLReadTheSame() throws {
        for format in [PropertyListSerialization.PropertyListFormat.binary, .xml] {
            let data = try PropertyListSerialization.data(fromPropertyList: object, format: format, options: 0)
            XCTAssertEqual(PropertyListStructure.isBinary(data.prefix(8)), format == .binary)
            let root = pairs(PropertyListStructure.value(of: data))
            XCTAssertEqual(root.map(\.key), ["blob", "count", "dict", "list", "name", "off", "on", "ratio", "when"], "keys sorted — the reader keeps no order")
            XCTAssertEqual(root.first { $0.key == "count" }?.value, .integer(25))
            XCTAssertEqual(root.first { $0.key == "ratio" }?.value, .number(0.5))
            XCTAssertEqual(root.first { $0.key == "on" }?.value, .bool(true), "a boolean is not a number")
            XCTAssertEqual(root.first { $0.key == "off" }?.value, .bool(false))
            XCTAssertEqual(root.first { $0.key == "when" }?.value, .string("1970-01-01T00:00:00Z"))
            XCTAssertEqual(root.first { $0.key == "blob" }?.value, .string("3 bytes"))
            XCTAssertEqual(root.first { $0.key == "list" }?.value, .sequence([.string("a"), .integer(2)]))
            XCTAssertEqual(pairs(root.first { $0.key == "dict" }?.value).map(\.key), ["a", "z"])
        }
        XCTAssertNil(PropertyListStructure.value(of: Data("not a plist".utf8)))
    }
}
