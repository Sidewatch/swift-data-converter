//
//  PropertyListStructure.swift
//  DataConverter
//
//  A property list's bytes — binary or XML — as ordered structure, through Foundation's reader.
//
//  Created by David Sherlock on 9/25/26.
//

import Foundation

/// A property list as the structure a tree shows (25 Sep 2026): Foundation reads any format it
/// knows — a BINARY plist (`bplist00`, what Xcode compiles `.strings` and `Info.plist` into, and
/// what `defaults export` writes), the XML one, or OpenStep text — and the value comes back as
/// `StructuredValue`: a dictionary's keys SORTED (the reader hands a dictionary; the file's order
/// is not knowable through it — an XML plist read with its order and its edit sites is
/// swift-code-highlighting's `PlistStructure`, next to the grammar), a date as ISO 8601, data as
/// its byte count, booleans told from numbers. Nil when the bytes are not a property list.
public enum PropertyListStructure {
    /// Whether `head` (the file's first bytes) is a binary property list.
    public static func isBinary(_ head: Data) -> Bool { head.starts(with: Array("bplist".utf8)) }

    /// The document as structure, or nil when the bytes are not a property list.
    public static func value(of data: Data) -> StructuredValue? {
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { return nil }
        return convert(object)
    }

    /// A date as the XML plist writes it (`2026-09-25T10:15:00Z`).
    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); return f.string(from: date)
    }

    /// One Foundation value as structure.
    static func convert(_ object: Any) -> StructuredValue {
        switch object {
        case let dict as [String: Any]:
            return .mapping(dict.keys.sorted().map { StructuredPair(key: $0, value: convert(dict[$0]!)) })
        case let array as [Any]:
            return .sequence(array.map(convert))
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            if CFNumberIsFloatType(number) { return .number(number.doubleValue) }
            return .integer(number.intValue)
        case let date as Date:
            return .string(iso(date))
        case let data as Data:
            return .string("\(data.count) bytes")
        default:
            return .string(String(describing: object))
        }
    }
}
