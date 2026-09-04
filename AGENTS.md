# Swift Data Converter

A dependency-free data-format converter that routes everything through a JSON value hub — **input** JSON or CSV, **output** pretty JSON, YAML, TOML, or CSV. Pure Foundation, zero dependencies; includes a robust, quote-aware CSV tokenizer that is reusable on its own.

- Module `DataConverter` in `Sources/DataConverter`; tests in `Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.2, macOS 14+, no dependencies unless the README says so.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.

## Module map

- `Core/` — the engine: DataConverter, JSONFormatter

## Rules

Read `CONTRIBUTING.md` before changing anything: it is the layout and PR rulebook for this package.
