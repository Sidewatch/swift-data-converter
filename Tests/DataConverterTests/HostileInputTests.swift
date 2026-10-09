//
//  HostileInputTests.swift
//  DataConverterTests
//
//  Inputs shaped to exhaust a reader: 100,000 nested brackets, a property list that contains
//  itself, a notebook whose fields hold the wrong types. Each is a nil or a partial reading, never
//  a trap or a stack overflow.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import DataConverter

final class HostileInputTests: XCTestCase {
    let deep = String(repeating: "[", count: 100_000) + String(repeating: "]", count: 100_000)

    func testAHundredThousandNestedArraysAreReadToADepthLimitNotTheStack() {
        XCTAssertNil(JSONStructure.value(of: deep), "past the depth limit the document is refused whole")
        XCTAssertNil(JSONEdit.site(in: deep, path: [.index(0), .index(0), .index(0)]), "an edit site is not searched past the limit")
        XCTAssertNil(JSONEdit.site(in: String(repeating: "[", count: 100_000), path: [.index(0)]), "nor in an unclosed one")
        let shallow = String(repeating: "[", count: 40) + "1" + String(repeating: "]", count: 40)
        XCTAssertNotNil(JSONEdit.site(in: shallow, path: Array(repeating: .index(0), count: 40)), "forty levels are an ordinary document")
    }

    func testAPropertyListContainingItselfIsNil() {
        var plist = Data("bplist00".utf8)
        plist += Data([0xA1, 0x00])  // an array of one element: object 0, itself
        plist += Data([0x08])  // the offset table: object 0 at byte 8
        plist += Data(count: 6) + Data([0x00, 0x01, 0x01])
        plist += Data([0, 0, 0, 0, 0, 0, 0, 1]) + Data([0, 0, 0, 0, 0, 0, 0, 0]) + Data([0, 0, 0, 0, 0, 0, 0, 10])
        XCTAssertTrue(PropertyListStructure.isBinary(plist))
        XCTAssertNil(PropertyListStructure.value(of: plist))
    }

    func testANotebookWithTheWrongShapesIsNilOrPartial() {
        XCTAssertNil(JupyterNotebook.markdown(from: Data("{\"cells\": 5, \"metadata\": {\"language_info\": 3}}".utf8)))
        XCTAssertNil(JupyterNotebook.markdown(from: Data("{\"cells\": [{\"cell_type\": \"code\", \"outputs\": [".utf8)))
        let odd = """
            {"cells": [{"cell_type": "code", "source": 7, "outputs": [{"output_type": "stream", "text": 5},
            {"output_type": "execute_result", "data": {"text/plain": 9, "image/png": 3}}, {"output_type": "error", "traceback": "x"}, 4]},
            {"cell_type": 3, "source": ["ok"]}], "metadata": {"kernelspec": {"language": 2}}}
            """
        let markdown = JupyterNotebook.markdown(from: Data(odd.utf8))
        XCTAssertNotNil(markdown)
        XCTAssertTrue(markdown?.contains("cell-1") == true, "every cell keeps its anchor")
    }
}
