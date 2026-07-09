# Swift Data Converter

A dependency-free data-format converter that routes everything through a JSON value hub: **input** JSON or CSV, **output** pretty JSON, YAML, TOML, or CSV. Includes a robust, quote-aware CSV tokenizer.

## Features

- 🔄 **Convert** between JSON / CSV (in) and JSON / YAML / TOML / CSV (out)
- 🧾 **Quote-aware CSV** — `csvRecords` handles quoted commas, embedded newlines, and doubled-quote escapes; `parseCSV` maps headers → row objects
- 🟨 **YAML & TOML emitters** — readable output (emit-only; parsing them back would need a real library)
- ⚠️ **Friendly errors** — clear messages for unparseable input or shape mismatches (e.g. "TOML needs a top-level object")
- 🪶 **Zero dependencies** — Foundation only
- 🍎 **Cross-platform** — iOS, macOS, tvOS, watchOS, visionOS

## Requirements

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+ / visionOS 1.0+
- Swift 5.9+

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/arraypress/swift-data-converter.git", from: "1.0.0")
]
```

## Usage

```swift
import DataConverter

DataConverter.convert(#"[{"name":"Ada","age":36}]"#, from: "JSON", to: "CSV")
// "age,name\n36,Ada"

DataConverter.convert("name,age\nAda,36", from: "CSV", to: "JSON")
// pretty-printed JSON array of objects

// The CSV tokenizer is reusable on its own:
let rows = DataConverter.parseCSV("a,b\n\"x,y\",z")   // [["a": "x,y", "b": "z"]]
```

`from` / `to` accept `"JSON"`, `"CSV"`, `"YAML"`, `"TOML"`.

## License

MIT
