//
//  JSONLinesTests.swift
//  DataConverterTests
//
//  JSON Lines split into records, each keeping the range its edit writes back to.
//
//  Created by David Sherlock on 9/26/26.
//

import XCTest
@testable import DataConverter

final class JSONLinesTests: XCTestCase {
    private let doc = #"{"type":"user","n":1}"# + "\n" + #"{"type":"assistant","n":2}"# + "\n"

    func testEachLineIsARecord() {
        let records = JSONLines.records(in: doc)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.map(\.index), [0, 1])
        XCTAssertEqual(records.map(\.line), [1, 2])
    }

    /// The range is what an edit is written back through, so it must name the record's own text.
    func testARecordsRangeIsItsOwnTextWithoutTheNewline() {
        let records = JSONLines.records(in: doc)
        let ns = doc as NSString
        XCTAssertEqual(ns.substring(with: records[0].range), #"{"type":"user","n":1}"#)
        XCTAssertEqual(ns.substring(with: records[1].range), #"{"type":"assistant","n":2}"#)
    }

    /// A trailing newline is normal and an empty line is not a record — but the LINE numbers must
    /// still count them, or a reported position disagrees with the editor's gutter.
    func testBlankLinesAreSkippedButStillCounted() {
        let text = #"{"a":1}"# + "\n\n\n" + #"{"a":2}"# + "\n"
        let records = JSONLines.records(in: text)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.map(\.index), [0, 1])
        XCTAssertEqual(records.map(\.line), [1, 4])
    }

    func testAFileWithNoTrailingNewlineKeepsItsLastRecord() {
        let records = JSONLines.records(in: #"{"a":1}"# + "\n" + #"{"a":2}"#)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual((#"{"a":1}"# + "\n" + #"{"a":2}"# as NSString).substring(with: records[1].range), #"{"a":2}"#)
    }

    /// `"\r\n"` is ONE Character in Swift, so a naive split on the Character "\n" never divides a
    /// CRLF file. The `\r` stays in the range, where the JSON reader treats it as whitespace.
    func testCRLFFilesSplit() {
        let text = #"{"a":1}"# + "\r\n" + #"{"a":2}"# + "\r\n"
        let records = JSONLines.records(in: text)
        XCTAssertEqual(records.count, 2)
        guard case .sequence(let items)? = JSONLines.value(of: text) else { return XCTFail("did not parse") }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0], .mapping([StructuredPair(key: "a", value: .integer(1))]))
    }

    func testTheDocumentReadsAsAnOrderedSequenceOfRecords() {
        guard case .sequence(let items)? = JSONLines.value(of: doc) else { return XCTFail("did not parse") }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0], .mapping([StructuredPair(key: "type", value: .string("user")),
                                           StructuredPair(key: "n", value: .integer(1))]))
    }

    /// A record that does not parse keeps its place as text: record numbers that silently
    /// disagree with the file's lines are the worse failure when the file is evidence.
    func testABrokenRecordKeepsItsPlaceAsText() {
        let text = #"{"a":1}"# + "\n" + "not json" + "\n" + #"{"a":3}"# + "\n"
        guard case .sequence(let items)? = JSONLines.value(of: text) else { return XCTFail("did not parse") }
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[1], .string("not json"))
        XCTAssertEqual(items[2], .mapping([StructuredPair(key: "a", value: .integer(3))]))
    }

    /// A file where nothing parses is not JSON Lines, and should fall back to its source.
    func testAFileWhereNothingParsesIsNotJSONLines() {
        XCTAssertNil(JSONLines.value(of: "hello\nworld\n"))
        XCTAssertNil(JSONLines.value(of: ""))
        XCTAssertNil(JSONLines.value(of: "\n\n\n"))
    }

    /// One JSON document per line — a pretty-printed document spanning lines is not JSON Lines,
    /// and must not be shown as a pile of broken records.
    func testAPrettyPrintedDocumentIsNotJSONLines() {
        XCTAssertNil(JSONLines.value(of: "{\n  \"a\": 1\n}\n"))
    }
}
