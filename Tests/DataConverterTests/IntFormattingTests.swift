//
//  IntFormattingTests.swift
//  DataConverterTests
//
//  Tests for the grouped-count and byte-size labels.
//
//  Created by David Sherlock on 9/5/26.
//

import XCTest
@testable import DataConverter

/// Tests for the `Int` formatting extensions: locale-grouped thousands and byte-size labels.
final class IntFormattingTests: XCTestCase {

    func testGroupedUsesTheLocalesThousandsSeparator() {
        XCTAssertEqual(174_950.grouped, NumberFormatter.localizedString(from: 174_950, number: .decimal))
        XCTAssertEqual(999.grouped, "999")
        XCTAssertEqual(1_234_567.grouped.filter(\.isNumber), "1234567", "digits survive, only separators are added")
        XCTAssertGreaterThan(1_234_567.grouped.count, 7, "separators were added")
    }

    func testByteSizeLabels() {
        XCTAssertEqual(0.byteSizeLabel, "0 B")
        XCTAssertEqual(500.byteSizeLabel, "500 B")
        XCTAssertEqual(1023.byteSizeLabel, "1023 B")
        XCTAssertEqual(2048.byteSizeLabel, "2.0 KB")
        XCTAssertEqual(1_500_000.byteSizeLabel, "1.4 MB")
        XCTAssertEqual((5 * 1024 * 1024 * 1024).byteSizeLabel, "5.0 GB")
        XCTAssertEqual((3000 * 1024 * 1024 * 1024).byteSizeLabel, "3000.0 GB", "GB is the largest unit")
    }
}
