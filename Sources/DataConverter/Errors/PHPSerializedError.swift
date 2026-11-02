//
//  PHPSerializedError.swift
//  DataConverter
//
//  Why a PHP-serialized value could not be read, and where.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Why `PHPSerialized.read` gave up, and the byte offset where it did.
public struct PHPSerializedError: Error, Equatable, Sendable, CustomStringConvertible {
    /// What went wrong.
    public enum Reason: Equatable, Sendable {
        /// The input ended inside a value.
        case unexpectedEnd
        /// A byte that cannot stand here (`expected` names what could).
        case unexpected(expected: String)
        /// Text follows the value.
        case trailingText
        /// Containers nested deeper than the reader follows.
        case tooDeep
        /// References copied out past the size the reader builds (a reference bomb).
        case tooLarge
        /// A reference (`r:` or `R:`) to a value that does not exist.
        case badReference(Int)
    }

    /// What went wrong.
    public let reason: Reason
    /// The byte offset where it did.
    public let offset: Int

    /// Creates an error.
    public init(_ reason: Reason, at offset: Int) {
        self.reason = reason
        self.offset = offset
    }

    /// One line for a status bar: what went wrong and at which byte.
    public var description: String {
        let at = offset.formatted()
        switch reason {
        case .unexpectedEnd:
            return String(localized: "The value ends early, at byte \(at)", bundle: .module, comment: "PHP unserialize: input truncated")
        case .unexpected(let expected):
            return String(
                localized: "Expected \(expected) at byte \(at)", bundle: .module,
                comment: "PHP unserialize: a wrong character; the first argument is what could come there, e.g. ';' or a number")
        case .trailingText:
            return String(
                localized: "Text follows the value, at byte \(at)", bundle: .module, comment: "PHP unserialize: extra text after the value")
        case .tooDeep:
            return String(
                localized: "Nested too deeply to read, at byte \(at)", bundle: .module, comment: "PHP unserialize: nesting limit reached")
        case .tooLarge:
            return String(
                localized: "Its references copy out too much to show, at byte \(at)", bundle: .module,
                comment: "PHP unserialize: references would expand into a huge value")
        case .badReference(let slot):
            return String(
                localized: "A reference to value \(slot), which does not exist, at byte \(at)", bundle: .module,
                comment: "PHP unserialize: r:/R: names a value number that is not there")
        }
    }
}
