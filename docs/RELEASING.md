# Releasing

How a version of AI Usage Monitor becomes a downloadable DMG. The design is recorded in
[ADR 0007](adr/0007-distribution-signing-and-releases.md) and its 2026-09-22 amendment: releases
are built, signed, notarised and published from the maintainer's Mac by one script. GitHub
Actions runs tests and lint only; it never builds a DMG.

## What runs where

| Piece | Purpose |
|---|---|
| `scripts/release.sh` | Checks the checkout, builds the DMG through `build-dmg.sh`, creates the `vX.Y.Z` tag, pushes it and publishes a GitHub Release whose notes are the matching `CHANGELOG.md` section |
| `scripts/build-dmg.sh` | Builds Release, signs the app inside-out (never `--deep`), creates a UDZO DMG with an Applications shortcut, signs the DMG, notarises and staples, writes a SHA-256 |
| `Config/Signing/` | Git-ignored folder holding the signing material described below; nothing in it is ever committed |

Without a Developer ID identity `build-dmg.sh` signs ad-hoc and names the file
`AIUsageMonitor-<version>-unsigned.dmg`. With one it produces `AIUsageMonitor-<version>.dmg`
and notarises it when the notary profile exists. `release.sh` refuses to publish an unsigned DMG
unless you pass `--allow-unsigned`.

## Prerequisites (once per Mac)

Everything below needs the paid Apple Developer Program and the **Account Holder** role,
because Developer ID certificates are only issued to program members. Apple Development
certificates (the ones Xcode creates for free accounts) cannot notarise.

1. **A Developer ID Application identity in the login keychain.** Generate a private key and a
   certificate signing request locally, create the certificate at
   <https://developer.apple.com/account/resources/certificates/add> (Software > Developer ID
   Application), download it and import it. A Developer ID *Installer* certificate is only for
   `.pkg` files and is not needed.

   ```sh
   mkdir -p Config/Signing && chmod 700 Config/Signing
   openssl req -new -newkey rsa:2048 -nodes -keyout Config/Signing/developer-id.key \
     -out Config/Signing/developer-id.csr -subj "/CN=Developer ID/emailAddress=you@example.com"
   # upload developer-id.csr on the Apple page, download developerID_application.cer, then:
   openssl pkcs12 -export -inkey Config/Signing/developer-id.key \
     -in Config/Signing/developerID_application.cer -out Config/Signing/developer-id.p12
   security import Config/Signing/developer-id.p12 -k ~/Library/Keychains/login.keychain-db \
     -T /usr/bin/codesign -T /usr/bin/security
   security find-identity -v -p codesigning        # expect one "Developer ID Application: …"
   ```

2. **A notary profile named `AIUsageMonitor`.** Create an App Store Connect **Team** API key
   (App Store Connect > Users and Access > Integrations > App Store Connect API > Team Keys >
   **+**; the Developer role is enough for notarisation), download the `.p8` once into
   `Config/Signing/`, note the Key ID and Issuer ID, then store the profile in the keychain:

   ```sh
   xcrun notarytool store-credentials AIUsageMonitor \
     --key Config/Signing/AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUER>
   xcrun notarytool history --keychain-profile AIUsageMonitor   # expect an empty or valid list
   ```

3. **GitHub CLI logged in** (`gh auth status`) with permission to push tags and create
   releases on the repository.

`Config/Signing/` ends up holding `developer-id.key`, `developer-id.csr`,
`developerID_application.cer`, `developer-id.p12`, `AuthKey_<KEYID>.p8` and, for reference,
`notary.env` with `NOTARY_KEY_ID` and `NOTARY_ISSUER_ID`. The private key and the `.p8` are
secrets: keep the folder mode `700`, keep the files mode `600`, and remember that a backup of
this Mac contains them. The folder is listed in `.gitignore`; `git status` must never show it.

## Cut a release

1. Merge a pull request that adds a `## [X.Y.Z] - YYYY-MM-DD` section to `CHANGELOG.md`; that
   section becomes the release notes. Bump `MARKETING_VERSION` in `project.yml` in the same
   pull request so `release.sh` picks the version up by default.
