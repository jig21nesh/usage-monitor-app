# ADR 0010: Mac App Store distribution alongside the GitHub DMG

Date: 2026-09-22
Status: Accepted

## Context

Version 0.1.0 shipped as a Developer ID signed, notarised DMG on GitHub Releases (ADR 0007).
The maintainer wants the app on the Mac App Store as well, under the existing paid team
"Curious Pi Pty Ltd" (34GSD8B76A), with the store version always equal to the GitHub tag.

The App Store imposes constraints the DMG does not:

- App Review guideline 2.4.5(i) expects a sandboxed app that uses the appropriate APIs to reach
  other apps' data. The temporary-exception entitlements from ADR 0004 are routinely rejected;
  ADR 0009 replaces them with a user-granted home folder bookmark for both channels.
- Store builds are signed with Apple Distribution and packaged with Mac Installer Distribution
  certificates plus a Mac App Store provisioning profile, not with Developer ID.
- Every upload for a version needs a strictly increasing `CFBundleVersion`.
- The listing needs a public privacy policy URL (`PRIVACY.md` in this repository), screenshots
  in Apple's fixed sizes, and answers to the age rating and App Privacy questionnaires.
- Reviewers have no vendor CLI logins, so the app shows every provider as "not linked" on their
  Mac; a screen recording and review notes explain what they are seeing.
- Guideline 5.2.2 (third-party terms) is a risk the project cannot engineer away (ADR 0003).

Options for producing the store build:

1. **Xcode Organizer by hand.** Works, but every release would differ by whoever clicked what.
2. **`xcodebuild archive` and `-exportArchive` with cloud-managed automatic signing**,
   authenticated with the App Store Connect API key already used for notarisation. Tried on
   2026-09-22: Xcode answered "Cloud signing permission error" because an App Manager key
   cannot mint cloud-managed distribution certificates, and `xcodebuild` cannot see Xcode's
   signed-in accounts from a shell ("No Accounts").
3. **`xcodebuild archive` and `-exportArchive` with manual signing** against an Apple
   Distribution certificate, a Mac Installer Distribution certificate and a Mac App Store
   provisioning profile held on the maintainer's Mac, created the same way as the Developer ID
   certificate (local key, CSR, download) and, for the profile, through the App Store Connect
   API with the existing key. Deterministic and scriptable.
4. **Separate store-only target or configuration.** Unnecessary: the same entitlements now
   suit both channels, and a second target would let the two builds drift.

## Decision

Adopt option 3.

- `scripts/build-appstore.sh` archives the `UsageMonitor` scheme in Release with
  `MARKETING_VERSION` set to the version and `CURRENT_PROJECT_VERSION` set to the git commit
  count, exactly as `scripts/build-dmg.sh` does, so a version's DMG and store build come from
  the same commit and report the same numbers. It exports with method `app-store-connect` and
  manual signing (Apple Distribution, 3rd Party Mac Developer Installer, profile "AI Usage
  Monitor Mac App Store"), either to a local `.pkg` (default) or straight to App Store Connect
  (`--upload`). It refuses to start unless both identities and the profile are installed,
  refuses archives that are not sandboxed or that carry `get-task-allow`, and warns when
  temporary-exception entitlements are still present.
- The store certificates and their private keys live next to the Developer ID material in the
  git-ignored `Config/Signing/` folder and in the login keychain; the profile is kept there too
  and installed under `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`. Uploads
  authenticate with the API key in `Config/Signing/` (App Manager role) through the
  `-authenticationKey*` flags.
- `ITSAppUsesNonExemptEncryption` is `false` in `Info.plist`: the app uses only HTTPS through
  the system frameworks, so every upload skips the export compliance question.
- The store build may present a different publisher in the About window through the
  build-setting overrides of ADR 0011; the code and version are still the DMG's.
- The store record is "AI Usage Monitor", macOS only, primary language English (Australia),
  free, category Utilities, seller Curious Pi Pty Ltd. The privacy policy URL points at
  `PRIVACY.md` on the `main` branch.
- The DMG on GitHub Releases remains the primary download; the README gains a Mac App Store
  link once the first version is approved.
- Release order for a version: merge the changelog section, run `scripts/release.sh` (tag and
  DMG), then `scripts/build-appstore.sh --upload` from the same commit, then submit in App
  Store Connect. The store listing's version string is set to the same `X.Y.Z` by hand.

## Consequences

- Two artefacts per version, one commit, one version number. A store rejection does not
  affect the GitHub release, and a fix ships as the next version in both places.
- Apple Distribution and Mac Installer Distribution certificates last one year (until
  2027-09-22) and the profile expires with them; renewing means a new CSR each, a new profile,
  and re-importing. `docs/RELEASING.md` carries the steps. A second Mac needs the same material.
- The commit count as build number means a re-upload for the same version needs at least one
  new commit on `main`, which is the intended workflow anyway.
- App Review outcome under guidelines 2.1 (reviewers cannot see live data) and 5.2.2 (vendor
  terms) is unknown until the first submission. A rejection on 5.2.2 ends the store channel
  and leaves the DMG as the only distribution; the project accepts that.
- Users who install from the store and from the DMG get the same bundle identifier and the
  same container, so switching channels keeps settings and the home folder grant.
