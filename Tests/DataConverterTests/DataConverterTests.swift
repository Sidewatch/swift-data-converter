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

    // MARK: - Regressions

    func testYAMLQuotesTypeLookalikeAndIndicatorStrings() {
        let out = DataConverter.convert(#"{"a":"true","b":"123","c":"- x","d":"'q'","e":"1e3"}"#, from: "JSON", to: "YAML")
        XCTAssertTrue(out.contains(#"a: "true""#), out)     // stays a string, not a bool
        XCTAssertTrue(out.contains(#"b: "123""#), out)      // stays a string, not an int
        XCTAssertTrue(out.contains(#"c: "- x""#), out)      // leading sequence indicator quoted
        XCTAssertTrue(out.contains(#"d: "'q'""#), out)      // leading single quote preserved
        XCTAssertTrue(out.contains(#"e: "1e3""#), out)      // float-lookalike quoted
    }

    func testYAMLQuotesUnsafeMappingKeys() {
        let out = DataConverter.convert(##"{"a: b":1,"#c":2}"##, from: "JSON", to: "YAML")
        XCTAssertTrue(out.contains(#""a: b": 1"#), out)     // colon-bearing key quoted
        XCTAssertTrue(out.contains(##""#c": 2"##), out)     // '#' key quoted, not a comment
    }

    func testTOMLQuotesNonBareKeys() {
        let out = DataConverter.convert(#"{"a b":2,"a.b":1}"#, from: "JSON", to: "TOML")
        XCTAssertTrue(out.contains(#""a b" = 2"#), out)     // space needs a quoted key
        XCTAssertTrue(out.contains(#""a.b" = 1"#), out)     // '.' quoted so it isn't a dotted key
    }

    func testTOMLQuotesNonBareTableHeaders() {
        let out = DataConverter.convert(#"{"a.b":{"c":1}}"#, from: "JSON", to: "TOML")
        XCTAssertTrue(out.contains(#"["a.b"]"#), out)       // header segment quoted, not [a.b]
    }

    func testTOMLEmitsInlineTableInMixedArray() {
        let out = DataConverter.convert(#"{"x":[1,{"a":2}]}"#, from: "JSON", to: "TOML")
        XCTAssertTrue(out.contains("x = [1, { a = 2 }]"), out)
    }

    func testEscapesCarriageReturnInYAMLAndTOML() {
        let yaml = DataConverter.convert(#"{"a":"x\ry"}"#, from: "JSON", to: "YAML")
        XCTAssertTrue(yaml.contains(#"a: "x\ry""#), yaml)   // quoted + escaped, no raw CR
        XCTAssertFalse(yaml.contains("\r"), yaml)
        let toml = DataConverter.convert(#"{"a":"x\ry"}"#, from: "JSON", to: "TOML")
        XCTAssertTrue(toml.contains(#"a = "x\ry""#), toml)
        XCTAssertFalse(toml.contains("\r"), toml)
    }

    func testEscapesC0ControlCharacters() {
        let toml = DataConverter.convert("{\"a\":\"x\\u0001y\"}", from: "JSON", to: "TOML")
        XCTAssertTrue(toml.contains(#"a = "x\u0001y""#), toml)
        XCTAssertFalse(toml.contains("\u{01}"), toml)
    }

    func testCSVRecordsHandlesBareCRAndCRLFLineEndings() {
        XCTAssertEqual(DataConverter.csvRecords("a,b\rc,d"), [["a", "b"], ["c", "d"]])
        XCTAssertEqual(DataConverter.csvRecords("a,b\r\nc,d"), [["a", "b"], ["c", "d"]])
    }

    func testCSVOutputRejectsMixedArray() {
        XCTAssertTrue(DataConverter.convert(#"[{"a":1},2,{"a":3}]"#, from: "JSON", to: "CSV").hasPrefix("⚠︎"))
    }

    func testCSVCellSerializesContainersAsJSON() {
        let out = DataConverter.convert(#"[{"a":[1,2],"b":{"k":1}}]"#, from: "JSON", to: "CSV")
        XCTAssertTrue(out.contains(#""[1,2]""#), out)             // nested array as compact JSON (quoted: contains a comma)
        XCTAssertTrue(out.contains(#"{""k"":1}"#), out)           // nested object as compact JSON with doubled quotes
        XCTAssertFalse(out.contains("(\n"), out)                  // no NSArray description text
    }

    func testCSVEscQuotesBareCRAndRoundTrips() {
        let once = DataConverter.convert("a\n\"x\ry\"", from: "CSV", to: "CSV")
        XCTAssertEqual(once, "a\n\"x\ry\"")                       // CR field stays quoted
        let rows = DataConverter.parseCSV(once)
        XCTAssertEqual(rows.first?["a"] as? String, "x\ry")       // no silent "xy" corruption
    }

    func testParseCSVDeduplicatesHeaders() {
        let rows = DataConverter.parseCSV("name,name\nA,B")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["name"] as? String, "A")
        XCTAssertEqual(rows[0]["name_2"] as? String, "B")
    }

    // Regression: cells beyond the header row were silently dropped.
    func testParseCSVKeepsExtraCellsUnderSynthesizedColumns() {
        let rows = DataConverter.parseCSV("a,b\n1,2,3\n4,5")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0]["a"] as? String, "1")
        XCTAssertEqual(rows[0]["b"] as? String, "2")
        XCTAssertEqual(rows[0]["column_3"] as? String, "3")   // extra cell survives
        XCTAssertEqual(rows[1]["column_3"] as? String, "")    // short rows pad the synthesized column too
        let out = DataConverter.convert("a,b\n1,2,3", from: "CSV", to: "JSON")
        XCTAssertTrue(out.contains(#""3""#), out)
    }

    // Regression: integral floats lost their float type (1.0 → 1) in YAML/TOML output.
    func testIntegralFloatsKeepFloatTypeInYAMLAndTOML() {
        let toml = DataConverter.convert(#"{"a":1.0,"b":2.5,"c":3}"#, from: "JSON", to: "TOML")
        XCTAssertTrue(toml.contains("a = 1.0"), toml)   // stays a TOML float
        XCTAssertTrue(toml.contains("b = 2.5"), toml)
        XCTAssertTrue(toml.contains("c = 3"), toml)     // genuine ints stay ints
        let yaml = DataConverter.convert(#"{"a":1.0,"c":3}"#, from: "JSON", to: "YAML")
        XCTAssertTrue(yaml.contains("a: 1.0"), yaml)
        XCTAssertTrue(yaml.contains("c: 3"), yaml)
    }

    // The byte-level tokenizer must pass multi-byte glyphs through untouched.
    func testCSVRecordsPreservesMultiByteCharacters() {
        let records = DataConverter.csvRecords("naïve,☕️\n\"héllo, wörld\",日本語")
        XCTAssertEqual(records[0], ["naïve", "☕️"])
        XCTAssertEqual(records[1], ["héllo, wörld", "日本語"])
    }

    func testCSVRecordsFlushesTrailingEmptyField() {
        XCTAssertEqual(DataConverter.csvRecords("a,b\n1,"), [["a", "b"], ["1", ""]])
        XCTAssertEqual(DataConverter.csvRecords("a,b\n1,2\n"), [["a", "b"], ["1", "2"]])   // trailing newline adds no row
    }
}
