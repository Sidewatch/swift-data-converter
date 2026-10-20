//
//  DotEnv+Lookup.swift
//  DataConverter
//
//  Finding an entry again after the file changed, and matching a filter without exposing a
//  masked value.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

public extension DotEnv {
    /// `old` (one of `shown`) as `current` names it after the file changed: the same OCCURRENCE of its
    /// key — a file may repeat a key, and a line inserted above moves every line number — else the first
    /// entry with its key, else `old` itself. For applying an edit typed against the table as it was.
    static func entry(matching old: Entry, among shown: [Entry], in current: [Entry]) -> Entry {
        let occurrence = shown.filter { $0.key == old.key }.firstIndex { $0.line == old.line } ?? 0
        let candidates = current.filter { $0.key == old.key }
        return candidates[safe: occurrence] ?? candidates.first ?? old
    }

    /// Whether `entry` answers a filter `query`: its key matches, or its value does — the value only
    /// when `valueIsSearchable` (shown in clear, or revealed), so a search can never confirm what a
    /// masked value holds.
    static func matches(_ entry: Entry, query: String, caseSensitive: Bool, valueIsSearchable: Bool) -> Bool {
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        return entry.key.range(of: query, options: options) != nil
            || (valueIsSearchable && entry.value.range(of: query, options: options) != nil)
    }
}
