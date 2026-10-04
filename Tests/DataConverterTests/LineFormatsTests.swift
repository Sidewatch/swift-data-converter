//
//  LineFormatsTests.swift
//  DataConverterTests
//
//  Procfiles, ssh configs, gettext catalogs and Jupyter notebooks read, and the line formats
//  edited in place.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import DataConverter

final class LineFormatsTests: XCTestCase {

    // MARK: - Procfile

    func testProcfile() {
        let text = "# processes\nweb: bundle exec puma -C config/puma.rb\nworker:   bundle exec sidekiq\nnot a process line\n"
        let entries = Procfile.parse(text)
        XCTAssertEqual(entries.map(\.process), ["web", "worker"])
        XCTAssertEqual(entries[1].command, "bundle exec sidekiq")
        XCTAssertTrue(
            Procfile.replacingCommand(in: text, line: 3, with: "bin/jobs").contains("\nworker:   bin/jobs\n"),
            "the gap after the colon is kept")
        XCTAssertTrue(Procfile.replacingProcess(in: text, line: 2, with: "app").contains("\napp: bundle exec puma"))
        XCTAssertEqual(Procfile.replacingProcess(in: text, line: 2, with: "has space"), text)
    }

    // MARK: - ssh config

    func testSSHConfig() {
        let text = """
            # global
            ServerAliveInterval 60
            Host bastion
              HostName bastion.example.com
              User deploy
              Port=2222
            Host *.internal !skip.internal
                ProxyJump bastion
                IdentityFile "~/.ssh/id with space"
            Match host build exec "true"
              ForwardAgent no
            """
        let blocks = SSHConfig.parse(text)
        XCTAssertEqual(blocks.map(\.patterns), ["", "bastion", "*.internal !skip.internal", "host build exec \"true\""])
        XCTAssertEqual(blocks[0].value("serveraliveinterval"), "60", "keywords are case-insensitive")
        XCTAssertEqual(blocks[1].value("Port"), "2222", "Keyword=value is read")
        XCTAssertEqual(blocks[2].value("IdentityFile"), "~/.ssh/id with space", "quotes removed")
        XCTAssertEqual(blocks[3].kind, "Match")
        let edited = SSHConfig.replacingValue(in: text, line: 6, with: "22")
        XCTAssertTrue(edited.contains("\n  Port=22\n"), "the separator is kept")
        XCTAssertTrue(SSHConfig.replacingValue(in: text, line: 9, with: "~/.ssh/other key").contains("IdentityFile \"~/.ssh/other key\""))
        XCTAssertTrue(SSHConfig.replacingValue(in: text, line: 3, with: "jump").contains("\nHost jump\n"))
    }

    // MARK: - gettext

    private let po = """
        msgid ""
        msgstr ""
        "Language: de\\n"
        "Plural-Forms: nplurals=2; plural=(n != 1);\\n"

        #: src/app.c:10
        #, fuzzy, c-format
        msgid "Hello, %s"
        msgstr "Hallo, %s"

        msgctxt "menu"
        msgid "Open"
        msgstr ""

        msgid "One file"
        msgid_plural "%d files"
        msgstr[0] "Eine Datei"
        msgstr[1] "%d Dateien"

        msgid ""
        "A long "
        "message"
        msgstr ""
        "Eine lange "
        "Nachricht"
        #~ msgid "Old"
        #~ msgstr "Alt"
        """

    func testGettextMessages() {
        let messages = GettextCatalog.parse(po)
        XCTAssertEqual(messages.count, 5)
        XCTAssertTrue(messages[0].isHeader)
        XCTAssertEqual(messages[1].source, "Hello, %s")
        XCTAssertTrue(messages[1].isFuzzy)
        XCTAssertEqual(messages[1].flags, ["fuzzy", "c-format"])
        XCTAssertEqual(messages[1].references, ["src/app.c:10"])
        XCTAssertEqual(messages[2].context, "menu")
        XCTAssertTrue(messages[2].isUntranslated)
        XCTAssertEqual(messages[3].plural, "%d files")
        XCTAssertEqual(messages[3].translations, ["Eine Datei", "%d Dateien"])
        XCTAssertEqual(messages[4].source, "A long message", "continued strings are joined")
        XCTAssertEqual(messages[4].translations, ["Eine lange Nachricht"])
        XCTAssertFalse(messages.contains { $0.source == "Old" }, "obsolete messages are skipped")
    }

