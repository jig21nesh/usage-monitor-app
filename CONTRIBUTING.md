# Contributing

Thanks for your interest in AI Usage Monitor. This document explains how to set up a
development environment, the conventions the project follows, and how changes are reviewed.

## Prerequisites

- macOS 26 or later (macOS 27 is supported).
- Xcode 26.6 or later.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) and [SwiftLint](https://github.com/realm/SwiftLint):
  `brew install xcodegen swiftlint`.

## Set up

```sh
git clone https://github.com/jig21nesh/usage-monitor-app.git
cd usage-monitor-app
cp Config/Local.xcconfig.example Config/Local.xcconfig   # set your DEVELOPMENT_TEAM
scripts/bootstrap.sh                                      # generates UsageMonitor.xcodeproj
open UsageMonitor.xcodeproj
```

The Core package does not need signing:

```sh
swift test --package-path Packages/UsageMonitorCore --enable-code-coverage
scripts/coverage-gate.sh
```

## Workflow

1. Open an issue describing the change first for anything larger than a typo.
2. Branch from `main`: `feat/...`, `fix/...`, `chore/...`, `refactor/...`.
3. Keep pull requests small and focused. Include a summary, the reason for the change, and test
   evidence.
4. Write or update an Architecture Decision Record in `docs/adr/` for any new pattern,
   integration, data model or significant trade-off.
5. Update `README.md` when the change affects anything a user needs to know.

## Standards

- Swift 6 language mode with strict concurrency. Warnings are errors for both the app target
  (`SWIFT_TREAT_WARNINGS_AS_ERRORS`) and the Core package (`scripts/coverage-gate.sh` passes
  `-warnings-as-errors`).
- SwiftLint must pass: `swiftlint lint --strict`.
- Tests use Swift Testing. Coverage on `UsageMonitorCore` must stay at or above 90%.
- Never persist, log or transmit a vendor credential. See `docs/adr/0002` and `SECURITY.md`.
- Commit messages: imperative mood, under 72 characters (`add grok provider`, not
  `Added grok provider`).

## Adding a provider

Create `Packages/UsageMonitorCore/Sources/UsageMonitorCore/Providers/<Vendor>/` containing a
`CredentialSource`, a client that performs one read-only request through `HTTPClient`, and a
pure mapper from `Data` to `UsageSnapshot`. Add JSON fixtures under the test target covering the
cases listed in `docs/adr/0005`. Register the provider in `ProviderRegistry.live`.

## Code of conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md). By participating you agree to
uphold it.
