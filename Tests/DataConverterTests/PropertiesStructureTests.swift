//
//  PropertiesStructureTests.swift
//  DataConverterTests
//
//  A .properties file by Java's rules, and one key or value rewritten in place.
//
//  Created by David Sherlock on 9/25/26.
//

import XCTest
@testable import DataConverter

final class PropertiesStructureTests: XCTestCase {
    let props = """
    # Gradle settings
    ! also a comment
    org.gradle.jvmargs=-Xmx2g -Dfile.encoding=UTF-8
    org.gradle.parallel = true
    version:1.4.0
    count 25
    bare
    welcome.message=Welcome to the service, \\
        nothing here is billable\\!
    path=C:\\\\Users\\\\app
    key\\ with\\ spaces = spaced
    unicode=caf\\u00E9
    tab=a\\tb
    """
    func pairs(_ v: StructuredValue?) -> [StructuredPair] { if case .mapping(let p)? = v { return p } else { return [] } }
    func raw(_ r: NSRange?) -> String? { r.map { (props as NSString).substring(with: $0) } }

    func testKeysValuesEscapesAndContinuations() throws {
        let root = pairs(PropertiesStructure.value(of: props))
        XCTAssertEqual(root.map(\.key), ["org.gradle.jvmargs", "org.gradle.parallel", "version", "count", "bare", "welcome.message", "path", "key with spaces", "unicode", "tab"])
        XCTAssertEqual(root[0].value, .string("-Xmx2g -Dfile.encoding=UTF-8"), "the value keeps its own = signs")
        XCTAssertEqual(root[1].value, .bool(true))
        XCTAssertEqual(root[2].value, .string("1.4.0"), "a colon separates; 1.4.0 is not a number")
        XCTAssertEqual(root[3].value, .integer(25), "whitespace separates")
        XCTAssertEqual(root[4].value, .string(""), "a bare key is the empty string")
        XCTAssertEqual(root[5].value, .string("Welcome to the service, nothing here is billable!"), "a continuation joins with the next line's indent dropped; \\! is !")
        XCTAssertEqual(root[6].value, .string("C:\\Users\\app"))
        XCTAssertEqual(root[8].value, .string("café"))
        XCTAssertEqual(root[9].value, .string("a\tb"))
        XCTAssertNil(PropertiesStructure.value(of: "# nothing\n"))
    }

    func testSitesAndReplacements() throws {
        let parallel = try XCTUnwrap(PropertiesStructure.site(in: props, path: [.key("org.gradle.parallel")]))
        XCTAssertEqual(raw(parallel.key), "org.gradle.parallel"); XCTAssertEqual(raw(parallel.value), "true")
        let welcome = try XCTUnwrap(PropertiesStructure.site(in: props, path: [.key("welcome.message")]))
        XCTAssertEqual(raw(welcome.value), "Welcome to the service, \\\n    nothing here is billable\\!", "a continued value's raw span")
        let spaced = try XCTUnwrap(PropertiesStructure.site(in: props, path: [.key("key with spaces")]))
        XCTAssertEqual(raw(spaced.key), "key\\ with\\ spaces")
        let bare = try XCTUnwrap(PropertiesStructure.site(in: props, path: [.key("bare")]))
        XCTAssertEqual(bare.value.length, 0)

        let edit = try XCTUnwrap(PropertiesStructure.replacement(in: props, path: [.key("version")], key: false, with: "2.0.0"))
        XCTAssertTrue((props as NSString).replacingCharacters(in: edit.range, with: edit.replacement).contains("version:2.0.0\n"))
        let bareEdit = try XCTUnwrap(PropertiesStructure.replacement(in: props, path: [.key("bare")], key: false, with: "x"))
        XCTAssertTrue((props as NSString).replacingCharacters(in: bareEdit.range, with: bareEdit.replacement).contains("bare=x\n"), "a bare key gains =")
        let multi = try XCTUnwrap(PropertiesStructure.replacement(in: props, path: [.key("welcome.message")], key: false, with: "Hi\nthere"))
        XCTAssertTrue((props as NSString).replacingCharacters(in: multi.range, with: multi.replacement).contains("welcome.message=Hi\\nthere\npath="), "a line break is written as \\n and the continuation lines go")
        let rename = try XCTUnwrap(PropertiesStructure.replacement(in: props, path: [.key("count")], key: true, with: "max count"))
        XCTAssertTrue((props as NSString).replacingCharacters(in: rename.range, with: rename.replacement).contains("max\\ count 25\n"))
        XCTAssertEqual(PropertiesStructure.encodedValue(" lead\\"), "\\ lead\\\\")
        XCTAssertNil(PropertiesStructure.site(in: props, path: [.key("nope")]))
    }
}
