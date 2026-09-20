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
            Text("Made by Curious Pi Labs")
                .font(.headline)
                .accessibilityIdentifier("about.maker")
            Image("CuriousPiLabsMark")
                .resizable()
                .scaledToFit()
                .frame(height: 56)
                .accessibilityLabel("Curious Pi Labs logo")
            Text(AboutInfo.tagline)
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

/// Static About copy in one place so the window and the tests agree.
enum AboutInfo {
    struct Link: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let url: URL
    }

    static let summary = "Menu bar usage limits for Claude, OpenAI, Grok, GitHub Copilot, Cursor, "
        + "Muse Code and OpenCode Go."

    static let tagline = "Curious Pi Labs builds products with curiosity, precision, and rigor. "
        + "Every product is tested, measured, and proven before it ships."

    static let legal = "Copyright © 2026 Curious Pi Labs. Released under the MIT License. "
        + "Claude, ChatGPT, Codex, Grok, GitHub Copilot, Cursor and Muse are trademarks of their "
        + "respective owners; this project is not affiliated with or endorsed by them."

    static let repository = "https://github.com/jig21nesh/usage-monitor-app"

    static let links: [Link] = [
        Link(id: "website", title: "Website", symbol: "globe", url: url("https://curiouspilabs.com")),
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

    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(short) (\(build))"
    }
}
