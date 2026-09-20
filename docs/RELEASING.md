# Releasing

How a version of AI Usage Monitor becomes a downloadable DMG. The design is recorded in
[ADR 0007](adr/0007-distribution-signing-and-releases.md): one script, one tag-triggered
workflow, signed and notarised when the credentials exist and clearly labelled unsigned
otherwise.

## What runs where

| Piece | Purpose |
|---|---|
| `scripts/build-dmg.sh` | Builds Release, signs the app inside-out (never `--deep`), creates a UDZO DMG with an Applications shortcut, signs the DMG, notarises and staples when it can, writes a SHA-256 |
| `.github/workflows/release.yml` | Runs the script on `v*` tags and attaches `dist/*.dmg` and `dist/*.sha256` to a GitHub Release; manual runs upload a workflow artifact instead |
| `.github/workflows/ci.yml` | Builds an unsigned DMG on every pull request as a smoke test and keeps it as a 7-day artifact |

Without a Developer ID identity the script signs ad-hoc and names the file
`AIUsageMonitor-<version>-unsigned.dmg`. With one it produces `AIUsageMonitor-<version>.dmg`,
and notarises it when notary credentials are also present.

## Cut a release

```sh
# 1. Bump MARKETING_VERSION (and CURRENT_PROJECT_VERSION) in project.yml, update CHANGELOG.md,
#    merge through a pull request.
# 2. Tag the merge commit on main and push the tag.
git checkout main && git pull
git tag -a v0.1.0 -m "v0.1.0"
git push origin v0.1.0
# 3. Watch the Release workflow, then check the Release page for the DMG and .sha256.
gh run watch
```

A manual build without a tag: **Actions > Release > Run workflow**, enter the version; the DMG
appears as a workflow artifact.

## Build locally

```sh
scripts/build-dmg.sh --dry-run                 # show the plan
scripts/build-dmg.sh                           # ad-hoc signed DMG in dist/
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="UsageMonitor-notary" scripts/build-dmg.sh   # signed and notarised
```

Flags: `--version X.Y.Z`, `--output DIR`, `--skip-build` (reuse the last Release build),
`--no-notarize`, `--dry-run`.

## One-time setup for signed releases

Everything below needs the paid Apple Developer Program (US$99 per year) and the
**Account Holder** role, because Developer ID certificates are only issued to program members.
Apple Development certificates (the ones Xcode creates for free accounts) cannot notarise.

1. **Enrol** at <https://developer.apple.com/programs/enroll/> and note your Team ID
   (Membership details).
2. **Create a Developer ID Application certificate.** Either Xcode > Settings > Accounts >
   your team > Manage Certificates > **+** > Developer ID Application, or
   <https://developer.apple.com/account/resources/certificates/add> > Software > Developer ID
   Application. A Developer ID *Installer* certificate is only for `.pkg` files and is not
   needed.
3. **Export the certificate** with its private key: Keychain Access > My Certificates >
   right-click the certificate > Export as `.p12` with a strong password. Keep a backup;
   the private key exists only where you exported it.
4. **Create notary credentials.** Either an app-specific password
   (<https://account.apple.com> > Sign-In and Security > App-Specific Passwords) for local use,
   or an App Store Connect **Team** API key for CI (App Store Connect > Users and Access >
   Integrations > App Store Connect API > Team Keys > **+**; Developer role is sufficient for
   `notarytool`; download the `.p8` once and record the Key ID and Issuer ID). Individual keys
   cannot notarise.
5. **Store a local notarytool profile** (optional, for local signed builds):

   ```sh
   xcrun notarytool store-credentials "UsageMonitor-notary" \
     --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
   # or with the API key
   xcrun notarytool store-credentials "UsageMonitor-notary" \
     --key ~/AuthKey_KEYID.p8 --key-id KEYID --issuer ISSUER-UUID
   ```

6. **Add the GitHub secrets** (repository > Settings > Secrets and variables > Actions, or with
   the CLI):

   ```sh
   gh secret set BUILD_CERTIFICATE_BASE64 --body "$(base64 -i DeveloperID.p12)"
   gh secret set P12_PASSWORD
   gh secret set KEYCHAIN_PASSWORD --body "$(openssl rand -base64 32)"
   gh secret set APP_STORE_CONNECT_KEY_ID
   gh secret set APP_STORE_CONNECT_ISSUER_ID
   gh secret set APP_STORE_CONNECT_PRIVATE_KEY --body "$(base64 -i AuthKey_KEYID.p8)"
   ```

   The workflow signs and notarises only when `BUILD_CERTIFICATE_BASE64` and
   `APP_STORE_CONNECT_PRIVATE_KEY` are both set. It imports the certificate into a temporary
   keychain and deletes that keychain in a final step that always runs.

## Verify a download

```sh
shasum -a 256 -c AIUsageMonitor-0.1.0.dmg.sha256
spctl -a -t open --context context:primary-signature -vv AIUsageMonitor-0.1.0.dmg
xcrun stapler validate AIUsageMonitor-0.1.0.dmg
```

`spctl` prints `accepted` and `source=Notarized Developer ID` for a notarised release. Unsigned
builds are rejected here; that is expected.

## Unsigned builds

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
  whether the app can read the Claude Code keychain item.
- Homebrew disables casks that fail Gatekeeper checks (since September 2026), so a Homebrew
  cask has to wait until releases are notarised.
