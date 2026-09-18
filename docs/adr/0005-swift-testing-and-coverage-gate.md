# ADR 0005: Swift Testing with a 90% coverage gate on Core

Date: 2026-09-19
Status: Accepted

## Context

The project requires close to 90% test coverage. Xcode 26 ships Swift Testing alongside XCTest.
Coverage can be gathered by `swift test --enable-code-coverage` (llvm-cov JSON) for packages and
by `xcodebuild test -enableCodeCoverage YES` plus `xccov` for app targets. SwiftUI view bodies
are only unit-testable via ViewInspector, a third-party dependency with no explicit macOS 26/27
support statement.

## Decision

- Core is tested with Swift Testing (`@Test`, `#expect`, `#require`, parameterised suites).
- `scripts/coverage-gate.sh` runs the package tests with coverage and fails when line coverage
  on `UsageMonitorCore` is below 90%. CI runs it on every pull request.
- The app target's SwiftUI view bodies are excluded from the numeric gate and covered by an
  XCUITest smoke suite (`UITests/`) that launches the app, opens the menu bar extra window and
  the Settings window.
- No ViewInspector dependency. Views stay thin; anything with a branch moves into Core.
- Every provider ships fixtures for the happy path, missing optional fields, malformed JSON, an
  oversized body, and 401/403/429/5xx. Security cases (path handling for `CODEX_HOME` and
  `GROK_HOME`, token redaction in logs, no secrets in `UserDefaults`, malformed JWT segments) are
  mandatory, not optional.
- Time and sleep are injected so no test depends on wall-clock timing.

## Consequences

- The 90% figure applies to Core, where all logic lives. Anyone adding logic to `App/` to dodge
  the gate is violating ADR 0001.
- Package tests need no code signing, so contributors and CI can run them on any Mac with
  Xcode 26.
