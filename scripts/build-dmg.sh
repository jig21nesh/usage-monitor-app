#!/usr/bin/env bash
# Builds a distributable DMG for AI Usage Monitor (ADR 0007).
#
# Signs with a Developer ID identity and notarises when credentials are provided; otherwise
# produces an ad-hoc signed DMG whose file name says "unsigned". Never uses `codesign --deep`
# for signing: nested code (none today) is signed inside-out, then the app, then the DMG.
#
# The build carries the version given with --version (the release tag) as MARKETING_VERSION and
# the git commit count as CURRENT_PROJECT_VERSION, so every DMG reports which commit built it.
#
# Environment:
#   SIGNING_IDENTITY   "Developer ID Application: Name (TEAMID)"; empty means ad-hoc.
#   NOTARY_PROFILE     notarytool keychain profile (xcrun notarytool store-credentials), or
#   NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID   an App Store Connect API key.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/build-dmg.sh [options]

Options:
  --version X.Y.Z   Marketing version built into the app and used in the DMG file name
                    (default: MARKETING_VERSION in project.yml). The build number is the git
                    commit count, or CURRENT_PROJECT_VERSION in project.yml outside a checkout.
  --output DIR      Output directory (default: dist)
  --skip-build      Reuse build/DerivedData/Build/Products/Release/UsageMonitor.app
  --no-notarize     Sign but do not notarise even when credentials are present
  --dry-run         Print the plan and exit without building
  -h, --help        Show this help

Environment: SIGNING_IDENTITY, NOTARY_PROFILE or NOTARY_KEY_PATH/NOTARY_KEY_ID/NOTARY_ISSUER_ID.
Without SIGNING_IDENTITY the app is ad-hoc signed and the DMG is named *-unsigned.dmg.
EOF
}

log() { printf '==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

cd "$(dirname "$0")/.."

APP_NAME="AI Usage Monitor"
PRODUCT="UsageMonitor"
SCHEME="UsageMonitor"
BUNDLE_ID="com.jiggykakkad.UsageMonitor"
DERIVED_DATA="build/DerivedData"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/$PRODUCT.app"
ENTITLEMENTS="App/$PRODUCT.entitlements"

VERSION=""
OUTPUT_DIR="dist"
SKIP_BUILD=0
NOTARIZE=1
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --version) [ $# -ge 2 ] || die "--version needs a value"; VERSION="$2"; shift 2 ;;
        --output) [ $# -ge 2 ] || die "--output needs a value"; OUTPUT_DIR="$2"; shift 2 ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        --no-notarize) NOTARIZE=0; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown option: $1" ;;
    esac
done

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
NOTARY_KEY_PATH="${NOTARY_KEY_PATH:-}"
NOTARY_KEY_ID="${NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${NOTARY_ISSUER_ID:-}"

if [ -z "$VERSION" ]; then
    VERSION="$(awk '/^ *MARKETING_VERSION:/ {print $2; exit}' project.yml | tr -d '"')"
    [ -n "$VERSION" ] || die "could not read MARKETING_VERSION from project.yml"
fi
case "$VERSION" in
    *[!0-9A-Za-z.+-]*|"") die "version '$VERSION' contains unexpected characters" ;;
esac

# CFBundleVersion: the commit count identifies the exact build. Outside a checkout (a source
# archive) fall back to the value in project.yml.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    BUILD_NUMBER="$(git rev-list --count HEAD)"
else
    BUILD_NUMBER="$(awk '/^ *CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml | tr -d '"')"
fi
case "$BUILD_NUMBER" in
    ""|*[!0-9]*|0*) die "build number '$BUILD_NUMBER' is not a positive integer" ;;
esac

DEVELOPER_ID=0
case "$SIGNING_IDENTITY" in
    "Developer ID Application:"*) DEVELOPER_ID=1 ;;
esac

HAS_NOTARY_CREDENTIALS=0
if [ -n "$NOTARY_PROFILE" ] || { [ -n "$NOTARY_KEY_PATH" ] && [ -n "$NOTARY_KEY_ID" ] && [ -n "$NOTARY_ISSUER_ID" ]; }; then
    HAS_NOTARY_CREDENTIALS=1
fi
WILL_NOTARIZE=0
if [ "$DEVELOPER_ID" -eq 1 ] && [ "$NOTARIZE" -eq 1 ] && [ "$HAS_NOTARY_CREDENTIALS" -eq 1 ]; then
    WILL_NOTARIZE=1
fi

if [ "$DEVELOPER_ID" -eq 1 ]; then
    DMG_NAME="AIUsageMonitor-$VERSION.dmg"
else
    DMG_NAME="AIUsageMonitor-$VERSION-unsigned.dmg"
fi
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

log "Plan"
note "version:        $VERSION"
note "build number:   $BUILD_NUMBER"
note "output:         $DMG_PATH"
note "build:          $([ "$SKIP_BUILD" -eq 1 ] && echo "skipped (reuse $BUILT_APP)" || echo "Release via xcodebuild")"
if [ -n "$SIGNING_IDENTITY" ]; then
    note "signing:        $SIGNING_IDENTITY$([ "$DEVELOPER_ID" -eq 1 ] || echo ' (not a Developer ID: treated as unsigned for distribution)')"
else
    note "signing:        ad-hoc (set SIGNING_IDENTITY for Developer ID)"
fi
note "notarisation:   $([ "$WILL_NOTARIZE" -eq 1 ] && echo yes || echo "no$([ "$DEVELOPER_ID" -eq 1 ] && [ "$HAS_NOTARY_CREDENTIALS" -eq 0 ] && echo ' (no credentials)')")"
if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry run; nothing built."
    exit 0
fi

