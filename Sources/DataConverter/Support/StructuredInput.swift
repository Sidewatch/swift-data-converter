//
//  StructuredInput.swift
//  DataConverter
//
//  Pasted text read as the JSON a query runs over: JSON as it is, PHP serialize read, either one
//  base64-wrapped unwrapped first.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// What a value copied out of a database or a log really is, as JSON a query can run over. JSON
/// passes through untouched (the query engine reports its own errors); a PHP-serialized value is
/// read, its nested serialized and JSON strings expanded; a value wrapped in base64 (standard or
/// URL-safe, line breaks allowed) is unwrapped when it holds one of those two.
public enum StructuredInput {
    /// Reads `text`; see the type's description.
    public static func reading(_ text: String) -> StructuredInputReading {
        if let php = phpReading(Array(text.utf8), wasBase64: false) { return php }
        if let decoded = base64Payload(text) {
            if let php = phpReading(decoded, wasBase64: true), php.problem == nil { return php }
            if startsLikeJSONContainer(decoded), let json = String(bytes: decoded, encoding: .utf8) {
                return StructuredInputReading(json: json, source: .json, wasBase64: true)
            }
        }
        return StructuredInputReading(json: text, source: .json, wasBase64: false)
    }

    /// A PHP-serialized value read with its nested values expanded, its failure kept; nil when the
    /// bytes do not start like one.
    private static func phpReading(_ bytes: [UInt8], wasBase64: Bool) -> StructuredInputReading? {
        guard PHPSerialized.looksSerialized(bytes) else { return nil }
        do {
            let reading = try PHPSerialized.read(bytes, expandingNested: true)
            return StructuredInputReading(
                json: reading.value.jsonText(), source: .phpSerialized, wasBase64: wasBase64, repairs: reading.repairs,
                expandedCount: reading.expandedCount)
        } catch {
            return StructuredInputReading(json: "", source: .phpSerialized, wasBase64: wasBase64, problem: error)
        }
    }

    /// The bytes `text` stands for when it is nothing but base64 (at least 8 characters of it).
    private static func base64Payload(_ text: String) -> [UInt8]? {
        var cleaned: [UInt8] = []
        cleaned.reserveCapacity(text.utf8.count)
        for b in text.utf8 {
            switch b {
            case UInt8(ascii: " "), 0x09, 0x0A, 0x0D: continue
            case UInt8(ascii: "-"): cleaned.append(UInt8(ascii: "+"))
            case UInt8(ascii: "_"): cleaned.append(UInt8(ascii: "/"))
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
                UInt8(ascii: "+"), UInt8(ascii: "/"), UInt8(ascii: "="):
                cleaned.append(b)
            default: return nil
            }
        }
        guard cleaned.count >= 8 else { return nil }
        while cleaned.count % 4 != 0 { cleaned.append(UInt8(ascii: "=")) }
        return Data(base64Encoded: Data(cleaned)).map { [UInt8]($0) }
    }

    private static func startsLikeJSONContainer(_ bytes: [UInt8]) -> Bool {
        let first = bytes.first { !PHPSerializedParser.isSpace($0) }
        return first == UInt8(ascii: "{") || first == UInt8(ascii: "[")
    }
}
