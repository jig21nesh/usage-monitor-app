# Architecture Decision Records

Numbered sequentially. Each record has Context, Decision and Consequences sections. Superseded
records are kept and link forward to their replacement.

| ADR | Title | Status | Summary |
|---|---|---|---|
| [0001](0001-thin-app-and-core-package-architecture.md) | Thin app target plus a testable Core Swift package | Accepted | All logic lives in `UsageMonitorCore` behind protocols with fakes; the app target holds scenes and views only |
| [0002](0002-reuse-official-cli-credentials-no-token-persistence.md) | Reuse the official CLIs' credentials; the app persists no tokens | Accepted | Read the vendor CLIs' logins, keep them in process memory only, never persist or refresh them; amended 2026-09-21 to cache between polls (re-read on expiry, 401 or Re-link) and to probe only enabled providers at start-up |
| [0003](0003-unofficial-usage-endpoints-and-terms-posture.md) | Unofficial usage endpoints and terms-of-service posture | Accepted | Read-only requests to undocumented usage endpoints with vendor-style headers, backoff and an explicit unofficial notice; amended 2026-09-20 for POST reads, key-minting endpoints and poll floors |
| [0004](0004-app-sandbox-with-read-only-exceptions.md) | App Sandbox on with read-only exceptions, Hardened Runtime on | Accepted | Sandbox verified by spike: two home-relative read-only file exceptions plus normal keychain access |
| [0005](0005-swift-testing-and-coverage-gate.md) | Swift Testing with a 90% coverage gate on Core | Accepted | Swift Testing for Core, gate enforced in CI, SwiftUI view bodies covered by XCUITest instead |
| [0006](0006-local-only-observability.md) | Local-only observability | Accepted | Unified logging, signposts and in-app counters; no telemetry leaves the Mac |
| [0007](0007-distribution-signing-and-releases.md) | Distribution as a DMG, signed and notarised when credentials exist | Accepted | One script and one tag-triggered workflow; Developer ID + notarisation when secrets exist, clearly labelled ad-hoc DMG otherwise |
| [0008](0008-additional-providers-and-menu-bar-status.md) | Four more providers and a colour-coded menu bar status | Accepted | GitHub Copilot, Cursor, Muse Code and OpenCode Go under the credential-reuse rule; menu bar tinted by a tracked provider's session limit |

## Writing a new record

1. Copy the structure of an existing record: title, `Date`, `Status`, then Context, Decision,
   Consequences.
2. Number it with the next free four-digit prefix and a kebab-case slug.
3. Add a row to the table above.
4. Land it in the same pull request as the change it documents.
