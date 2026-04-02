import SwiftUI

@main
struct TrabantApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
        .defaultSize(width: 1200, height: 700)
        .windowStyle(HiddenTitleBarWindowStyle())
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Certificate") {
                Button("Show Setup") {
                    appState.isShowingCertificateSetup = true
                }
            }
        }

        WindowGroup("Request Detail", id: "request-inspector", for: UUID.self) { $sessionID in
            DetachedRequestDetailView(sessionID: sessionID)
                .environment(appState)
        }
        .defaultSize(width: 780, height: 620)

        Window("Certificate Setup", id: "certificate-setup") {
            CertificateSetupWindow()
                .environment(appState)
        }
        .defaultSize(width: 1000, height: 780)
        .windowResizability(.contentMinSize)
    }
}
