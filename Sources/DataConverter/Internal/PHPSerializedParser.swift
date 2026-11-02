//
//  PHPSerializedParser.swift
//  DataConverter
//
//  The byte scanner behind PHPSerialized: one method per value kind.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Reads PHP's serialize() format byte by byte (lengths count bytes, not characters). Every value
/// but an `R:` takes the next reference number, a container before its members, as PHP's
/// unserializer numbers them; array keys and property names take none. A reference copies the
/// finished value it names, or reads as `*RECURSION*` while that value is still being built.
struct PHPSerializedParser {
    /// How deep containers may nest (JSONStructure's bound too).
    static let maxDepth = 256
    /// How many values the tree may hold once references are copied out.
    static let maxValues = 2_000_000

    let bytes: [UInt8]
    let expandingNested: Bool
    /// The depth this parser starts at: a string read as the value it holds continues its parent's.
    var baseDepth = 0
    private var pos = 0
    /// Each numbered value once finished (nil while it is being built), and how many values it holds.
    private var slots: [(value: StructuredValue?, size: Int)] = []
    private var valueCount = 0
    private var repairs: [PHPSerializedRepair] = []
    private var expanded = 0

    init(bytes: [UInt8], expandingNested: Bool, baseDepth: Int = 0) {
        self.bytes = bytes
        self.expandingNested = expandingNested
        self.baseDepth = baseDepth
    }

