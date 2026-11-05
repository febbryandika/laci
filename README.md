# Laci

An offline point of sale for a one-outlet Indonesian shop, on one iPad: scan a barcode, take cash, print a receipt over Bluetooth, and count the drawer at close-out. No account, no subscription, no server.

## Local setup

```bash
git clone https://github.com/febbryandika/laci.git
```

```bash
cd laci/Packages/LaciMoney && swift test
```

Then open `Laci.xcodeproj`.

## CI and releases

| Trigger | Workflow | What runs |
|---|---|---|
| Pull request, push to `main` | [`ci.yml`](.github/workflows/ci.yml) | `swift test` on all three packages, SwiftLint, SwiftFormat, the import-graph and boundary scripts, and `xcodebuild test` with XCUITest on an iPhone and an iPad simulator |
| A `vX.Y.Z` tag on `main` | [`release.yml`](.github/workflows/release.yml) | A preflight check, the same `ci.yml` matrix, then Fastlane `match`, `gym` and `pilot` to TestFlight |

A failed or cancelled test job blocks the upload. There is no beta build configuration and there are no beta feature flags: TestFlight gets the Release build. The tag is the only thing that ships, and [docs/RELEASING.md](docs/RELEASING.md) has the setup.

## The Bitrise equivalent

Japanese mobile teams mostly run Bitrise, so this is the same pipeline as a `bitrise.yml`. It is documentation: this repository runs on GitHub Actions and this file has not been run. Check the step versions in the Bitrise Step Library first.

| GitHub Actions | Bitrise |
|---|---|
| `swift test` jobs in `ci.yml` | A `script` step named `swift-test` |
| `xcodebuild test` job in `ci.yml` | The `xcode-test` step |
| `fastlane ship`, up to and including `gym` | The `manage-ios-code-signing` and `xcode-archive` steps |
| `fastlane ship`, the `pilot` part | The `deploy-to-itunesconnect-application-loader` step |
| The `testflight` environment's secrets | Bitrise Secrets, with the App Store Connect API key as an Apple service connection |
| The `v[0-9]+.[0-9]+.[0-9]+` tag filter | A `tag` entry in `trigger_map` |
| `needs: [preflight, tests]` | Steps in one workflow, which stop at the first failure |

```yaml
trigger_map:
  - pull_request_source_branch: "*"
    workflow: test
  - tag: "v*"
    workflow: release

workflows:
  test:
    steps:
      - git-clone: {}
      - script:
          title: swift-test
          inputs:
            - content: |
                set -e
                for package in LaciMoney LaciPrint LaciCore; do
                  swift test --package-path "Packages/$package"
                done
      - xcode-test:
          inputs:
            - project_path: Laci.xcodeproj
            - scheme: Laci
            - destination: platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=26.5

  release:
    # Runs `test` first, and a failure there stops the upload.
    before_run:
      - test
    steps:
      - manage-ios-code-signing:
          inputs:
            - distribution_method: app-store
      - xcode-archive:
          inputs:
            - project_path: Laci.xcodeproj
            - scheme: Laci
            - configuration: Release
            - distribution_method: app-store
      - deploy-to-itunesconnect-application-loader:
          inputs:
            - connection: api_key
```
