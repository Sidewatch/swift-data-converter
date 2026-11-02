//
//  StructuredInputSource.swift
//  DataConverter
//
//  The format pasted text was read as.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

/// The format `StructuredInput` read pasted text as.
public enum StructuredInputSource: Equatable, Sendable {
    /// JSON (or text that is nothing else; the query engine says what is wrong with it).
    case json
    /// PHP's serialize() format.
    case phpSerialized
}