    static func isSpace(_ b: UInt8) -> Bool { b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D }
    static func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }

    /// One value, white space around it and nothing else.
    mutating func readDocument() throws(PHPSerializedError) -> PHPSerializedReading {
        skipSpace()
        let value = try readValue(depth: baseDepth)
        skipSpace()
        guard pos == bytes.count else { throw PHPSerializedError(.trailingText, at: pos) }
        return PHPSerializedReading(value: value, repairs: repairs, expandedCount: expanded)
    }

    // MARK: - Values

    private mutating func readValue(depth: Int) throws(PHPSerializedError) -> StructuredValue {
        guard depth < Self.maxDepth else { throw PHPSerializedError(.tooDeep, at: pos) }
        let start = pos
        let kind = try peek()
        if kind == UInt8(ascii: "R") { return try readReference(at: start) }
        let slot = slots.count
        slots.append((nil, 0))
        let countBefore = valueCount
        let value: StructuredValue
        switch kind {
        case UInt8(ascii: "N"):
            pos += 1
            try expect(";")
            value = .null
        case UInt8(ascii: "b"): value = try readBool()
        case UInt8(ascii: "i"): value = try readInteger()
        case UInt8(ascii: "d"): value = try readDouble()
        case UInt8(ascii: "s"), UInt8(ascii: "S"): value = try expandedIfAsked(readStringBytes(), depth: depth)
        case UInt8(ascii: "a"): value = try readArray(depth: depth)
        case UInt8(ascii: "O"): value = try readObject(depth: depth)
        case UInt8(ascii: "C"): value = try readCustomObject()
        case UInt8(ascii: "E"): value = try readEnumCase()
        case UInt8(ascii: "r"): value = try readReference(at: start)
        default: throw PHPSerializedError(.unexpected(expected: Self.Words.aValue), at: pos)
        }
        valueCount += 1
        slots[slot] = (value, valueCount - countBefore)
        return value
    }

    private mutating func readBool() throws(PHPSerializedError) -> StructuredValue {
        pos += 1
        try expect(":")
        let digit = try next()
        guard digit == UInt8(ascii: "0") || digit == UInt8(ascii: "1") else {
            throw PHPSerializedError(.unexpected(expected: "0 / 1"), at: pos - 1)
        }
        try expect(";")
        return .bool(digit == UInt8(ascii: "1"))
    }

    /// `i:-42;` — an integer past Int's range reads as a number, as PHP's own reader does.
    private mutating func readInteger() throws(PHPSerializedError) -> StructuredValue {
        pos += 1
        try expect(":")
        let token = try readToken(until: ";")
        guard isIntegerToken(token) else {
            throw PHPSerializedError(.unexpected(expected: Self.Words.anInteger), at: pos - token.count - 1)
        }
        let text = String(decoding: token, as: UTF8.self)
        if let n = Int(text) { return .integer(n) }
        return .number(Double(text) ?? 0)
    }

    /// `d:0.1;`, `d:1.0E+25;`, `d:-0;`, `d:INF;`, `d:NAN;` — the three that JSON cannot hold as words.
    private mutating func readDouble() throws(PHPSerializedError) -> StructuredValue {
        pos += 1
        try expect(":")
        let token = try readToken(until: ";")
        let text = String(decoding: token, as: UTF8.self)
        if text == "INF" || text == "-INF" || text == "NAN" { return .string(text) }
        guard
            token.first.map({ Self.isDigit($0) || $0 == UInt8(ascii: "-") || $0 == UInt8(ascii: "+") || $0 == UInt8(ascii: ".") }) == true,
            let d = Double(text), d.isFinite
        else { throw PHPSerializedError(.unexpected(expected: Self.Words.aNumber), at: pos - token.count - 1) }
        return .number(d)
    }

    /// `E:11:"Suit:Hearts";` — the case as PHP writes it in code, `Suit::Hearts`.
    private mutating func readEnumCase() throws(PHPSerializedError) -> StructuredValue {
        pos += 1
        try expect(":")
        let length = try readLength()
        try expect(":")
        try expect("\"")
        let name = try take(length)
        try expect("\"")
        try expect(";")
        return .string(String(decoding: name, as: UTF8.self).replacingOccurrences(of: ":", with: "::"))
    }

    /// `r:3;` (an object handle) or `R:3;` (a PHP reference): a copy of value 3.
    private mutating func readReference(at start: Int) throws(PHPSerializedError) -> StructuredValue {
        pos += 1
        try expect(":")
        let number = try readLength()
        try expect(";")
        guard number >= 1, number <= slots.count else { throw PHPSerializedError(.badReference(number), at: start) }
        guard let value = slots[number - 1].value else { return .string("*RECURSION*") }
        valueCount += slots[number - 1].size
        guard valueCount <= Self.maxValues else { throw PHPSerializedError(.tooLarge, at: start) }
        return value
    }

    // MARK: - Containers

    /// `a:2:{i:0;s:5:"Apple";i:1;s:6:"Orange";}` — a list when its keys are 0, 1, 2… in order.
    private mutating func readArray(depth: Int) throws(PHPSerializedError) -> StructuredValue {
        pos += 1
        try expect(":")
        let count = try readLength()
        try expect(":")
        try expect("{")
        var members = Members()
        for _ in 0..<count {
            let key = try readKey()
            members.set(key, try readValue(depth: depth + 1))
        }
        try expect("}")
        return members.isList ? .sequence(members.pairs.map(\.value)) : .mapping(members.pairs)
    }

    /// `O:5:"Point":3:{s:1:"x";i:1;s:4:"\0*\0y";i:2;s:8:"\0Point\0z";i:3;}` — `__class` first, then
    /// the properties under print_r's names for their visibility.
    private mutating func readObject(depth: Int) throws(PHPSerializedError) -> StructuredValue {
        pos += 1
        let className = try readClassName()
        try expect(":")
        let count = try readLength()
        try expect(":")
        try expect("{")
        var members = Members()
        for _ in 0..<count {
            let key = try readKey()
            members.set(MemberKey(text: Self.propertyName(key.text), isInteger: false), try readValue(depth: depth + 1))
        }
        try expect("}")
        return .mapping([StructuredPair(key: "__class", value: .string(className))] + members.pairs)
    }

    /// `C:6:"ArrayO":12:{x:i:0;a:0:{}}` — a class's own format (the Serializable interface), kept
    /// as its text: only the class can read it.
    private mutating func readCustomObject() throws(PHPSerializedError) -> StructuredValue {
        pos += 1
        let className = try readClassName()
        try expect(":")
        let length = try readLength()
        try expect(":")
        try expect("{")
        let payload = try take(length)
        try expect("}")
        return .mapping([
            StructuredPair(key: "__class", value: .string(className)),
            StructuredPair(key: "__serialized", value: .string(String(decoding: payload, as: UTF8.self))),
        ])
    }

    /// `:5:"Point"` after an `O` or a `C`.
    private mutating func readClassName() throws(PHPSerializedError) -> String {
        try expect(":")
        let length = try readLength()
        try expect(":")
        try expect("\"")
        let name = try take(length)
        try expect("\"")
        return String(decoding: name, as: UTF8.self)
    }

    /// An array key or property name: `i:3;`, `s:4:"name";` or `S:…`. Keys take no reference number.
    private mutating func readKey() throws(PHPSerializedError) -> MemberKey {
        switch try peek() {
        case UInt8(ascii: "i"):
            guard case .integer(let n) = try readInteger() else {
                throw PHPSerializedError(.unexpected(expected: Self.Words.anIntegerOrStringKey), at: pos)
            }
            return MemberKey(text: String(n), isInteger: true)
        case UInt8(ascii: "s"), UInt8(ascii: "S"):
            return MemberKey.normalised(String(decoding: try readStringBytes(), as: UTF8.self))
        default: throw PHPSerializedError(.unexpected(expected: Self.Words.anIntegerOrStringKey), at: pos)
        }
    }

    /// `\0*\0name` is protected, `\0Class\0name` private; print_r writes them `name:protected` and
    /// `name:Class:private`.
    static func propertyName(_ raw: String) -> String {
        guard raw.hasPrefix("\0") else { return raw }
        let parts = raw.dropFirst().split(separator: "\0", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return raw }
        return parts[0] == "*" ? "\(parts[1]):protected" : "\(parts[1]):\(parts[0]):private"
    }

    // MARK: - Strings

    /// The bytes of `s:N:"…";` (or the escaped `S:N:"…";`). A plain string whose N is wrong is read
    /// to its real end and recorded as a repair.
    private mutating func readStringBytes() throws(PHPSerializedError) -> ArraySlice<UInt8> {
        let start = pos
        let escaped = bytes[pos] == UInt8(ascii: "S")
        pos += 1
        try expect(":")
        let length = try readLength()
        try expect(":")
        try expect("\"")
        if escaped { return try readEscapedBody(length) }
        let body = pos
        if length <= bytes.count - body, closesString(at: body + length) {
            pos = body + length + 2
            return bytes[body..<body + length]
        }
        guard let end = repairedEnd(from: body) else {
            pos = min(body + length, bytes.count)
            throw PHPSerializedError(pos >= bytes.count ? .unexpectedEnd : .unexpected(expected: "\";"), at: pos)
        }
        repairs.append(PHPSerializedRepair(offset: start, declaredLength: length, actualLength: end - body))
        pos = end + 2
        return bytes[body..<end]
    }

    /// Whether `"` `;` sit at `i`.
    private func closesString(at i: Int) -> Bool {
        i + 1 < bytes.count && bytes[i] == UInt8(ascii: "\"") && bytes[i + 1] == UInt8(ascii: ";")
    }

    /// The first `";` after `from` that something serialized can follow: the end, a `}`, or the
    /// start of a value or key. Where the declared length lied, this is where the string ends.
    private func repairedEnd(from: Int) -> Int? {
        var i = from
        while i + 1 < bytes.count {
            if closesString(at: i), canFollowValue(at: i + 2) { return i }
            i += 1
        }
        return nil
    }

    private func canFollowValue(at j: Int) -> Bool {
        var k = j
        while k < bytes.count, Self.isSpace(bytes[k]) { k += 1 }
        if k == bytes.count { return true }
        if bytes[k] == UInt8(ascii: "}") { return true }
        guard k + 1 < bytes.count else { return false }
        if bytes[k] == UInt8(ascii: "N") { return bytes[k + 1] == UInt8(ascii: ";") }
        return Self.kindLetters.contains(bytes[k]) && bytes[k + 1] == UInt8(ascii: ":")
    }

    private static let kindLetters: Set<UInt8> = Set("bidsSaOCErR".utf8)

    /// `S:` strings write a byte as `\` and two hex digits; N counts the bytes they stand for.
    private mutating func readEscapedBody(_ length: Int) throws(PHPSerializedError) -> ArraySlice<UInt8> {
        var out: [UInt8] = []
        out.reserveCapacity(length)
        while out.count < length {
            let b = try next()
            guard b == UInt8(ascii: "\\") else { out.append(b); continue }
            let hex = try take(2)
            guard let byte = UInt8(String(decoding: hex, as: UTF8.self), radix: 16) else {
                throw PHPSerializedError(.unexpected(expected: Self.Words.twoHexDigits), at: pos - 2)
            }
            out.append(byte)
        }
        try expect("\"")
        try expect(";")
        return out[...]
    }

    /// A string as text, or, when asked, as the serialized value or JSON object or array it holds.
    private mutating func expandedIfAsked(_ raw: ArraySlice<UInt8>, depth: Int) throws(PHPSerializedError) -> StructuredValue {
        let text = String(decoding: raw, as: UTF8.self)
        guard expandingNested else { return .string(text) }
        let inner = Array(raw)
        if PHPSerialized.looksSerialized(inner) {
            var parser = PHPSerializedParser(bytes: inner, expandingNested: true, baseDepth: depth + 1)
            if let reading = try? parser.readDocument() {
                expanded += 1 + reading.expandedCount
                return reading.value
            }
        }
        let first = inner.first { !Self.isSpace($0) }
        if first == UInt8(ascii: "{") || first == UInt8(ascii: "["), let json = JSONStructure.value(of: text) {
            expanded += 1
            return json
        }
        return .string(text)
    }

    // MARK: - Bytes

    private mutating func skipSpace() { while pos < bytes.count, Self.isSpace(bytes[pos]) { pos += 1 } }

    private func peek() throws(PHPSerializedError) -> UInt8 {
        guard pos < bytes.count else { throw PHPSerializedError(.unexpectedEnd, at: pos) }
        return bytes[pos]
    }

    private mutating func next() throws(PHPSerializedError) -> UInt8 {
        let b = try peek()
        pos += 1
        return b
    }

    private mutating func expect(_ char: Unicode.Scalar) throws(PHPSerializedError) {
        let b = try peek()
        guard b == UInt8(char.value) else { throw PHPSerializedError(.unexpected(expected: String(char)), at: pos) }
        pos += 1
    }

    private mutating func take(_ count: Int) throws(PHPSerializedError) -> ArraySlice<UInt8> {
        guard count <= bytes.count - pos else { throw PHPSerializedError(.unexpectedEnd, at: bytes.count) }
        defer { pos += count }
        return bytes[pos..<pos + count]
    }

    /// A count or length: decimal digits, at most 18 of them.
    private mutating func readLength() throws(PHPSerializedError) -> Int {
        let start = pos
        var n = 0
        while pos < bytes.count, Self.isDigit(bytes[pos]), pos - start < 18 {
            n = n * 10 + Int(bytes[pos] - 0x30)
            pos += 1
        }
        guard pos > start else {
            if pos >= bytes.count { throw PHPSerializedError(.unexpectedEnd, at: pos) }
            throw PHPSerializedError(.unexpected(expected: Self.Words.aNumber), at: pos)
        }
        return n
    }

    /// The bytes up to `terminator`, which is consumed.
    private mutating func readToken(until terminator: Unicode.Scalar) throws(PHPSerializedError) -> ArraySlice<UInt8> {
        let start = pos
        while pos < bytes.count, bytes[pos] != UInt8(terminator.value), pos - start < 64 { pos += 1 }
        guard pos < bytes.count else { throw PHPSerializedError(.unexpectedEnd, at: pos) }
        guard bytes[pos] == UInt8(terminator.value) else { throw PHPSerializedError(.unexpected(expected: String(terminator)), at: pos) }
        pos += 1
        return bytes[start..<pos - 1]
    }

    private func isIntegerToken(_ token: ArraySlice<UInt8>) -> Bool {
        var digits = token[...]
        if let sign = digits.first, sign == UInt8(ascii: "-") || sign == UInt8(ascii: "+") { digits = digits.dropFirst() }
        return !digits.isEmpty && digits.allSatisfy(Self.isDigit)
    }

    /// The words an error names, localised once.
    private enum Words {
        static let aValue = String(localized: "a value", bundle: .module, comment: "PHP unserialize error: what may come here")
        static let anInteger = String(localized: "an integer", bundle: .module, comment: "PHP unserialize error: what may come here")
        static let aNumber = String(localized: "a number", bundle: .module, comment: "PHP unserialize error: what may come here")
        static let anIntegerOrStringKey = String(
            localized: "an integer or string key", bundle: .module, comment: "PHP unserialize error: what may come here")
        static let twoHexDigits = String(
            localized: "two hex digits", bundle: .module, comment: "PHP unserialize error: an S: string escape")
    }
}

