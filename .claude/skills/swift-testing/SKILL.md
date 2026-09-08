---
name: swift-testing
description: Write tests with the Swift Testing framework using @Test and #expect, and know the narrow cases where XCTest is still required
---

# Swift Testing

We use the **Swift Testing** framework (`import Testing`) for unit tests.
Tests exist to catch real defects, not to raise a coverage number.

## Framework Choice

- **PREFER** Swift Testing (`@Test`, `#expect`, `#require`) for all unit tests
- **XCTest is still required** for UI automation (`XCUITest`) and `measure`-based performance tests — use it there and nowhere else
- **AVOID** Quick, Nimble, and other third-party test frameworks

## Structure

- **PREFER** `struct` suites — a fresh instance per test means no shared mutable state
- Use `@Suite` to group, `init`/`deinit` for setup and teardown
- Name tests as a sentence describing the guarantee: `@Test("Change is never negative")`
- One behavior per test; a test asserting five unrelated things tells you nothing when it fails

## Assertions

- `#expect` for checks that should continue on failure
- `#require` for preconditions where continuing is meaningless (`let value = try #require(optional)`)
- `#expect(throws: SomeError.self)` for error paths
- **ALWAYS** include context in the failure message when the input is generated or non-obvious
- **AVOID** asserting on formatted strings when you can assert on the value

## Parameterized & Property Tests

- **PREFER** `@Test(arguments:)` over hand-copied near-identical tests
- For property-based testing, a seeded `RandomNumberGenerator` plus `@Test(arguments: 0..<N)` is enough — **AVOID** pulling in a property-testing dependency
- **ALWAYS** print the seed in the failure message so a counterexample is reproducible

## Async & Concurrency

- Mark tests `async` and `await` directly; **NEVER** use `sleep` or a fixed delay
- Use `confirmation` to assert a callback fired the expected number of times
- Give async tests a timeout rather than letting CI hang

## What to Test

- **TEST** pure domain logic exhaustively — it is fast, deterministic, and where the expensive bugs are
- **TEST** boundaries: empty, one, many, the rounding edge, the timezone cutover
- **DO NOT** test the framework, the compiler, or trivial property accessors
- **DO NOT** write a test that mirrors the implementation line for line — it locks in the bug
- When something genuinely cannot be tested (a system framework object that cannot be constructed), **say so in the README** rather than faking coverage

## Hygiene

- Tests must not touch the network, the clock, or the real filesystem unless that is the subject
- Inject dates and randomness; a test that fails at midnight is a broken test
- **PREFER** `withKnownIssue` over disabling or deleting a failing test
- Every bug fix gets a regression test written **before** the fix

## General Principles

- A test suite that is slow will not be run
- A flaky test is worse than no test
- If a unit is hard to test, extract the logic until it is easy
