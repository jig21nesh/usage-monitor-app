## Summary

<!-- What changes and where. One paragraph or a short list. -->

## Why

<!-- The problem or request this addresses. Link the issue if there is one. -->

## Test evidence

<!-- Paste the relevant lines, for example:
swift test: N tests in M suites passed
scripts/coverage-gate.sh: TOTAL line coverage (UsageMonitorCore): NN.NN% (threshold 90%)
swiftlint lint --strict: 0 violations
xcodebuild test (UsageMonitor scheme): TEST SUCCEEDED
-->

## ADR and README

- [ ] No new pattern, integration, data model or trade-off, so no ADR needed
- [ ] ADR added or updated: `docs/adr/NNNN-...`
- [ ] README updated (public behaviour, configuration, platforms or architecture changed)
- [ ] README not affected

## Security checklist

- [ ] No credential is persisted, logged or transmitted anywhere new
- [ ] Input from files, environment and HTTP is validated at the boundary
- [ ] New failure paths have tests

## Follow-ups

<!-- Anything deliberately left out, with an issue link if it should be tracked. -->
