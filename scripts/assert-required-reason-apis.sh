#!/usr/bin/env bash
#
# assert-required-reason-apis.sh — the privacy manifest must not understate (SPEC §15).
#
# Laci/PrivacyInfo.xcprivacy declares UserDefaults and no other required-reason API. Exits 1, listing
# every offender, if any Swift file under Laci/ or Packages/*/Sources calls an API from a category
# the manifest does not declare: file timestamp, disk space, system boot time or active keyboards.
# Adding one is a decision: declare the category and its reason in the manifest, then widen this.
# Portable to bash 3.2 and both BSD and GNU grep.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/Laci/PrivacyInfo.xcprivacy"

TIMESTAMP='\.(creationDate|modificationDate|fileModificationDate|contentModificationDate|attributeModificationDate|contentAccessDate)\b|(creationDate|contentModificationDate|attributeModificationDate|contentAccessDate)Key\b|attributesOfItem\(|\b(stat|fstat|lstat|fstatat|getattrlist|fgetattrlist|getattrlistat|getattrlistbulk)\('
DISK='volumeAvailableCapacity|volumeTotalCapacity|systemFreeSize|systemSize\b|attributesOfFileSystem\(|\b(statfs|statvfs|fstatfs|fstatvfs)\('
BOOT='systemUptime|mach_absolute_time\('
KEYBOARD='activeInputModes'

[[ -f "$MANIFEST" ]] || { echo "assert-required-reason-apis: cannot find $MANIFEST" >&2; exit 1; }

offenders=""
count=0
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  offenders="${offenders}  - ${hit#"$ROOT"/}"$'\n'
  count=$((count + 1))
done < <(grep -RnE "$TIMESTAMP|$DISK|$BOOT|$KEYBOARD" --include='*.swift' "$ROOT/Laci" "$ROOT"/Packages/*/Sources || true)

if [[ "$count" -gt 0 ]]; then
  echo "assert-required-reason-apis: $count call(s) the privacy manifest does not declare:" >&2
  printf '%s' "$offenders" >&2
  exit 1
fi
echo "assert-required-reason-apis: only UserDefaults, as the manifest declares."