/// An array key or property name: its text, and whether PHP holds it as an integer.
private struct MemberKey: Hashable {
    let text: String
    let isInteger: Bool

    /// A string key PHP stores as an integer: decimal digits with no leading zero, an optional
    /// minus (never `-0`), within Int's range.
    static func normalised(_ text: String) -> MemberKey {
        let digits = text.hasPrefix("-") ? text.dropFirst() : text[...]
        let canonical =
            !digits.isEmpty && digits.utf8.allSatisfy(PHPSerializedParser.isDigit) && (digits == "0" ? text == "0" : digits.first != "0")
            && Int(text) != nil
        return MemberKey(text: text, isInteger: canonical)
    }
}

/// Members in first-written order; a key written again replaces the value and keeps its place.
private struct Members {
    private(set) var pairs: [StructuredPair] = []
    private var keys: [MemberKey] = []
    private var index: [String: Int] = [:]

    mutating func set(_ key: MemberKey, _ value: StructuredValue) {
        if let i = index[key.text] {
            pairs[i] = StructuredPair(key: key.text, value: value)
            return
        }
        index[key.text] = pairs.count
        keys.append(key)
        pairs.append(StructuredPair(key: key.text, value: value))
    }

    /// Integer keys 0, 1, 2… in order: a list, as `array_is_list` says.
    var isList: Bool { keys.enumerated().allSatisfy { $0.element.isInteger && $0.element.text == String($0.offset) } }
}
