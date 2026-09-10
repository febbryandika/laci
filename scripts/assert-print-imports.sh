#!/usr/bin/env bash
#
# assert-print-imports.sh — LaciPrint turns a Receipt into Data and nothing else (SPEC §7).
#
# Exits 1, listing every offender, if:
#   1. any `import` under Packages/LaciPrint/Sources names a module outside Foundation, CoreGraphics
#      and LaciMoney — so never CoreBluetooth, UIKit or LaciCore.
#      Handles `@testable import X`, `@_exported import X`, `public import X`,
#      `import struct Foundation.Decimal`; flags `@preconcurrency import` outright.
#   2. Packages/LaciPrint/Package.swift declares a `.package(...)` other than the local LaciMoney path,
#      or any target `dependencies:` other than LaciMoney (library) and LaciPrint (tests).
# Tests/ is not scanned: it legitimately imports Testing, CoreGraphics and LaciMoney.
# Portable to bash 3.2 and both BSD and GNU grep/sed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT/Packages/LaciPrint"
SOURCES_DIR="$PACKAGE_DIR/Sources"
MANIFEST="$PACKAGE_DIR/Package.swift"
ALLOWED_MODULES="Foundation CoreGraphics LaciMoney"

# An import declaration: optional attributes (with or without arguments), optional access level.
IMPORT_LINE_RE='^[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*((public|package|internal|private|fileprivate)[[:space:]]+)?import[[:space:]]'
ALLOWED_DEPS_RE='dependencies[[:space:]]*:[[:space:]]*\[[[:space:]]*(\.package\(path:[[:space:]]*"\.\./LaciMoney"\)|"LaciMoney"|"LaciPrint")[[:space:]]*\][[:space:]]*,?'
ALLOWED_PACKAGE_RE='\.package\(path:[[:space:]]*"\.\./LaciMoney"\)'

offenders=""
count=0
add_offender() {
  offenders="${offenders}  - $1"$'\n'
  count=$((count + 1))
}
is_allowed() {
  local candidate
  for candidate in $ALLOWED_MODULES; do
    [[ "$1" == "$candidate" ]] && return 0
  done
  return 1
}

[[ -f "$MANIFEST" ]] || { echo "error: $MANIFEST not found" >&2; exit 1; }
[[ -d "$SOURCES_DIR" ]] || { echo "error: $SOURCES_DIR not found" >&2; exit 1; }

scanned=0
while IFS= read -r -d '' file; do
  scanned=$((scanned + 1))
  rel="${file#"$ROOT"/}"
  while IFS= read -r match; do
    [[ -n "$match" ]] || continue
    lineno="${match%%:*}"
    line="${match#*:}"
    # Drop everything through `import` and an optional kind keyword; keep the first module component.
    module="$(printf '%s\n' "$line" | sed -E \
      's/^.*[[:space:]]import[[:space:]]+//; s/^import[[:space:]]+//; s/^(struct|class|enum|protocol|typealias|func|var|let|actor|macro)[[:space:]]+//; s/[^A-Za-z0-9_].*$//')"
    if printf '%s\n' "$line" | grep -qE '@preconcurrency[[:space:]]+import'; then
      add_offender "$rel:$lineno: @preconcurrency import is not allowed: $line"
    elif ! is_allowed "$module"; then
      add_offender "$rel:$lineno: imports '$module' (allowed: $ALLOWED_MODULES): $line"
    fi
  done < <(grep -nE "$IMPORT_LINE_RE" "$file" || true)
done < <(find "$SOURCES_DIR" -type f -name '*.swift' -print0)

if (( scanned == 0 )); then
  echo "error: no Swift sources found under $SOURCES_DIR; refusing to pass vacuously" >&2
  exit 1
fi

manifest_rel="${MANIFEST#"$ROOT"/}"
while IFS= read -r match; do
  [[ -n "$match" ]] || continue
  add_offender "$manifest_rel:${match%%:*}: external package dependency declared: ${match#*:}"
done < <(grep -nE '\.package\(' "$MANIFEST" | grep -vE "$ALLOWED_PACKAGE_RE" || true)

while IFS= read -r match; do
  [[ -n "$match" ]] || continue
  add_offender "$manifest_rel:${match%%:*}: unexpected 'dependencies:' (only the LaciMoney path package, the library's [\"LaciMoney\"] and the tests' [\"LaciPrint\"] are permitted): ${match#*:}"
done < <(grep -nE 'dependencies[[:space:]]*:' "$MANIFEST" | grep -vE "$ALLOWED_DEPS_RE" || true)

if (( count > 0 )); then
  echo "error: LaciPrint boundary check failed ($count problem(s)). LaciPrint may import only $ALLOWED_MODULES and depend only on LaciMoney (SPEC §7)." >&2
  printf '%s' "$offenders" >&2
  exit 1
fi

echo "ok: LaciPrint imports only $ALLOWED_MODULES ($scanned source file(s) scanned) and depends only on LaciMoney."
