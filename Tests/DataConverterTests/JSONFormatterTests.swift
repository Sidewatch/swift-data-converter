import XCTest
@testable import DataConverter

/// Covers ``JSONFormatter``.
///
/// The contract is narrow and worth stating, because it is what separates a formatter from a
/// converter: formatting changes WHITESPACE AND NOTHING ELSE. Key order, number literals, string
/// bytes and structure all come out exactly as they went in. Most of these tests exist to pin
/// that invariant rather than to check the indentation, because indentation is the part you would
/// notice was broken.
final class JSONFormatterTests: XCTestCase {

    // MARK: - The invariants that ruled out parse-and-re-encode

    /// The bug that decided the implementation. `JSONSerialization` yields an unordered
    /// dictionary, so a parse/re-encode formatter emits keys in arbitrary or alphabetical order
    /// and rewrites the whole file. Author order has to survive verbatim.
    func testKeyOrderIsPreserved() {
        let input = #"{"zebra":1,"apple":2,"mango":3}"#
        let out = JSONFormatter.format(input)!
        let keys = out.components(separatedBy: "\"").enumerated()
            .filter { $0.offset % 2 == 1 }.map(\.element)
        XCTAssertEqual(keys, ["zebra", "apple", "mango"], "keys were reordered:\n\(out)")
    }

    /// The second reason. Every one of these changes value if it round-trips through `Double`:
    /// `1.0` becomes `1`, `1e3` becomes `1000`, and the large integer loses its low digits.
    func testNumberLiteralsAreCopiedNotReformatted() {
        for literal in ["1.0", "1e3", "1E+3", "0.10", "-0.0", "9007199254740993", "1.7976931348623157e308"] {
            let out = JSONFormatter.format("{\"n\":\(literal)}")!
            XCTAssertTrue(out.contains(literal), "literal \(literal) was rewritten:\n\(out)")
        }
    }

