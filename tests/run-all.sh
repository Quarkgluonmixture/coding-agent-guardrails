#!/usr/bin/env bash
# run-all.sh — run every tests/test-*.sh; nonzero exit if any fails.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
overall=0
for t in "$HERE"/test-*.sh; do
  echo "=== $(basename "$t")"
  if ! bash "$t"; then overall=1; fi
done
echo "==="
[ "$overall" -eq 0 ] && echo "ALL SUITES PASS" || echo "SUITE FAILURES"
exit "$overall"