    func testGettextEdits() {
        let messages = GettextCatalog.parse(po)
        let translated = GettextCatalog.replacingTranslation(in: po, message: messages[2], with: "Öffnen \"jetzt\"")
        XCTAssertTrue(translated.contains("msgid \"Open\"\nmsgstr \"Öffnen \\\"jetzt\\\"\"\n"), translated)
        XCTAssertEqual(GettextCatalog.parse(translated)[2].translations, ["Öffnen \"jetzt\""])
        let multi = GettextCatalog.replacingTranslation(in: po, message: messages[4], with: "Kurz")
        XCTAssertEqual(GettextCatalog.parse(multi)[4].translations, ["Kurz"], "a continued msgstr is replaced whole")
        XCTAssertFalse(multi.contains("Nachricht"))
        XCTAssertEqual(GettextCatalog.replacingTranslation(in: po, message: messages[3], with: "x"), po, "plural messages are not edited")
        let reviewed = GettextCatalog.settingFuzzy(in: po, message: messages[1], false)
        XCTAssertTrue(reviewed.contains("#, c-format\nmsgid \"Hello, %s\""))
        let marked = GettextCatalog.settingFuzzy(in: po, message: messages[2], true)
        XCTAssertTrue(marked.contains("#, fuzzy\nmsgctxt \"menu\""), marked)
        XCTAssertTrue(GettextCatalog.parse(marked)[2].isFuzzy)
    }

    func testTheCorpusCatalog() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
            "../../../../TestFiles/languages/gettext/sample.po")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw XCTSkip("corpus not cloned") }
        let messages = GettextCatalog.parse(text)
        XCTAssertGreaterThan(messages.filter { !$0.isHeader }.count, 5)
        XCTAssertTrue(messages.contains { $0.plural != nil })
    }

    // MARK: - Jupyter

    func testNotebookAsMarkdown() throws {
        let notebook: [String: Any] = [
            "metadata": ["language_info": ["name": "python"]],
            "cells": [
                ["cell_type": "markdown", "source": ["# Title\n", "Some *text*."]],
                [
                    "cell_type": "code", "execution_count": 3, "source": "print('hi')\nx = 1 + 1\nx",
                    "outputs": [
                        ["output_type": "stream", "text": ["hi\n"]],
                        ["output_type": "execute_result", "data": ["text/plain": "2", "text/html": "<b>2</b>"]],
                        ["output_type": "display_data", "data": ["image/png": "iVBORw0K\nGgo="]],
                        [
                            "output_type": "error", "ename": "ValueError", "evalue": "bad",
                            "traceback": ["\u{1B}[0;31mValueError\u{1B}[0m: bad"],
                        ],
                    ],
                ],
                ["cell_type": "code", "source": "```nested``` fence", "outputs": []],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: notebook)
        let md = try XCTUnwrap(JupyterNotebook.markdown(from: data))
        XCTAssertTrue(md.hasPrefix("# Title\nSome *text*."))
        XCTAssertTrue(md.contains("*In [3]:*\n\n```python\nprint('hi')\nx = 1 + 1\nx\n```"))
        XCTAssertTrue(md.contains("```text\nhi\n```"))
        XCTAssertTrue(md.contains("```text\n2\n```"))
        XCTAssertFalse(md.contains("<b>2</b>"), "HTML outputs are not rendered")
        XCTAssertTrue(md.contains("![output](data:image/png;base64,iVBORw0KGgo=)"))
        XCTAssertTrue(md.contains("ValueError: bad"))
        XCTAssertFalse(md.contains("\u{1B}"), "ANSI codes removed")
        XCTAssertTrue(md.contains("*In [ ]:*\n\n````python\n```nested``` fence\n````"), "a longer fence around backticks")
        XCTAssertEqual(JupyterNotebook.summary(from: data), .init(codeCells: 2, markdownCells: 1, language: "python"))
        XCTAssertNil(JupyterNotebook.markdown(from: Data("{\"a\": 1}".utf8)))
    }

    func testTheCorpusNotebook() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
            "../../../../TestFiles/data/trees/analysis.ipynb")
        guard let data = try? Data(contentsOf: url) else { throw XCTSkip("corpus not cloned") }
        let md = try XCTUnwrap(JupyterNotebook.markdown(from: data))
        XCTAssertTrue(md.contains("```"))
    }
}
