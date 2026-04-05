import Foundation
import AppKit

enum CertificateStatus: Sendable {
    case notGenerated
    case generated
    case error(String)

    var label: String {
        switch self {
        case .notGenerated: return "No CA generated yet"
        case .generated: return "CA certificate ready"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var isReady: Bool {
        if case .generated = self { return true }
        return false
    }
}

@MainActor
@Observable
final class AppState {
    private static let debugLoggingDefaultsKey = "me.gsdv.Trabant.DebugLoggingEnabled"
    private static let redactedModeDefaultsKey = "me.gsdv.Trabant.RedactedModeEnabled"

    var isProxyRunning = false
    var localIP: String = "–"
    var proxyPort: Int = 9090
    var certServerPort: Int = 9091
    var debugLoggingEnabled: Bool = UserDefaults.standard.object(forKey: AppState.debugLoggingDefaultsKey) as? Bool ?? false {
        didSet {
            ProxyLogger.isVerboseEnabled = debugLoggingEnabled
            UserDefaults.standard.set(debugLoggingEnabled, forKey: AppState.debugLoggingDefaultsKey)
        }
    }
    var redactedModeEnabled: Bool = UserDefaults.standard.object(forKey: AppState.redactedModeDefaultsKey) as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(redactedModeEnabled, forKey: AppState.redactedModeDefaultsKey)
        }
    }
    var certificateStatus: CertificateStatus = .notGenerated
    var isShowingCertificateSetup = false
    var selectedDeviceIP: String?
    var selectedSessionID: UUID?
    var proxyError: String?

    let captureStore = CaptureStore()

    private var proxyServer: ProxyServer?
    private var sessionAccumulator: SessionAccumulator?
    private(set) var certificateAuthority: CertificateAuthority?
    private var certFileServer: CertificateFileServer?

    init() {
        ProxyLogger.isVerboseEnabled = debugLoggingEnabled
        refreshLocalIP()
        loadExistingCA()
    }

    func refreshLocalIP() {
        localIP = LocalNetworkInfo.localIPAddress() ?? "No network"
    }

    func toggleProxy() {
        if isProxyRunning {
            stopProxy()
        } else {
            startProxy()
        }
    }

    func startProxy() {
        guard !isProxyRunning else { return }
        proxyError = nil
        refreshLocalIP()

        let accumulator = SessionAccumulator(store: captureStore)
        sessionAccumulator = accumulator
        let ca = certificateAuthority
        let port = proxyPort

        Task.detached {
            do {
                let server = ProxyServer(
                    certificateAuthority: ca,
                    onSessionCaptured: { session in
                        accumulator.captured(session)
                    },
                    onSessionUpdated: { session in
                        accumulator.updated(session)
                    }
                )
                try await server.start(port: port)
                await MainActor.run {
                    self.proxyServer = server
                    self.isProxyRunning = true
                    self.proxyError = nil
                }
            } catch {
                let failure = ProxyFailureClassifier.localProxy(operation: "Proxy startup", port: port, error: error)
                ProxyLogger.error("proxy startup failed port=\(port) error=\(failure.message)")
                await MainActor.run {
                    self.proxyError = failure.displayText
                    self.isProxyRunning = false
                }
            }
        }
    }

    func stopProxy() {
        guard isProxyRunning else { return }
        let server = proxyServer
        proxyServer = nil
        sessionAccumulator = nil
        isProxyRunning = false

        Task.detached {
            try? await server?.stop()
        }
    }

    func generateCA() {
        do {
            let ca = CertificateAuthority()
            try ca.generateCA()
            certificateAuthority = ca
            certificateStatus = .generated
            startCertFileServer()

            // If proxy is running, restart to pick up new CA
            if isProxyRunning {
                stopProxy()
                Task.detached {
                    try? await Task.sleep(for: .milliseconds(150))
                    await MainActor.run {
                        self.startProxy()
                    }
                }
            }
        } catch {
            certificateStatus = .error(error.localizedDescription)
        }
    }

    func revealCertFile() {
        guard let ca = certificateAuthority, let path = try? ca.exportedCertPath() else { return }
        NSWorkspace.shared.selectFile(path.path, inFileViewerRootedAtPath: "")
    }

    var certDownloadURL: String? {
        guard certificateStatus.isReady, localIP != "No network" else { return nil }
        return "http://\(localIP):\(certServerPort)/trabant-ca.cer"
    }

    private func loadExistingCA() {
        let ca = CertificateAuthority()
        if (try? ca.loadExistingCA()) == true {
            certificateAuthority = ca
            certificateStatus = .generated
            startCertFileServer()
        }
    }

    private func startCertFileServer() {
        guard let ca = certificateAuthority else { return }
        let port = certServerPort
        let existingServer = certFileServer
        certFileServer = nil

        Task.detached {
            try? await existingServer?.stop()
            let server = CertificateFileServer(certificateAuthority: ca)
            do {
                try await server.start(port: port)
                await MainActor.run {
                    self.certFileServer = server
                }
            } catch {
                let failure = ProxyFailureClassifier.localProxy(
                    operation: "Certificate server startup",
                    port: port,
                    error: error
                )
                ProxyLogger.error("certificate server startup failed port=\(port) error=\(failure.message)")
                await MainActor.run {
                    self.proxyError = failure.displayText
                }
            }
        }
    }
}
