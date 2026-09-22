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

# A release Mac may carry a git-ignored publisher branding spec that includes project.yml and
# adds the logo asset catalog (ADR 0011). Everyone else generates from project.yml alone.
SPEC="project.yml"
BRANDING_SPEC="Config/Branding/Branding.yml"
if [ -f "$BRANDING_SPEC" ]; then
    SPEC="$BRANDING_SPEC"
fi
xcodegen generate --quiet --spec "$SPEC" --project . --project-root .
echo "Generated UsageMonitor.xcodeproj from $SPEC"
