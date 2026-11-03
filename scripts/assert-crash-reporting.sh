#!/usr/bin/env bash
#
# assert-crash-reporting.sh — Crashlytics, crashes only, behind consent (SPEC §1, §5.4, §14).
#
# Exits 1, listing every offender, if:
#   1. the project links a Firebase product other than FirebaseCrashlytics (no Analytics, no
#      Messaging/FCM, no Remote Config). Reads the project file; never writes it.
#   2. any Swift file under Laci/ other than Laci/Observability/CrashReporting.swift imports a
#      Firebase module or calls FirebaseApp.configure — so Firebase can only start after consent.
#   3. any Swift file anywhere in the app calls a Crashlytics API that carries app data: log,
#      record, setCustomValue, setCustomKeysAndValues or setUserID. Crash stacks only, never a sale.
# Portable to bash 3.2 and both BSD and GNU grep.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Laci.xcodeproj/project.pbxproj"
SOURCES="$ROOT/Laci"
REPORTER="Laci/Observability/CrashReporting.swift"

offenders=""
count=0
add_offender() {
  offenders="${offenders}  - $1"$'\n'
  count=$((count + 1))
}

if [[ ! -f "$PROJECT" || ! -f "$ROOT/$REPORTER" ]]; then
  echo "assert-crash-reporting: cannot find $PROJECT or $REPORTER" >&2
  exit 1
fi

# 1. Linked Firebase products.
while IFS= read -r product; do
  [[ -z "$product" ]] && continue
  [[ "$product" == "FirebaseCrashlytics" ]] && continue
  add_offender "project links $product; only FirebaseCrashlytics is allowed"
done < <(grep -Eo 'productName = "?Firebase[A-Za-z]*' "$PROJECT" | sed -E 's/productName = "?//' | sort -u || true)

# 2. Firebase outside the reporter.
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  file="${hit%%:*}"
  [[ "${file#"$ROOT"/}" == "$REPORTER" ]] && continue
  add_offender "${hit#"$ROOT"/}: Firebase is only touched in $REPORTER"
done < <(grep -RnE '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+Firebase|FirebaseApp\.configure' \
  --include='*.swift' "$SOURCES" || true)

# 3. Crashlytics calls that would carry app data.
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  add_offender "${hit#"$ROOT"/}: Crashlytics sends crash stacks only"
done < <(grep -RnE '\.(log|record|setCustomValue|setCustomKeysAndValues|setUserID)\(' --include='*.swift' \
  "$SOURCES" | grep -E 'rashlytics' || true)

if [[ "$count" -gt 0 ]]; then
  echo "assert-crash-reporting: $count offender(s):" >&2
  printf '%s' "$offenders" >&2
  exit 1
fi
echo "assert-crash-reporting: Crashlytics only, configured only in $REPORTER, no app data sent."
