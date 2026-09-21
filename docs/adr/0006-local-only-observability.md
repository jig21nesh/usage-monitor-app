# ADR 0006: Local-only observability

Date: 2026-09-19
Status: Accepted

## Context

The house rules ask every feature that calls an external system to ship structured logs,
metrics and trace spans, preferring OpenTelemetry. This app is a single-user desktop utility
whose only data is the user's own subscription usage. Exporting telemetry off the machine would
itself be a privacy regression and would require infrastructure the project does not have.

## Decision

- **Logs:** unified logging via `os.Logger(subsystem: "com.jiggykakkad.UsageMonitor",
  category:)` with structured key=value messages. Provider id, outcome, HTTP status and duration
  are `.public`; anything derived from a credential is never logged. Levels: debug for request
  detail, info for state transitions, error for failures.
- **Traces:** `OSSignposter` intervals around every network call and every poll cycle, visible in
  Instruments.
- **Metrics:** in-process counters per provider (polls, successes, failures by category, last
  success time, last duration) surfaced in a Diagnostics pane in Settings and exportable as a
  redacted text report for bug reports.
- **No network export** of any telemetry. This is a deliberate exception to the OpenTelemetry
  preference, recorded here.

## Consequences

- Debugging a user's report relies on the Diagnostics export and `log show` output, both of
  which are redacted at source.
- If the project ever adds opt-in crash reporting, it needs a new ADR and explicit user consent.
