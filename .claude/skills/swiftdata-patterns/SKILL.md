---
name: swiftdata-patterns
description: Use SwiftData correctly — schema versioning, migration, context and actor boundaries, and testable persistence behind repositories
---

# SwiftData Patterns

SwiftData is a persistence layer, not an architecture.
Keep it at the edge, behind types you own.

## Models

- `@Model final class` — SwiftData models are reference types by necessity
- `@Attribute(.unique)` for natural keys; **REMEMBER** it is incompatible with a CloudKit container
- `@Relationship(deleteRule:inverse:)` — always state the delete rule explicitly, never rely on the default
- **DENORMALISE deliberately**: a historical record (a receipt line, an audit row) copies the values it needs. A foreign key into a mutable table rewrites history when the parent is edited
- Store a computed bucketing value (a trading day, a period key) at write time rather than deriving it on every read
- Store a published or reconciled figure; **NEVER** recompute it on read, or a later arithmetic change retroactively edits the past

## Schema Versioning

- Ship the first release inside a `VersionedSchema`, not a bare model list — retrofitting one later is painful
- Every schema change after that gets a new `VersionedSchema` and a `MigrationStage` in a `SchemaMigrationPlan`
- Prefer lightweight migration; use a custom stage when data must be transformed, and test the transform
- **ALWAYS** test migration against a real store file captured from the previous version, not an empty one

## Contexts & Concurrency

- `ModelContext` and model objects are **not** `Sendable` — they do not cross actor boundaries
- `PersistentIdentifier` **is** sendable — pass identifiers between actors, then re-fetch
- Use `@ModelActor` for background work; do not hand a context to a `Task.detached`
- Group related writes and save once — a partial save is a corrupt state
- Consider disabling autosave for explicit control over when writes land

## Queries

- **PREFER** `FetchDescriptor` inside a repository over `@Query` in a view, except for the simplest read-only lists — `@Query` in a view makes the logic untestable
- Always set `fetchLimit` on anything that could grow unbounded
- `#Predicate` is compiled, not arbitrary Swift: it cannot call your own functions. Reshape the data or filter after fetch, and comment why
- Push sorting and filtering into the descriptor, not into Swift after loading everything

## Architecture

- Define repository **protocols** in your own module; the SwiftData implementation conforms
- View models depend on the protocol, never on `ModelContext`
- This is what makes the domain testable without a store

## Testing

- Use `ModelConfiguration(isStoredInMemoryOnly: true)` for fast tests
- **ALWAYS** round-trip test any type whose storage fidelity you are assuming — `Decimal`, `Date`, enums stored as raw values
- Test the delete rules: cascade actually cascading is not obvious

## General Principles

- Persistence is an edge concern; the domain should not know it exists
- A migration you have not run against real data is not a migration
- If a query is complex enough to be interesting, it belongs in a tested repository, not a view
