import SwiftUI
import CoreImage.CIFilterBuiltins

struct CertificateView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        certificateAuthorityCard
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        installCard
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        certificateAuthorityCard
                        installCard
                    }
                }

                setupGuideCard
                privacyCard
            }
            .padding(24)
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(TrabantTheme.windowBackground)
    }

    private func generateQRCode(from string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let ciImage = filter.outputImage else { return nil }
        // Scale up for crisp rendering
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let rep = NSCIImageRep(ciImage: scaled)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Certificate Setup")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(TrabantTheme.primaryText)

            Text("Generate the local certificate authority, install it from Safari on your iPhone, then trust it before routing device traffic through Trabant.")
                .font(.system(size: 14))
                .foregroundStyle(TrabantTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var certificateAuthorityCard: some View {
        card(
            title: "Certificate Authority",
            subtitle: "Create or rotate the local root certificate used for HTTPS interception."
        ) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: appState.certificateStatus.isReady ? "checkmark.shield.fill" : "shield.slash")
                    .font(.system(size: 26))
                    .foregroundStyle(certificateStatusColor)

                VStack(alignment: .leading, spacing: 6) {
                    Text(appState.certificateStatus.label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TrabantTheme.primaryText)

                    Text(certificateStatusDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(TrabantTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Group {
                if #available(macOS 26.0, *) {
                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) {
                            primaryActionButton(
                                title: appState.certificateStatus.isReady ? "Regenerate CA" : "Generate CA",
                                systemImage: appState.certificateStatus.isReady ? "arrow.clockwise.circle.fill" : "plus.circle.fill",
                                tint: TrabantTheme.accentLight,
                                action: { appState.generateCA() }
                            )

                            if appState.certificateStatus.isReady {
                                secondaryActionButton(
                                    title: "Reveal in Finder",
                                    systemImage: "folder",
                                    action: { appState.revealCertFile() }
                                )
                            }
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        primaryActionButton(
                            title: appState.certificateStatus.isReady ? "Regenerate CA" : "Generate CA",
                            systemImage: appState.certificateStatus.isReady ? "arrow.clockwise.circle.fill" : "plus.circle.fill",
                            tint: TrabantTheme.accentLight,
                            action: { appState.generateCA() }
                        )

                        if appState.certificateStatus.isReady {
                            secondaryActionButton(
                                title: "Reveal in Finder",
                                systemImage: "folder",
                                action: { appState.revealCertFile() }
                            )
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                metricTile(title: "Mac Address", value: appState.redactedModeEnabled ? Redactor.redactIP(appState.localIP) : appState.localIP)
                metricTile(title: "Proxy Port", value: "\(appState.proxyPort)")
                metricTile(title: "Download Port", value: "\(appState.certServerPort)")
            }
        }
    }

    private var installCard: some View {
        cardSurface {
            if let url = appState.certDownloadURL {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 18) {
                        cardHeader(
                            title: "Install on Device",
                            subtitle: "Open the certificate in Safari on the iPhone. Other browsers cannot trigger the profile install flow."
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Download URL")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(TrabantTheme.secondaryText)

                            Text(appState.redactedModeEnabled ? Redactor.redactIPsInText(url) : url)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(TrabantTheme.accentLight)
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(TrabantTheme.windowBackground, in: RoundedRectangle(cornerRadius: 10))

                            Text("Scan the QR code or open the URL directly in Safari on the device you want to inspect.")
                                .font(.system(size: 12))
                                .foregroundStyle(TrabantTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let qrImage = generateQRCode(from: url) {
                        VStack(spacing: 0) {
                            Image(nsImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 168, height: 168)
                                .padding(14)

                            Spacer(minLength: 0)
                        }
                        .frame(width: 196, alignment: .top)
                        .frame(minHeight: 208, alignment: .top)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    cardHeader(
                        title: "Install on Device",
                        subtitle: "Open the certificate in Safari on the iPhone. Other browsers cannot trigger the profile install flow."
                    )

                    HStack(spacing: 14) {
                        Image(systemName: "iphone.slash")
                            .font(.system(size: 24))
                            .foregroundStyle(TrabantTheme.dimText)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Generate the CA to enable device install")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(TrabantTheme.primaryText)
                            Text("The QR code and Safari download link appear here as soon as the certificate authority is ready.")
                                .font(.system(size: 12))
                                .foregroundStyle(TrabantTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TrabantTheme.windowBackground, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var setupGuideCard: some View {
        cardSurface {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: "iphone.gen3")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(TrabantTheme.primaryText.opacity(0.92))
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("iPhone Setup Guide")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(TrabantTheme.primaryText)

                        Text("Follow these steps in order to install the profile, trust the certificate, and route traffic through Trabant.")
                            .font(.system(size: 13))
                            .foregroundStyle(TrabantTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Rectangle()
                    .fill(TrabantTheme.cardBorder)
                    .frame(height: 1)

                guideSection(number: "1.", title: "Create Trabant Root Certificate on This Mac") {
                    VStack(alignment: .leading, spacing: 12) {
                        statusBadge(
                            title: appState.certificateStatus.isReady ? "Generated & Ready" : "Awaiting Certificate",
                            systemImage: appState.certificateStatus.isReady ? "checkmark.circle.fill" : "clock.fill",
                            tint: appState.certificateStatus.isReady ? TrabantTheme.accentLight : TrabantTheme.accent
                        )

                        Text("Use the Certificate Authority card above to generate or rotate the Trabant Root CA before connecting an iPhone.")
                            .font(.system(size: 13))
                            .foregroundStyle(TrabantTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                guideSection(number: "2.", title: "Configure Wi-Fi Proxy on Your iPhone") {
                    VStack(alignment: .leading, spacing: 14) {
                        guideInstructionLine(
                            label: "Open",
                            value: "Settings > Wi-Fi > current network > Configure Proxy > Manual"
                        )

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Config with the following info:")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(TrabantTheme.secondaryText)

                            proxyConfigurationCard
                        }

                        Text("Turn off any active VPN on both the Mac and iPhone while routing traffic through Trabant.")
                            .font(.system(size: 13))
                            .foregroundStyle(TrabantTheme.secondaryText)
                            .underline()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                guideSection(number: "3.", title: "Download Trabant Certificate on the Device") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Use Safari on the iPhone or scan the QR code in the Install on Device card above. Other browsers cannot trigger the profile install flow.")
                            .font(.system(size: 13))
                            .foregroundStyle(TrabantTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        if let url = appState.certDownloadURL {
                            Text(appState.redactedModeEnabled ? Redactor.redactIPsInText(url) : url)
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(TrabantTheme.accentLight)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Generate the certificate authority above first to reveal the Safari download URL and QR code.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(TrabantTheme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                guideSection(number: "4.", title: "Install and Trust Trabant Root CA") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Complete both trust steps on the iPhone after the profile has been downloaded.")
                            .font(.system(size: 13))
                            .foregroundStyle(TrabantTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 16) {
                                trustStepPanel(
                                    number: "4.1",
                                    title: "Install the Downloaded Profile",
                                    systemImage: "square.and.arrow.down.fill",
                                    tint: TrabantTheme.accent,
                                    lines: [
                                        "Open Settings, then tap Profile Downloaded if it appears.",
                                        "If not, go to General > VPN & Device Management.",
                                        "Select Trabant Root CA and tap Install."
                                    ],
                                    emphasis: nil
                                )

                                trustStepPanel(
                                    number: "4.2",
                                    title: "Enable Certificate Trust",
                                    systemImage: "checkmark.shield.fill",
                                    tint: TrabantTheme.accentLight,
                                    lines: [
                                        "Open Settings > General > About.",
                                        "Tap Certificate Trust Settings.",
                                        "Enable full trust for Trabant Root CA."
                                    ],
                                    emphasis: "Trabant Root CA"
                                )
                            }

                            VStack(alignment: .leading, spacing: 16) {
                                trustStepPanel(
                                    number: "4.1",
                                    title: "Install the Downloaded Profile",
                                    systemImage: "square.and.arrow.down.fill",
                                    tint: TrabantTheme.accent,
                                    lines: [
                                        "Open Settings, then tap Profile Downloaded if it appears.",
                                        "If not, go to General > VPN & Device Management.",
                                        "Select Trabant Root CA and tap Install."
                                    ],
                                    emphasis: nil
                                )

                                trustStepPanel(
                                    number: "4.2",
                                    title: "Enable Certificate Trust",
                                    systemImage: "checkmark.shield.fill",
                                    tint: TrabantTheme.accentLight,
                                    lines: [
                                        "Open Settings > General > About.",
                                        "Tap Certificate Trust Settings.",
                                        "Enable full trust for Trabant Root CA."
                                    ],
                                    emphasis: "Trabant Root CA"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var privacyCard: some View {
        card(title: "Privacy", subtitle: nil) {
            Text("Trabant captures and decrypts traffic only for devices that you explicitly configure to trust its local certificate authority and route through this Mac. Captured data stays local on this Mac.")
                .font(.system(size: 11))
                .foregroundStyle(TrabantTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var certificateStatusColor: Color {
        switch appState.certificateStatus {
        case .generated:
            return TrabantTheme.statusGreen
        case .error:
            return TrabantTheme.statusRed
        case .notGenerated:
            return TrabantTheme.statusOrange
        }
    }

    private var certificateStatusDescription: String {
        switch appState.certificateStatus {
        case .generated:
            return "HTTPS interception is available for devices that install and trust the Trabant Root CA."
        case .error(let message):
            return message
        case .notGenerated:
            return "Generate the CA before opening the install URL on an iPhone or other test device."
        }
    }

    private func card<Content: View>(
        title: String,
        subtitle: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        cardSurface {
            VStack(alignment: .leading, spacing: 18) {
                cardHeader(title: title, subtitle: subtitle)
                content()
            }
        }
    }

    private func cardHeader(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TrabantTheme.primaryText)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(TrabantTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func cardSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TrabantTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(TrabantTheme.cardBorder, lineWidth: 1)
            }
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(TrabantTheme.dimText)

            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(TrabantTheme.primaryText)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TrabantTheme.windowBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private func guideSection<Content: View>(
        number: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(number)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TrabantTheme.primaryText)
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TrabantTheme.primaryText)
            }

            content()
                .padding(.leading, 30)
        }
    }

    private func statusBadge(title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(TrabantTheme.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(TrabantTheme.windowBackground, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.32), lineWidth: 1)
            }
    }

    private func guideInstructionLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(label):")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TrabantTheme.primaryText)

            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(TrabantTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var proxyConfigurationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            proxyConfigurationRow(label: "Server", value: appState.redactedModeEnabled ? Redactor.redactIP(appState.localIP) : appState.localIP)
            proxyConfigurationRow(label: "Port", value: "\(appState.proxyPort)")
            proxyConfigurationRow(label: "Authentication", value: "No")
        }
        .padding(16)
        .frame(maxWidth: 430, alignment: .leading)
        .background(TrabantTheme.windowBackground.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(TrabantTheme.cardBorder, lineWidth: 1)
        }
    }

    private func proxyConfigurationRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text("\(label):")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TrabantTheme.primaryText)
                .frame(width: 106, alignment: .trailing)

            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(TrabantTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func trustStepPanel(
        number: String,
        title: String,
        systemImage: String,
        tint: Color,
        lines: [String],
        emphasis: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(number)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(TrabantTheme.secondaryText)
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TrabantTheme.primaryText)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 13))
                        .foregroundStyle(TrabantTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let emphasis {
                Text(emphasis)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TrabantTheme.accentLight)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(TrabantTheme.windowBackground.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(TrabantTheme.cardBorder, lineWidth: 1)
        }
    }

    private func primaryActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
        .modifier(GlassProminentFallback())
        .tint(tint)
    }

    private func secondaryActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
        .modifier(GlassFallback())
    }
}

private struct GlassProminentFallback: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

private struct GlassFallback: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
