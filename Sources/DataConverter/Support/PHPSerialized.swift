//
//  PHPSerialized.swift
//  DataConverter
//
//  PHP's serialize() format read as ordered structure: WordPress options and post meta, Laravel
//  caches and queue payloads, Drupal and Magento rows.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A value written by PHP's `serialize()`, read as `StructuredValue` by PHP's own rules
/// (`ext/standard/var_unserializer.re`), never by running anything: no class is loaded, no
/// `__wakeup` or `__unserialize` is called.
///
/// The tree: a list array (integer keys 0, 1, 2… in order) is a sequence and any other array a
/// mapping, its keys as strings; an object is a mapping whose first key is `__class`, a protected
/// property named `name:protected` and a private one `name:Class:private` (print_r's words); a
/// custom-serialized object (`C:`) is `__class` and its payload as `__serialized`; an enum case is
/// the string `Enum::Case`; `INF`, `-INF` and `NAN` are those strings; a string's bytes are read
/// as UTF-8, a bad sequence as U+FFFD; a reference (`r:`, `R:`) is a copy of the value it names,
/// or `*RECURSION*` where it names a value that contains it.
///
/// A string whose declared length is wrong, as a database search-and-replace leaves it, is read up
/// to its real end and reported as a repair, where PHP would refuse the whole value.
public enum PHPSerialized {
    /// Whether `text` starts the way a serialized value does (`a:2:{`, `s:5:"`, `O:8:"`, `N;`…),
    /// after leading white space. A cheap test of the first bytes, not a parse.
    public static func looksSerialized(_ text: some StringProtocol) -> Bool {
        looksSerialized(Array(text.utf8.prefix(64)))
    }

    /// Whether `bytes` start the way a serialized value does; see `looksSerialized(_:)`.
    public static func looksSerialized(_ bytes: [UInt8]) -> Bool {
        var i = 0
        while i < bytes.count, PHPSerializedParser.isSpace(bytes[i]) { i += 1 }
        guard i + 1 < bytes.count else { return false }
        let kind = bytes[i], next = bytes[i + 1]
        if kind == UInt8(ascii: "N") { return next == UInt8(ascii: ";") }
        guard next == UInt8(ascii: ":"), i + 2 < bytes.count else { return false }
        let after = bytes[i + 2]
        switch kind {
        case UInt8(ascii: "b"): return after == UInt8(ascii: "0") || after == UInt8(ascii: "1")
        case UInt8(ascii: "i"), UInt8(ascii: "d"):
            return PHPSerializedParser.isDigit(after) || after == UInt8(ascii: "-") || after == UInt8(ascii: "+")
                || after == UInt8(ascii: "I")
                || after == UInt8(ascii: "N")
        case UInt8(ascii: "s"), UInt8(ascii: "S"), UInt8(ascii: "a"), UInt8(ascii: "O"), UInt8(ascii: "C"), UInt8(ascii: "E"):
            return PHPSerializedParser.isDigit(after)
        default: return false
        }
    }

    /// Reads one serialized value from `bytes` (white space may follow it, nothing else).
    /// `expandingNested` also reads a string that is itself a whole serialized value (WordPress
    /// serializes some values twice) or a JSON object or array, as structure in its place.
    public static func read(_ bytes: [UInt8], expandingNested: Bool = false) throws(PHPSerializedError) -> PHPSerializedReading {
        var parser = PHPSerializedParser(bytes: bytes, expandingNested: expandingNested)
        return try parser.readDocument()
    }

    /// Reads `text` as a serialized value; see `read(_:expandingNested:)`.
    public static func read(_ text: String, expandingNested: Bool = false) throws(PHPSerializedError) -> PHPSerializedReading {
        try read(Array(text.utf8), expandingNested: expandingNested)
    }
}
