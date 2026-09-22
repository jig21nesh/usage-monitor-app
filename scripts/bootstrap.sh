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

# The store build asks for the git-ignored publisher branding spec through this variable
# (ADR 0011). Its mere presence on disk must not change the open-source DMG, so nothing here
# looks for that file on its own.
SPEC="${USAGE_MONITOR_PROJECT_SPEC:-project.yml}"
case "$SPEC" in
    *[!A-Za-z0-9_./-]*|/*|*..*) echo "USAGE_MONITOR_PROJECT_SPEC '$SPEC' must be a relative path inside the repository" >&2; exit 1 ;;
esac
[ -f "$SPEC" ] || { echo "project spec not found: $SPEC" >&2; exit 1; }
xcodegen generate --quiet --spec "$SPEC" --project . --project-root .
echo "Generated UsageMonitor.xcodeproj from $SPEC"
