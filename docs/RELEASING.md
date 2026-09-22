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
   **+**; the Developer role is enough for notarisation, App Manager is needed for App
   Store uploads), download the `.p8` once into
   `Config/Signing/`, note the Key ID and Issuer ID, then store the profile in the keychain:

   ```sh
   xcrun notarytool store-credentials AIUsageMonitor \
     --key Config/Signing/AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUER>
   xcrun notarytool history --keychain-profile AIUsageMonitor   # expect an empty or valid list
   ```

3. **GitHub CLI logged in** (`gh auth status`) with permission to push tags and create
   releases on the repository.

`Config/Signing/` ends up holding `developer-id.key`, `developer-id.csr`,
`developerID_application.cer`, `AuthKey_<KEYID>.p8`, `notary.env` (with `NOTARY_KEY_ID`,
`NOTARY_ISSUER_ID` and `NOTARY_KEY_PATH`) and, once the App Store material exists, the two
extra key/CSR/certificate triples and the `.provisionprofile` described below. The private key and the `.p8` are
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

## Build and upload the App Store version

The Mac App Store build is produced from the same commit as the DMG, after `scripts/release.sh`
has tagged it, by `scripts/build-appstore.sh` ([ADR 0010](adr/0010-mac-app-store-distribution.md)).
The export is signed manually with three pieces of material that live in `Config/Signing/`
(once per Mac, and again when they expire after a year):

1. **Apple Distribution** and **Mac Installer Distribution** certificates, created exactly like
   the Developer ID one above: a fresh key and CSR per certificate (`apple-distribution.key`,
   `mac-installer.key`), the CSR uploaded at
   <https://developer.apple.com/account/resources/certificates/add>, the `.cer` downloaded
   (`distribution.cer`, `mac_installer.cer`), then bundled with its key into a `.p12` and
   imported with `security import … -T /usr/bin/codesign -T /usr/bin/productbuild`.
   `security find-identity -v -p codesigning` must list "Apple Distribution: …" and
   `security find-identity -v -p basic` must list "3rd Party Mac Developer Installer: …".
2. **A Mac App Store provisioning profile** named `AI Usage Monitor Mac App Store` for the App
   ID `com.jiggykakkad.UsageMonitor` and the Apple Distribution certificate. Create it at
   <https://developer.apple.com/account/resources/profiles/add> (Distribution > Mac App Store
   Connect) or through the App Store Connect API, save it as
   `Config/Signing/AIUsageMonitor_MacAppStore.provisionprofile` and copy it to
   `~/Library/Developer/Xcode/UserData/Provisioning Profiles/<UUID>.provisionprofile`. The
   script finds it by its `Name` entry, so the file name does not matter.
3. The API key from the notary step, whose role must be **App Manager** for uploads.

Cloud-managed automatic signing was tried and does not work from a shell: an App Manager API
key is refused ("Cloud signing permission error") and `xcodebuild` cannot use Xcode's
signed-in accounts ("No Accounts").

```sh
scripts/build-appstore.sh --dry-run             # show the plan
scripts/build-appstore.sh                       # archive and export dist/appstore/UsageMonitor.pkg
scripts/build-appstore.sh --upload              # archive and upload to App Store Connect
scripts/build-appstore.sh --version 0.2.0 --upload
```

The script sets `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` like `build-dmg.sh`, refuses
an archive that is not sandboxed or that carries `get-task-allow`, and warns when
temporary-exception entitlements are present because App Review rejects them. After an upload,
App Store Connect processes the build for a few minutes; then, in the app record, set the
version string to the same `X.Y.Z`, pick the build, complete the listing and submit for review.
`CFBundleVersion` is the commit count, so a second upload for the same version needs a new
commit on `main`.

### Publisher branding for the App Store build

The About window reads its publisher from build settings ([ADR 0011](adr/0011-build-time-publisher-branding.md)).
The committed defaults are the open-source identity; the store build overrides them with the
git-ignored file `Config/Branding/AppStore.xcconfig`, which `build-appstore.sh` passes to
`xcodebuild archive` when it exists (`APP_STORE_BRANDING=<path>` points elsewhere; the plan
output shows `branding: <file>` or `branding: defaults`). The five settings:

| Setting | About window use |
|---|---|
| `UM_BRAND_MAKER_NAME` | "Made by <name>" |
| `UM_BRAND_TAGLINE` | The line under the maker |
| `UM_BRAND_WEBSITE_URL` | The Website button; `http(s)` only |
| `UM_BRAND_COPYRIGHT_HOLDER` | "Copyright © 2026 <holder>." in the window and in `NSHumanReadableCopyright` |
| `UM_BRAND_LOGO_ASSET` | Name of an image in `Config/Branding/BrandAssets.xcassets`; empty for no logo |

xcconfig treats `//` as the start of a comment, so write URLs as `https:/$()/example.com`.

The logo needs the catalog to be part of the generated project without appearing in
`project.yml`. `scripts/bootstrap.sh` generates from `Config/Branding/Branding.yml` whenever
that file exists (from the repository root, so paths are root-relative) and from `project.yml`
otherwise. The branding spec includes the main spec and adds the catalog:

```yaml
include:
  - path: project.yml
    relativePaths: false
targets:
  UsageMonitor:
    sources:
      - path: Config/Branding/BrandAssets.xcassets
```

`Config/Branding/BrandAssets.xcassets/<name>.imageset/` holds the logo (light and dark
variants work like any asset catalog image) and `<name>` is the value of `UM_BRAND_LOGO_ASSET`.
A name that does not resolve at runtime simply hides the logo. Keep the store listing's
marketing URL and copyright fields in step with these values by hand; App Store Connect does
not read them from the build.

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
