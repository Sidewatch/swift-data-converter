//
//  CSVEditTests.swift
//  DataConverterTests
//
//  One field rewritten in place: plain, quoted, after a multiline field, ragged, CRLF, header.
//
//  Created by David Sherlock on 9/24/26.
//

import XCTest
@testable import DataConverter

final class CSVEditTests: XCTestCase {
    let text = "name,qty,note\napple,1,\"red, crisp\"\nkiwi,12,\"two\nlines\"\nbanana,3,\n"

    func testFieldRangesCoverRawFieldsQuotesIncluded() {
        let ranges = CSVTokenizer.fieldRanges(in: text)
        let bytes = Array(text.utf8)
        func raw(_ r: Range<Int>) -> String { String(decoding: bytes[r], as: UTF8.self) }
        XCTAssertEqual(ranges.count, 4)
        XCTAssertEqual(ranges[1].map(raw), ["apple", "1", "\"red, crisp\""])
        XCTAssertEqual(ranges[2].map(raw), ["kiwi", "12", "\"two\nlines\""])
        XCTAssertEqual(ranges[3].map(raw), ["banana", "3", ""])
    }

    func testReplacesAPlainFieldAndKeepsEverythingElse() {
        XCTAssertEqual(CSVEdit.replacingField(in: text, record: 1, column: 1, with: "2"),
                       "name,qty,note\napple,2,\"red, crisp\"\nkiwi,12,\"two\nlines\"\nbanana,3,\n")
    }

    func testReplacesAQuotedFieldWithAPlainOne() {
        XCTAssertEqual(CSVEdit.replacingField(in: text, record: 1, column: 2, with: "green"),
                       "name,qty,note\napple,1,green\nkiwi,12,\"two\nlines\"\nbanana,3,\n")
    }

    func testARecordAfterAMultilineFieldIsFoundByItsRange() {
        XCTAssertEqual(CSVEdit.replacingField(in: text, record: 3, column: 0, with: "cherry"),
                       "name,qty,note\napple,1,\"red, crisp\"\nkiwi,12,\"two\nlines\"\ncherry,3,\n")
    }

    func testAValueThatNeedsQuotingIsQuotedWithDoubledQuotes() {
        XCTAssertEqual(CSVEdit.encoded("12,5"), "\"12,5\"")
        XCTAssertEqual(CSVEdit.encoded("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(CSVEdit.encoded(" padded"), "\" padded\"")
        XCTAssertEqual(CSVEdit.encoded("plain"), "plain")
        XCTAssertEqual(CSVEdit.replacingField(in: "a,b\n1,2\n", record: 1, column: 1, with: "x,y"), "a,b\n1,\"x,y\"\n")
    }

    func testCRLFAndTheHeaderAndTheLastLineWithoutANewline() {
        XCTAssertEqual(CSVEdit.replacingField(in: "a,b\r\n1,2\r\n", record: 1, column: 0, with: "9"), "a,b\r\n9,2\r\n")
        XCTAssertEqual(CSVEdit.replacingField(in: "a,b\n1,2", record: 1, column: 1, with: "3"), "a,b\n1,3")
        XCTAssertEqual(CSVEdit.replacingField(in: "a,b\n1,2\n", record: 0, column: 1, with: "count"), "a,count\n1,2\n")
    }

    func testARaggedRowGainsTheCommasItNeeds() {
        XCTAssertEqual(CSVEdit.replacingField(in: "a,b,c\n1\n", record: 1, column: 2, with: "z"), "a,b,c\n1,,z\n")
    }

    func testAMissingRecordIsNil() {
        XCTAssertNil(CSVEdit.replacingField(in: "a,b\n1,2\n", record: 5, column: 0, with: "x"))
        XCTAssertNil(CSVEdit.fieldReplacement(in: "", record: 0, column: 0, with: "x"))
    }

    func testTheReplacementRangeMapsToTheOriginalText() throws {
        let edit = try XCTUnwrap(CSVEdit.fieldReplacement(in: text, record: 2, column: 1, with: "13"))
        XCTAssertEqual(String(text[edit.range]), "12")
        XCTAssertEqual(edit.replacement, "13")
        XCTAssertEqual(NSRange(edit.range, in: text), NSRange(location: 40, length: 2))
    }
}
