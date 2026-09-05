//
//  Int+Grouped.swift
//  DataConverter
//
//  A count with thousands separators: the number a person can read at a glance.
//
//  Created by David Sherlock on 8/1/26.
//

import Foundation

extension Int {
    /// The number with locale-aware thousands separators — `174950` → `174,950`.
    ///
    /// Every user-facing count should go through this. Above four figures a bare integer
    /// is a smear you have to count digits in, and the places these appear — "174950 files
    /// · 4848 folders", "100 of 10068 files" — are precisely the ones whose whole job is
    /// conveying scale at a glance.
    public var grouped: String {
        Self.groupingFormatter.string(from: NSNumber(value: self)) ?? String(self)
    }

    private static let groupingFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()
}
