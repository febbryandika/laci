---
name: apple-frameworks-first
description: Prefer Apple's own frameworks over third-party dependencies, and treat every added package as a decision that needs justifying
---

# Apple Frameworks First

We build on **Apple's frameworks by default**.
Every dependency is code we did not write, cannot fix quickly, and must carry through every OS release.

## The Rule

- **DO NOT add any dependency without asking first** — state what it does, what it replaces, and why the platform cannot
- **PREFER** a hundred lines we own over a package we do not
- If a dependency is genuinely warranted: prefer Swift Package Manager, pin an **exact version**, prefer small and single-purpose, and confirm it builds in Swift 6 language mode

## What the Platform Already Does

| Reach for | Not |
|---|---|
| `URLSession` with `async`/`await` | Alamofire, Moya |
| `Codable` | SwiftyJSON, ObjectMapper |
| SwiftUI layout | SnapKit, PureLayout |
| `async`/`await`, `AsyncSequence` | RxSwift, PromiseKit, Combine for new code |
| Swift Testing | Quick, Nimble |
| `os.Logger` and `OSLogStore` | CocoaLumberjack, print-based logging |
| `FormatStyle` | hand-rolled formatters, third-party formatting |
| Keychain (behind a thin local wrapper) | third-party keychain packages |
| `UserDefaults`, SwiftData, or a file | a third-party cache or store |
| `CryptoKit` | third-party crypto |
| `Observation` | third-party state containers |

## Foundation Worth Knowing

- `FormatStyle` for currency, dates, numbers, lists, and measurements
- `Duration` and `Clock` for time intervals; `Date` only for points in time
- `Measurement` and `Unit` for physical quantities
- `Calendar` for every date computation — **NEVER** arithmetic on raw seconds
- `URLComponents` for building URLs; **NEVER** string concatenation
- `FileManager` plus `FileWrapper` / `FileDocument` for document I/O

## Cost of a Dependency

Before adding one, account for all of it:

- Supply-chain risk — it runs with the app's full privileges
- Swift 6 and annual OS migration work, on their schedule not ours
- App Store review surface, privacy manifest obligations, and binary size
- A reviewer reading the repo sees what we chose not to build ourselves

## Fallbacks

- Check availability with `#available` for newer APIs and provide a real fallback, not a crash
- When a platform API is genuinely missing something, write the thin piece ourselves and comment why

## General Principles

- The platform is the framework; a library is a bet on someone else's maintenance
- Fewer dependencies is a smaller attack surface and a shorter upgrade path
- If a package saves ten lines, it is not worth it
