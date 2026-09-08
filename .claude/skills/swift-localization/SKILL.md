---
name: swift-localization
description: Localize iOS apps properly with String Catalogs and FormatStyle, separating UI language from domain-fixed formatting
---

# Swift Localization

Localization is a **structural decision made early**, not a translation pass at the end.
Retrofitting it means rewriting every layout that assumed English width.

## Strings

- **USE String Catalogs (`.xcstrings`)** — `.strings` and `.stringsdict` files are legacy
- Set the development language deliberately; it is the source of truth, not a default
- **NEVER** build a sentence by concatenation — use one localized string with interpolation, so translators see the whole sentence
- **NEVER** use `count == 1 ? "item" : "items"` — use the catalog's plural rules. Languages have between one and six plural forms; Indonesian has one, English two, and hardcoding either breaks the moment a third language is added
- Give strings a comment explaining context — translators cannot see the screen
- **DO NOT** localize log messages, identifiers, or debug output

## Formatting

- **USE `FormatStyle`** for every number, currency, date, duration, and list — never a hand-built string
- **DECIDE PER VALUE which locale applies**:
  - *UI language* follows the device locale
  - *Domain-fixed values* — a business's own currency, a receipt, an invoice, an export — use an **explicit locale** regardless of device
- A shop in one country with a phone set to another language must still see and print its own currency format
- **NEVER** put a locale-formatted number into a CSV, a filename, or an API payload — a decimal separator that flips between `.` and `,` silently corrupts data. Serialize unformatted, format only for display

## Layout

- **USE `leading`/`trailing`**, never `left`/`right`
- Expect text to change length by ±50%; German and Japanese fail in opposite directions
- **AVOID** fixed-width containers around localized text
- Test with the longest language at the largest Dynamic Type size — that is where it breaks

## Accessibility & Assets

- **LOCALIZE accessibility labels and usage strings** — they are user-facing copy
- Usage strings (`NSCameraUsageDescription` and friends) must be written for the actual user, in their language, and say why
- Localize images only when they contain text or culturally specific meaning

## Verification

- Add a debug language override so any language can be checked without changing device settings
- Screenshot every screen in every language at default and largest text size
- An untranslated string that falls back to the development language is a bug to fix, not an acceptable default

## General Principles

- Language is a user preference; currency and units are often a property of the data
- If a string is assembled in code, it cannot be translated
- The second language finds the bugs; the third proves they are fixed
