import AppKit
import SwiftUI

/// A terminal command the user must run themselves, with a one-click copy.
struct CopyableCommand: View {
    let command: String
    let identifier: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .accessibilityIdentifier(identifier)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy command")
            .accessibilityLabel(copied ? "Copied" : "Copy command")
            .accessibilityIdentifier("\(identifier).copy")
        }
    }
}
