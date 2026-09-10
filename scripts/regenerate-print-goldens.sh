#!/usr/bin/env bash
#
# regenerate-print-goldens.sh — rewrite the LaciPrint golden receipt fixtures.
#
# The golden tests in Packages/LaciPrint/Tests/LaciPrintTests (receipt and diagnostic print) compare
# bytes on every run and writes only when LACI_REGENERATE_GOLDENS=1, which nothing but this
# script sets. Run it after a deliberate layout change, read the diff, and commit the .bin files
# with the change that caused them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="Packages/LaciPrint/Tests/LaciPrintTests/Fixtures"

cd "$ROOT"
LACI_REGENERATE_GOLDENS=1 swift test --package-path Packages/LaciPrint --filter GoldenTests

echo
echo "Golden fixtures now differ from HEAD as follows (empty means unchanged):"
git status --short -- "$FIXTURES"
