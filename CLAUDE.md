# Swift Data Converter

A dependency-free data-format converter that routes everything through a JSON value hub — **input** JSON or CSV, **output** pretty JSON, YAML, TOML, or CSV. Pure Foundation, zero dependencies; includes a robust, quote-aware CSV tokenizer that is reusable on its own.

- Module `DataConverter` in `Sources/DataConverter`; tests in `Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.2, macOS 14+, no dependencies unless the README says so.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.

## Module map

- `Enums/` — ASCII: the delimiter bytes
- `Extensions/` — one extension per Foundation idiom: Data+UTF8, Int+ByteSize, Int+Grouped
- `Support/` — CSVTokenizer: the quote-aware byte scanner, one method per state and per step; CellOrder: how one grid cell orders against another (`compare`, `permutation(of:by:ascending:nullsFirst:)`); DotEnv: a `.env` file as entries (`parse`), the masking rule (`shouldMask(key:value:)`, `mask`) and `replacingValue(in:line:with:)` for an edited value; CSVEdit: one CSV field rewritten in place (`replacingField`, `fieldReplacement` with the old field's range, `encoded` quoting) over the tokenizer's `fieldRanges(in:)`; JSONEdit (a member's token ranges by path, the typed-replacement encoder), YAMLEdit / TOMLEdit / XMLEdit / PlistEdit (the scalar and key encoders for the grammar-read formats — their range finders are swift-code-highlighting's, next to the grammars), StructuredEdit (the shared path / kind / edit-site vocabulary and escaper); INIStructure, PropertiesStructure, StringsStructure (each: `value(of:)` as ordered typed structure, `site(in:path:)`, `replacement(in:path:key:with:)` for one key or value rewritten in place); PropertyListStructure (any plist Foundation reads — binary, XML, OpenStep — as structure, keys sorted; `isBinary`)
- `Models/` — StructuredValue / StructuredPair: the ordered, typed value model every tree reader in the family produces (YAML, TOML, XML and plists in swift-code-highlighting; INI, .properties, .strings and property lists here)
- `Core/` — the engine: DataConverter, JSONFormatter

## Rules

@CONTRIBUTING.md

- **Auditing? Read `AUDIT.md` first** — what the last full audit checked and fixed, and the known non-issues to skip; extend it, do not redo it.
