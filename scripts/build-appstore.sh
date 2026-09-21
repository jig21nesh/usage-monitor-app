#!/usr/bin/env bash
# Builds the Mac App Store package for AI Usage Monitor and optionally uploads it (ADR 0010).
#
# The archive is signed automatically by Xcode with the team's cloud-managed Apple Distribution
# and Mac Installer Distribution certificates; nothing is imported into the keychain. The same
# App Store Connect API key used for notarisation authenticates provisioning and the upload.
#
# The build carries the version given with --version (the release tag) as MARKETING_VERSION and
# the git commit count as CURRENT_PROJECT_VERSION, exactly like scripts/build-dmg.sh, so the
# App Store build and the GitHub release for a version are the same commit.
#
# Environment:
#   APP_STORE_TEAM_ID  Apple Developer team that owns the App Store record (default 34GSD8B76A).
#   NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID   App Store Connect API key; when unset
#                      they are read from Config/Signing/notary.env (git-ignored).
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/build-appstore.sh [options]

Options:
  --version X.Y.Z   Marketing version built into the app (default: MARKETING_VERSION in
                    project.yml). The build number is the git commit count, or
                    CURRENT_PROJECT_VERSION in project.yml outside a checkout.
  --output DIR      Output directory for the .pkg (default: dist/appstore)
  --upload          Upload to App Store Connect instead of exporting a .pkg
  --dry-run         Print the plan and exit without building
  -h, --help        Show this help

Requires an App Store Connect API key (App Manager role) in Config/Signing/notary.env or the
NOTARY_KEY_PATH, NOTARY_KEY_ID and NOTARY_ISSUER_ID variables. See docs/RELEASING.md.
EOF
}

log() { printf '==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

cd "$(dirname "$0")/.."

PRODUCT="UsageMonitor"
SCHEME="UsageMonitor"
ARCHIVE_PATH="build/AppStore/$PRODUCT.xcarchive"
CREDENTIALS_FILE="Config/Signing/notary.env"

VERSION=""
OUTPUT_DIR="dist/appstore"
UPLOAD=0
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --version) [ $# -ge 2 ] || die "--version needs a value"; VERSION="$2"; shift 2 ;;
        --output) [ $# -ge 2 ] || die "--output needs a value"; OUTPUT_DIR="$2"; shift 2 ;;
        --upload) UPLOAD=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown option: $1" ;;
    esac
done

TEAM_ID="${APP_STORE_TEAM_ID:-34GSD8B76A}"
[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || die "APP_STORE_TEAM_ID '$TEAM_ID' is not a ten-character team id"

if [ -z "$VERSION" ]; then
    VERSION="$(awk '/^ *MARKETING_VERSION:/ {print $2; exit}' project.yml | tr -d '"')"
    [ -n "$VERSION" ] || die "could not read MARKETING_VERSION from project.yml"
fi
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version '$VERSION' is not X.Y.Z"

# CFBundleVersion: the commit count identifies the exact build and rises with every commit on
# main, which is what App Store Connect requires of successive uploads for one version.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    BUILD_NUMBER="$(git rev-list --count HEAD)"
else
    BUILD_NUMBER="$(awk '/^ *CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml | tr -d '"')"
fi
case "$BUILD_NUMBER" in
    ""|*[!0-9]*|0*) die "build number '$BUILD_NUMBER' is not a positive integer" ;;
esac

# API key: explicit variables win; otherwise read the three known keys from notary.env without
# executing the file, and validate their shapes before use.
read_credential() {
    awk -F= -v key="$1" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$CREDENTIALS_FILE"
}
KEY_PATH="${NOTARY_KEY_PATH:-}"
KEY_ID="${NOTARY_KEY_ID:-}"
ISSUER_ID="${NOTARY_ISSUER_ID:-}"
if { [ -z "$KEY_PATH" ] || [ -z "$KEY_ID" ] || [ -z "$ISSUER_ID" ]; } && [ -f "$CREDENTIALS_FILE" ]; then
    [ -n "$KEY_PATH" ] || KEY_PATH="$(read_credential NOTARY_KEY_PATH)"
    [ -n "$KEY_ID" ] || KEY_ID="$(read_credential NOTARY_KEY_ID)"
    [ -n "$ISSUER_ID" ] || ISSUER_ID="$(read_credential NOTARY_ISSUER_ID)"
