//
//  Int+ByteSize.swift
//  DataConverter
//
//  A byte count as B / KB / MB / GB, one decimal above bytes.
//
//  Created by David Sherlock on 7/19/26.
//

import Foundation

extension Int {
    /// Human-readable byte size (B / KB / MB / GB), e.g. `2048` → `"2.0 KB"`, `500` → `"500 B"`.
    /// Binary units (1024), one decimal above bytes.
    public var byteSizeLabel: String {
        let units = ["B", "KB", "MB", "GB"]
        var v = Double(self), i = 0
        while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
        return i == 0 ? "\(self) B" : String(format: "%.1f %@", v, units[i])
    }
}
