# Privacy Policy for AI Usage Monitor

Effective date: 2026-09-22

AI Usage Monitor is published by Curious Pi Pty Ltd and maintained by Jiggy Kakkad
(<https://jiggykakkad.com>). It is an open-source macOS menu bar app that shows the usage limits of
AI coding subscriptions you already pay for.

## Summary

- The app collects nothing about you. There are no accounts, no analytics, no crash reporting, no
  advertising and no tracking of any kind.
- The developer and the publisher never receive any data from the app. Nothing it reads or shows
  ever leaves your Mac except the requests described below, which go to the vendors you already
  use, with your own login.

## What the app reads on your Mac

To show your usage, the app reuses the login that each vendor's own tool has already stored on
your Mac. Depending on which providers you switch on, that is:

- the Claude Code keychain item;
- the login files written by the Codex CLI, the Grok Build CLI, the GitHub CLI, the Copilot CLI,
  the Muse Code CLI and the OpenCode CLI, all inside your home folder;
- Cursor's keychain item or its local settings database.

These credentials are read only when a request is about to be made, are held in memory only, and
are never written anywhere by this app. The app never refreshes, rotates or changes them.

Reading them requires your consent. Keychain items are read through the standard macOS keychain
dialog, which you can decline. From version 0.2.0 the files in your home folder are read only
after you grant the app one-time, read-only access to that folder through the standard macOS
folder picker; you can revoke that access at any time in Settings. Without these consents the
matching provider simply shows as not linked.

## Where data goes

The app makes one read-only HTTPS request per enabled provider per refresh, at the interval you
choose (between one and fifteen minutes; Muse Code at most every fifteen minutes), to that
vendor's own usage endpoint:

| Provider | Host |
|---|---|
| Claude | `api.anthropic.com` |
| OpenAI (ChatGPT and Codex) | `chatgpt.com` |
| Grok | `cli-chat-proxy.grok.com` |
| GitHub Copilot | `api.github.com` |
| Cursor | `api2.cursor.sh` |
| Muse Code | `api.meta.ai` |
| OpenCode Go | `opencode.ai` |

Each request carries your own token for that vendor and asks only for usage figures. The app makes
no other network connections: no update checks, no telemetry, no requests to the developer, and
never a request to any AI model.

## What the app stores

The app stores only your settings: which providers are enabled, the refresh interval, launch at
login, the percentage style, the menu bar colour options and whether you have finished the welcome
screen. From version 0.2.0 it also stores the system bookmark that records your home folder grant.
Everything is kept in the app's own sandbox container on your Mac. Usage figures are shown from
memory and are not saved to disk. No credential, token, cookie or account identifier is ever
stored by the app.

## Logging and diagnostics

The app logs to the macOS unified logging system on your Mac only. Log entries contain provider
names, outcomes, HTTP status codes and timings, never tokens, cookies, response bodies or account
identifiers. The Diagnostics tab in Settings can copy a text report to your clipboard for bug
reports; it is produced only when you press the button, contains the same redacted information,
and is not sent anywhere by the app.

## Third-party services

When the app contacts a vendor with your login, that vendor's own privacy policy governs how the
vendor handles the request: [Anthropic](https://www.anthropic.com/privacy),
[OpenAI](https://openai.com/policies/privacy-policy), [xAI](https://x.ai/legal/privacy-policy),
[GitHub](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement),
[Cursor](https://cursor.com/privacy), [Meta](https://www.facebook.com/privacy/policy) and
OpenCode. This app shares nothing with any other party.

## Children

The app is not directed at children under 13 and does not collect personal information from
anyone.

## Changes to this policy

Changes are made to this file in the project's public repository, with the effective date
updated at the top. The history of every change is visible in the repository.

## Contact

Questions or concerns can be raised through the project's issue tracker:
<https://github.com/jig21nesh/usage-monitor-app/issues>.
