# ADR 0013: Menu bar percentage and reset details

Date: 2026-11-04
Status: Implemented; review pending

## Context

Users need a numeric reading without opening the panel, exact scheduled reset times, and details
of extra/manual resets. Scheduled resets and earned reset entitlements are different data.

[Codex App Server documentation](https://learn.chatgpt.com/docs/app-server) confirms optional earned
reset counts. The backend client at revision `93b4e5b4c6474cdbf12614c4ac3acbd006fbee89` reads
`rate_limit_reset_credits.available_count` alongside the existing `wham/usage` response:
[wire types](https://github.com/openai/codex/blob/93b4e5b4c6474cdbf12614c4ac3acbd006fbee89/codex-rs/backend-client/src/types.rs),
[client](https://github.com/openai/codex/blob/93b4e5b4c6474cdbf12614c4ac3acbd006fbee89/codex-rs/backend-client/src/client/rate_limit_resets.rs).
[Claude's reset guide](https://support.claude.com/en/articles/17007452-what-is-a-limit-reset) confirms
manual offers in its web/desktop Usage page; it does not document a count in the CLI OAuth usage
response. No such field was verified for this implementation.

## Decision

- Add an optional percentage beside the gauge, on by default including migrated settings. It
  uses the existing provider/window selection and used/remaining preference. Unknown usage is
  `—`; stale usage retains its value with `*`, explained in the tooltip and Settings.
- Show the selected window's countdown and exact local reset time in the menu bar tooltip.
  Each panel row shows both too. Panel timelines update every minute without new vendor requests.
  The menu bar label is a static SwiftUI Label and updates with usage/settings changes: a
  TimelineView inside MenuBarExtra caused an invalidation loop during macOS 27 launch testing.
  Expired timestamps say "Resets soon"; only a successful poll can change usage.
- Add an optional nonnegative `availableResetCount` to `UsageSnapshot`. Nil means unreported,
  zero means explicitly none. Older snapshots still decode; malformed optional reset metadata
  must not prevent otherwise valid OpenAI usage from rendering.
- Map the verified OpenAI field from the existing GET. Show the count with a last-known label
  when stale. Show "not reported" for unknown counts, including Claude, with a link to the
  provider's own usage page. Omit reset-count rows for the other providers.
- Keep the monitor read-only. Do not fetch browser cookies, add requests, launch an app server
  that may refresh credentials, redeem resets, or infer a count from paid credit balances.

## Consequences

The menu bar uses more space, with an icon-only setting available. All accounts retain their
existing provider preferences. OpenAI reset counts are account-dependent and optional; Claude's
count remains unavailable until a compatible read-only source is verified. A count alone does
not provide entitlement expiry dates or guarantee that a reset applies to a particular window.
