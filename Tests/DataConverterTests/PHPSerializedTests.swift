//
//  PHPSerializedTests.swift
//  DataConverterTests
//
//  PHP's serialize() format against PHP's own unserialize(), plus the repairs and expansions PHP
//  does not make.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import DataConverter

final class PHPSerializedTests: XCTestCase {
    func read(_ text: String, expanding: Bool = false) throws -> PHPSerializedReading {
        try PHPSerialized.read(text, expandingNested: expanding)
    }
    func json(_ text: String) throws -> StructuredValue { try XCTUnwrap(JSONStructure.value(of: text)) }
    func error(_ text: String) -> PHPSerializedError? {
        do {
            _ = try PHPSerialized.read(text)
            return nil
        } catch { return error }
    }

    /// Every value PHP 8.5 serialized in `Fixtures/php-serialize.json` reads as the tree PHP's own
    /// unserialize() gives (computed in PHP by `Fixtures/php-serialize.php`, which writes the
    /// file): every kind, visibility, references and recursion, enums, bad UTF-8, 300 random values.
    func testMatchesPHPOnEveryFixture() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "php-serialize", withExtension: "json", subdirectory: "Fixtures"))
        let text = try String(contentsOf: url, encoding: .utf8)
        guard case .sequence(let cases) = try json(text) else { return XCTFail("the fixture is not a list") }
        XCTAssertGreaterThanOrEqual(cases.count, 328)
        var mismatches: [String] = []
        for c in cases {
            guard case .mapping(let fields) = c, fields.count == 3, case .string(let name) = fields[0].value,
                case .string(let encoded) = fields[1].value, let bytes = Data(base64Encoded: encoded)
            else { return XCTFail("a malformed case: \(c)") }
            let expected = fields[2].value
            do {
                let reading = try PHPSerialized.read(Array(bytes))
                if reading.value != expected || !reading.repairs.isEmpty {
                    mismatches.append("\(name): got \(reading.value.jsonText())\nexpected \(expected.jsonText())")
                }
            } catch {
                mismatches.append("\(name): \(error)")
            }
        }
        XCTAssertEqual(mismatches.count, 0, mismatches.prefix(3).joined(separator: "\n\n"))
    }

    func testTheExampleFromTheUnserializeSite() throws {
        let reading = try read(#"a:2:{i:0;s:12:"Sample array";i:1;a:2:{i:0;s:5:"Apple";i:1;s:6:"Orange";}}"#)
        XCTAssertEqual(reading.value, try json(#"["Sample array", ["Apple", "Orange"]]"#))
    }

    /// A search-and-replace over a WordPress database lengthens a URL and leaves `s:19:` as it was;
    /// PHP refuses the whole option ("Error at offset 41 of 49 bytes"). It reads, and says where.
    func testAWrongLengthIsReadToTheStringsRealEnd() throws {
        let damaged = #"a:2:{s:4:"home";s:19:"https://www.example.org/";s:4:"name";s:4:"Shop";}"#
        let reading = try read(damaged)
        XCTAssertEqual(reading.value, try json(#"{"home": "https://www.example.org/", "name": "Shop"}"#))
        XCTAssertEqual(reading.repairs, [PHPSerializedRepair(offset: 16, declaredLength: 19, actualLength: 24)])
        // Too short: the real end is further on, past a `";` inside the text that nothing can follow.
        let short = try read(#"a:1:{i:0;s:2:"say "hi"; now";}"#)
        XCTAssertEqual(short.value, try json(#"["say \"hi\"; now"]"#))
        XCTAssertEqual(short.repairs.map(\.actualLength), [13])
    }

    /// WordPress serializes some values twice, and plugins store JSON in options: asked to, the
    /// reader shows them as the structure they hold, and counts them.
    func testNestedValuesExpandWhenAsked() throws {
        let inner = #"a:1:{s:5:"inner";s:5:"value";}"#
        let text = #"a:2:{s:6:"double";s:\#(inner.utf8.count):"\#(inner)";s:4:"json";s:21:"{"id":7,"tags":["a"]}";}"#
        XCTAssertEqual(
            try read(text).value, try json(#"{"double": \#(StructuredValue.jsonString(inner)), "json": "{\"id\":7,\"tags\":[\"a\"]}"}"#))
        let expanded = try read(text, expanding: true)
        XCTAssertEqual(expanded.value, try json(#"{"double": {"inner": "value"}, "json": {"id": 7, "tags": ["a"]}}"#))
        XCTAssertEqual(expanded.expandedCount, 2)
        // Text that merely starts like a value stays text.
        XCTAssertEqual(try read(#"s:7:"a:1:{x}";"#, expanding: true).value, .string("a:1:{x}"))
        XCTAssertEqual(try read(#"s:5:"[oops";"#, expanding: true).value, .string("[oops"))
    }

    func testCustomSerializedObjectsKeepTheirPayload() throws {
        let reading = try read(#"C:11:"ArrayObject":21:{x:i:0;a:0:{};m:a:0:{}}"#)
        XCTAssertEqual(reading.value, try json(#"{"__class": "ArrayObject", "__serialized": "x:i:0;a:0:{};m:a:0:{}"}"#))
    }

    /// PHP's own key rules: a key written again replaces the value in its first place, and a
    /// string key that is a canonical integer is that integer (so this array is a list).
    func testKeysFollowPHP() throws {
        XCTAssertEqual(try read(#"a:2:{i:0;s:1:"a";i:0;s:1:"b";}"#).value, try json(#"["b"]"#))
        XCTAssertEqual(try read(#"a:2:{s:1:"0";s:1:"x";s:1:"1";s:1:"y";}"#).value, try json(#"["x", "y"]"#))
        XCTAssertEqual(try read(#"a:1:{s:2:"01";s:1:"x";}"#).value, try json(#"{"01": "x"}"#))
        XCTAssertEqual(try read(#"a:1:{s:2:"-0";s:1:"x";}"#).value, try json(#"{"-0": "x"}"#))
    }

    func testEscapedStrings() throws {
        XCTAssertEqual(try read(#"S:3:"a\41b";"#).value, .string("aAb"))
    }

    func testWhatCannotBeReadSaysWhereAndWhy() {
        XCTAssertEqual(error(#"a:2:{i:0;s:1:"a";"#)?.reason, .unexpectedEnd)
        XCTAssertEqual(error("i:1;x"), PHPSerializedError(.trailingText, at: 4))
        XCTAssertEqual(error("a:1:{i:0;r:5;}"), PHPSerializedError(.badReference(5), at: 9))
        XCTAssertEqual(error("i:1x;")?.reason, .unexpected(expected: String(localized: "an integer", bundle: .module)))
        XCTAssertEqual(error("q:1;")?.offset, 0)
        XCTAssertEqual(error(#"s:5:"abc""#)?.reason, .unexpectedEnd)
        XCTAssertEqual(error("d:abc;")?.offset, 2)
        XCTAssertNil(error("  i:1;\n"))  // white space around the value is fine
    }

    func testNestingAndReferenceBombsAreBounded() {
        let deep = String(repeating: "a:1:{i:0;", count: 300) + "N;" + String(repeating: "}", count: 300)
        XCTAssertEqual(error(deep)?.reason, .tooDeep)
        // Item k holds two references to item k-1 (values are numbered from the outer array, 1;
        // item 0 is 2, item k is 2 + 3k): 2^40 values once copied out.
        var bomb = "a:41:{i:0;a:2:{i:0;i:1;i:1;i:1;}"
        for k in 1...40 {
            let previous = k == 1 ? 2 : 2 + 3 * (k - 1)
            bomb += "i:\(k);a:2:{i:0;r:\(previous);i:1;r:\(previous);}"
        }
        XCTAssertEqual(error(bomb + "}")?.reason, .tooLarge)
        // A small value with references reads.
        XCTAssertNoThrow(try read("a:3:{i:0;a:1:{i:0;i:1;}i:1;r:2;i:2;r:2;}"))
    }

    func testLooksSerialized() {
        for yes in ["a:2:{", "  s:5:\"x", "O:8:\"stdClass\"", "N;", "b:1;", "i:-4;", "d:INF;", "C:3:", "E:11:", "S:1:"] {
            XCTAssertTrue(PHPSerialized.looksSerialized(yes), yes)
        }
        for no in [#"{"a":1}"#, "[1]", "hello", "b:2;", "a:x", "N", "", "null", "s:\"x\""] {
            XCTAssertFalse(PHPSerialized.looksSerialized(no), no)
        }
    }

    func testErrorsReadAsOneLine() {
        XCTAssertEqual(PHPSerializedError(.trailingText, at: 1_200).description, "Text follows the value, at byte 1,200")
    }
}
