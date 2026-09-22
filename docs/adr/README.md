# Architecture Decision Records

Numbered sequentially. Each record has Context, Decision and Consequences sections. Superseded
records are kept and link forward to their replacement.

| ADR | Title | Status | Summary |
|---|---|---|---|
| [0001](0001-thin-app-and-core-package-architecture.md) | Thin app target plus a testable Core Swift package | Accepted | All logic lives in `UsageMonitorCore` behind protocols with fakes; the app target holds scenes and views only |
| [0002](0002-reuse-official-cli-credentials-no-token-persistence.md) | Reuse the official CLIs' credentials; the app persists no tokens | Accepted | Read the vendor CLIs' logins, keep them in process memory only, never persist or refresh them; amended 2026-09-21 to cache between polls (re-read on expiry, 401 or Re-link) and to probe only enabled providers at start-up |
| [0003](0003-unofficial-usage-endpoints-and-terms-posture.md) | Unofficial usage endpoints and terms-of-service posture | Accepted | Read-only requests to undocumented usage endpoints with vendor-style headers, backoff and an explicit unofficial notice; amended 2026-09-20 for POST reads, key-minting endpoints and poll floors |
| [0004](0004-app-sandbox-with-read-only-exceptions.md) | App Sandbox on with read-only exceptions, Hardened Runtime on | Amended by 0009 | Sandbox verified by spike: home-relative read-only file exceptions plus normal keychain access; the exceptions were replaced by a user grant on 2026-09-22 |
| [0005](0005-swift-testing-and-coverage-gate.md) | Swift Testing with a 90% coverage gate on Core | Accepted | Swift Testing for Core, gate enforced in CI, SwiftUI view bodies covered by XCUITest instead |
| [0006](0006-local-only-observability.md) | Local-only observability | Accepted | Unified logging, signposts and in-app counters; no telemetry leaves the Mac |
| [0007](0007-distribution-signing-and-releases.md) | Distribution as a DMG, signed and notarised when credentials exist | Accepted | `scripts/build-dmg.sh` signs with Developer ID and notarises when credentials exist, clearly labelled ad-hoc DMG otherwise; amended 2026-09-22: `scripts/release.sh` builds, tags and publishes from the maintainer's Mac, no release workflow |
| [0008](0008-additional-providers-and-menu-bar-status.md) | Four more providers and a colour-coded menu bar status | Accepted | GitHub Copilot, Cursor, Muse Code and OpenCode Go under the credential-reuse rule; menu bar tinted by a tracked provider's session limit |
| [0009](0009-user-granted-home-folder-access.md) | User-granted home folder access instead of sandbox temporary exceptions | Accepted | The user grants the home folder once in the open panel; a read-only security-scoped bookmark replaces seven temporary-exception entitlements, identically for the DMG and the App Store build |
| [0010](0010-mac-app-store-distribution.md) | Mac App Store distribution alongside the GitHub DMG | Accepted | `scripts/build-appstore.sh` archives and exports with the Apple Distribution and Mac Installer Distribution certificates held on the maintainer's Mac, from the same commit as the DMG; store version equals the GitHub tag; DMG stays the primary download |
| [0011](0011-build-time-publisher-branding.md) | Publisher branding comes from build settings | Accepted | The About window reads maker, tagline, website, copyright holder and logo from Info.plist keys fed by build settings; the open-source defaults are committed, a git-ignored xcconfig and asset catalog brand the App Store build |

## Writing a new record

1. Copy the structure of an existing record: title, `Date`, `Status`, then Context, Decision,
   Consequences.
2. Number it with the next free four-digit prefix and a kebab-case slug.
3. Add a row to the table above.
4. Land it in the same pull request as the change it documents.
