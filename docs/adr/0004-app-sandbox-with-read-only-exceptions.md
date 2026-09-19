# ADR 0004: App Sandbox on with read-only exceptions, Hardened Runtime on

Date: 2026-09-19
Status: Accepted

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

Adopt option 2: App Sandbox on, Hardened Runtime on, outbound network only, read-only
home-relative exceptions for the two credential files.

Evidence (spike run 2026-09-19 on macOS 27.0 with Xcode 26.6, sandboxed Debug build executed
directly with `USAGE_MONITOR_SPIKE=1`):

```
home=/Users/<user>/ container=/Users/<user>/Library/Containers/com.curiouspilabs.UsageMonitor/Data
file=codex ok bytes=3968
file=grok ok bytes=1629
keychain ok present=true bytes=524
```

- `NSHomeDirectory()` returned the container while `getpwuid` returned the real home, confirming
  the sandbox was active and the resolver in `UserEnvironment` is required.
- Both auth files were readable through the temporary-exception entitlement.
- `SecItemCopyMatching` returned the Claude Code item with interaction disallowed and no consent
  dialog on this machine. Other machines may still show the standard keychain consent dialog
  depending on the item's access control list; onboarding keeps explaining it.

## Consequences

- Custom `CODEX_HOME` or `GROK_HOME` locations cannot be read under the sandbox; the app reports
  "not linked" with an explanation.
- Hardened Runtime is enabled in both options; no JIT, no unsigned memory, no library
  validation exceptions.
- Distribution outside the App Store still requires Developer ID signing and notarisation,
  which are out of scope for the first release.
