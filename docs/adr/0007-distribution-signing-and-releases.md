# ADR 0007: Distribution as a DMG, signed and notarised when credentials exist

Date: 2026-09-20
Status: Accepted

## Context

Users should be able to install the app without Xcode. macOS 26 and 27 block unsigned or
unnotarised apps downloaded from the internet, and since Sequoia the Control-click "Open"
bypass no longer exists; users must go to System Settings > Privacy & Security > Open Anyway.
Notarisation requires a Developer ID Application certificate, which only a paid Apple Developer
Program membership can issue. At the time of writing the maintainer's Mac holds only Apple
Development certificates and no notarisation credentials.

Options:

1. **Ship only when notarised.** Cleanest for users but blocks releases on enrolment.
2. **Dual mode.** One script and one release workflow that sign with Developer ID and notarise
   when an identity and credentials are present, and otherwise produce an ad-hoc signed DMG that
   is clearly labelled unsigned, with README instructions for Open Anyway.
3. **Homebrew cask first.** Not possible: Homebrew disables casks that fail Gatekeeper checks
   (September 2026), so a cask must wait for notarisation anyway.

## Decision

Adopt option 2.

- `scripts/build-dmg.sh` builds Release, signs inside-out without `--deep` using
  `SIGNING_IDENTITY` when set (otherwise ad-hoc), creates a UDZO DMG with an `/Applications`
  symlink, signs the DMG, notarises with `NOTARY_PROFILE` when set, staples, verifies with
  `spctl`, writes a SHA-256 next to the DMG and names unsigned artefacts as such.
- `.github/workflows/release.yml` runs on `v*` tags on `macos-26`, imports the Developer ID
  certificate from secrets into a temporary keychain, notarises with an App Store Connect API key
  from secrets, and attaches the DMG and checksum to a GitHub Release. Signing is gated on the
  secrets being present; without them the release is published as unsigned.
- Release builds set `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` so the binary never carries
  `get-task-allow`, which notarisation rejects.
- `docs/RELEASING.md` holds the manual checklist: enrol, create the certificate, export the
  `.p12`, create an App Store Connect Team API key, store the GitHub secrets, tag.

## Consequences

- Until the maintainer enrols and stores the secrets, releases are ad-hoc signed and users need
  the Open Anyway step; the README says so plainly.
- The sandbox entitlements, including the temporary file exceptions, need no provisioning
  profile for Developer ID distribution and do not block notarisation.
- A changed signing identity (ad-hoc rebuilds, or the move from Apple Development to Developer
  ID) re-triggers the keychain consent dialog for the Claude Code item on users' Macs.
