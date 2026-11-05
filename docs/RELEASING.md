# Releasing

A `vX.Y.Z` tag on `main` is the only thing that ships. [`release.yml`](../.github/workflows/release.yml) checks the tag, runs the full test matrix, then archives and uploads to TestFlight. Nothing is uploaded from a laptop, and no signing material is committed here.

Do the setup once, in this order: the provisioning profile has to include the iCloud capability.

## 1. Xcode

These change the project file, so they are done in the Xcode UI. `scripts/assert-release-ready.sh` blocks the tag until they are done.

On the **Laci** target, under **Signing & Capabilities**:

1. Add **iCloud**, tick **iCloud Documents**, and add the container `iCloud.id.Laci`.
2. Add **Background Modes** and tick **Background processing**.

On the **Laci** target, under **Info**:

3. Add `BGTaskSchedulerPermittedIdentifiers` as an array containing `id.laci.backup`.

On the **Laci** project, under **Info › Localizations**:

4. Add **Indonesian** and **Japanese**, then make Indonesian the default.

Then link Crashlytics:

5. **File › Add Package Dependencies**, enter `https://github.com/firebase/firebase-ios-sdk`, and add only the **FirebaseCrashlytics** product to the Laci target. `scripts/assert-crash-reporting.sh` rejects any other Firebase product.
6. Create a Firebase project for `id.Laci` and download `GoogleService-Info.plist`. Keep it out of git; it goes into a secret in step 4 of this guide.

## 2. App Store Connect

Sign in at [appstoreconnect.apple.com](https://appstoreconnect.apple.com).

1. Accept the **Paid Apps** agreement under Business, or the in-app purchase cannot load.
2. Create the app under **Apps › +**: iOS, name `Laci`, primary language **Indonesian**, bundle ID `id.Laci`, SKU `laci`. The bundle ID cannot change afterwards.
3. Under **App Information**, set the primary category to **Business**.
4. Under **In-App Purchases**, create one **Non-Consumable**: product ID `id.laci.unlock`, price Rp 149.000. The ID must match exactly.
5. Under **TestFlight**, fill in **Test Information**, including the Beta App Review contact. Apple reviews the first build sent to external testers.
6. Under **TestFlight › External Testing**, create a group named exactly `Tiga Toko` and add the three shop owners by email. Their addresses stay in App Store Connect and never go in this repository.
7. Under **Users and Access › Integrations › App Store Connect API**, create a team key with the **App Manager** role. Download the `.p8`, which Apple offers only once, and note the key ID and issuer ID.

## 3. Signing certificates

Create a **private** repository, `febbryandika/laci-certificates`. It holds match's encrypted certificates, because this repository is public. Then run this once on your Mac. It creates a certificate and a profile and uploads nothing to App Store Connect:

```bash
bundle install
```

```bash
bundle exec fastlane match appstore --git_url git@github.com:febbryandika/laci-certificates.git --username YOUR_APPLE_ID
```

Choose a strong passphrase when asked; it becomes `MATCH_PASSWORD`. Then generate an SSH key pair and add its public half to `laci-certificates` as a **read-only** deploy key.

Run the same command with `--force` after adding a capability or when the certificate expires.

## 4. GitHub environment and secrets

Create a `testflight` environment that only `v*` tags can deploy from. This is what stops any branch or laptop from reading the keys:

```bash
gh api -X PUT repos/febbryandika/laci/environments/testflight --input - <<< '{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
```

```bash
gh api -X POST repos/febbryandika/laci/environments/testflight/deployment-branch-policies -f name='v*' -f type=tag
```

Then add these as secrets of that environment, with `gh secret set NAME --env testflight`, which prompts for the value:

| Secret | Value |
|---|---|
| `ASC_KEY_ID` | The App Store Connect key ID |
| `ASC_ISSUER_ID` | The App Store Connect issuer ID |
| `ASC_KEY_CONTENT` | The `.p8` file, base64-encoded |
| `MATCH_GIT_URL` | `git@github.com:febbryandika/laci-certificates.git` |
| `MATCH_GIT_PRIVATE_KEY` | The private half of the read-only deploy key |
| `MATCH_PASSWORD` | The match passphrase |
| `GOOGLE_SERVICE_INFO_PLIST` | `GoogleService-Info.plist`, base64-encoded |

Afterwards, delete the `.p8`, the deploy key's private half and any local `GoogleService-Info.plist` from your Mac, or move them to your password manager.

## 5. Ship

Before the first tag, test on a real iPad: Face ID, file protection, and an iCloud backup and restore.

The tag's message becomes "What was changed" in the [What to Test note](../fastlane/what_to_test.id.txt), so write it for the shop owners, in Indonesian:

```bash
git tag -a v1.0.0 -m "Versi pertama untuk tiga toko."
```

```bash
git push origin v1.0.0
```

| Comes from | Becomes |
|---|---|
| The tag, `v1.0.0` | Version `1.0.0` |
| `github.run_number` of `release.yml` | Build number, so the first run is build 1 |
| The tag's message | "What was changed" |

Preview the note without uploading:

```bash
bundle exec fastlane preview_what_to_test tag:v1.0.0
```

## When a release fails

- **A test fails:** nothing shipped. Fix it on `main` and push a new tag; never move a shipped tag.
- **A job is cancelled with "not acquired by Runner":** GitHub had no macOS runner. Run `gh run rerun <run-id> --failed`.
- **The upload succeeded but distribution failed:** finish it in App Store Connect, or push a new tag. A rerun would reuse the build number, which Apple refuses.
