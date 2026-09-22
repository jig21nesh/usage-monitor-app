# ADR 0009: User-granted home folder access instead of sandbox temporary exceptions

Date: 2026-09-22
Status: Accepted (amends ADR 0004)

## Context

ADR 0004 kept App Sandbox on and opened seven read-only holes with
`com.apple.security.temporary-exception.files.home-relative-path.read-only`, one per vendor
credential file plus Cursor's `globalStorage` folder. That was acceptable while the project
shipped only as a DMG. The maintainer now intends to publish the same app on the Mac App Store,
where App Review guideline 2.4.5(i) requires apps to be "appropriately sandboxed" and to use the
appropriate macOS APIs for other apps' data; temporary-exception entitlements are, in practice,
rejected unless the reviewer accepts a justification, and there is no supported way to argue
for seven of them.

The sanctioned mechanism is user consent through the open panel: the folder the user picks
becomes a security-scoped bookmark the app may store and re-open on later launches
(`com.apple.security.files.user-selected.read-only` plus
`com.apple.security.files.bookmarks.app-scope`). Keychain items are outside this discussion:
they are read through the normal macOS consent dialog with no file entitlement at all.

Options:

1. **Keep the exceptions on the DMG and use bookmarks only in the store build.** Two behaviours
   to test, two onboarding flows, two sets of support answers.
2. **One behaviour: the user grants the home folder once, in both builds.** One extra step on
   the Welcome screen; identical binaries apart from the signing identity and the distribution
   method, so the store version and the GitHub tag stay the same number.
3. **Drop the sandbox.** Rules the store out and loses the defence in depth ADR 0004 chose.

## Decision

Adopt option 2.

- Entitlements: remove the temporary exceptions; add `files.user-selected.read-only` and
  `files.bookmarks.app-scope`. App Sandbox, Hardened Runtime and `network.client` stay.
- `HomeFolderAccess` (Core) owns one security-scoped bookmark to the home folder:
  `activate()` at launch resolves the stored bookmark and starts access for the life of the
  process; `grant(_:)` accepts only the real home directory (trailing slashes and `.` segments
  ignored), stores a read-only bookmark and starts access; `revoke()` stops access and deletes
  the bookmark. States are `granted`, `notGranted`, `stale` and `unavailable(reason)`.
- The bookmark is stored in the app's own `UserDefaults`. It is a pointer to a folder the user
  chose, not a credential, so ADR 0002's rule that the app persists no token is untouched.
- `HomeFolderGatedFileSystem` wraps `LocalFileSystem`: while the grant is missing, any read
  inside the home folder fails with `FileReadError.accessNotGranted`, which every file-backed
  source maps to `ProviderError.credentialsUnreadable("home_folder_not_granted")`. The UI then
  says "Grant access to your home folder" instead of "could not be read". Paths outside the
  home folder (an absolute `CODEX_HOME`, for example) pass straight through.
- `UsageMonitorModel` activates the grant in `start()` before the first poll, exposes
  `homeFolderState`, and after `grantHomeFolder` re-probes every provider and polls once so the
  cards flip without a relaunch. The Welcome window shows a "Home folder access" card above the
  provider cards; Settings > Accounts shows the state with Grant and Revoke; Diagnostics shows
  the state in its footer.
- The open panel lives in the app target behind `HomeFolderPicking`; UI-test builds use a fake
  that answers with the expected folder, and a fixed `/Users/you` path so screenshots never
  show a real user name.

Evidence (spike on 2026-09-22, macOS 27.0, a throwaway sandboxed app with exactly the new
entitlements and none of the old exceptions):

| Step | Result |
|---|---|
| Open panel on the real home with `canChooseDirectories`, `showsHiddenFiles` | Pressing the prompt button without selecting a child returned `/Users/<user>` |
| `bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])` | 632 bytes; resolving with `.withSecurityScope` gave `stale=false` |
| Same launch, before `startAccessingSecurityScopedResource` | All present files readable: the panel itself grants a session extension |
| Fresh launch, before `startAccessing…` | Every read failed with `NSCocoaErrorDomain` 513 (no permission), so the sandbox is enforced |
| Fresh launch, after `startAccessing…` returned true | `.codex/auth.json` 3968 B, `.grok/auth.json` 1725 B, `.config/gh/hosts.yml` 86 B, `.copilot/config.json` 280 B and Cursor's `state.vscdb` (1 MB cap) all read; Muse and OpenCode files absent on that Mac (code 4, expected) |
| After `stopAccessing…` | Reads failed with 513 again |

One home-folder bookmark therefore covers all seven locations, including the Cursor database
under `~/Library/Application Support`, persists across launches, and access is process-wide by
path once started, which is why `UserEnvironment.homeDirectory` stays the passwd-derived home.

## Consequences

- One extra step on first run: the user clicks Grant Access and confirms the pre-selected home
  folder. Until then the six file-backed providers show "Not linked" with the grant hint;
  Claude, which is keychain-only, works regardless.
- The grant is revocable in Settings > Accounts and survives updates, because the bookmark is
  app-scoped to the bundle identifier.
- A renamed or migrated home folder makes the bookmark stale or unresolvable; the app reports
  it and asks for a fresh grant rather than guessing.
- Custom store locations outside the home folder stay unreadable under the sandbox, as before;
  absolute overrides inside the home folder now work once the grant exists.
- The DMG and the App Store build share this behaviour and version number; only signing and
  the upload path differ (ADR 0007).
- The first keychain consent dialog for the Claude Code item is unchanged.
- `FoundationSecurityScopedBookmarks` is the only code that touches the security-scope APIs. It
  is exercised by a round-trip test on a temporary folder; the scope start and stop calls are
  no-ops outside a sandbox, so their return value is not asserted.
