//
//  PHPSerializedRepair.swift
//  DataConverter
//
//  One string whose declared length did not match its bytes.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

/// One `s:N:"…";` whose N was wrong, the usual damage a search-and-replace over a database leaves
/// (a URL replaced by a longer one, the length left as it was).
public struct PHPSerializedRepair: Equatable, Sendable {
    /// The byte offset of the string's `s`.
    public let offset: Int
    /// The length the value declared.
    public let declaredLength: Int
    /// The length of the bytes it holds.
    public let actualLength: Int

    /// Creates a repair record.
    public init(offset: Int, declaredLength: Int, actualLength: Int) {
        self.offset = offset
        self.declaredLength = declaredLength
        self.actualLength = actualLength
    }
}
