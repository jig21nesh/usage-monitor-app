# ADR 0011: Publisher branding comes from build settings

Date: 2026-09-22
Status: Accepted

## Context

The app ships through two channels with two identities. The open-source build on GitHub is
published by the maintainer personally: the About window names the maintainer, links to the
maintainer's website and carries the maintainer's copyright line. The Mac App Store build is
published by the maintainer's company, and the store listing, the About window and the
copyright line must name that company instead.

Until now the About window's maker line, tagline, website link, copyright holder and logo were
constants in `App/Views/About/AboutView.swift`. Presenting a different publisher meant either
committing the company's name, logo and URL to the public repository, which the maintainer does
not want, or maintaining a second branch of the code, which would drift.

Options:

1. **Two branches or a fork per channel.** Rejected: every change would be made twice and the
   builds would drift.
2. **A compile-time flag with both identities in the source.** Rejected: the company identity
   would still be committed.
3. **Read the publisher details at runtime from the bundle's Info.plist, fed by build settings
   whose committed defaults are the open-source identity.** The store build layers a
   git-ignored xcconfig over the project and an optional, git-ignored asset catalog for the
   logo. Nothing channel-specific enters the repository.

## Decision

Adopt option 3.

- Five build settings, defined in `project.yml` with the open-source defaults:
  `UM_BRAND_MAKER_NAME`, `UM_BRAND_TAGLINE`, `UM_BRAND_WEBSITE_URL`,
  `UM_BRAND_COPYRIGHT_HOLDER` and `UM_BRAND_LOGO_ASSET` (empty by default).
- The Info.plist carries them as `UMBrandMakerName`, `UMBrandTagline`, `UMBrandWebsiteURL`,
  `UMBrandCopyrightHolder` and `UMBrandLogoAsset`, and `NSHumanReadableCopyright` is built from
  the copyright holder.
- `AboutBranding` reads those keys with the defaults as fallback, ignores blank values and
  accepts only `http(s)` website URLs. The About window shows "Made by <name>", the tagline,
  the website link, "Copyright © 2026 <holder>. Released under the MIT License." plus the
  trademark sentence, and the logo only when the named image resolves in the bundle.
- `scripts/bootstrap.sh` generates the project from `Config/Branding/Branding.yml` when that
  file exists and from `project.yml` otherwise. The branding spec includes `project.yml` with
  `relativePaths: false` and adds `Config/Branding/BrandAssets.xcassets` to the app target, so
  the logo catalog reaches the build without a reference in the committed spec. (An
  `optional` source path in `project.yml` was tried first; XcodeGen keeps the dangling
  reference and the asset compiler warns on every open-source build.)
- `scripts/build-appstore.sh` passes `Config/Branding/AppStore.xcconfig` to `xcodebuild archive`
  when the file exists (`APP_STORE_BRANDING` overrides the path) and prints which branding it
  used. `Config/Branding/` is git-ignored.
- Debug builds accept `USAGE_MONITOR_BRAND_MAKER`, `USAGE_MONITOR_BRAND_TAGLINE`,
  `USAGE_MONITOR_BRAND_WEBSITE` and `USAGE_MONITOR_BRAND_HOLDER` as launch-environment
  overrides so one UI test exercises the path; Release builds ignore them.
- The store listing's own copyright and marketing URL fields are edited by hand in App Store
  Connect to match the branded build.

## Consequences

- The open-source build is unchanged: without the override file every value is the committed
  default, and the existing About UI test keeps passing untouched.
- The publisher identity for the store lives only on the release Mac, next to the signing
  material. A second release Mac needs a copy of `Config/Branding/`.
- Both channels still build from the same commit; only the xcconfig and the asset catalog
  differ, so a store build's behaviour is otherwise identical to the DMG of the same version.
- A wrong `UM_BRAND_LOGO_ASSET` degrades to the plain layout rather than an empty frame.
- The website URL in the About window and the marketing URL in the store listing are set in two
  places; the release guide lists both so they stay in step.
