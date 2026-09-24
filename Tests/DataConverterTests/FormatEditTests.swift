//
//  FormatEditTests.swift
//  DataConverterTests
//
//  The TOML and XML encoders: a typed replacement keeps its kind and its escapes.
//
//  Created by David Sherlock on 9/25/26.
//

import XCTest
@testable import DataConverter

final class FormatEditTests: XCTestCase {
    func testTOMLEncodingKeepsTheKind() {
        XCTAssertEqual(TOMLEdit.encodedScalar("hello", kind: .string), "\"hello\"")
        XCTAssertEqual(TOMLEdit.encodedScalar("42", kind: .string), "\"42\"")
        XCTAssertEqual(TOMLEdit.encodedScalar("42", kind: .number), "42")
        XCTAssertEqual(TOMLEdit.encodedScalar("1.5e3", kind: .number), "1.5e3")
        XCTAssertEqual(TOMLEdit.encodedScalar("0xDEADBEEF", kind: .number), "0xDEADBEEF")
        XCTAssertEqual(TOMLEdit.encodedScalar("1_000", kind: .number), "1_000")
        XCTAssertEqual(TOMLEdit.encodedScalar("lots", kind: .number), "\"lots\"")
        XCTAssertEqual(TOMLEdit.encodedScalar("true", kind: .bool), "true")
        XCTAssertEqual(TOMLEdit.encodedScalar("maybe", kind: .bool), "\"maybe\"")
        XCTAssertEqual(TOMLEdit.encodedScalar("a \"b\"\nc", kind: .string), "\"a \\\"b\\\"\\nc\"")
        XCTAssertEqual(TOMLEdit.encodedKey("max_connections"), "max_connections")
        XCTAssertEqual(TOMLEdit.encodedKey("with space"), "\"with space\"")
    }

    func testXMLEncodingAndDecoding() {
        XCTAssertEqual(XMLEdit.encodedText("a < b & c > d"), "a &lt; b &amp; c &gt; d")
        XCTAssertEqual(XMLEdit.encodedAttribute("say \"hi\" & go"), "\"say &quot;hi&quot; &amp; go\"")
        XCTAssertEqual(XMLEdit.encodedAttributeName("@ width"), "width")
        XCTAssertEqual(XMLEdit.decodedReferences("5 &lt;copies&gt; &#8212; &#x41; &amp;&publisher; &bogus"), "5 <copies> — A &&publisher; &bogus")
    }
}
