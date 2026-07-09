//
//  DataConverterTests.swift
//  Tests for SwiftDataConverter
//
//  Created by David Sherlock on 7/9/26.
//

import XCTest
@testable import DataConverter

final class DataConverterTests: XCTestCase {

    // MARK: - convert

    func testJSONToYAML() {
        let out = DataConverter.convert(#"{"a":1,"b":"hi"}"#, from: "JSON", to: "YAML")
        XCTAssertTrue(out.contains("a: 1"), out)
        XCTAssertTrue(out.contains("b: hi"), out)
    }

    func testJSONToTOML() {
        let out = DataConverter.convert(#"{"name":"Ada","n":2}"#, from: "JSON", to: "TOML")
        XCTAssertTrue(out.contains(#"name = "Ada""#), out)
        XCTAssertTrue(out.contains("n = 2"), out)
    }

    func testJSONArrayToCSVSortsKeys() {
        let out = DataConverter.convert(#"[{"name":"Ada","age":36},{"name":"Alan","age":41}]"#, from: "JSON", to: "CSV")
        XCTAssertEqual(out, "age,name\n36,Ada\n41,Alan")
    }

    func testCSVToJSONRoundTrips() {
        let out = DataConverter.convert("name,age\nAda,36", from: "CSV", to: "JSON")
        XCTAssertTrue(out.contains("\"name\""), out)
        XCTAssertTrue(out.contains("\"Ada\""), out)
        XCTAssertTrue(out.contains("\"age\""), out)
    }

    func testBadJSONReportsError() {
        XCTAssertTrue(DataConverter.convert("not json {", from: "JSON", to: "JSON").hasPrefix("⚠︎"))
    }

    func testTOMLNeedsTopLevelObject() {
        XCTAssertTrue(DataConverter.convert("[1,2,3]", from: "JSON", to: "TOML").hasPrefix("⚠︎"))
    }

    func testCSVOutputNeedsArrayOfObjects() {
        XCTAssertTrue(DataConverter.convert(#"{"a":1}"#, from: "JSON", to: "CSV").hasPrefix("⚠︎"))
    }

    // MARK: - CSV tokenizer

    func testParseCSVMapsHeadersToRows() {
        let rows = DataConverter.parseCSV("name,age\nAda,36\nAlan,41")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0]["name"] as? String, "Ada")
        XCTAssertEqual(rows[1]["age"] as? String, "41")
    }

    func testCSVRecordsHandlesQuotedCommasAndNewlines() {
        let records = DataConverter.csvRecords("a,b\n\"x,y\",\"line1\nline2\"")
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0], ["a", "b"])
        XCTAssertEqual(records[1], ["x,y", "line1\nline2"])   // quoted comma + embedded newline preserved
    }

    func testCSVRecordsUnescapesDoubledQuotes() {
        let records = DataConverter.csvRecords(#"a"# + "\n" + #""he said ""hi"""#)
        XCTAssertEqual(records[1], [#"he said "hi""#])
    }
}
