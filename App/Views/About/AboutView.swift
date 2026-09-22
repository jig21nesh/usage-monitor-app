import AppKit
import SwiftUI
import UsageMonitorCore

/// About window: what the app is, who made it, and where the source and licence live.
struct AboutView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            appIdentity
            Divider()
            makerBlock
            Divider()
            links
            footer
        }
        .padding(28)
        .frame(width: 460)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("about.window")
    }

    private var appIdentity: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("AI Usage Monitor")
                .font(.title.weight(.semibold))
                .accessibilityIdentifier("about.name")
            Text(AboutInfo.versionText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("about.version")
            Text(AboutInfo.summary)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var makerBlock: some View {
        VStack(spacing: 10) {
            Text(AboutInfo.makerLine)
                .font(.headline)
                .accessibilityIdentifier("about.maker")
            if let logo = AboutInfo.logoImage {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 56)
                    .accessibilityLabel("\(AboutInfo.branding.makerName) logo")
                    .accessibilityIdentifier("about.logo")
            }
            Text(AboutInfo.branding.tagline)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("about.tagline")
        }
    }

    private var links: some View {
        HStack(spacing: 10) {
            ForEach(AboutInfo.links) { link in
                Button {
                    openURL(link.url)
                } label: {
                    Label(link.title, systemImage: link.symbol)
                }
                .accessibilityIdentifier("about.\(link.id)")
            }
        }
        .controlSize(.regular)
    }

    private var footer: some View {
        Text(AboutInfo.legal)
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("about.legal")
    }
}

/// Who publishes this build. The values come from Info.plist keys that build settings fill in
/// (ADR 0011), so each distribution channel can present its publisher without a code change;
/// a bundle without the keys shows the open-source defaults below.
struct AboutBranding: Equatable {
    var makerName: String
    var tagline: String
    var websiteURL: URL
    var copyrightHolder: String
    /// Asset catalog image shown under the maker line; empty means no logo.
    var logoAssetName: String

    static let defaults = AboutBranding(
        makerName: "Jiggy Kakkad",
        tagline: "Principal AI Engineer in Sydney, Australia. I build AI systems for production.",
        websiteURL: URL(string: "https://jiggykakkad.com")!,
        copyrightHolder: "Jiggy Kakkad",
        logoAssetName: ""
    )

    /// Info.plist values win over the defaults; blank values are treated as absent so an empty
    /// build setting cannot blank out the window. Launch-option overrides exist only in Debug
    /// builds so the UI tests can exercise this path without a branded build.
    static func load(info: [String: Any]?, options: LaunchOptions) -> AboutBranding {
        func value(_ key: String) -> String? {
            let raw = (info?[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.flatMap { $0.isEmpty ? nil : $0 }
        }
        var branding = defaults
        if let name = value("UMBrandMakerName") { branding.makerName = name }
        if let tagline = value("UMBrandTagline") { branding.tagline = tagline }
        if let url = value("UMBrandWebsiteURL").flatMap(URL.init(string:)), url.scheme?.hasPrefix("http") == true {
            branding.websiteURL = url
        }
        if let holder = value("UMBrandCopyrightHolder") { branding.copyrightHolder = holder }
        if let asset = value("UMBrandLogoAsset") { branding.logoAssetName = asset }

        if let name = options.brandMakerName { branding.makerName = name }
        if let tagline = options.brandTagline { branding.tagline = tagline }
        if let url = options.brandWebsiteURL.flatMap(URL.init(string:)), url.scheme?.hasPrefix("http") == true {
            branding.websiteURL = url
        }
        if let holder = options.brandCopyrightHolder { branding.copyrightHolder = holder }
        return branding
    }
}

/// Static About copy in one place so the window and the tests agree.
enum AboutInfo {
    struct Link: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let url: URL
    }

    static let branding = AboutBranding.load(info: Bundle.main.infoDictionary, options: AppComposition.launchOptions)

    static let summary = "Menu bar usage limits for Claude, OpenAI, Grok, GitHub Copilot, Cursor, "
        + "Muse Code and OpenCode Go."

    static var makerLine: String { "Made by \(branding.makerName)" }

    static var legal: String {
        "Copyright © 2026 \(branding.copyrightHolder). Released under the MIT License. "
            + "Claude, ChatGPT, Codex, Grok, GitHub Copilot, Cursor and Muse are trademarks of their "
            + "respective owners; this project is not affiliated with or endorsed by them."
    }

    /// Nil when no logo asset is configured or the named image is not in the bundle, so a typo
    /// in the setting degrades to the plain layout instead of a blank frame.
    static var logoImage: NSImage? {
        guard !branding.logoAssetName.isEmpty else { return nil }
        return NSImage(named: NSImage.Name(branding.logoAssetName))
    }

    static let repository = "https://github.com/jig21nesh/usage-monitor-app"

    static let links: [Link] = [
        Link(id: "website", title: "Website", symbol: "globe", url: branding.websiteURL),
        Link(id: "github", title: "Source on GitHub", symbol: "chevron.left.forwardslash.chevron.right",
             url: url(repository)),
        Link(id: "issues", title: "Report an issue", symbol: "ladybug",
             url: url("\(repository)/issues/new/choose")),
        Link(id: "license", title: "Licence: MIT", symbol: "doc.text",
             url: url("\(repository)/blob/main/LICENSE")),
    ]

    /// The strings above are compile-time constants; a malformed one is a programming error.
    private static func url(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("invalid About link: \(string)")
        }
        return url
    }

    /// Marketing version only; the build number lives in Settings > Diagnostics where bug
    /// reports need it.
    static var versionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return "Version \(short)"
    }
}
