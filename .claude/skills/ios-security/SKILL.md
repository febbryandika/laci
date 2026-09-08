---
name: ios-security
description: Enforce iOS security and privacy — Keychain, file protection, privacy manifests, and never leaking sensitive data through logs or storage
---

# iOS Security & Privacy

Security and privacy are **core requirements**, not a pre-submission checklist.
Assume the device can be lost, the backup can be read, and the logs will be shared.

## Secrets

- **NEVER** store credentials, tokens, or PINs in `UserDefaults`, a plist, or a source file
- **USE Keychain** for secrets, with the narrowest `kSecAttrAccessible` that still works — prefer `...ThisDeviceOnly` variants unless the value must migrate to a new device
- **NEVER** commit an API key, certificate, or provisioning profile; CI secrets live in the CI secret store
- A key compiled into the binary is a public key — treat it as extractable
- Store a PIN as a salted hash, never reversibly

## Data at Rest

- **CHOOSE** a file protection class deliberately (`.complete`, `.completeUntilFirstUserAuthentication`, `.completeUnlessOpen`, `.none`) and comment the trade-off
- An app that must work after a reboot before first unlock cannot use `.complete` — state that in the README rather than hiding it
- Exclude caches and derived files from backup with `isExcludedFromBackupKey`
- Understand what a backup exposes, and tell the user in the restore flow

## Biometrics

- `LAContext` is a **UX gate**, not a cryptographic guarantee — it can be bypassed on a compromised device
- For real protection, put the key in the Secure Enclave with an access control flag, so the data is unreadable without the biometric
- **ALWAYS** provide a fallback (passcode or app PIN); biometrics fail routinely
- Never gate the app's core function behind it — gate the sensitive parts

## Logging

- **NEVER** log money, personal data, tokens, or full request bodies
- `OSLog` interpolations are private by default — mark values `.public` only when you have decided they are safe, one at a time
- Log shapes and counts, not contents: `"print chunk 3/9, mtu 244"`, not the receipt
- Assume any log the user can share will be shared

## Privacy Manifest

- **AUTHOR `PrivacyInfo.xcprivacy` from the actual data flows**, not from a template
- Declare `NSPrivacyTracking`, tracking domains, collected data types, and every required-reason API code you use (`UserDefaults`, file timestamp, disk space, active keyboards, system boot time)
- A manifest that overstates is a rejection; one that understates is a lie — verify it against a written list of everything that crosses the app's edge
- Usage strings (`NSCameraUsageDescription` and friends) must say **why**, in the user's language

## Network

- **NEVER** disable App Transport Security or set `NSAllowsArbitraryLoads`
- Validate and encode everything crossing a boundary; treat all input as hostile
- Certificate pinning only when you control both ends and have a rotation plan

## Third-Party Code

- Every SDK is data potentially leaving the device — audit what it sends before adding it
- Analytics and attribution SDKs are a product decision, not a technical one; put them behind explicit consent or leave them out
- Anything behind consent must not initialise at all until consent is granted

## General Principles

- Simplicity reduces attack surface
- If unsure, choose the more restrictive option
- Say the honest thing in the README about what the app cannot protect against