    func testStringContentsAreUntouched() {
        // Braces, colons and commas inside a string are text. If the scanner ever treated a
        // string as structure, this is where it would show up as stray indentation.
        let input = #"{"tricky":"{\"a\": 1, [b]\n\t\\ \" end"}"#
        let out = JSONFormatter.format(input)!
        XCTAssertTrue(out.contains(#""{\"a\": 1, [b]\n\t\\ \" end""#), "string was altered:\n\(out)")
    }

    func testUnicodeAndEscapesSurvive() {
        let input = #"{"emoji":"🎛️ café","escaped":"\u00e9\/\b"}"#
        let out = JSONFormatter.format(input)!
        XCTAssertTrue(out.contains("🎛️ café"))
        XCTAssertTrue(out.contains(#"\u00e9\/\b"#), "escapes were decoded:\n\(out)")
    }

    // MARK: - Shape

    func testFormatsNestedObject() {
        let out = JSONFormatter.format(#"{"a":{"b":[1,2]}}"#)!
        XCTAssertEqual(out, """
        {
          "a": {
            "b": [
              1,
              2
            ]
          }
        }
        """)
    }

    /// Regression: an empty container must not consume a level. With the depth bookkeeping
    /// wrong, `{}` decremented a level it never opened and everything after it — here `"c"` —
    /// indented one step too shallow while still parsing fine.
    func testEmptyContainerDoesNotShiftFollowingSiblings() {
        let out = JSONFormatter.format(#"{"a":{"b":{},"c":1}}"#)!
        XCTAssertEqual(out, """
        {
          "a": {
            "b": {},
            "c": 1
          }
        }
        """)
    }

    func testEmptyContainersStayOnOneLine() {
        XCTAssertEqual(JSONFormatter.format("{}"), "{}")
        XCTAssertEqual(JSONFormatter.format("[]"), "[]")
        XCTAssertEqual(JSONFormatter.format(#"{"a":[],"b":{}}"#), "{\n  \"a\": [],\n  \"b\": {}\n}")
    }

    func testCustomIndent() {
        XCTAssertEqual(JSONFormatter.format(#"{"a":1}"#, indent: "\t"), "{\n\t\"a\": 1\n}")
        XCTAssertEqual(JSONFormatter.format(#"{"a":1}"#, indent: "    "), "{\n    \"a\": 1\n}")
    }

    func testTopLevelScalarsAndArrays() {
        XCTAssertEqual(JSONFormatter.format("42"), "42")
        XCTAssertEqual(JSONFormatter.format(#""hello""#), #""hello""#)
        XCTAssertEqual(JSONFormatter.format("null"), "null")
        XCTAssertEqual(JSONFormatter.format("[1,2]"), "[\n  1,\n  2\n]")
    }

    func testDeepNestingIndentsMonotonically() {
        let depth = 20
        let input = String(repeating: "[", count: depth) + "1" + String(repeating: "]", count: depth)
        let out = JSONFormatter.format(input)!
        // The innermost value sits at exactly `depth` levels — off-by-one bookkeeping shows here.
        XCTAssertTrue(out.contains("\n" + String(repeating: "  ", count: depth) + "1\n"),
                      "innermost value is at the wrong depth:\n\(out)")
    }

    // MARK: - Correctness properties

    /// The strongest single check: whatever comes out must parse to the same value that went in.
    /// Catches any structural damage the shape assertions above would miss.
    func testFormattingPreservesTheParsedValue() {
        let inputs = [
            #"{"a":1,"b":[true,false,null],"c":{"d":"e"}}"#,
            #"[{"x":[[]]},{},[],""]"#,
            #"{"nested":{"deep":{"deeper":[1,{"k":"v"}]}}}"#,
        ]
        for input in inputs {
            let out = JSONFormatter.format(input)!
            let before = try! JSONSerialization.jsonObject(with: Data(input.utf8), options: [.fragmentsAllowed])
            let after  = try! JSONSerialization.jsonObject(with: Data(out.utf8),   options: [.fragmentsAllowed])
            XCTAssertTrue(NSDictionary(dictionary: ["v": before]).isEqual(to: ["v": after]),
                          "value changed for \(input):\n\(out)")
        }
    }

    /// Formatting an already-formatted file must be a no-op, or the action produces a diff every
    /// time it is run and "Format" stops being safe to invoke habitually.
    func testFormattingIsIdempotent() {
        let once = JSONFormatter.format(#"{"a":{"b":[1,{},2]},"c":[]}"#)!
        XCTAssertEqual(JSONFormatter.format(once), once)
    }

    func testWhitespaceVariantsAllConvergeOnTheSameOutput() {
        let expected = JSONFormatter.format(#"{"a":1}"#)!
        for variant in [#"{ "a" : 1 }"#, "{\n\n\"a\"\t:\t1\n}", "  {\"a\":1}  ", "{\r\n\"a\": 1\r\n}"] {
            XCTAssertEqual(JSONFormatter.format(variant), expected, "variant diverged: \(variant)")
        }
    }

    // MARK: - Refusal

    /// The scanner knows structure, not grammar, so on malformed input it would emit tidy
    /// nonsense. Declining is the honest outcome — "Format" must never mangle a broken file
    /// into a differently-broken one that looks deliberate.
    func testInvalidJSONIsRejectedRatherThanTidied() {
        for bad in ["{", "{\"a\":}", "{'a':1}", "[1,2,]", "{\"a\":1,}", "", "not json", #"{"a" 1}"#] {
            XCTAssertNil(JSONFormatter.format(bad), "should have refused: \(bad)")
            XCTAssertNil(JSONFormatter.minify(bad), "should have refused: \(bad)")
        }
    }

    /// An unterminated string must not send the scanner past the end of the buffer.
    func testUnterminatedStringIsRefusedAndDoesNotCrash() {
        XCTAssertNil(JSONFormatter.format(#"{"a":"unclosed"#))
    }

    // MARK: - Minify

    func testMinifyRemovesAllInsignificantWhitespace() {
        XCTAssertEqual(JSONFormatter.minify("{\n  \"a\": [\n    1,\n    2\n  ]\n}"), #"{"a":[1,2]}"#)
    }

    func testMinifyKeepsWhitespaceInsideStrings() {
        XCTAssertEqual(JSONFormatter.minify(#"{"a": "keep  me\n"}"#), #"{"a":"keep  me\n"}"#)
    }

    func testMinifyAndFormatRoundTrip() {
        let pretty = JSONFormatter.format(#"{"a":{"b":[1,2],"c":{}}}"#)!
        XCTAssertEqual(JSONFormatter.format(JSONFormatter.minify(pretty)!), pretty)
    }

    // MARK: - The file this feature was asked for

    /// A Sidewatch theme is the case that prompted this: Duplicate & Edit wrote unformatted JSON.
    /// Theme files group related keys (all the ANSI colours together, then the UI colours), and
    /// alphabetising would scatter that grouping — which is precisely what a parse/re-encode
    /// formatter does and why this one works on tokens.
    func testThemeFileKeepsItsPropertyGrouping() {
        // `##"…"##`: the palette values contain `"#`, which would close a single-hash raw string.
        let theme = ##"{"name":"Test","isDark":true,"background":"#1e1e1e","foreground":"#d4d4d4","ansiBlack":"#000000","ansiRed":"#ff0000"}"##
        let out = JSONFormatter.format(theme)!
        let nameAt = out.range(of: "\"name\"")!.lowerBound
        let darkAt = out.range(of: "\"isDark\"")!.lowerBound
        let bgAt   = out.range(of: "\"background\"")!.lowerBound
        let ansiAt = out.range(of: "\"ansiBlack\"")!.lowerBound
        XCTAssertTrue(nameAt < darkAt && darkAt < bgAt && bgAt < ansiAt,
                      "grouping lost — keys were sorted:\n\(out)")
        XCTAssertTrue(out.contains("\"background\": \"#1e1e1e\""), "colour value altered:\n\(out)")
    }
}
