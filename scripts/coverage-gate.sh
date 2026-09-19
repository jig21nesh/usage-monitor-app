#!/usr/bin/env bash
# Runs the Core package tests with coverage and fails when line coverage of
# Sources/UsageMonitorCore is below the threshold (ADR 0005). Override with COVERAGE_THRESHOLD.
set -euo pipefail
cd "$(dirname "$0")/.."

THRESHOLD="${COVERAGE_THRESHOLD:-90}"
PACKAGE="Packages/UsageMonitorCore"

swift test --package-path "$PACKAGE" --enable-code-coverage --parallel
CODECOV_JSON="$(swift test --package-path "$PACKAGE" --show-codecov-path)"

/usr/bin/python3 - "$CODECOV_JSON" "$THRESHOLD" <<'PY'
import json
import sys

path, threshold = sys.argv[1], float(sys.argv[2])
with open(path) as handle:
    report = json.load(handle)

marker = "/Sources/UsageMonitorCore/"
files = [f for f in report["data"][0]["files"] if marker in f["filename"]]
covered = sum(f["summary"]["lines"]["covered"] for f in files)
count = sum(f["summary"]["lines"]["count"] for f in files)
total = 100.0 * covered / count if count else 0.0

rows = sorted((f["summary"]["lines"]["percent"], f["filename"].split(marker)[1]) for f in files)
print(f"{'file':64} {'lines%':>7}")
for percent, name in rows:
    print(f"{name:64} {percent:7.1f}")
print(f"\nTOTAL line coverage (UsageMonitorCore): {total:.2f}% (threshold {threshold:.0f}%)")
sys.exit(0 if total >= threshold else 1)
PY
