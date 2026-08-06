import XCTest
@testable import DataConverter

/// Randomised checks on ``JSONFormatter``.
///
/// The hand-written tests pin cases someone thought of. These pin the invariants themselves
/// against a few thousand generated documents, which is how the awkward shapes — an empty object
/// as the last element, a string full of structural characters, nesting deeper than anyone would
/// write by hand — get covered without having to imagine each one.
///
/// Seeded deliberately: a formatter that fails once in a thousand runs and passes on re-run is
/// worse than one that fails every time, because CI teaches you to ignore it. Same corpus every
/// run, and a failure reproduces from the printed input.
final class JSONFormatterPropertyTests: XCTestCase {

    /// The invariant that matters most, and the tightest one available: minifying both sides
    /// strips every byte the formatter is allowed to touch, so what remains is the token stream.
    /// If those are equal, formatting changed whitespace and provably nothing else — no reordered
    /// key, no rewritten number, no dropped element. Comparing parsed values is weaker: it would
    /// pass even if keys came back alphabetised.
    func testFormattingOnlyEverChangesWhitespace() {
        var rng = SeededRNG(seed: 0x5EED)
        for i in 0..<2000 {
            let input = randomJSON(&rng)
            guard let formatted = JSONFormatter.format(input) else {
                XCTFail("refused generated-valid input #\(i): \(input)"); continue
            }
            XCTAssertEqual(JSONFormatter.minify(formatted), JSONFormatter.minify(input),
                           "token stream changed for #\(i): \(input)\n→\n\(formatted)")
        }
    }

    func testFormattingIsAlwaysIdempotent() {
        var rng = SeededRNG(seed: 0xF0F0)
        for _ in 0..<1000 {
            let once = JSONFormatter.format(randomJSON(&rng))!
            XCTAssertEqual(JSONFormatter.format(once), once, "not idempotent:\n\(once)")
        }
    }

    /// Every closing brace must sit at the same indent as the line that opened its container.
    /// Depth bookkeeping is the part most likely to drift, and it drifts silently — the output
    /// still parses, it just stops lining up.
    func testIndentationIsAlwaysBalanced() {
        var rng = SeededRNG(seed: 0xBA1A)
        for _ in 0..<1000 {
            let out = JSONFormatter.format(randomJSON(&rng))!
            var depth = 0
            for line in out.split(separator: "\n", omittingEmptySubsequences: false) {
                let indent = line.prefix { $0 == " " }.count
                let trimmed = line.drop { $0 == " " }
                // A line that closes a container is written at its OPENER's level, one less
                // than its contents; every other line sits at the current level.
                let expected = trimmed.first.map { "}]".contains($0) } == true ? depth - 1 : depth
                XCTAssertEqual(indent, expected * 2, "misaligned line '\(line)' in:\n\(out)")
                depth += trimmed.filter { "{[".contains($0) }.count
                depth -= trimmed.filter { "}]".contains($0) }.count
            }
            XCTAssertEqual(depth, 0, "unbalanced:\n\(out)")
        }
    }

    /// Whatever the generator produced, `JSONSerialization` must still read the same value back.
    func testFormattedOutputAlwaysReparsesToTheSameValue() {
        var rng = SeededRNG(seed: 0xC0DE)
        for _ in 0..<1000 {
            let input = randomJSON(&rng)
            let out = JSONFormatter.format(input)!
            let before = try! JSONSerialization.jsonObject(with: Data(input.utf8), options: [.fragmentsAllowed])
            let after  = try! JSONSerialization.jsonObject(with: Data(out.utf8),   options: [.fragmentsAllowed])
            XCTAssertTrue(NSDictionary(dictionary: ["v": before]).isEqual(to: ["v": after]),
                          "value changed:\n\(input)\n→\n\(out)")
        }
    }

    // MARK: - Generation

    /// Deterministic PRNG — `SystemRandomNumberGenerator` would make failures unreproducible.
    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
        mutating func next() -> UInt64 {          // xorshift64*
            state ^= state >> 12; state ^= state << 25; state ^= state >> 27
            return state &* 2685821657736338717
        }
    }

    /// A random valid JSON document. The leaf pool is chosen to include exactly the things a
    /// naive formatter breaks on: literals that change under a `Double` round-trip, and strings
    /// containing braces, quotes, colons and escapes.
    private func randomJSON(_ rng: inout SeededRNG, depth: Int = 0) -> String {
        let leaves = [
            "1", "0", "-1", "1.0", "1e3", "-0.0", "9007199254740993", "0.30000000000000004",
            "true", "false", "null",
            #""""#, #""plain""#, #""{\"nested\": [1,2]}""#, #""a:b,c""#, #""tab\there""#,
            #""quote\"inside""#, #""back\\slash""#, #""🎛️ unicode café""#,
        ]
        // Past depth 4, always emit a leaf: unbounded recursion would generate megabyte
        // documents and turn a fast property test into a timeout.
        if depth >= 4 || Int.random(in: 0..<10, using: &rng) < 4 {
            return leaves[Int.random(in: 0..<leaves.count, using: &rng)]
        }
        let count = Int.random(in: 0..<4, using: &rng)     // 0 exercises the empty-container path
        if Bool.random(using: &rng) {
            let items = (0..<count).map { _ in randomJSON(&rng, depth: depth + 1) }
            return "[" + items.joined(separator: ",") + "]"
        } else {
            let pairs = (0..<count).map { i in
                "\"k\(i)\":" + randomJSON(&rng, depth: depth + 1)
            }
            return "{" + pairs.joined(separator: ",") + "}"
        }
    }
}
