import SwiftUI
import UsageMonitorCore

/// Grant state plus the Grant and Revoke buttons, shared by the Welcome window and Settings.
struct HomeFolderAccessControls: View {
    @Environment(UsageMonitorModel.self) private var model
    /// Prefix for accessibility identifiers, for example `onboarding.homeFolder`.
    let identifierPrefix: String
    var showsRevoke = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var picker: any HomeFolderPicking { AppComposition.homeFolderPicker }

    var body: some View {
        HStack(spacing: 10) {
            stateLabel
                .accessibilityIdentifier("\(identifierPrefix).state")
            Spacer()
            if isWorking {
                ProgressView().controlSize(.small)
            } else if model.homeFolderState.isGranted {
                if showsRevoke {
                    Button("Revoke") { revoke() }
                        .accessibilityIdentifier("\(identifierPrefix).revoke")
                }
            } else {
                Button("Grant Access…") { grant() }
                    .accessibilityIdentifier("\(identifierPrefix).grant")
            }
        }
        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier("\(identifierPrefix).error")
        }
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch model.homeFolderState {
        case .granted:
            Label("Granted · \(grantedPath)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .notGranted, .stale, .unavailable:
            Label(model.homeFolderState.userMessage, systemImage: "xmark.circle.fill")
                .foregroundStyle(.orange)
        }
    }

    /// Without the trailing slash `URL` adds to directories.
    private var grantedPath: String {
        let path = model.homeFolderDirectory.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func grant() {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            guard let folder = await picker.pickHomeFolder(expected: model.homeFolderDirectory) else { return }
            do throws(HomeFolderGrantError) {
                try await model.grantHomeFolder(folder)
            } catch {
                errorMessage = error.userMessage
            }
        }
    }

    private func revoke() {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            await model.revokeHomeFolder()
        }
    }
}
