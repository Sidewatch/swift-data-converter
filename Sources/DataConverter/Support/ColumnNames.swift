//
//  ColumnNames.swift
//  DataConverter
//
//  Column names made distinct, for the keys of a JSON object.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Column names made distinct, as the keys of a JSON object must be: a repeated name becomes `name_2`, `name_3`…, in
/// order, skipping any suffix another column already has (`id`, `id_2`, `id` gives `id`, `id_2`, `id_3`).
public enum ColumnNames {
    /// `names` with every repeat renamed; a name seen once is kept as it is.
    public static func unique(_ names: [String]) -> [String] {
        var used = Set(names)
        var seen = Set<String>()
        var next: [String: Int] = [:]
        return names.map { name in
            guard seen.contains(name) else {
                seen.insert(name)
                return name
            }
            var n = next[name] ?? 2
            while used.contains("\(name)_\(n)") { n += 1 }
            next[name] = n + 1
            used.insert("\(name)_\(n)")
            return "\(name)_\(n)"
        }
    }
}
