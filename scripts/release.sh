#!/usr/bin/env bash
# Cuts a release from the maintainer's Mac (ADR 0007, amended 2026-09-22).
#
# Checks that main is clean and in sync, that CHANGELOG.md has a section for the version and
# that the tag does not exist yet; builds the DMG with scripts/build-dmg.sh (Developer ID signed
# and notarised unless --allow-unsigned); then tags, pushes the tag and publishes a GitHub
# Release whose notes are that CHANGELOG.md section. Nothing here reads or prints a credential:
# signing uses the login keychain and notarisation uses a notarytool keychain profile.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/release.sh [options]

Options:
  --version X.Y.Z         Version to release (default: MARKETING_VERSION in project.yml)
  --notary-profile NAME   notarytool keychain profile (default: AIUsageMonitor)
  --allow-unsigned        Skip the Developer ID and notary checks and build an unsigned DMG
  --dry-run               Run every check and the build but do not tag, push or publish
  -h, --help              Show this help

Requires a clean main checkout in sync with origin, a `## [X.Y.Z]` section in CHANGELOG.md,
a logged-in GitHub CLI and, unless --allow-unsigned, exactly one Developer ID Application
identity in the keychain plus the notary profile (see docs/RELEASING.md).
EOF
}

log() { printf '==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

cd "$(dirname "$0")/.."

VERSION=""
PROFILE="AIUsageMonitor"
ALLOW_UNSIGNED=0
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --version) [ $# -ge 2 ] || die "--version needs a value"; VERSION="$2"; shift 2 ;;
        --notary-profile) [ $# -ge 2 ] || die "--notary-profile needs a value"; PROFILE="$2"; shift 2 ;;
        --allow-unsigned) ALLOW_UNSIGNED=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown option: $1" ;;
    esac
done

if [ -z "$VERSION" ]; then
    VERSION="$(awk '/^ *MARKETING_VERSION:/ {print $2; exit}' project.yml | tr -d '"')"
    [ -n "$VERSION" ] || die "could not read MARKETING_VERSION from project.yml"
fi
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version '$VERSION' is not X.Y.Z"
[[ "$PROFILE" =~ ^[A-Za-z0-9._-]+$ ]] || die "notary profile name '$PROFILE' contains unexpected characters"
TAG="v$VERSION"

# Preflight: repository state
log "Checking repository"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git work tree"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = "main" ] || die "releases are cut from main; current branch is '$BRANCH'"
[ -z "$(git status --porcelain)" ] || die "working tree is not clean; commit or discard changes first"
git fetch --quiet origin main || die "could not fetch origin/main"
LOCAL_SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git rev-parse origin/main)"
[ "$LOCAL_SHA" = "$REMOTE_SHA" ] || die "local main ($LOCAL_SHA) differs from origin/main ($REMOTE_SHA); pull or push first"
note "main at $LOCAL_SHA, in sync with origin"

# Preflight: changelog and tag
awk -v v="$VERSION" 'index($0, "## [" v "]") == 1 { found = 1 } END { exit found ? 0 : 1 }' CHANGELOG.md \
    || die "CHANGELOG.md has no '## [$VERSION]' section; add it through a pull request first"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    die "tag $TAG already exists locally"
fi
if [ -n "$(git ls-remote --tags origin "refs/tags/$TAG")" ]; then
    die "tag $TAG already exists on origin"
fi
note "changelog section present, tag $TAG free"

# Preflight: tooling and credentials
gh auth status >/dev/null 2>&1 || die "GitHub CLI is not logged in; run: gh auth login"
IDENTITY=""
if [ "$ALLOW_UNSIGNED" -eq 0 ]; then
    IDENTITIES="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2}')"
    IDENTITY_COUNT="$(printf '%s' "$IDENTITIES" | grep -c . || true)"
    case "$IDENTITY_COUNT" in
        0) die "no 'Developer ID Application' identity in the keychain (see docs/RELEASING.md), or pass --allow-unsigned" ;;
        1) IDENTITY="$IDENTITIES" ;;
        *) die "found $IDENTITY_COUNT 'Developer ID Application' identities; keep exactly one in the keychain" ;;
    esac
    xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
        || die "notary profile '$PROFILE' is missing or rejected; run xcrun notarytool store-credentials (see docs/RELEASING.md)"
    note "signing identity: $IDENTITY"
    note "notary profile:   $PROFILE"
    DMG_NAME="AIUsageMonitor-$VERSION.dmg"
    SIGNING_SENTENCE="Signed with Developer ID and notarised by Apple."