# 1. Build
if [ "$SKIP_BUILD" -eq 0 ]; then
    log "Generating project"
    scripts/bootstrap.sh
    log "Building Release"
    # Signing is disabled here on purpose: the app is re-signed explicitly below with the chosen
    # identity and the source entitlements, so the result does not depend on local Xcode accounts.
    xcodebuild -project "$PRODUCT.xcodeproj" -scheme "$SCHEME" -configuration Release \
        -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED_DATA" \
        MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
        CODE_SIGNING_ALLOWED=NO -quiet build
fi
[ -d "$BUILT_APP" ] || die "built app not found at $BUILT_APP"
[ -f "$ENTITLEMENTS" ] || die "entitlements not found at $ENTITLEMENTS (run scripts/bootstrap.sh)"
plutil -lint "$ENTITLEMENTS" >/dev/null

# 2. Sign inside-out
if [ -n "$SIGNING_IDENTITY" ]; then
    IDENTITY_ARG="$SIGNING_IDENTITY"
    TIMESTAMP_ARG="--timestamp"
else
    IDENTITY_ARG="-"
    TIMESTAMP_ARG="--timestamp=none"
fi

log "Signing nested code"
NESTED_COUNT=0
for dir in "$BUILT_APP/Contents/Frameworks" "$BUILT_APP/Contents/XPCServices" "$BUILT_APP/Contents/PlugIns" \
    "$BUILT_APP/Contents/Library"; do
    [ -d "$dir" ] || continue
    while IFS= read -r -d '' item; do
        codesign --force --sign "$IDENTITY_ARG" --options runtime "$TIMESTAMP_ARG" "$item"
        NESTED_COUNT=$((NESTED_COUNT + 1))
    done < <(find "$dir" -depth \( -name '*.framework' -o -name '*.dylib' -o -name '*.xpc' -o -name '*.appex' \
        -o -name '*.app' -o -name '*.bundle' \) -print0)
done
note "nested items signed: $NESTED_COUNT"

log "Signing $PRODUCT.app"
codesign --force --sign "$IDENTITY_ARG" --options runtime "$TIMESTAMP_ARG" --entitlements "$ENTITLEMENTS" "$BUILT_APP"
codesign --verify --deep --strict --verbose=2 "$BUILT_APP"
# grep exits 1 when nothing matches, which is the expected outcome here; pipefail must not abort.
EXCEPTION_COUNT="$(codesign -d --entitlements :- "$BUILT_APP" 2>/dev/null | { grep -o '<string>/[^<]*' || true; } | wc -l | tr -d ' ')"
note "sandbox temporary path exceptions in signed app: $EXCEPTION_COUNT (expected 0, ADR 0009)"

# 3. Stage and create the DMG
log "Creating DMG"
mkdir -p "$OUTPUT_DIR"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/usage-monitor-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$APP_NAME"
ditto "$BUILT_APP" "$STAGE/$APP_NAME/$APP_NAME.app"
ln -s /Applications "$STAGE/$APP_NAME/Applications"
rm -f "$DMG_PATH" "$DMG_PATH.sha256"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE/$APP_NAME" -ov -format UDZO -fs HFS+ -quiet "$DMG_PATH"

# 4. Sign, notarise and staple the DMG
NOTARISED=no
if [ "$DEVELOPER_ID" -eq 1 ]; then
    log "Signing DMG"
    codesign --sign "$SIGNING_IDENTITY" --timestamp -i "$BUNDLE_ID.dmg" "$DMG_PATH"
    if [ "$WILL_NOTARIZE" -eq 1 ]; then
        log "Submitting to Apple notary service"
        NOTARY_ARGS=()
        if [ -n "$NOTARY_PROFILE" ]; then
            NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
        else
            NOTARY_ARGS=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
        fi
        SUBMIT_OUTPUT="$(xcrun notarytool submit "$DMG_PATH" "${NOTARY_ARGS[@]}" --wait 2>&1 | tee /dev/stderr)"
        SUBMISSION_ID="$(printf '%s\n' "$SUBMIT_OUTPUT" | awk '/^ *id: / {print $2; exit}')"
        if ! printf '%s\n' "$SUBMIT_OUTPUT" | grep -q 'status: Accepted'; then
            if [ -n "$SUBMISSION_ID" ]; then
                xcrun notarytool log "$SUBMISSION_ID" "${NOTARY_ARGS[@]}" || true
            fi
            die "notarisation was not accepted"
        fi
        log "Stapling"
        xcrun stapler staple "$DMG_PATH"
        xcrun stapler validate "$DMG_PATH"
        NOTARISED=yes
    fi
fi

log "Gatekeeper assessment"
if spctl -a -t open --context context:primary-signature -vv "$DMG_PATH" 2>&1 | sed 's/^/    /'; then
    note "accepted"
else
    if [ "$NOTARISED" = yes ]; then
        die "Gatekeeper rejected a notarised DMG"
    fi
    note "rejected as expected for an unsigned or un-notarised build (see README > Installation)"
fi

# 5. Checksum and summary
(cd "$OUTPUT_DIR" && shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256")
SHA256="$(awk '{print $1}' "$DMG_PATH.sha256")"
SIZE="$(du -h "$DMG_PATH" | awk '{print $1}')"

log "Done"
printf '    %-12s %s\n' "dmg" "$DMG_PATH"
printf '    %-12s %s\n' "version" "$VERSION (build $BUILD_NUMBER)"
printf '    %-12s %s\n' "size" "$SIZE"
printf '    %-12s %s\n' "signing" "$([ "$DEVELOPER_ID" -eq 1 ] && echo "Developer ID" || echo "unsigned (ad-hoc)")"
printf '    %-12s %s\n' "notarised" "$NOTARISED"
printf '    %-12s %s\n' "sha256" "$SHA256"
