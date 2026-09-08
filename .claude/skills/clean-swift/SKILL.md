---
name: clean-swift
description: Write clean, safe Swift that uses the type system to make illegal states unrepresentable and avoids force unwrapping and stringly-typed code
---

# Clean Swift

We use **Swift's type system as a correctness tool**, not as ceremony.
If the compiler can reject a bad state, it should.

## Types

- **PREFER** `struct` and `enum`; reach for `class` only when you need reference identity or Objective-C interop
- Mark classes `final` unless designed for subclassing
- **PREFER** value semantics for domain models
- **MAKE ILLEGAL STATES UNREPRESENTABLE**: an `enum` with associated values beats two optional properties where only one may be set
- **AVOID** stringly-typed code — use enums, and store a raw value only at the persistence boundary

## Optionals & Safety

- **NEVER** use `!` force unwrap, `try!`, or `as!` in shipped code
- **PREFER** `guard let` for early return, `if let` for narrow scopes
- `precondition` is acceptable for genuine programmer errors with a message explaining the invariant
- Handle `nil` explicitly; do not paper over it with a default that hides the case

## Errors

- **PREFER** `throws` over returning an optional to signal failure
- Use typed throws (`throws(SomeError)`) where the error set is genuinely closed
- Define domain error enums; **AVOID** throwing `NSError` or bare strings
- **DO NOT** swallow errors with `try?` unless the failure is genuinely uninteresting, and say so in a comment
- A function that cannot fail should not be marked `throws`

## Functions & APIs

- **PREFER** explicit return types on public API
- Follow the Swift API Design Guidelines: clarity at the point of use over brevity
- Keep argument lists short; group related parameters into a type
- **AVOID** boolean parameters — an enum reads better at the call site

## Access Control & Structure

- `internal` by default; `public` is a deliberate decision in a package
- Use extensions to organize by concern, not to scatter a type across ten files
- **AVOID** singletons and global mutable state; inject dependencies

## Protocols & Generics

- **PREFER** protocols for dependency boundaries you actually swap (repositories, transports)
- **AVOID** a protocol with exactly one conformer and no test double behind it
- **PREFER** generic constraints over class inheritance
- Use `some` and `any` deliberately — `any` where you need existential storage, `some` otherwise

## Numbers & Money

- **NEVER** use `Double` or `Float` for money — use `Decimal`
- Be explicit about rounding; never let it happen implicitly at a display boundary

## General Principles

- Write for the reader, not the compiler
- Prefer explicitness over cleverness
- If a type is hard to name, the boundary is probably wrong
