# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Repository bootstrap: project rules, Architecture Decision Records 0001 to 0006, README,
  MIT license, contributing, security and code of conduct documents (#1).
- Scaffold: `UsageMonitorCore` Swift package with domain models, provider, credential, HTTP,
  keychain, file-system, settings and sleeper protocols, the `UsageMonitorModel` poll loop with
  per-provider backoff and diagnostics, log redaction, a thin SwiftUI menu bar app shell, XcodeGen
  project spec, SwiftLint configuration, coverage gate script and GitHub Actions CI (#1).
- Claude provider: reads the Claude Code keychain login and maps the OAuth usage endpoint's
  session, weekly and per-model windows.
- OpenAI provider: reads the Codex CLI login file and maps the ChatGPT usage endpoint's 5-hour
  and weekly windows plus per-model limits.
- Grok provider (experimental): reads the Grok Build CLI login file and maps the billing
  endpoint's weekly credit usage.
- Polling hardening: refresh on wake from sleep, reset-time formatting, redacted diagnostics
  report.
- App UI: onboarding, menu bar panel with usage bars, Settings with Accounts, Providers, Refresh
  and Diagnostics tabs, launch at login, XCUITest coverage.
- Repository hygiene: README refresh, pinned CI actions, UI-test and markdown-lint jobs,
  Dependabot for GitHub Actions, issue and pull request templates, CODEOWNERS.

[Unreleased]: https://github.com/jig21nesh/usage-monitor-app/commits/main
