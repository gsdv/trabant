import SwiftUI

struct OnboardingCardView: View {
    @Environment(AppState.self) var appState

    private var currentStep: OnboardingStep {
        if !appState.certificateStatus.isReady {
            return .generateCertificate
        } else if !appState.isProxyRunning {
            return .startProxy
        } else {
            return .connectDevice
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                headerSection
                stepsSection
                fullGuideButton
            }
            .padding(24)
            .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(TrabantTheme.accentLight)

            Text("Get Started")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(TrabantTheme.primaryText)

            Text("Set up HTTPS interception to capture traffic from your iPhone.")
                .font(.system(size: 12))
                .foregroundStyle(TrabantTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(spacing: 0) {
            stepRow(
                number: 1,
                title: "Generate Certificate",
                subtitle: "Create the local root CA for HTTPS interception",
                state: stepState(for: .generateCertificate),
                action: currentStep == .generateCertificate ? { appState.generateCA() } : nil
            )

            stepConnector(completed: currentStep != .generateCertificate)

            stepRow(
                number: 2,
                title: "Start Proxy",
                subtitle: "Begin listening for device connections on port \(appState.proxyPort)",
                state: stepState(for: .startProxy),
                action: currentStep == .startProxy ? { appState.startProxy() } : nil
            )

            stepConnector(completed: currentStep == .connectDevice)

            stepRow(
                number: 3,
                title: "Connect Device",
                subtitle: "Install the certificate and configure your iPhone",
                state: stepState(for: .connectDevice),
                action: nil
            )
        }
        .padding(16)
        .background(TrabantTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(TrabantTheme.cardBorder, lineWidth: 1)
        }
    }

    private func stepRow(
        number: Int,
        title: String,
        subtitle: String,
        state: StepState,
        action: (() -> Void)?
    ) -> some View {
        HStack(spacing: 12) {
            stepIndicator(number: number, state: state)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(state == .upcoming ? TrabantTheme.dimText : TrabantTheme.primaryText)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(state == .upcoming ? TrabantTheme.dimText.opacity(0.7) : TrabantTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let action {
                Button(action: action) {
                    Text(number == 1 ? "Generate" : "Start")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.82))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(TrabantTheme.accentLight, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func stepIndicator(number: Int, state: StepState) -> some View {
        ZStack {
            Circle()
                .fill(state == .completed ? TrabantTheme.statusGreen.opacity(0.18) :
                      state == .current ? TrabantTheme.accentLight.opacity(0.18) :
                      TrabantTheme.windowBackground)
                .overlay {
                    Circle()
                        .stroke(
                            state == .completed ? TrabantTheme.statusGreen.opacity(0.5) :
                            state == .current ? TrabantTheme.accentLight.opacity(0.5) :
                            TrabantTheme.separator,
                            lineWidth: 1
                        )
                }

            if state == .completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TrabantTheme.statusGreen)
            } else {
                Text("\(number)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(state == .current ? TrabantTheme.accentLight : TrabantTheme.dimText)
            }
        }
        .frame(width: 26, height: 26)
    }

    private func stepConnector(completed: Bool) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(completed ? TrabantTheme.statusGreen.opacity(0.4) : TrabantTheme.separator)
                .frame(width: 1, height: 20)
                .padding(.leading, 12) // centers under the 26pt indicator
            Spacer(minLength: 0)
        }
    }

    // MARK: - Full Guide Link

    private var fullGuideButton: some View {
        Button(action: { appState.isShowingCertificateSetup = true }) {
            HStack(spacing: 6) {
                Image(systemName: "book")
                    .font(.system(size: 11, weight: .medium))
                Text("Full Setup Guide")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(TrabantTheme.accentLight)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func stepState(for step: OnboardingStep) -> StepState {
        if step.rawValue < currentStep.rawValue { return .completed }
        if step == currentStep { return .current }
        return .upcoming
    }
}

private enum OnboardingStep: Int {
    case generateCertificate = 0
    case startProxy = 1
    case connectDevice = 2
}

private enum StepState {
    case completed
    case current
    case upcoming
}
