//
//  StructuredValue.swift
//  DataConverter
//
//  One ordered value model for every document a tree can show: YAML, TOML, XML, JSON, plists.
//
//  Created by David Sherlock on 9/25/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A document as ordered structure — the value model every format's reader produces and a tree
/// preview shows. Mappings keep the file's key order (a `[String: Any]` would not); scalars keep
/// the type the file gives them; anything a format has no better word for is a string.
public indirect enum StructuredValue: Equatable, Sendable {
    /// Keyed members in file order.
    case mapping([StructuredPair])
    /// Unkeyed members in file order.
    case sequence([StructuredValue])
    case string(String)
    case integer(Int)
    /// A number with a fraction or exponent, or too big for `Int`.
    case number(Double)
    case bool(Bool)
    case null
}

/// One `key: value` of a mapping, in file order.
public struct StructuredPair: Equatable, Sendable {
    /// The member's key as written, quotes removed.
    public let key: String
    /// The member's value.
    public let value: StructuredValue
    /// Creates a pair.
    public init(key: String, value: StructuredValue) { self.key = key; self.value = value }
}
