# ADR 0008: Four more providers and a colour-coded menu bar status

Date: 2026-09-20
Status: Accepted

## Context

The maintainer asked for more providers ("Cursor, Muse and others") and for the menu bar icon to
signal the session limit by colour for a provider of the user's choosing. A survey of twenty
candidates under ADR 0002's rule (reuse the vendor CLI's stored login, one read-only request,
no refresh, no browser) ranked feasibility. Google's Gemini CLI and Antigravity fail the rule
(consumer OAuth withdrawn in June 2026; one-hour tokens refreshed only in memory); z.ai,
MiniMax and Kimi only expose an API key that sits in another agent's configuration; Windsurf,
Perplexity and Augment are browser-cookie only.

## Decision

Add, in this order of confidence:

| Provider | Credential source | Request | Windows |
|---|---|---|---|
| GitHub Copilot | Keychain `gh:github.com`, else `~/.config/gh/hosts.yml`, else keychain `copilot-cli` / `~/.copilot/config.json` | `GET api.github.com/copilot_internal/user` | Monthly premium requests (plus chat and completions when metered), reset from `quota_reset_date_utc` |
| Cursor | `cursorAuth/accessToken` in Cursor's SQLite store (read-only), else keychain `cursor-access-token`, else `~/.cursor/auth.json`; tokens within 60 s of expiry are ignored | `POST api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage` | Monthly included usage against the plan limit, reset at billing-cycle end |
| Muse Code (Meta) | `~/.config/muse/auth.json`, else keychain `ai.meta.dev.credentials`; only `dca:` tokens | `POST api.meta.ai/muse-code/key` with `x-api-version: 1.0.0`, 15-minute poll floor | 5-hour and weekly windows; the returned API key is discarded |
| OpenCode Go | `~/.local/share/opencode/auth.json` | `GET opencode.ai/zen/go/v1/usage` | Rolling 5-hour, weekly and monthly |

Cursor and Muse Code are labelled experimental. The sandbox gains read-only exceptions for the
new paths; Cursor's exception covers its `globalStorage` directory because SQLite needs the
write-ahead-log files beside the database.

Defaults change: a fresh install enables Claude, OpenAI and Grok; onboarding then enables the
providers whose login it detects and leaves the rest off, so a user with two tools does not see
five "not linked" cards.

Menu bar status: the icon keeps its gauge needle (level is readable without colour) and is
tinted green below 60% used, orange from 60%, red from 80%, grey when unknown or stale.
Thresholds live in settings. The tracked provider is the user's choice; when none is chosen the
single enabled provider is used, otherwise the enabled provider whose session window is
fullest. Because the tint means the image is no longer a template image, a settings switch
restores the monochrome icon for users who prefer the system look. The resolver is pure Core
code (`MenuBarStatusResolver`) with unit tests; the app only renders its result.

## Consequences

- Seven providers means the onboarding and Providers tab scroll; the panel shows only enabled
  ones.
- Muse Code's key-minting endpoint is the least understood: the poll floor and the discard rule
  are the mitigations, and the provider stays experimental until a live subscription confirms
  polling tolerance.
- Copilot's endpoint is VS Code-internal and has been stable for years; Cursor's dashboard RPC
  has changed field semantics before, so both keep fixtures and lenient decoding.