fi
[ -n "$KEY_PATH" ] && [ -n "$KEY_ID" ] && [ -n "$ISSUER_ID" ] \
    || die "App Store Connect API key not configured (see docs/RELEASING.md, App Store build)"
[[ "$KEY_ID" =~ ^[A-Z0-9]{10}$ ]] || die "NOTARY_KEY_ID has an unexpected shape"
[[ "$ISSUER_ID" =~ ^[0-9a-f-]{36}$ ]] || die "NOTARY_ISSUER_ID is not a UUID"
[ -f "$KEY_PATH" ] || die "API key file not found at $KEY_PATH"

AUTH_ARGS=(
    -allowProvisioningUpdates
    -authenticationKeyPath "$(cd "$(dirname "$KEY_PATH")" && pwd)/$(basename "$KEY_PATH")"
    -authenticationKeyID "$KEY_ID"
    -authenticationKeyIssuerID "$ISSUER_ID"
)
DESTINATION="$([ "$UPLOAD" -eq 1 ] && echo upload || echo export)"

log "Plan"
note "version:        $VERSION"
note "build number:   $BUILD_NUMBER"
note "team:           $TEAM_ID"
note "signing:        automatic, cloud-managed Apple Distribution"
note "destination:    $DESTINATION$([ "$UPLOAD" -eq 0 ] && echo " to $OUTPUT_DIR")"
if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry run; nothing built."
    exit 0
fi

log "Generating project"
scripts/bootstrap.sh

log "Archiving Release"
rm -rf "$ARCHIVE_PATH"
xcodebuild -project "$PRODUCT.xcodeproj" -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE_PATH" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic \
    "${AUTH_ARGS[@]}" -quiet archive
ARCHIVED_APP="$ARCHIVE_PATH/Products/Applications/$PRODUCT.app"
[ -d "$ARCHIVED_APP" ] || die "archived app not found at $ARCHIVED_APP"

log "Checking archived app"
codesign --verify --deep --strict "$ARCHIVED_APP"
ENTITLEMENTS_XML="$(codesign -d --entitlements :- "$ARCHIVED_APP" 2>/dev/null)"
printf '%s' "$ENTITLEMENTS_XML" | grep -q 'com.apple.security.app-sandbox' \
    || die "archived app is not sandboxed; the App Store requires App Sandbox"
if printf '%s' "$ENTITLEMENTS_XML" | grep -q 'temporary-exception'; then
    warn "archived app still carries temporary-exception entitlements; App Review is likely to reject it"
fi
if printf '%s' "$ENTITLEMENTS_XML" | grep -q 'get-task-allow'; then
    die "archived app carries get-task-allow; App Store Connect rejects such builds"
fi
note "bundle version: $(defaults read "$(pwd)/$ARCHIVED_APP/Contents/Info.plist" CFBundleShortVersionString) ($(defaults read "$(pwd)/$ARCHIVED_APP/Contents/Info.plist" CFBundleVersion))"

# Export options: app-store-connect handles both a local .pkg and the upload.
OPTIONS="$(mktemp "${TMPDIR:-/tmp}/usage-monitor-export.XXXXXX")"
trap 'rm -f "$OPTIONS"' EXIT
cat > "$OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>$DESTINATION</string>
<key>teamID</key><string>$TEAM_ID</string>
<key>signingStyle</key><string>automatic</string>
<key>uploadSymbols</key><true/>
<key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
EOF

if [ "$UPLOAD" -eq 1 ]; then
    log "Uploading to App Store Connect"
else
    log "Exporting package"
    mkdir -p "$OUTPUT_DIR"
fi
xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportOptionsPlist "$OPTIONS" \
    -exportPath "$OUTPUT_DIR" "${AUTH_ARGS[@]}"

if [ "$UPLOAD" -eq 0 ]; then
    PKG="$OUTPUT_DIR/$PRODUCT.pkg"
    [ -f "$PKG" ] || die "expected $PKG after export"
    log "Package signature"
    pkgutil --check-signature "$PKG" | sed 's/^/    /'
    log "Done"
    printf '    %-10s %s\n' "package" "$PKG"
else
    log "Done"
    note "build $VERSION ($BUILD_NUMBER) uploaded; it appears in App Store Connect after processing"
fi
