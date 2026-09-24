# Swift Data Converter

A dependency-free data-format converter that routes everything through a JSON value hub — **input** JSON or CSV, **output** pretty JSON, YAML, TOML, or CSV. Pure Foundation, zero dependencies; includes a robust, quote-aware CSV tokenizer that is reusable on its own.

## Features

- 🔄 **One-call conversion** — `DataConverter.convert(_:from:to:)` takes JSON or CSV in and emits pretty-printed sorted-key JSON, YAML, TOML, or CSV
- 🧾 **Quote-aware CSV tokenizer** — `DataConverter.csvRecords(_:)` handles quoted commas, multiline quoted fields, doubled-quote escapes, and LF / CRLF / bare-CR row endings
- 🗂 **Header-mapped CSV parsing** — `DataConverter.parseCSV(_:)` maps the header row onto row dictionaries, de-duplicating repeated headers (`name`, `name_2`, …) and padding short rows
- 🟨 **YAML & TOML emitters** — block-style YAML with minimal quoting; TOML with `[table]` / `[[array-of-tables]]` sections and bare keys where legal (both emit-only; parsing them back would need a real library)
- 🔢 **One cell-ordering rule for every grid** — `CellOrder.compare(_:_:nullsFirst:)` orders two cell texts numerically when both are numbers ("9" before "10", scientific and negative values right) and Finder-style otherwise, with SQL `NULL` first on request; `CellOrder.permutation(of:by:ascending:)` sorts rows by a column stably and hands back the row order so a parallel array (rowids) can follow
- 🔐 **dotenv** — `DotEnv.parse(_:)` reads a `.env` file as `KEY=value` entries the way the loaders do (`export` dropped, double quotes with escapes and over lines, single quotes literal, an unquoted value cut at ` #`); `DotEnv.shouldMask(key:value:)` names what a screen should bullet out until asked — secret words in the key, credentials in a URL; `DotEnv.replacingValue(in:line:with:)` rewrites one entry's value in place, keeping `export`, the spacing, the quoting and a trailing comment (what an edited cell writes back)
- ✏️ **JSON and YAML edits** — `JSONEdit.site(in:path:)` scans a JSON file once and answers the raw ranges of the member at a path (its value, and its key in an object) so one token can be replaced and nothing else touched; `JSONEdit.encodedValue(_:kind:)` and `YAMLEdit.encodedScalar(_:kind:)` write a typed replacement that keeps its kind (a string that looks like a number is quoted; YAML quotes what it would misread); `StructuredEdit` is the path and kind vocabulary and the one double-quoted escaper they share. Finding a YAML member's range needs the grammar and lives in swift-code-highlighting's `YAMLStructure.site(in:path:)`
- ✏️ **CSV cells edited in place** — `CSVEdit.replacingField(in:record:column:with:)` rewrites one field of a CSV file and nothing else (line endings, quoting and ragged rows kept; the new value quoted only when CSV needs it), and `CSVEdit.fieldReplacement(in:record:column:with:)` hands back the old field's range and the replacement so a text view can apply it as one undoable edit; the tokenizer's `fieldRanges(in:)` is what finds the field
- ⚠️ **Friendly errors, no throws** — unparseable input or shape mismatches come back as `"⚠︎ …"` messages (e.g. "TOML needs a top-level object"), so a converter UI can show the result verbatim
- 🪶 **Zero dependencies** — Foundation only
- 🍎 **Cross-platform** — iOS, macOS, tvOS, watchOS, visionOS

## Requirements

- macOS 14+ (Foundation only; other Apple platforms at SwiftPM's default minimums)
- Swift 6.2+ (Swift 6 language mode)

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Sidewatch/swift-data-converter.git", from: "0.1.0")
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

// One ordering rule for every grid: numbers as numbers, names as Finder sorts them, ties stable.
let rows = [["b", "10"], ["a", "9"], ["c", "9"]]
CellOrder.permutation(of: rows, by: 1, ascending: true)          // [1, 2, 0]
CellOrder.compare("NULL", "-5", nullsFirst: true)              // .orderedAscending

// A .env file as entries, and which to show as bullets.
let env = DotEnv.parse("export API_KEY=abc # prod\nPORT=3000\n")
env.map { ($0.key, DotEnv.shouldMask(key: $0.key, value: $0.value) ? DotEnv.mask : $0.value) }   // [("API_KEY", "••••••••"), ("PORT", "3000")]
```

`from` accepts `"CSV"` (anything else parses as JSON); `to` accepts `"YAML"`, `"TOML"`, `"CSV"` (anything else emits pretty JSON).

## Notes

- `convert` never throws — errors are returned as `"⚠︎"`-prefixed strings.
- CSV output requires a JSON **array of objects**; TOML output requires a **top-level object**.
- YAML and TOML are output formats only; they are not accepted as `from` values.

## For agents

Read `CONTRIBUTING.md` first: the folder layout and the PR rules. `swift test` is the whole
check, and a new test must fail before the change it covers. `CLAUDE.md` / `AGENTS.md` carry a
module map.

## License

MIT
