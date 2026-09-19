# Architecture Decision Records

Numbered sequentially. Each record has Context, Decision and Consequences sections. Superseded
records are kept and link forward to their replacement.

| ADR | Title | Status | Summary |
|---|---|---|---|
| [0001](0001-thin-app-and-core-package-architecture.md) | Thin app target plus a testable Core Swift package | Accepted | All logic lives in `UsageMonitorCore` behind protocols with fakes; the app target holds scenes and views only |
| [0002](0002-reuse-official-cli-credentials-no-token-persistence.md) | Reuse the official CLIs' credentials; the app persists no tokens | Accepted | Read Claude Code, Codex CLI and Grok Build CLI logins at poll time, keep them in memory only, never refresh them |
| [0003](0003-unofficial-usage-endpoints-and-terms-posture.md) | Unofficial usage endpoints and terms-of-service posture | Accepted | Read-only GETs to the three undocumented usage endpoints with vendor-style headers, backoff and an explicit unofficial notice |
| [0004](0004-app-sandbox-with-read-only-exceptions.md) | App Sandbox on with read-only exceptions, Hardened Runtime on | Accepted | Sandbox verified by spike: two home-relative read-only file exceptions plus normal keychain access |
| [0005](0005-swift-testing-and-coverage-gate.md) | Swift Testing with a 90% coverage gate on Core | Accepted | Swift Testing for Core, gate enforced in CI, SwiftUI view bodies covered by XCUITest instead |
| [0006](0006-local-only-observability.md) | Local-only observability | Accepted | Unified logging, signposts and in-app counters; no telemetry leaves the Mac |

## Writing a new record

1. Copy the structure of an existing record: title, `Date`, `Status`, then Context, Decision,
   Consequences.
2. Number it with the next free four-digit prefix and a kebab-case slug.
3. Add a row to the table above.
4. Land it in the same pull request as the change it documents.
