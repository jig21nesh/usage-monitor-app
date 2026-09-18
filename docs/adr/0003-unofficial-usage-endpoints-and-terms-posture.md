# ADR 0003: Unofficial usage endpoints and terms-of-service posture

Date: 2026-09-19
Status: Accepted

## Context

The only sources for subscription usage are undocumented endpoints:

| Vendor | Endpoint | Notes |
|---|---|---|
| Claude | `GET https://api.anthropic.com/api/oauth/usage` | Needs `anthropic-beta: oauth-2025-04-20` and a Claude-Code-style `User-Agent`; other user agents fall into a bucket that returns persistent 429s. Response carries `five_hour`, `seven_day` and a `limits[]` array with per-model weekly windows. |
| OpenAI | `GET https://chatgpt.com/backend-api/wham/usage` | Needs `Authorization: Bearer` and `ChatGPT-Account-Id`. Windows must be classified by `limit_window_seconds` (18000 = 5 h, 604800 = week), never by position. Codex CLI itself polls it every 60 s. |
| Grok | `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` | Needs `Authorization: Bearer` and `X-XAI-Token-Auth: xai-grok-cli`. Used by xAI's open-source Grok Build CLI. Percent only; zero-valued scalars are omitted from the JSON. Chat routes already enforce a 426 client-version gate. |

All three vendors' consumer terms contain clauses against automated access. No enforcement
against read-only usage monitors has been observed, while enforcement against third-party
inference on subscription tokens has. The official alternatives (Admin usage APIs) cover
pay-as-you-go API keys, not subscriptions, and Claude Code's status-line JSON only updates during
an active Claude Code session.

## Decision

- Use the three endpoints above, read-only, with the user's own token, at the user's chosen
  interval (default 2 minutes, minimum 1 minute).
- Never call inference endpoints and never read rate-limit headers off inference responses.
- Send the vendor-style headers each endpoint is known to require. Apply exponential backoff
  (3, 6, 12, 15 minutes) on 429 and 5xx, honour `Retry-After` when present, and treat 426 as
  "client outdated" rather than retrying.
- Each provider is an isolated adapter with recorded JSON fixtures, so endpoint drift breaks one
  adapter and its tests, not the app.
- Grok is labelled "experimental" in the UI and README.
- The README and the onboarding screen state plainly that these endpoints are unofficial and
  that use is at the user's discretion.

## Consequences

- Any vendor may change or close an endpoint without notice. The app degrades to "unavailable"
  for that provider and keeps showing the last successful snapshot marked stale.
- Polling below roughly 3 minutes on Claude may trip its rate-limit bucket; the scaffold spike
  measures this and the Claude adapter clamps its interval if needed.
- The maintainers accept the terms-of-service grey area on behalf of the project but not on
  behalf of users; users opt in per provider.
