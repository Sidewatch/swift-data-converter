//
//  JSONEditTests.swift
//  DataConverterTests
//
//  The site of a key or value by path, and how a typed replacement is written.
//
//  Created by David Sherlock on 9/25/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import DataConverter

final class JSONEditTests: XCTestCase {
    let text = """
        {
          "name": "inventory",
          "port": 3000,
          "debug": false,
          "tags": ["a, b", "c:d", null],
          "db": { "host": "db.internal", "note": "say \\"hi\\"", "retries": -1 }
        }
        """

    func raw(_ r: Range<String.Index>?) -> String? { r.map { String(text[$0]) } }

    func testFindsScalarsByPathWithTheirKeys() throws {
        let port = try XCTUnwrap(JSONEdit.site(in: text, path: [.key("port")]))
        XCTAssertEqual(raw(port.value), "3000"); XCTAssertEqual(raw(port.key), "\"port\"")
        let host = try XCTUnwrap(JSONEdit.site(in: text, path: [.key("db"), .key("host")]))
        XCTAssertEqual(raw(host.value), "\"db.internal\""); XCTAssertEqual(raw(host.key), "\"host\"")
        let note = try XCTUnwrap(JSONEdit.site(in: text, path: [.key("db"), .key("note")]))
        XCTAssertEqual(raw(note.value), "\"say \\\"hi\\\"\"", "escapes inside the token are part of it")
        let retries = try XCTUnwrap(JSONEdit.site(in: text, path: [.key("db"), .key("retries")]))
        XCTAssertEqual(raw(retries.value), "-1")
        XCTAssertEqual(raw(JSONEdit.site(in: text, path: [.key("debug")])?.value), "false")
    }

    func testArrayElementsHaveNoKeyAndCommasInsideStringsDoNotSplit() throws {
        let first = try XCTUnwrap(JSONEdit.site(in: text, path: [.key("tags"), .index(0)]))
        XCTAssertEqual(raw(first.value), "\"a, b\""); XCTAssertNil(first.key)
        XCTAssertEqual(raw(JSONEdit.site(in: text, path: [.key("tags"), .index(1)])?.value), "\"c:d\"")
        XCTAssertEqual(raw(JSONEdit.site(in: text, path: [.key("tags"), .index(2)])?.value), "null")
        XCTAssertNil(JSONEdit.site(in: text, path: [.key("tags"), .index(3)]))
        XCTAssertNil(JSONEdit.site(in: text, path: [.key("nope")]))
        XCTAssertNil(JSONEdit.site(in: "not json", path: [.key("a")]))
    }

    func testAContainerIsASiteToo() throws {
        let db = try XCTUnwrap(JSONEdit.site(in: text, path: [.key("db")]))
        XCTAssertTrue(raw(db.value)!.hasPrefix("{ \"host\"")); XCTAssertEqual(raw(db.key), "\"db\"")
    }

    func testReplacingThroughTheSiteLeavesTheRestByteForByte() throws {
        let site = try XCTUnwrap(JSONEdit.site(in: text, path: [.key("port")]))
        var out = text; out.replaceSubrange(site.value, with: JSONEdit.encodedValue("3001", kind: .number))
        XCTAssertEqual(out, text.replacingOccurrences(of: "\"port\": 3000", with: "\"port\": 3001"))
        var renamed = text; renamed.replaceSubrange(site.key!, with: JSONEdit.encodedKey("listen"))
        XCTAssertEqual(renamed, text.replacingOccurrences(of: "\"port\": 3000", with: "\"listen\": 3000"))
    }

    func testEncodingKeepsTheKind() {
        XCTAssertEqual(JSONEdit.encodedValue("hello", kind: .string), "\"hello\"")
        XCTAssertEqual(JSONEdit.encodedValue("42", kind: .string), "\"42\"", "a string stays a string")
        XCTAssertEqual(JSONEdit.encodedValue("42", kind: .number), "42")
        XCTAssertEqual(JSONEdit.encodedValue("4.5e3", kind: .number), "4.5e3")
        XCTAssertEqual(JSONEdit.encodedValue("lots", kind: .number), "\"lots\"", "not a number: becomes a string")
        XCTAssertEqual(JSONEdit.encodedValue("true", kind: .bool), "true")
        XCTAssertEqual(JSONEdit.encodedValue("maybe", kind: .bool), "\"maybe\"")
        XCTAssertEqual(JSONEdit.encodedValue("null", kind: .null), "null")
        XCTAssertEqual(JSONEdit.jsonString("a \"q\" \\ \n\ttab"), "\"a \\\"q\\\" \\\\ \\n\\ttab\"")
        XCTAssertEqual(JSONEdit.encodedKey("na\"me"), "\"na\\\"me\"")
    }

    // JSONC (`tsconfig.json`, `devcontainer.json`) and JSON5: comments, trailing commas, bare and
    // single-quoted keys. Strict JSON's scanner stops at the first comment and finds nothing.
    let jsonc = """
        // Build settings
        {
          /* the compiler */
          "compilerOptions": {
            "target": "es2022", // newest the runtime has
            "strict": true,
          },
          include: ['src/**/*'],
          'out dir': 'dist',
          hex: 0xFF,
          ratio: +Infinity,
        }
        """

    func testJSONCCommentsAndTrailingCommasAreSkipped() throws {
        let target = try XCTUnwrap(JSONEdit.site(in: jsonc, path: [.key("compilerOptions"), .key("target")]))
        XCTAssertEqual(String(jsonc[target.value]), "\"es2022\"")
        let strict = try XCTUnwrap(JSONEdit.site(in: jsonc, path: [.key("compilerOptions"), .key("strict")]))
        XCTAssertEqual(String(jsonc[strict.value]), "true", "a trailing comma closes the object")
        XCTAssertNotNil(JSONEdit.site(in: jsonc, path: [.key("ratio")]), "members after the trailing-comma object are reached")
    }

    func testJSON5BareAndSingleQuotedKeysAndValues() throws {
        let include = try XCTUnwrap(JSONEdit.site(in: jsonc, path: [.key("include"), .index(0)]))
        XCTAssertEqual(String(jsonc[include.value]), "'src/**/*'")
        let includeKey = try XCTUnwrap(JSONEdit.site(in: jsonc, path: [.key("include")])?.key)
        XCTAssertEqual(String(jsonc[includeKey]), "include")
        let outDir = try XCTUnwrap(JSONEdit.site(in: jsonc, path: [.key("out dir")]))
        XCTAssertEqual(outDir.key.map { String(jsonc[$0]) }, "'out dir'")
        XCTAssertEqual(String(jsonc[outDir.value]), "'dist'")
        XCTAssertEqual(JSONEdit.site(in: jsonc, path: [.key("hex")]).map { String(jsonc[$0.value]) }, "0xFF")
        XCTAssertEqual(JSONEdit.site(in: jsonc, path: [.key("ratio")]).map { String(jsonc[$0.value]) }, "+Infinity")
    }

    func testAnEditInAJSONCFileKeepsItsComments() throws {
        let site = try XCTUnwrap(JSONEdit.site(in: jsonc, path: [.key("compilerOptions"), .key("target")]))
        var out = jsonc; out.replaceSubrange(site.value, with: JSONEdit.encodedValue("es2024", kind: .string))
        XCTAssertEqual(out, jsonc.replacingOccurrences(of: "\"es2022\"", with: "\"es2024\""))
        XCTAssertNil(JSONEdit.site(in: "{ /* never closed", path: [.key("a")]))
    }
}
