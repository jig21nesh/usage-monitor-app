# ADR 0002: Reuse the official CLIs' credentials; the app persists no tokens

Date: 2026-09-19
Status: Accepted

## Context

None of Anthropic, OpenAI or xAI publishes an API for consumer subscription usage limits. The
data shown on claude.ai, chatgpt.com/codex and grok.com is served by undocumented endpoints that
require the user's own OAuth token. Three ways to obtain such a token were evaluated:

1. **Reuse the credentials the vendors' own CLIs already store on the Mac.** Claude Code keeps a
   Keychain generic password (service `Claude Code-credentials`), Codex CLI writes
   `~/.codex/auth.json`, and Grok Build CLI writes `~/.grok/auth.json`. Each CLI refreshes its
   own token.
2. **Run our own OAuth PKCE flow** using the vendors' public client ids. This impersonates a
   native vendor app. Anthropic's Claude Code legal page reserves OAuth for "Claude Code and other
   native Anthropic applications"; OpenAI has declined to bless third-party use of the Codex
   client id; xAI has no third-party sign-in programme.
3. **Embedded web login** (WKWebView) and harvesting session cookies. Anthropic's policy states
   developers "may not collect, store, or intermediate Claude.ai credentials or session tokens".
   Cloudflare bot protection breaks it intermittently for OpenAI, and grok.com's weekly-usage
   endpoint has required a browser-held key pair since August 2026.

Every maintained open-source usage monitor (CodexBar, CCSeva, claude-usage-bar, codex-usage-tracker,
Hermes) converged on option 1.

## Decision

Adopt option 1 exclusively.

- "Sign in" in the app means "link the credentials already on this Mac". Onboarding detects each
  CLI login and explains how to install or log in to the CLI when it is missing.
- For Claude, the `CLAUDE_CODE_OAUTH_TOKEN` environment variable is accepted as a fallback when
  no keychain item exists, matching Claude Code's own precedence. It is read, never written.
- Credentials are read at poll time and held in memory for the duration of one request. The app
  never writes a vendor token, cookie or refresh token anywhere: not to Keychain, not to
  `UserDefaults`, not to disk, not to logs.
- The app never refreshes or rotates a vendor token. Claude and Grok rotate refresh tokens, and
  rotating from a second process logs the CLI out. On 401 the app re-reads the store once and,
  if that fails, marks the provider "re-link needed".
- Only the fields needed for display are decoded from credential stores (token, account id,
  plan type). Identity JWTs are decoded for claims only; signatures are not verified because the
  app does not rely on them for any security decision.
- Under App Sandbox the real home directory is resolved with `getpwuid`, because
  `NSHomeDirectory()` returns the container path.

If a future feature genuinely needs the app to persist a secret, it must use the data-protection
Keychain (`kSecUseDataProtectionKeychain`) with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`,
wrapped with a Secure Enclave key via CryptoKit, and this ADR must be superseded.

## Consequences

- Users must have the vendor CLI installed and logged in. Codex "keyring" credential storage
  leaves no `auth.json` and is reported as "not linked" in this version.
- The first Keychain read of the Claude Code item triggers a macOS consent dialog; the user
  should choose "Always Allow". Onboarding explains this.
- Token expiry is surfaced as "re-link needed" with instructions to run the CLI login command.
- Grok Build access tokens last about six hours and the CLI refreshes them only when it runs
  (observed 2026-09-19: a token issued at login expired six hours later; `grok models` refreshed
  it). Grok therefore reads "re-link needed" whenever the CLI has been idle, which is accepted
  rather than adding a second refresher that would rotate the CLI's refresh token.
- Threat surface is limited to read-only access to three files or Keychain items that the user
  already trusts those CLIs with.

## Amendment 2026-09-21: credentials cached in process memory

"Read at poll time, hold for one request" produced far more keychain consent dialogs than the
consequences above anticipated:

- A locally built app is ad-hoc signed, so macOS ties **Always Allow** to that build's code hash
  and asks again after every rebuild.
- With a one-shot **Allow**, every poll re-read the Claude Code item, so the dialog came back at
  each refresh interval.
- Start-up probed the link state of every provider, so the GitHub CLI item was read even while
  Copilot was switched off.

Decision:

- Every live provider wraps its source in `CachedCredentialSource`, which keeps the last
  credential in process memory and reads the store again only when the credential is within
  60 seconds of its own expiry, after the vendor rejects it (401 or 403) or the source reports it
  expired, when the user presses **Re-link** or **Re-check**, or after the app restarts. Errors are
  never cached. The credential still never touches disk, `UserDefaults`, the keychain or the log;
  only the miss and its reason (`cold`, `expired`, `forgotten`) are logged.
- Start-up probes the link state of enabled providers only. Onboarding and Settings > Accounts
  still probe every provider when they open, because that is where the user is looking at the
  answer.
- Builds for the developer's own Mac are signed with an Apple Development identity
  (`SIGNING_IDENTITY="Apple Development: …" scripts/build-dmg.sh --no-notarize`). The code
  requirement is then the bundle identifier plus the team, stable across rebuilds, so one
  **Always Allow** lasts. Public releases still follow ADR 0007.

Consequences:

- With **Allow**, at most one dialog per keychain item per launch; with **Always Allow** on a
  build whose signature is stable, none.
- A token revoked by a CLI re-login is noticed at the next poll (401), dropped, and re-read on the
  poll after that: one failed poll, then recovery. This is the "re-read once" rule above,
  implemented as a cache drop.
- Tokens without an expiry (GitHub CLI) stay cached for the life of the process; only a 401,
  **Re-link** or a restart re-reads them.
- `CredentialSource` no longer forbids holding a credential between calls; it forbids writing it
  anywhere and refreshing it.
