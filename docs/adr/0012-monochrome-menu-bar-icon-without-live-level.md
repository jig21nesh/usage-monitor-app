# ADR 0012: Monochrome menu bar icon without a live level

Date: 2026-10-03
Status: Accepted; supersedes the grey unknown and stale icon in ADR 0008

## Context

ADR 0008 tints the menu bar gauge green, orange or red by threshold and grey when the tracked
provider is unknown or stale. The grey was the secondary label colour, and a tinted image is not
a template image, so the system draws it as given. Secondary label colour is translucent, and over
the translucent macOS 26 menu bar the gauge almost disappears.

A fresh install has no vendor logins, so the status is unknown from launch and the colour option
is on by default. App Review's screenshot of build 0.2.1 (100) showed exactly that: every other
status item at full contrast and ours barely visible.

Options:

1. Keep a tint for unknown and stale, but pick an opaque colour. Any fixed colour fights some
   wallpaper or appearance, and a solid grey still reads as disabled.
2. Turn the colour option off by default. Users who want colour lose it until they find the
   switch, and the problem returns as soon as they turn it on and lose a login.
3. Tint only when there is a live threshold reading; otherwise draw the template image.

## Decision

Option 3. `MenuBarStatus.hasLiveLevel` is true only for an ok, warning or critical level that is
not stale. The renderer applies a tint only when the colour option is on and that property is
true; in every other case it returns the template image, which the system draws in the menu
bar's own label colour.

## Consequences

- The icon is always fully visible, including on first launch and in App Review.
- In colour mode a stale or unknown reading looks the same as the monochrome option. The needle
  still shows the last known level, the panel shows the stale badge and the accessibility label
  says "stale", so the information is still available, just not by colour.
- The decision lives in Core and is unit tested; the app only reads it.
