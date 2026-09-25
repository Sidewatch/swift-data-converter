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

    func testReplacingAValueKeepsTheLineAroundItAndRoundTrips() {
        let text = "# c\nexport A = one # note\nB=\"two words\" # kept\nC='lit'\nD=plain\nE=\n"
        let a = DotEnv.replacingValue(in: text, line: 2, with: "uno")
        XCTAssertEqual(a.components(separatedBy: "\n")[1], "export A = uno # note", "export, the spacing and the comment stay")
        let b = DotEnv.replacingValue(in: text, line: 3, with: "three words")
        XCTAssertEqual(b.components(separatedBy: "\n")[2], "B=\"three words\" # kept", "a quoted line stays quoted, its comment kept")
        let c = DotEnv.replacingValue(in: text, line: 4, with: "it's \"q\"")
        XCTAssertEqual(c.components(separatedBy: "\n")[3], "C=\"it's \\\"q\\\"\"", "a single-quoted line moves to double quotes when the value needs escapes")
        let d = DotEnv.replacingValue(in: text, line: 5, with: "has space")
        XCTAssertEqual(d.components(separatedBy: "\n")[4], "D=\"has space\"", "a bare value is quoted once it needs it")
        let e = DotEnv.replacingValue(in: text, line: 6, with: "x")
        XCTAssertEqual(e.components(separatedBy: "\n")[5], "E=x")
        for (edited, line, value) in [(a, 2, "uno"), (b, 3, "three words"), (c, 4, "it's \"q\""), (d, 5, "has space"), (e, 6, "x")] {
            XCTAssertEqual(DotEnv.parse(edited).first { $0.line == line }?.value, value, "line \(line) reads back")
        }
        XCTAssertEqual(DotEnv.replacingValue(in: text, line: 1, with: "x"), text, "a comment line is not an entry")
        XCTAssertEqual(DotEnv.replacingValue(in: text, line: 99, with: "x"), text)
        XCTAssertEqual(DotEnv.replacingValue(in: "K=v\n", line: 1, with: "multi\nline"), "K=\"multi\\nline\"\n")
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

    // MARK: - Renaming a key

    func testReplacingKeyKeepsExportSpacingAndEverythingAfterTheSign() {
        let text = "NAME=grove\nexport  API_KEY = abc  # prod\n  PORT   =3000\n# a comment\n"
        XCTAssertEqual(DotEnv.replacingKey(in: text, line: 1, with: "TITLE"),
                       "TITLE=grove\nexport  API_KEY = abc  # prod\n  PORT   =3000\n# a comment\n")
        XCTAssertEqual(DotEnv.replacingKey(in: text, line: 2, with: "TOKEN"),
                       "NAME=grove\nexport  TOKEN = abc  # prod\n  PORT   =3000\n# a comment\n",
                       "export, the spacing and the trailing comment all survive")
        XCTAssertEqual(DotEnv.replacingKey(in: text, line: 3, with: "HTTP_PORT"),
                       "NAME=grove\nexport  API_KEY = abc  # prod\n  HTTP_PORT   =3000\n# a comment\n",
                       "the indent and the spaces before the sign are kept")
    }

    func testAKeyIsSanitisedAndAnImpossibleOneLeavesTheFileAlone() {
        let text = "NAME=grove\n"
        XCTAssertEqual(DotEnv.replacingKey(in: text, line: 1, with: "MY NAME"), "MYNAME=grove\n", "a .env name holds no spaces")
        XCTAssertEqual(DotEnv.replacingKey(in: text, line: 1, with: "A=B#C"), "ABC=grove\n")
        XCTAssertEqual(DotEnv.replacingKey(in: text, line: 1, with: "   "), text, "nothing left to name it with")
        XCTAssertEqual(DotEnv.replacingKey(in: text, line: 4, with: "X"), text, "no such line")
        XCTAssertEqual(DotEnv.replacingKey(in: "# just a comment\n", line: 1, with: "X"), "# just a comment\n")
    }

    func testRenamingThenReadingBackGivesTheNewNameAndTheSameValue() throws {
        let text = "export DB_URL=\"postgres://app:s3cret@db/app\"  # main\n"
        let renamed = DotEnv.replacingKey(in: text, line: 1, with: "DATABASE_URL")
        let entries = DotEnv.parse(renamed)
        XCTAssertEqual(entries.map(\.key), ["DATABASE_URL"])
        XCTAssertEqual(entries.first?.value, "postgres://app:s3cret@db/app", "the value is untouched by a rename")
        XCTAssertTrue(renamed.contains("# main"))
    }
}
