---
name: xcode-project-hygiene
description: Never hand-edit or regenerate the Xcode project file; use synchronized folders, xcconfig files, and hand project changes back to the human
---

# Xcode Project Hygiene

`project.pbxproj` is a generated plist of UUID cross-references.
Editing it by hand produces a project that opens broken, and the failure is slow to diagnose.

## The Prime Rule

- **NEVER** create, regenerate, reformat, or hand-edit `*.xcodeproj/project.pbxproj`
- **NEVER** create an `.xcodeproj` or `.xcworkspace` from scratch
- If a task needs a project-level change, **STOP and give the human the exact Xcode GUI steps** instead of doing it
- This applies to adding targets, linking packages, adding build phases, changing signing, and adding capabilities

## Adding Files

- Xcode 16 and later use **synchronized folders** (blue folder icon): a `.swift` file written into a synchronized directory is picked up automatically with no project edit
- So: create real directories and write files into them normally
- If the project uses legacy yellow groups, say so and ask the human to convert the folder or add the file — do not edit the project file to compensate

## Build Settings

- **PUT BUILD SETTINGS IN `.xcconfig`** files, never in the project file
- One shared config for project-wide settings, per-target configs only when they genuinely differ
- `.xcconfig` is plain text and safe to edit; the settings UI is not
- If a setting must be set in the UI (signing, capabilities), hand it back to the human

## Packages

- `Package.swift` is plain text — **edit it freely**
- Adding a local package to the app target is a project change: write the `Package.swift`, then give the human the GUI steps to link it
- Prefer local packages over app-target code for anything worth testing without a simulator

## Schemes

- Shared schemes live in `xcshareddata/xcschemes/` and **are committed** — CI needs them
- `xcuserdata/` is per-developer and **is gitignored**
- If CI cannot find a scheme, the scheme is not shared — tell the human to tick "Shared" rather than editing XML

## Command Line

- Build and test with `xcodebuild -scheme <name> -destination 'platform=iOS Simulator,name=<device>'`
- Use `xcrun simctl` to manage simulators
- Run `swift build` / `swift test` inside a package directory — it is far faster than the app target and needs no simulator
- **AVOID** reflexive `clean` and deleting DerivedData; fix the actual problem

## Gitignore

- Ignore `xcuserdata/`, `DerivedData/`, `build/`, `.swiftpm/`, `*.xcuserstate`, `Packages/*/.build/`
- Never commit `.mobileprovision`, `.p12`, or anything from `fastlane/report*`

## General Principles

- The project file is generated state; treat it as read-only
- A change you cannot make safely is a change to hand back, not to attempt
- Ten minutes of the human's time in the GUI beats an hour debugging a corrupted project
