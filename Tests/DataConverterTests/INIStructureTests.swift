//
//  INIStructureTests.swift
//  DataConverterTests
//
//  An INI file as sections of typed keys, and one key or value rewritten in place.
//
//  Created by David Sherlock on 9/25/26.
//

import XCTest
@testable import DataConverter

final class INIStructureTests: XCTestCase {
    let ini = """
    ; Application settings
    name = Inventory API
    flag

    [database]
    host: db.internal
    port = 5432
    # a comment, not a value
    timeout = 30.5
    debug = Off
    dsn = "postgres://db/app; not a comment"
    motd = first line
        second line

    [remote "origin"]
    url = git@github.com:x/y.git
    url = https://example.com/y.git
    """
    func pairs(_ v: StructuredValue?) -> [StructuredPair] { if case .mapping(let p)? = v { return p } else { return [] } }
    func raw(_ r: NSRange?) -> String? { r.map { (ini as NSString).substring(with: $0) } }

    func testSectionsKeysAndTypesInFileOrder() throws {
        let root = pairs(INIStructure.value(of: ini))
        XCTAssertEqual(root.map(\.key), ["name", "flag", "database", "remote \"origin\""], "root keys first, then sections as written")
        XCTAssertEqual(root[0].value, .string("Inventory API"))
        XCTAssertEqual(root[1].value, .null, "a key with no separator")
        let db = pairs(root[2].value)
        XCTAssertEqual(db.map(\.key), ["host", "port", "timeout", "debug", "dsn", "motd"])
        XCTAssertEqual(db[0].value, .string("db.internal"), "a colon separates too")
        XCTAssertEqual(db[1].value, .integer(5432))
        XCTAssertEqual(db[2].value, .number(30.5))
        XCTAssertEqual(db[3].value, .bool(false), "Off is a boolean, any case")
        XCTAssertEqual(db[4].value, .string("postgres://db/app; not a comment"), "quotes removed, no inline comment")
        XCTAssertEqual(db[5].value, .string("first line\nsecond line"), "an indented line continues the value")
        let remote = pairs(root[3].value)
        XCTAssertEqual(remote.map(\.key), ["url", "url"], "duplicates are listed")
        XCTAssertNil(INIStructure.value(of: "; only a comment\n\n"))
    }

    func testSitesAndReplacements() throws {
        let port = try XCTUnwrap(INIStructure.site(in: ini, path: [.key("database"), .key("port")]))
        XCTAssertEqual(raw(port.key), "port"); XCTAssertEqual(raw(port.value), "5432")
        let dsn = try XCTUnwrap(INIStructure.site(in: ini, path: [.key("database"), .key("dsn")]))
        XCTAssertEqual(raw(dsn.value), "postgres://db/app; not a comment", "inside the quotes, so they stay")
        let motd = try XCTUnwrap(INIStructure.site(in: ini, path: [.key("database"), .key("motd")]))
        XCTAssertEqual(raw(motd.value), "first line\n    second line")
        let section = try XCTUnwrap(INIStructure.site(in: ini, path: [.key("remote \"origin\"")]))
        XCTAssertEqual(raw(section.key), "remote \"origin\"")
        XCTAssertTrue(raw(section.value)!.hasPrefix("url = git@"), raw(section.value)!)
        let name = try XCTUnwrap(INIStructure.site(in: ini, path: [.key("name")]))
        XCTAssertEqual(raw(name.value), "Inventory API")
        XCTAssertNil(INIStructure.site(in: ini, path: [.key("database"), .key("nope")]))
        XCTAssertNil(INIStructure.site(in: ini, path: [.key("nope")]))

        let edit = try XCTUnwrap(INIStructure.replacement(in: ini, path: [.key("database"), .key("host")], key: false, with: "localhost"))
        XCTAssertTrue((ini as NSString).replacingCharacters(in: edit.range, with: edit.replacement).contains("host: localhost\n"))
        let flag = try XCTUnwrap(INIStructure.replacement(in: ini, path: [.key("flag")], key: false, with: "yes"))
        XCTAssertTrue((ini as NSString).replacingCharacters(in: flag.range, with: flag.replacement).contains("flag = yes\n"), "a bare key gains its separator")
        let rename = try XCTUnwrap(INIStructure.replacement(in: ini, path: [.key("database")], key: true, with: "db"))
        XCTAssertTrue((ini as NSString).replacingCharacters(in: rename.range, with: rename.replacement).contains("[db]\n"))
        let multi = try XCTUnwrap(INIStructure.replacement(in: ini, path: [.key("database"), .key("motd")], key: false, with: "one\ntwo"))
        XCTAssertTrue((ini as NSString).replacingCharacters(in: multi.range, with: multi.replacement).contains("motd = one\n    two\n"))
    }

    func testCRLF() {
        let crlf = "[s]\r\na = 1\r\nb = two\r\n"
        XCTAssertEqual(pairs(pairs(INIStructure.value(of: crlf)).first?.value).map(\.key), ["a", "b"])
        let site = INIStructure.site(in: crlf, path: [.key("s"), .key("b")])
        XCTAssertEqual(site.map { (crlf as NSString).substring(with: $0.value) }, "two")
    }
}
