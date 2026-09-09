#!/usr/bin/env bash
#
# assert-money-imports.sh — LaciMoney must import nothing but Foundation (SPEC §8).
#
# Exits 1, listing every offender, if:
#   1. any `import` under Packages/LaciMoney/Sources names a module other than Foundation.
#      Handles `@testable import X`, `@_exported import X`, `public import X`,
#      `import struct Foundation.Decimal`; flags `@preconcurrency import` outright.
#   2. Packages/LaciMoney/Package.swift declares a `.package(...)` dependency, or any
#      `dependencies:` other than the test target's one-line `dependencies: ["LaciMoney"]`.
# Tests/ is not scanned: it legitimately imports Testing and LaciMoney.
# Portable to bash 3.2 and both BSD and GNU grep/sed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT/Packages/LaciMoney"
SOURCES_DIR="$PACKAGE_DIR/Sources"
MANIFEST="$PACKAGE_DIR/Package.swift"
ALLOWED_MODULE="Foundation"

# An import declaration: optional attributes (with or without arguments), optional access level.
IMPORT_LINE_RE='^[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*((public|package|internal|private|fileprivate)[[:space:]]+)?import[[:space:]]'
ALLOWED_DEPS_RE='dependencies[[:space:]]*:[[:space:]]*\[[[:space:]]*"LaciMoney"[[:space:]]*\][[:space:]]*,?'

offenders=""
count=0
add_offender() {
  offenders="${offenders}  - $1"$'\n'
  count=$((count + 1))
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
    elif [[ "$module" != "$ALLOWED_MODULE" ]]; then
      add_offender "$rel:$lineno: imports '$module' (only $ALLOWED_MODULE is allowed): $line"
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
done < <(grep -nE '\.package\(' "$MANIFEST" || true)

while IFS= read -r match; do
  [[ -n "$match" ]] || continue
  add_offender "$manifest_rel:${match%%:*}: unexpected 'dependencies:' (only the test target's one-line dependencies: [\"LaciMoney\"] is permitted): ${match#*:}"
done < <(grep -nE 'dependencies[[:space:]]*:' "$MANIFEST" | grep -vE "$ALLOWED_DEPS_RE" || true)

if (( count > 0 )); then
  echo "error: LaciMoney purity check failed ($count problem(s)). LaciMoney may import only $ALLOWED_MODULE and declare no dependencies (SPEC §8)." >&2
  printf '%s' "$offenders" >&2
  exit 1
fi

echo "ok: LaciMoney imports only $ALLOWED_MODULE ($scanned source file(s) scanned) and declares no dependencies."
