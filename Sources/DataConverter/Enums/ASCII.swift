//
//  ASCII.swift
//  DataConverter
//
//  The bytes the CSV grammar is made of.
//
//  Created by David Sherlock on 9/5/26.
//

/// The bytes the CSV grammar is made of. Every delimiter is a single ASCII byte, and UTF-8
/// continuation bytes are all ≥ 0x80, so a byte scanner passes multi-byte glyphs through untouched.
enum ASCII {
    static let quote: UInt8 = 0x22
    static let comma: UInt8 = 0x2C
    static let cr: UInt8 = 0x0D
    static let lf: UInt8 = 0x0A
}
