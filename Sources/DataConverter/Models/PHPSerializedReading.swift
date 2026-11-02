//
//  PHPSerializedReading.swift
//  DataConverter
//
//  What reading a PHP-serialized value produced: the tree, and what was repaired or expanded.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

/// A PHP-serialized value read as structure (`PHPSerialized.read`).
public struct PHPSerializedReading: Equatable, Sendable {
    /// The value as ordered structure.
    public let value: StructuredValue
    /// Strings whose declared length was wrong and were read to their real end, in byte order.
    public let repairs: [PHPSerializedRepair]
    /// How many strings were read as the structure they hold (`expandingNested`).
    public let expandedCount: Int

    /// Creates a reading.
    public init(value: StructuredValue, repairs: [PHPSerializedRepair], expandedCount: Int) {
        self.value = value
        self.repairs = repairs
        self.expandedCount = expandedCount
    }
}
