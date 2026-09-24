//
//  StructuredValue.swift
//  DataConverter
//
//  One ordered value model for every document a tree can show: YAML, TOML, XML, JSON, plists.
//
//  Created by David Sherlock on 9/25/26.
//

import Foundation

/// A document as ordered structure — the value model the readers produce and a tree preview
/// shows (25 Sep 2026; it was `YAMLStructure.Value` until TOML and XML needed the same shape).
/// Mappings keep the file's key order (a `[String: Any]` would not); scalars keep the type the
/// file gives them; anything a format has no better word for is a string.
public indirect enum StructuredValue: Equatable, Sendable {
    case mapping([StructuredPair])
    case sequence([StructuredValue])
    case string(String)
    case integer(Int)
    case number(Double)
    case bool(Bool)
    case null
}

/// One `key: value` of a mapping, in file order.
public struct StructuredPair: Equatable, Sendable {
    public let key: String
    public let value: StructuredValue
    public init(key: String, value: StructuredValue) { self.key = key; self.value = value }
}
