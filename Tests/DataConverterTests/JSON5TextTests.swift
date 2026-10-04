//
//  JSON5TextTests.swift
//  DataConverterTests
//
//  Created by David Sherlock on 10/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest

@testable import DataConverter

final class JSON5TextTests: XCTestCase {
    private func read(_ text: String) -> Any? {
        try? JSONSerialization.jsonObject(with: Data(JSON5Text.foundationReadable(text).utf8), options: [.fragmentsAllowed, .json5Allowed])
    }

    func testJSON5OnlyEscapesReadAsJSON5Means() {
        let value = read(#"{a: 'v\v z\0 x\x41 id\a\c q\' "\"" t\t', /* it's */ b: 1 // don't"# + "\n}") as? [String: Any]
        XCTAssertEqual(value?["a"] as? String, "v\u{0B} z\u{2400} xA id" + "ac q' \"\"\" t\t")
        XCTAssertEqual(value?["b"] as? Int, 1)
    }

    func testANulIsShownAsItsSymbolSoTheDocumentStillReads() {
        XCTAssertEqual((read(#"{a: '\0', b: '\x00'}"#) as? [String: String])?.values.sorted(), ["\u{2400}", "\u{2400}"])
    }

    func testTextWithoutEscapesIsUntouched() {
        let text = "{a: 'it is', b: [1, 2]}"
        XCTAssertEqual(JSON5Text.foundationReadable(text), text)
    }

    func testDigitsAfterBackslashZeroAndShortHexAreLeftAlone() {
        XCTAssertEqual(JSON5Text.foundationReadable(#"'\01 \x4'"#), #"'01 x4'"#)
    }

    func testNumbersPastTheReadersRangeStillRead() {
        let value = read("{a: 0xFFFFFFFFFFFFFFFF, b: -0x10, c: 1E400, d: -1e400, e: +.5e-2, f: 0x7530, g: 2e+10, k1: 1}") as? [String: Any]
        XCTAssertEqual((value?["a"] as? NSNumber)?.uint64Value, UInt64.max)
        XCTAssertEqual(value?["b"] as? Int, -16)
        XCTAssertEqual(value?["c"] as? Double, .infinity)
        XCTAssertEqual(value?["d"] as? Double, -.infinity)
        XCTAssertEqual(value?["e"] as? Double, 0.005)
        XCTAssertEqual(value?["f"] as? Int, 30000)
        XCTAssertEqual(value?["g"] as? Double, 2e10)
        XCTAssertEqual(value?["k1"] as? Int, 1, "a key ending in a digit is not a number")
    }
}
