//
//  HostsFileTests.swift
//  DataConverterTests
//
//  A hosts file read as entries — disabled ones and section titles included — and edited a
//  line at a time with its spacing kept.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import DataConverter

final class HostsFileTests: XCTestCase {
    private let text = """
        ##
        # Host database for local development.
        ##
        # ── Loopback ──
        127.0.0.1       localhost
        ::1             localhost ip6-localhost
        # ── Local services ──
        127.0.0.1       db.local        # Postgres in Docker
        192.0.2.61     trailing.example.com#no-space
        #192.0.2.99     disabled.example.com
        # a comment about 10.0.0.1 servers
          192.0.2.64  indented.example.com
        0.0.0.0         ads.example.net tracker.example.net
        """

    func testEntriesSectionsAndDisabledLines() {
        let entries = HostsFile.parse(text)
        XCTAssertEqual(entries.map(\.line), [5, 6, 8, 9, 10, 12, 13])
        XCTAssertEqual(entries[1].names, ["localhost", "ip6-localhost"])
        XCTAssertTrue(entries[1].isIPv6)
        XCTAssertEqual(entries[0].section, "Loopback")
        XCTAssertEqual(entries[2].section, "Local services")
        XCTAssertEqual(entries[2].comment, "Postgres in Docker")
        XCTAssertEqual(entries[3].names, ["trailing.example.com"], "# starts a comment anywhere")
        XCTAssertEqual(entries[3].comment, "no-space")
        XCTAssertFalse(entries[4].isEnabled)
        XCTAssertEqual(entries[4].address, "192.0.2.99")
        XCTAssertTrue(entries[6].isBlocked)
        XCTAssertFalse(entries.contains { $0.names.contains("servers") }, "commented prose is not an entry")
    }

    func testEditsKeepSpacing() {
        XCTAssertTrue(
            HostsFile.replacingAddress(in: text, line: 8, with: "10.1.1.1").contains(
                "\n10.1.1.1       db.local        # Postgres in Docker\n"))
        XCTAssertTrue(
            HostsFile.replacingNames(in: text, line: 13, with: ["ads.example.net", "more.example.net"])
                .contains("\n0.0.0.0         ads.example.net more.example.net"))
        XCTAssertTrue(HostsFile.replacingComment(in: text, line: 8, with: "Postgres 17").contains("db.local        # Postgres 17\n"))
        XCTAssertTrue(HostsFile.replacingComment(in: text, line: 5, with: "loopback").contains("\n127.0.0.1       localhost # loopback\n"))
        XCTAssertTrue(
            HostsFile.replacingComment(in: text, line: 8, with: "").contains("\n127.0.0.1       db.local\n"), "an empty comment removes it")
        XCTAssertTrue(
            HostsFile.replacingAddress(in: text, line: 10, with: "192.0.2.100").contains("\n#192.0.2.100     disabled.example.com\n"),
            "a disabled entry stays disabled")
        XCTAssertTrue(HostsFile.replacingAddress(in: text, line: 12, with: "192.0.2.65").contains("\n  192.0.2.65  indented.example.com\n"))
        XCTAssertEqual(HostsFile.replacingAddress(in: text, line: 5, with: "1.2.3.4 evil"), text, "an address with a space is refused")
    }

    func testEnableAndDisable() {
        XCTAssertTrue(HostsFile.settingEnabled(in: text, line: 10, true).contains("\n192.0.2.99     disabled.example.com\n"))
        XCTAssertTrue(HostsFile.settingEnabled(in: text, line: 12, false).contains("\n  #192.0.2.64  indented.example.com\n"))
        let roundTrip = HostsFile.settingEnabled(in: HostsFile.settingEnabled(in: text, line: 5, false), line: 5, true)
        XCTAssertEqual(roundTrip, text)
    }

    func testTheCorpusFile() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
            "../../../../TestFiles/languages/hosts/hosts")
        guard let corpus = try? String(contentsOf: url, encoding: .utf8) else { throw XCTSkip("corpus not cloned") }
        let entries = HostsFile.parse(corpus)
        XCTAssertGreaterThan(entries.count, 50)
        XCTAssertTrue(entries.contains { !$0.isEnabled && $0.names == ["disabled.example.com"] })
        XCTAssertTrue(entries.contains { $0.address == "fe80::1%lo0" })
        XCTAssertTrue(entries.contains { $0.address == "0x7f.0.0.1" })
        XCTAssertFalse(entries.contains { $0.address == "Unicode" || $0.address == "Double-hash" })
    }
}
