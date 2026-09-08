---
name: ios-accessibility
description: Build iOS interfaces that work with Dynamic Type, VoiceOver, and the system accessibility settings — as a baseline, not a later pass
---

# iOS Accessibility

Accessibility is a **baseline requirement**, not an enhancement.
Most of it is free if the interface is built with system primitives from the start.

## Dynamic Type

- **ALWAYS** use semantic text styles (`.body`, `.headline`, `.caption`) — **NEVER** a fixed point size
- Use `@ScaledMetric` for spacing, icon sizes, and any dimension that should grow with text
- **TEST AT AX5** (`accessibilityExtraExtraExtraLarge`), not just the default size
- Multi-column and side-by-side layouts break first — collapse them at large sizes and assert the transition in a UI test
- **AVOID** fixed-height containers around text; let them grow
- `lineLimit` with truncation on a critical value is a bug, not a layout choice

## Hit Targets & Input

- **MINIMUM 44×44pt** for anything tappable; larger for controls used at speed
- Make the whole row tappable, not just the label
- **ALWAYS** support the hardware keyboard on iPad: `.keyboardShortcut` on real buttons so shortcuts appear in the ⌘-hold overlay
- **AVOID** gesture-only actions with no visible equivalent

## VoiceOver

- Give every interactive control an accessible name — a label, or `.accessibilityLabel`
- Use `.accessibilityValue` for the current value, `.accessibilityHint` sparingly for non-obvious actions
- **COMBINE** related elements with `.accessibilityElement(children: .combine)` so a row reads as one thing
- **HIDE** decorative elements with `.accessibilityHidden(true)`
- **FORMAT NUMBERS FOR SPEECH**: pass a `FormatStyle`-produced string as the accessibility label so an amount is announced as an amount, not spelled digit by digit
- Announce state changes that happen without user action

## System Settings

- **RESPECT** `accessibilityReduceMotion` — drop or replace animations, do not just shorten them
- **RESPECT** `accessibilityReduceTransparency` and `accessibilityDifferentiateWithoutColor`
- Support Dark Mode and Increase Contrast; use semantic colors from the asset catalog

## Color & Feedback

- **MINIMUM 4.5:1** contrast for text
- **NEVER** rely on color alone to carry meaning — pair it with a shape, an icon, or text
- Feedback that matters when the user is not looking at the screen should be haptic **and** audible, not one or the other

## Verification

- Run the Accessibility Inspector audit on every screen before calling a phase done
- Write at least one XCUITest that launches at AX5 and asserts the primary action is still hittable
- Turn VoiceOver on and use the app for one real task — the audit tool does not catch bad reading order

## General Principles

- Native controls are accessible by default; recreating them from scratch throws that away
- If it only works by looking at it, it does not work
- Accessibility labels are user-facing copy — localize them
