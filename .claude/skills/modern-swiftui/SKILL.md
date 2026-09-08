---
name: modern-swiftui
description: Build clean, modern SwiftUI views using @Observable and current APIs, avoiding legacy Combine patterns and common lifecycle pitfalls
---

# Modern SwiftUI

We use **current SwiftUI (iOS 17+ Observation, iOS 18 APIs)**.
Views are cheap value types that describe state. Logic lives elsewhere.

## Observation & State

- **PREFER** the `@Observable` macro for models and view models
- **AVOID** `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject` — legacy, and they over-invalidate
- With `@Observable`:
  - `@State` for an instance the view **owns**
  - a plain `let` property for one **passed in**
  - `@Environment` for one injected from above
  - `@Bindable` when you need two-way bindings into it
- **AVOID** Combine in new code; use `async`/`await` and `AsyncSequence`

## State Discipline

- **AVOID** unnecessary `@State` — derive values during `body` evaluation instead
- **DO NOT** mirror a model's value in view state
- Localize state to the smallest view that needs it
- Keep `body` pure: no side effects, no I/O, no `Task` kicked off during evaluation

## Lifecycle

- **PREFER** `.task { }` over `.onAppear` for async work — it cancels automatically when the view goes away
- **PREFER** `.task(id:)` to re-run work when a value changes
- **BEWARE** `onAppear` in `TabView` and `NavigationStack`: it can fire while the view is still off-screen, and it does not pair reliably with a matching disappear
- When something genuinely needs UIKit lifecycle (a camera preview, a text-input responder), use `UIViewControllerRepresentable` and say why in a comment

## Views & Composition

- **PREFER** small named subviews over long `body` methods and computed-property soup — real subviews give SwiftUI finer-grained invalidation
- **AVOID** `AnyView`; use `@ViewBuilder`, generics, or a `switch` returning concrete branches
- **PREFER** composition over configuration; avoid views with a dozen boolean parameters
- Keep view files free of business logic — a view that calculates money is a bug

## Navigation & Presentation

- **USE** `NavigationStack` with an explicit `path` for programmatic navigation; `NavigationView` is deprecated
- **USE** `NavigationSplitView` for iPad multi-column layouts
- **PREFER** `.sheet(item:)` over a `Bool` plus a parallel optional — one source of truth
- Model navigation state as an enum, not a pile of booleans

## Lists & Identity

- **ALWAYS** give `ForEach` stable identity; index-based identity breaks animations and selection
- **PREFER** `List` over `ScrollView` + `LazyVStack` when you need selection, swipe actions, or system row behavior
- Give lists real empty states — never an empty screen

## Performance

- **AVOID** premature `Equatable` conformance and `.equatable()`
- Measure before optimizing; most SwiftUI slowness is over-broad state invalidation, not rendering
- Keep expensive work out of `body` — compute it in the model

## General Principles

- Describe what the UI *is* for a given state, never how to mutate it into place
- If a view is hard to preview in isolation, its dependencies are wrong
- Prefer the platform's own controls and behaviors over recreating them
