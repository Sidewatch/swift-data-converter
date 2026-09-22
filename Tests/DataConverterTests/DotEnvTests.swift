//
//  DotEnvTests.swift
//  DataConverterTests
//
//  A .env file read as entries the way the loaders read it, and the masking rule.
//
//  Created by David Sherlock on 9/22/26.
//

import XCTest
@testable import DataConverter

/// Tests for `DotEnv`: quoting, comments, `export`, malformed lines, and what gets masked.
final class DotEnvTests: XCTestCase {

    func testEntriesInFileOrderWithQuotesAndCommentsResolved() {
        let text = """
        # database
        DB_HOST=localhost
        export DB_PORT = 5432
        NAME="grove app" # trailing comment
        MOTTO='it''s # not a comment'
        PATH_LIKE=/usr/local # a comment
        EMPTY=
        HASH=#not-a-value
        not a line
        =novalue
        MULTI="line one
        line two"
        ESC="tab\\there \\"quoted\\" \\$5"
        """
        let entries = DotEnv.parse(text)
        XCTAssertEqual(entries.map(\.key), ["DB_HOST", "DB_PORT", "NAME", "MOTTO", "PATH_LIKE", "EMPTY", "HASH", "MULTI", "ESC"])
        XCTAssertEqual(entries[0], DotEnv.Entry(key: "DB_HOST", value: "localhost", line: 2))
        XCTAssertEqual(entries[1].value, "5432", "export and the spaces around = are dropped")
        XCTAssertEqual(entries[2].value, "grove app", "a double-quoted value keeps its spaces; the comment after it goes")
        XCTAssertEqual(entries[3].value, "it", "a single-quoted value ends at the first quote, like the loaders")
        XCTAssertEqual(entries[4].value, "/usr/local", "an unquoted value is cut at space-hash")
        XCTAssertEqual(entries[5].value, "")
        XCTAssertEqual(entries[6].value, "", "a bare # right after = is a comment")
        XCTAssertEqual(entries[7].value, "line one\nline two", "double quotes may run over lines")
        XCTAssertEqual(entries[7].line, 11)
        XCTAssertEqual(entries[8].value, "tab\there \"quoted\" $5")
    }

    func testEmptyAndCommentOnlyFilesHaveNoEntries() {
        XCTAssertEqual(DotEnv.parse(""), [])
        XCTAssertEqual(DotEnv.parse("# just\n\n# comments\n"), [])
        XCTAssertEqual(DotEnv.parse("A=1\r\nB=2\r\n").map(\.value), ["1", "2"], "CRLF files")
    }

    func testSecretsAreMaskedByKeyWordOrByCredentialsInAURL() {
        for key in ["API_KEY", "SECRET", "DB_PASSWORD", "AUTH_TOKEN", "PRIVATE_KEY", "aws_secret_access_key", "JWT_SIGNATURE", "SENTRY_DSN", "CREDENTIALS"] {
            XCTAssertTrue(DotEnv.shouldMask(key: key, value: "x"), key)
        }
        for key in ["PORT", "NAME", "VERSION", "THEME", "DB_HOST", "KEYBOARD_LAYOUT", "MONKEY", "AUTHOR"] {
            XCTAssertFalse(DotEnv.shouldMask(key: key, value: "x"), "\(key) only contains a secret word inside another")
        }
        XCTAssertTrue(DotEnv.shouldMask(key: "DB_URL", value: "postgres://app:s3cret@db.internal:5432/app"), "credentials in the URL")
        XCTAssertFalse(DotEnv.shouldMask(key: "DB_URL", value: "postgres://db.internal:5432/app"))
        XCTAssertFalse(DotEnv.shouldMask(key: "EMAIL", value: "someone@example.com"))
        XCTAssertEqual(DotEnv.mask, "••••••••")
    }
}