else
    note "signing:          none (--allow-unsigned)"
    DMG_NAME="AIUsageMonitor-$VERSION-unsigned.dmg"
    SIGNING_SENTENCE="Unsigned build. See README, Installation, for how to open it on macOS 26 and 27."
fi
DMG_PATH="dist/$DMG_NAME"

log "Plan"
note "version:   $VERSION"
note "tag:       $TAG"
note "artefact:  $DMG_PATH"
note "publish:   $([ "$DRY_RUN" -eq 1 ] && echo "no (dry run)" || echo "tag, push, GitHub Release")"

# Build
log "Building DMG"
if [ "$ALLOW_UNSIGNED" -eq 0 ]; then
    SIGNING_IDENTITY="$IDENTITY" NOTARY_PROFILE="$PROFILE" scripts/build-dmg.sh --version "$VERSION"
else
    SIGNING_IDENTITY="" NOTARY_PROFILE="" scripts/build-dmg.sh --version "$VERSION" --no-notarize
fi
[ -f "$DMG_PATH" ] || die "expected $DMG_PATH after the build"
[ -f "$DMG_PATH.sha256" ] || die "expected $DMG_PATH.sha256 after the build"
(cd dist && shasum -a 256 -c "$DMG_NAME.sha256" >/dev/null) || die "checksum in $DMG_PATH.sha256 does not match the DMG"
SHA256="$(awk '{print $1}' "$DMG_PATH.sha256")"
note "sha256: $SHA256"

# Release notes: the CHANGELOG section body, trimmed, plus the signing status and checksum.
NOTES="$(mktemp "${TMPDIR:-/tmp}/usage-monitor-notes.XXXXXX")"
trap 'rm -f "$NOTES"' EXIT
awk -v v="$VERSION" '
    index($0, "## [" v "]") == 1 { found = 1; next }
    found && /^## \[/ { exit }
    found && /^\[[^]]+\]: / { exit }
    found { lines[++n] = $0 }
    END {
        first = 1; last = n
        while (first <= last && lines[first] ~ /^[[:space:]]*$/) first++
        while (last >= first && lines[last] ~ /^[[:space:]]*$/) last--
        for (i = first; i <= last; i++) print lines[i]
    }
' CHANGELOG.md > "$NOTES"
[ -s "$NOTES" ] || die "the '## [$VERSION]' section in CHANGELOG.md is empty"
printf '\n%s\n\nSHA-256 (`%s`): `%s`\n' "$SIGNING_SENTENCE" "$DMG_NAME" "$SHA256" >> "$NOTES"

log "Release notes"
sed 's/^/    /' "$NOTES"

# Publish
if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry run; would now run:"
    note "git tag -a $TAG -m \"Release $VERSION\""
    note "git push origin $TAG"
    note "gh release create $TAG $DMG_PATH $DMG_PATH.sha256 --verify-tag --title $TAG --notes-file <notes>"
    exit 0
fi

log "Tagging $TAG"
git tag -a "$TAG" -m "Release $VERSION"
git push origin "$TAG"

log "Publishing GitHub Release"
gh release create "$TAG" "$DMG_PATH" "$DMG_PATH.sha256" --verify-tag --title "$TAG" --notes-file "$NOTES"
URL="$(gh release view "$TAG" --json url -q .url)"

log "Done"
printf '    %-10s %s\n' "release" "$URL"
printf '    %-10s %s\n' "dmg" "$DMG_PATH"
printf '    %-10s %s\n' "sha256" "$SHA256"
