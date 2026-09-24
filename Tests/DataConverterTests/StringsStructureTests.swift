//
//  StringsStructureTests.swift
//  DataConverterTests
//
//  A .strings file as its entries, and one key or value rewritten in place.
//
//  Created by David Sherlock on 9/25/26.
//

import XCTest
@testable import DataConverter

final class StringsStructureTests: XCTestCase {
    let strings = """
    /* Localizable.strings — English. */
    "orders.title" = "Orders for %@";
    "orders.count" = "%d orders"; // trailing note
    // "commented.out" = "no";
    "error.gateway" = "The gateway said \\"try later\\".\\nNot charged.";
    button.retry = "Try Again";
    "shorthand";
    "unicode" = "caf\\U00E9";
    """
    func pairs(_ v: StructuredValue?) -> [StructuredPair] { if case .mapping(let p)? = v { return p } else { return [] } }
    func raw(_ r: NSRange?) -> String? { r.map { (strings as NSString).substring(with: $0) } }

    func testEntriesCommentsAndEscapes() throws {
        let root = pairs(StringsStructure.value(of: strings))
        XCTAssertEqual(root.map(\.key), ["orders.title", "orders.count", "error.gateway", "button.retry", "shorthand", "unicode"], "comments are skipped, both kinds")
        XCTAssertEqual(root[0].value, .string("Orders for %@"))
        XCTAssertEqual(root[2].value, .string("The gateway said \"try later\".\nNot charged."))
        XCTAssertEqual(root[3].value, .string("Try Again"), "a bare key")
        XCTAssertEqual(root[4].value, .string("shorthand"), "\"key\"; means the value is the key")
        XCTAssertEqual(root[5].value, .string("café"))
        XCTAssertNil(StringsStructure.value(of: "/* nothing */"))
    }

    func testSitesAndReplacements() throws {
        let title = try XCTUnwrap(StringsStructure.site(in: strings, path: [.key("orders.title")]))
        XCTAssertEqual(raw(title.key), "\"orders.title\""); XCTAssertEqual(raw(title.value), "\"Orders for %@\"")
        let retry = try XCTUnwrap(StringsStructure.site(in: strings, path: [.key("button.retry")]))
        XCTAssertEqual(raw(retry.key), "button.retry")
        let edit = try XCTUnwrap(StringsStructure.replacement(in: strings, path: [.key("orders.count")], key: false, with: "%d orders \"now\"\nplease"))
        XCTAssertTrue((strings as NSString).replacingCharacters(in: edit.range, with: edit.replacement).contains("\"orders.count\" = \"%d orders \\\"now\\\"\\nplease\"; // trailing note"))
        let short = try XCTUnwrap(StringsStructure.replacement(in: strings, path: [.key("shorthand")], key: false, with: "Long"))
        XCTAssertTrue((strings as NSString).replacingCharacters(in: short.range, with: short.replacement).contains("\"shorthand\" = \"Long\";"))
        let rename = try XCTUnwrap(StringsStructure.replacement(in: strings, path: [.key("button.retry")], key: true, with: "button.again"))
        XCTAssertTrue((strings as NSString).replacingCharacters(in: rename.range, with: rename.replacement).contains("\"button.again\" = \"Try Again\";"))
        XCTAssertNil(StringsStructure.site(in: strings, path: [.key("commented.out")]))
    }
}