2. On `main`, in sync with `origin/main`, with a clean tree:

   ```sh
   scripts/release.sh --dry-run          # all checks plus a real signed build, no tag, no publish
   scripts/release.sh                    # the release
   scripts/release.sh --version 0.2.0    # release a version other than project.yml's
   ```

The script checks, in order: inside a git checkout; branch is `main`; tree is clean;
`origin/main` matches `HEAD`; `CHANGELOG.md` has the `## [X.Y.Z]` heading; tag `vX.Y.Z` exists
neither locally nor on origin; `gh` is logged in; exactly one Developer ID Application identity
is in the keychain; the notary profile answers. Then it builds the DMG with
`MARKETING_VERSION=X.Y.Z` and `CURRENT_PROJECT_VERSION` set to the git commit count, verifies
the checksum, prints the release notes, creates the annotated tag, pushes it and runs
`gh release create` with the DMG and its `.sha256`. Flags: `--version`, `--notary-profile`
(default `AIUsageMonitor`), `--allow-unsigned`, `--dry-run`, `-h`.

## Recover from a bad release

Tags and releases are deleted by hand, never by the script, and deleting either needs the
maintainer's explicit approval (project rule 13):

```sh
gh release delete vX.Y.Z --yes          # removes the GitHub Release and its assets
git push --delete origin vX.Y.Z         # removes the remote tag
git tag -d vX.Y.Z                       # removes the local tag
```

Fix the problem through a pull request, then run `scripts/release.sh` again for the same
version. A notarised DMG that was already downloaded stays valid; publish a new version rather
than replacing assets in place.

## Local install on your own Mac

An ad-hoc build gets a new code identity on every rebuild, so macOS forgets the **Always Allow**
you gave the previous build for the Claude Code and GitHub CLI keychain items and asks again.
Sign local builds with an Apple Development identity instead: its code requirement is the bundle
identifier plus your team, which does not change between builds.

```sh
security find-identity -v -p codesigning                    # list the identities on this Mac
SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/build-dmg.sh --no-notarize
```

The DMG is still named `-unsigned` because an Apple Development identity is not valid for
distribution; it is only for the Mac that holds the certificate. Click **Always Allow** once
after the first launch. Apple Development certificates last one year: when yours expires the
script falls back to ad-hoc signing and the dialog returns until you renew it and rebuild.

## Build a DMG without releasing

```sh
scripts/build-dmg.sh --dry-run                 # show the plan
scripts/build-dmg.sh                           # ad-hoc signed DMG in dist/
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="AIUsageMonitor" scripts/build-dmg.sh   # signed and notarised, no tag
```

Flags: `--version X.Y.Z`, `--output DIR`, `--skip-build` (reuse the last Release build),
`--no-notarize`, `--dry-run`.

## Verify a download

```sh
shasum -a 256 -c AIUsageMonitor-0.1.0.dmg.sha256
spctl -a -t open --context context:primary-signature -vv AIUsageMonitor-0.1.0.dmg
xcrun stapler validate AIUsageMonitor-0.1.0.dmg
```

`spctl` prints `accepted` and `source=Notarized Developer ID` for a notarised release. Unsigned
builds are rejected here; that is expected.

## Unsigned builds

Only builds you compile yourself, or a release published with `--allow-unsigned`, are unsigned.
Since macOS Sequoia, Control-click > Open no longer bypasses Gatekeeper. A user who installs an
unsigned build must:

1. Double-click the app and dismiss the "cannot verify" dialog.
2. Open System Settings > Privacy & Security, scroll to Security, click **Open Anyway** (shown
   for about an hour after the attempt), and confirm with the login password.

Power users can instead clear the quarantine flag:

```sh
xattr -d com.apple.quarantine "/Applications/AI Usage Monitor.app"
```

Two consequences to know about:

- Every ad-hoc build has a different code identity, so macOS may ask again after each update
  whether the app can read the Claude Code keychain item (once per launch at most; see
  [Local install on your own Mac](#local-install-on-your-own-mac) for a stable identity).
- Homebrew disables casks that fail Gatekeeper checks (since September 2026), so a Homebrew
  cask needs notarised releases.
