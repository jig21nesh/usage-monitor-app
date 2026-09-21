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

## Amendment 2026-09-22: releases are built locally

### Context

The tag-triggered `release.yml` ran on GitHub's macOS runners, which are billed at ten times
the Linux rate, and CI additionally built a throwaway DMG on every push. The maintainer now has
a paid Apple Developer Program team with a Developer ID Application identity and notary
credentials on one Mac, so the reason for keeping signing material in GitHub secrets is gone.

### Decision

- `scripts/release.sh`, run on the maintainer's Mac, replaces `.github/workflows/release.yml`.
  It verifies that `main` is clean and in sync with origin, that `CHANGELOG.md` has a section
  for the version and that the tag is free, builds the DMG with `scripts/build-dmg.sh`, creates
  and pushes the annotated tag and publishes the GitHub Release with the DMG and its checksum.
  The release notes are the `CHANGELOG.md` section plus the signing status and the SHA-256.
- Signing material lives in the git-ignored `Config/Signing/` folder (private key, certificate
  signing request, certificate, `.p8` notary key); the identity itself is in the login keychain
  and the notary credentials in a notarytool keychain profile named `AIUsageMonitor`. No
  secret is stored on GitHub.
- CI no longer builds a DMG. `scripts/build-dmg.sh` keeps its dual mode so a Mac without the
  identity can still produce a clearly labelled unsigned DMG; `release.sh` publishes one only
  with `--allow-unsigned`.

### Consequences

- Releases depend on one machine: the Mac that holds the identity and the notary profile. A
  second maintainer needs their own Developer ID certificate under the same team.
- Notary credentials and the private key live in that Mac's keychain and in `Config/Signing/`;
  a backup of the Mac contains them.
- The README instructions for unsigned builds remain only as a fallback for self-compiled or
  `--allow-unsigned` builds; published releases are notarised.
- Deleting a tag or release stays a manual, explicitly approved step, so a bad release is
  corrected by publishing the next version rather than by automation.
