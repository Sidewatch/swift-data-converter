//
//  StructuredInputReading.swift
//  DataConverter
//
//  Pasted text as the JSON a query runs over, and what it was before.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

/// What `StructuredInput.reading` made of pasted text.
public struct StructuredInputReading: Equatable, Sendable {
    /// The JSON to run a query over: the text itself when it is JSON (or not readable as anything).
    public let json: String
    /// What the text was.
    public let source: StructuredInputSource
    /// Whether it was wrapped in base64.
    public let wasBase64: Bool
    /// PHP strings read past a wrong declared length.
    public let repairs: [PHPSerializedRepair]
    /// Nested serialized or JSON strings read as structure.
    public let expandedCount: Int
    /// Why text that starts like PHP serialize could not be read; `json` is empty then.
    public let problem: PHPSerializedError?

    /// Creates a reading.
    public init(
        json: String, source: StructuredInputSource, wasBase64: Bool, repairs: [PHPSerializedRepair] = [], expandedCount: Int = 0,
        problem: PHPSerializedError? = nil
    ) {
        self.json = json
        self.source = source
        self.wasBase64 = wasBase64
        self.repairs = repairs
        self.expandedCount = expandedCount
        self.problem = problem
    }
}
