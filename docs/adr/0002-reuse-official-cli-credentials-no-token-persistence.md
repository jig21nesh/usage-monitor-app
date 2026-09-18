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
- Threat surface is limited to read-only access to three files or Keychain items that the user
  already trusts those CLIs with.
