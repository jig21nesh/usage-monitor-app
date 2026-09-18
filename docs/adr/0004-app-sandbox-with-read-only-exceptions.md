# ADR 0004: App Sandbox on with read-only exceptions, Hardened Runtime on

Date: 2026-09-19
Status: Proposed (to be confirmed by the scaffold spike)

## Context

ADR 0002 requires reading three credential stores owned by other programs: a login-keychain item
and two files under the user's home directory. App Sandbox confines file access to the app's
container unless entitlements grant more. Comparable apps (CodexBar) ship without the sandbox
for exactly this reason. Hardened Runtime is required for notarisation regardless.

Options:

1. **Sandbox off, Hardened Runtime on.** Simplest; matches peers; loses defence in depth.
2. **Sandbox on with `com.apple.security.temporary-exception.files.home-relative-path.read-only`
   for `/.codex/auth.json` and `/.grok/auth.json`, plus `network.client`.** Temporary-exception
   entitlements are only a problem for Mac App Store review, which this project does not target.
   Keychain reads from a sandboxed app go through the normal ACL consent dialog.

## Decision

Attempt option 2 first. The scaffold pull request includes a spike that builds the sandboxed app
and verifies (a) reading both files through the real home directory resolved with `getpwuid`,
and (b) `SecItemCopyMatching` reaching the Claude Code item (an `errSecInteractionNotAllowed`
result with UI suppressed proves the sandbox is not the blocker). If the spike fails, fall back
to option 1 and mark this ADR superseded with the evidence.

## Consequences

- Custom `CODEX_HOME` or `GROK_HOME` locations cannot be read under the sandbox; the app reports
  "not linked" with an explanation.
- Hardened Runtime is enabled in both options; no JIT, no unsigned memory, no library
  validation exceptions.
- Distribution outside the App Store still requires Developer ID signing and notarisation,
  which are out of scope for the first release.
