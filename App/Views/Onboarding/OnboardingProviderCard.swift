import SwiftUI
import UsageMonitorCore

struct OnboardingProviderCard: View {
    @Environment(UsageMonitorModel.self) private var model
    let status: ProviderStatus
    @State private var isChecking = false

    private var id: String { status.provider.rawValue }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: status.provider.symbolName)
                        .font(.title2)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(status.provider.displayName).font(.headline)
                            if status.provider.isExperimental { ExperimentalTag() }
                        }
                        LinkStateLabel(link: status.link)
                            .font(.callout)
                            .accessibilityIdentifier("onboarding.provider.\(id).state")
                    }
                    Spacer()
                    Toggle("Show", isOn: enabledBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityLabel("Show \(status.provider.displayName)")
                        .accessibilityIdentifier("onboarding.provider.\(id).toggle")
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    CopyableCommand(
                        command: status.provider.loginCommand,
                        identifier: "onboarding.provider.\(id).command"
                    )
                    Spacer()
                    Button {
                        isChecking = true
                        Task {
                            await model.relink(status.provider)
                            isChecking = false
                        }
                    } label: {
                        if isChecking {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Re-check")
                        }
                    }
                    .disabled(isChecking)
                    .accessibilityIdentifier("onboarding.provider.\(id).recheck")
                }
            }
            .padding(4)
        }
    }

    private var detail: String {
        switch status.link {
        case .unknown:
            "Looking for a \(status.provider.credentialOrigin) login…"
        case .linked(let info):
            "Using the \(info.origin) login on this Mac" + (info.planName.map { " · \($0)" } ?? "") + "."
        case .notLinked(let error):
            // The login command is shown right below, so the card does not repeat "sign in" wording.
            "\(error.userMessage) Run the command below, then press Re-check."
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { model.settings.enabledProviders.contains(status.provider) },
            set: { isOn in
                var settings = model.settings
                if isOn {
                    settings.enabledProviders.insert(status.provider)
                } else {
                    settings.enabledProviders.remove(status.provider)
                }
                model.settings = settings
            }
        )
    }
}
