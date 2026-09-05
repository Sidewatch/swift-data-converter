# Swift Data Converter

A dependency-free data-format converter that routes everything through a JSON value hub — **input** JSON or CSV, **output** pretty JSON, YAML, TOML, or CSV. Pure Foundation, zero dependencies; includes a robust, quote-aware CSV tokenizer that is reusable on its own.

- Module `DataConverter` in `Sources/DataConverter`; tests in `Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.2, macOS 14+, no dependencies unless the README says so.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.

## Module map

- `Enums/` — ASCII: the delimiter bytes
- `Extensions/` — one extension per Foundation idiom: Data+UTF8, Int+ByteSize, Int+Grouped
- `Support/` — CSVTokenizer: the quote-aware byte scanner, one method per state and per step
- `Core/` — the engine: DataConverter, JSONFormatter

## Rules

@CONTRIBUTING.md
