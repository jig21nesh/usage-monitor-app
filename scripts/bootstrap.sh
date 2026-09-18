#!/usr/bin/env bash
# Generates UsageMonitor.xcodeproj from project.yml. The project file is gitignored on purpose.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen not found. Install it with: brew install xcodegen" >&2
    exit 1
fi

if [ ! -f Config/Local.xcconfig ]; then
    cp Config/Local.xcconfig.example Config/Local.xcconfig
    echo "Created Config/Local.xcconfig from the example. Set DEVELOPMENT_TEAM before archiving." >&2
fi

xcodegen generate --quiet
echo "Generated UsageMonitor.xcodeproj"
