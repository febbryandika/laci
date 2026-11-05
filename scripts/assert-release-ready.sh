#!/usr/bin/env bash
#
# assert-release-ready.sh <tag> — what must be true before a tag may ship (SPEC §12).
#
# Exits 1, listing every offender, if:
#   1. the tag is not vX.Y.Z, or the tagged commit is not on origin/main.
#   2. signing material is tracked in git (nothing signing-related is committed).
#   3. AppIcon has no 1024 image, which App Store Connect rejects.
#   4. an Xcode step is missing: iCloud Documents, the background task, the `id` development
#      language, or the Crashlytics link the privacy manifest already declares.
#   5. the release job would build with a different Xcode than the tests ran on.
# Reads the project file; never writes it. Portable to bash 3.2 and both BSD and GNU grep.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Laci.xcodeproj/project.pbxproj"
ICON_JSON="$ROOT/Laci/Assets.xcassets/AppIcon.appiconset/Contents.json"
TAG="${1:-}"

offenders=""
count=0
add_offender() {
  offenders="${offenders}  - $1"$'\n'
  count=$((count + 1))
}

# 1. The tag.
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || add_offender "tag '$TAG' is not vX.Y.Z"
git -C "$ROOT" merge-base --is-ancestor HEAD origin/main 2>/dev/null \
  || add_offender "the tagged commit is not on origin/main"

# 2. Signing material.
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  add_offender "$file is signing material and must not be committed"
done < <(git -C "$ROOT" ls-files | grep -E '\.(p12|p8|cer|mobileprovision|certSigningRequest)$|(^|/)GoogleService-Info\.plist$' || true)

# 3. The icon.
icon="$(sed -n 's/.*"filename"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ICON_JSON" | head -1)"
if [[ -z "$icon" || ! -f "$(dirname "$ICON_JSON")/$icon" ]]; then
  add_offender "AppIcon has no 1024 image"
fi

# 4. The Xcode steps (docs/RELEASING.md).
grep -q 'CODE_SIGN_ENTITLEMENTS' "$PROJECT" || add_offender "no entitlements file: add the iCloud capability in Xcode"
entitlements="$(find "$ROOT/Laci" -name '*.entitlements' 2>/dev/null | head -1)"
if [[ -z "$entitlements" ]] || ! grep -q 'CloudDocuments' "$entitlements"; then
  add_offender "iCloud Documents is not ticked in Signing & Capabilities"
fi
plists="$(find "$ROOT/Laci" -name '*Info.plist' ! -name 'GoogleService-Info.plist' 2>/dev/null || true)"
for needed in processing BGTaskSchedulerPermittedIdentifiers id.laci.backup; do
  # shellcheck disable=SC2086
  if [[ -z "$plists" ]] || ! grep -q "$needed" $plists; then
    add_offender "Info.plist has no $needed: the charging-time backup cannot run"
  fi
done
grep -q 'developmentRegion = id;' "$PROJECT" || add_offender "the development language is not id (SPEC §9)"
grep -q 'productName = FirebaseCrashlytics;' "$PROJECT" \
  || add_offender "FirebaseCrashlytics is not linked, but the privacy manifest declares crash data"

# 5. One Xcode for tests and archive.
xcode() { sed -n 's/^[[:space:]]*DEVELOPER_DIR:[[:space:]]*//p' "$1" | sort -u; }
if [[ "$(xcode "$ROOT/.github/workflows/ci.yml")" != "$(xcode "$ROOT/.github/workflows/release.yml")" ]]; then
  add_offender "ci.yml and release.yml name different Xcode versions"
fi

if [[ "$count" -gt 0 ]]; then
  echo "assert-release-ready: $count reason(s) this tag cannot ship:" >&2
  printf '%s' "$offenders" >&2
  exit 1
fi
echo "assert-release-ready: $TAG can ship."
