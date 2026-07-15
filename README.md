# Swift Data Converter

A dependency-free data-format converter that routes everything through a JSON value hub — **input** JSON or CSV, **output** pretty JSON, YAML, TOML, or CSV. Pure Foundation, zero dependencies; includes a robust, quote-aware CSV tokenizer that is reusable on its own.

## Features

- 🔄 **One-call conversion** — `DataConverter.convert(_:from:to:)` takes JSON or CSV in and emits pretty-printed sorted-key JSON, YAML, TOML, or CSV
- 🧾 **Quote-aware CSV tokenizer** — `DataConverter.csvRecords(_:)` handles quoted commas, multiline quoted fields, doubled-quote escapes, and LF / CRLF / bare-CR row endings
- 🗂 **Header-mapped CSV parsing** — `DataConverter.parseCSV(_:)` maps the header row onto row dictionaries, de-duplicating repeated headers (`name`, `name_2`, …) and padding short rows
- 🟨 **YAML & TOML emitters** — block-style YAML with minimal quoting; TOML with `[table]` / `[[array-of-tables]]` sections and bare keys where legal (both emit-only; parsing them back would need a real library)
- ⚠️ **Friendly errors, no throws** — unparseable input or shape mismatches come back as `"⚠︎ …"` messages (e.g. "TOML needs a top-level object"), so a converter UI can show the result verbatim
- 🪶 **Zero dependencies** — Foundation only
- 🍎 **Cross-platform** — iOS, macOS, tvOS, watchOS, visionOS

## Requirements

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+ / visionOS 1.0+
- Swift 5.9+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/arraypress/swift-data-converter.git", from: "1.0.0")
]
```

## Usage

```swift
import DataConverter

// JSON → CSV (header is the union of keys; nested values become compact JSON cells).
DataConverter.convert(#"[{"name":"Ada","age":36}]"#, from: "JSON", to: "CSV")
// "age,name\n36,Ada"

// CSV → pretty JSON (every cell is a string; repeated headers become name, name_2, …).
DataConverter.convert("name,age\nAda,36", from: "CSV", to: "JSON")

// JSON → YAML / TOML (emit-only).
DataConverter.convert(#"{"server":{"host":"x","ports":[80,443]}}"#, from: "JSON", to: "YAML")
DataConverter.convert(#"{"server":{"host":"x","ports":[80,443]}}"#, from: "JSON", to: "TOML")

// The CSV layer is reusable on its own.
let rows = DataConverter.parseCSV("a,b\n\"x,y\",z")   // [["a": "x,y", "b": "z"]]
let records = DataConverter.csvRecords("a,b\n\"multi\nline\",z")   // raw fields, header included
```

`from` accepts `"CSV"` (anything else parses as JSON); `to` accepts `"YAML"`, `"TOML"`, `"CSV"` (anything else emits pretty JSON).

## Notes

- `convert` never throws — errors are returned as `"⚠︎"`-prefixed strings.
- CSV output requires a JSON **array of objects**; TOML output requires a **top-level object**.
- YAML and TOML are output formats only; they are not accepted as `from` values.

## License

MIT
