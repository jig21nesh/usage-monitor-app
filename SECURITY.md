# Security Policy

## Supported versions

Only the latest release on the `main` branch receives security fixes.

## Reporting a vulnerability

Please do not open a public issue for security problems. Use GitHub's private vulnerability
reporting on this repository ("Security" tab, "Report a vulnerability"). You will receive an
acknowledgement within 72 hours and a fix or mitigation plan within 14 days for confirmed
issues.

## Security model

- The app reads credentials that Claude Code, Codex CLI and Grok Build CLI already store on the
  Mac. It reads them at poll time, keeps them in memory for one request, and never writes them
  anywhere. See `docs/adr/0002`.
- The app never refreshes, rotates or shares a vendor token, and never calls inference
  endpoints. See `docs/adr/0003`.
- Network access is outbound HTTPS only, under App Transport Security, with response bodies
  capped at 1 MB.
- The app runs with Hardened Runtime and, where the platform allows, App Sandbox with read-only
  exceptions for the two credential files. See `docs/adr/0004`.
- Logs and diagnostics are redacted at source; no telemetry leaves the machine. See
  `docs/adr/0006`.

## Dependency policy

The app has no runtime third-party dependencies. Development tools (XcodeGen, SwiftLint) are
pinned in CI. Any Dependabot or GitHub security alert is treated as technical debt to be
resolved in the next release; exceptions are documented here with severity, mitigation, owner and
review date.

No exceptions are currently recorded.
