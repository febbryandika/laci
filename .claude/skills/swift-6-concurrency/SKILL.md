---
name: swift-6-concurrency
description: Write Swift 6 code that passes strict concurrency checking honestly, without escape hatches that hide data races
---

# Swift 6 Concurrency

We build in **Swift 6 language mode with complete strict concurrency**.
A concurrency warning is a real bug report from the compiler. Fix the isolation, never the diagnostic.

## The Prime Rule

- **NEVER** silence a concurrency error with `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency import`
- If one of these seems necessary, **STOP and explain why** before writing it
- The only legitimate use is wrapping a genuinely thread-safe C or Objective-C API, with a comment stating what makes it safe

## Isolation

- **PREFER** value types crossing concurrency boundaries — a `struct` of `Sendable` members is the easiest thing to reason about
- **PREFER** `actor` for mutable state shared across tasks
- Use `@MainActor` for UI and view models — but do **NOT** blanket-annotate types just to make errors disappear
- Mark types `Sendable` explicitly when they are public; conformance is not inferred across module boundaries
- `nonisolated` for pure computed properties and functions that touch no isolated state

## Actors

- **REMEMBER** actors are reentrant: state can change across every `await` inside an actor method
- Re-check invariants after each suspension point; do not assume what you read before `await` is still true
- Keep actor methods short — long methods with several `await`s are where reentrancy bugs live
- **AVOID** actors for things that are only ever touched from one place; `@MainActor` or plain isolation is simpler

## Tasks

- **PREFER** `Task { }` — it inherits actor context and priority
- **AVOID** `Task.detached` unless you specifically need to escape the current context, and say why in a comment
- **ALWAYS** handle cancellation: check `Task.isCancelled` or call `try Task.checkCancellation()` in loops
- Store long-lived tasks and cancel them in `deinit`
- **AVOID** unstructured tasks where `async let` or a `TaskGroup` expresses the same thing

## Bridging Callback APIs

- Wrap one-shot delegate callbacks with `withCheckedThrowingContinuation`
- **ALWAYS** resume a continuation exactly once on every path — a leaked continuation hangs forever, a double resume crashes
- Guard against double resume by nilling the stored continuation before resuming it
- Use `AsyncStream` / `AsyncThrowingStream` for callbacks that fire repeatedly
- Keep the bridging layer thin and isolate it in one type

## Global State

- Global and static `var` is a compile error in Swift 6 — that is correct
- **PREFER** `let` constants, actor-isolated state, or `@MainActor` statics
- **AVOID** singletons; pass dependencies explicitly

## Package Configuration

- Set `swiftLanguageMode(.v6)` in every `Package.swift`
- Keep strict concurrency on for test targets too — tests that opt out stop proving anything

## General Principles

- The compiler is describing a real race, not being pedantic
- If isolation is hard to express, the design is probably wrong — reconsider the boundary
- Concurrency is not performance; do not add it where synchronous code is correct
